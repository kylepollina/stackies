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
    let side: Side
    private var restingFrame: NSRect = .zero

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

    /// Slides a little further out from the edge while hovered.
    func setHovered(_ hovered: Bool) {
        var f = restingFrame
        if hovered {
            f.size.width = Self.hoverWidth
            if side == .right { f.origin.x -= Self.hoverWidth - Self.width }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().setFrame(f, display: true)
        }
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

    override func mouseDown(with event: NSEvent) { tab?.onClick?() }
    // Cursor rects only apply in the active app, so also set the cursor directly as the mouse
    // moves over the tab while another app is in front.
    override func mouseEntered(with event: NSEvent) {
        tab?.setHovered(true)
        NSCursor.pointingHand.set()
    }
    override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) {
        tab?.setHovered(false)
        NSCursor.arrow.set()
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}
