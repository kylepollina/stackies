import AppKit

/// The slim tab a tucked-away note leaves at the screen edge, showing its first line sideways
/// like a book spine. Clicking it brings the note back.
final class TuckTab: NSPanel {
    enum Side { case left, right }

    static let width: CGFloat = 40
    private static let hoverWidth: CGFloat = 50

    /// The edge opposite Stage Manager's strip, which sits on the left unless the Dock is there.
    /// (With the Dock on the left, the strip moves right, so tabs go left.)
    static var side: Side {
        UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") == "left" ? .left : .right
    }

    var onClick: (() -> Void)?
    /// Called with the new resting frame after the tab is dragged along the edge.
    var onMove: ((NSRect) -> Void)?
    let side: Side
    private var restingFrame: NSRect = .zero
    private var isHovered = false

    init(title: NSAttributedString, color: NoteColor, side: Side) {
        self.side = side
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // Like a pinned note: stays reachable over every app's Stage Manager stage.
        collectionBehavior = [.canJoinAllApplications, .ignoresCycle, .fullScreenAuxiliary]
        contentView = TuckTabView(title: title, color: color, side: side, tab: self)
    }

    override var canBecomeKey: Bool { false }

    /// Places the tab without any hover offset.
    func place(at frame: NSRect) {
        restingFrame = frame
        setFrame(frame, display: true)
    }

    var resting: NSRect { restingFrame }

    /// The frame while hovered: slid a little further out from the edge.
    private var hoverFrame: NSRect {
        var f = restingFrame
        f.size.width = Self.hoverWidth
        if side == .right { f.origin.x -= Self.hoverWidth - Self.width }
        return f
    }

    /// Opens or closes the hover state from where the mouse actually is. Tracking-area
    /// enter/exit events fire spuriously while the tab animates (especially with the mouse
    /// pinned at the screen edge), so they only prompt a re-check. Once open, the tab stays open
    /// until the mouse leaves the wider, hovered frame.
    func updateHover() {
        let mouse = NSEvent.mouseLocation
        let zone = (isHovered ? hoverFrame : restingFrame).insetBy(dx: -2, dy: 0) // include the edge pixel
        let hovered = zone.contains(mouse)
        guard hovered != isHovered else { return }
        isHovered = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().setFrame(hovered ? hoverFrame : restingFrame, display: true)
        }
    }

    /// Moves the tab along the screen edge, kept on screen.
    func move(toY y: CGFloat) {
        let screen = (screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        restingFrame.origin.y = min(max(y, screen.minY + 4), screen.maxY - restingFrame.height - 4)
        setFrame(isHovered ? hoverFrame : restingFrame, display: true)
    }
}

private final class TuckTabView: NSView {
    let title: NSAttributedString
    let color: NoteColor
    let side: TuckTab.Side
    weak var tab: TuckTab?

    init(title: NSAttributedString, color: NoteColor, side: TuckTab.Side, tab: TuckTab) {
        self.title = title
        self.color = color
        self.side = side
        self.tab = tab
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways,
                                                              .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
        toolTip = title.string
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        // Extend the shape past the screen edge so only the inner corners are rounded.
        let radius: CGFloat = 9
        var shape = bounds.insetBy(dx: 0, dy: 0.5)
        shape.size.width += radius
        if side == .left { shape.origin.x -= radius }
        let path = NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius)
        color.background.setFill()
        path.fill()
        color.accent.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        // The first line, as if the note were turned on its side and slid over: on the right edge
        // it reads bottom to top, on the left top to bottom, with the text's top facing inward.
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let lineHeight = ceil(title.size().height)
        let length = bounds.height - 28
        ctx.saveGState()
        if side == .right {
            ctx.translateBy(x: bounds.midX, y: bounds.minY + 14)
            ctx.rotate(by: .pi / 2)
        } else {
            ctx.translateBy(x: bounds.midX, y: bounds.maxY - 14)
            ctx.rotate(by: -.pi / 2)
        }
        title.draw(with: NSRect(x: 0, y: -lineHeight / 2, width: length, height: lineHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        ctx.restoreGState()
    }

    // A click brings the note back; a drag slides the tab up or down the edge.
    private var dragStart: (mouse: CGFloat, tabY: CGFloat)?
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        guard let tab else { return }
        dragStart = (NSEvent.mouseLocation.y, tab.resting.minY)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tab, let start = dragStart else { return }
        let dy = NSEvent.mouseLocation.y - start.mouse
        if !isDragging && abs(dy) < 3 { return }
        isDragging = true
        NSCursor.closedHand.set()
        tab.move(toY: start.tabY + dy)
    }

    override func mouseUp(with event: NSEvent) {
        guard let tab else { return }
        if isDragging {
            tab.onMove?(tab.resting)
            NSCursor.pointingHand.set()
        } else {
            tab.onClick?()
        }
        dragStart = nil
        isDragging = false
    }
    // Cursor rects only apply in the active app, so also set the cursor directly as the mouse
    // moves over the tab while another app is in front.
    override func mouseEntered(with event: NSEvent) {
        tab?.updateHover()
        NSCursor.pointingHand.set()
    }
    override func mouseMoved(with event: NSEvent) {
        tab?.updateHover()
        NSCursor.pointingHand.set()
    }
    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        tab?.updateHover()
        NSCursor.arrow.set()
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}
