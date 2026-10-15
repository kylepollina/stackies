import AppKit

/// One window per note: a borderless-looking tinted window with controls that appear on hover.
@MainActor
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let noteID: UUID
    var onClose: ((NoteWindowController) -> Void)?
    var onNewNote: (() -> Void)?
    var onBecomeKey: ((NoteWindowController) -> Void)?
    var onFrameChange: (() -> Void)?

    private let store: NoteStore
    private let textStorage = MarkdownTextStorage()
    private let layoutManager = NoteLayoutManager()
    private let textView: NoteTextView
    private var buttons: [NSButton] = []
    private var pinButton: NSButton!
    private var colorButton: NSButton!
    private var isHovering = false
    private var isBeingDeleted = false

    private var note: Note? { store.note(noteID) }
    var color: NoteColor { note?.color ?? .yellow }
    var isPinned: Bool { note?.isPinned ?? false }

    init(note: Note, store: NoteStore) {
        self.noteID = note.id
        self.store = store

        let container = NSTextContainer(size: NSSize(width: note.frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        layoutManager.addTextContainer(container)
        textStorage.addLayoutManager(layoutManager)
        textView = NoteTextView(frame: .zero, textContainer: container)

        let window = NSWindow(contentRect: note.frame,
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)

        configureWindow(window, frame: note.frame)
        configureTextView(text: note.text)
        configureTitlebarControls(window)
        apply(color: note.color)
        apply(pinned: note.isPinned)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Setup

    private func configureWindow(_ window: NSWindow, frame: NSRect) {
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 180, height: 120)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setFrame(frame, display: false)

        let content = NSView()
        window.contentView = content
        content.addTrackingArea(NSTrackingArea(rect: .zero,
                                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                               owner: self, userInfo: nil))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView
        content.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func configureTextView(text: String) {
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 4)
        textView.defaultParagraphStyle = Markdown.baseParagraph
        textView.typingAttributes = Markdown.baseAttributes

        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    private func configureTitlebarControls(_ window: NSWindow) {
        let newButton = makeButton("plus", "New Note", #selector(newNoteClicked))
        colorButton = makeButton("circle.fill", "Note Color", #selector(showColorMenu(_:)))
        pinButton = makeButton("pin", "Keep on Top", #selector(togglePin))
        buttons = [newButton, colorButton, pinButton]

        let stack = NSStackView(views: buttons)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 92, height: 28))
        holder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
        ])

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = holder
        window.addTitlebarAccessoryViewController(accessory)

        setControlsVisible(false, animated: false)
    }

    private func makeButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))!
        let button = NSButton(image: image, target: self, action: action)
        button.toolTip = tooltip
        button.contentTintColor = .secondaryLabelColor
        var side: CGFloat = 20
        if #available(macOS 26.0, *) {
            // Liquid Glass circles, matching the system's titlebar controls.
            button.bezelStyle = .glass
            button.borderShape = .circle
            button.controlSize = .small
            side = 24
        } else {
            button.isBordered = false
        }
        button.widthAnchor.constraint(equalToConstant: side).isActive = true
        button.heightAnchor.constraint(equalToConstant: side).isActive = true
        return button
    }

    // MARK: - Public actions

    func focus() {
        showWindow(nil)
        window?.makeFirstResponder(textView)
    }

    func setColor(_ color: NoteColor) {
        store.update(noteID) { $0.color = color }
        apply(color: color)
    }

    /// Switches to a random color other than the current one.
    func randomizeColor() {
        setColor(NoteColor.allCases.filter { $0 != color }.randomElement() ?? color)
    }

    @objc func togglePin() {
        let pinned = !isPinned
        store.update(noteID) { $0.isPinned = pinned }
        apply(pinned: pinned)
    }

    /// Closes the window without the empty-note/save handling in `windowWillClose`.
    func closeForDeletion() {
        isBeingDeleted = true
        close()
    }

    // MARK: - Appearance

    private func apply(color: NoteColor) {
        window?.backgroundColor = color.background
        layoutManager.accentColor = color.accent
        textView.insertionPointColor = color.accent
        textView.linkTextAttributes = [.foregroundColor: color.accent,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        colorButton.contentTintColor = color.accent
        textView.needsDisplay = true
    }

    private func apply(pinned: Bool) {
        window?.level = pinned ? .floating : .normal
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Keep on Top")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        pinButton.contentTintColor = pinned ? color.accent : .secondaryLabelColor
        setControlsVisible(isHovering, animated: true)
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        let views: [(NSView?, Bool)] = [
            (window?.standardWindowButton(.closeButton), visible),
            (buttons[0], visible),
            (colorButton, visible),
            (pinButton, visible || isPinned),
        ]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.15 : 0
            for (view, show) in views {
                (animated ? view?.animator() : view)?.alphaValue = show ? 1 : 0
            }
        }
    }

    private func updateTitle() {
        window?.title = note?.title ?? "Note"
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        setControlsVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        setControlsVisible(false, animated: true)
    }

    // MARK: - Titlebar button actions

    @objc private func newNoteClicked() {
        onNewNote?()
    }

    @objc private func showColorMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for c in NoteColor.allCases {
            let item = NSMenuItem(title: c.displayName, action: #selector(colorChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = c.rawValue
            item.image = Self.swatch(for: c)
            item.state = c == color ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let random = NSMenuItem(title: "Random", action: #selector(randomColorChosen), keyEquivalent: "")
        random.target = self
        random.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: "Random Color")
        menu.addItem(random)
        let y = sender.isFlipped ? sender.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
    }

    @objc private func colorChosen(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let c = NoteColor(rawValue: raw) { setColor(c) }
    }

    @objc private func randomColorChosen() { randomizeColor() }

    static func swatch(for color: NoteColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            color.background.setFill()
            circle.fill()
            color.accent.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
            return true
        }
    }

    // MARK: - Autosave hooks

    func textDidChange(_ notification: Notification) {
        let text = textView.string
        store.update(noteID) {
            $0.text = text
            $0.modified = Date()
        }
        updateTitle()
    }

    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?(self) }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        guard let frame = window?.frame else { return }
        store.update(noteID) { $0.frame = frame }
        onFrameChange?()
    }

    func windowWillClose(_ notification: Notification) {
        if !isBeingDeleted {
            // A note closed with nothing in it isn't worth keeping.
            if note?.isEmpty ?? false { store.remove(noteID) } else { store.saveNow() }
        }
        onClose?(self)
    }
}
