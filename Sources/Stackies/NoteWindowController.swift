import AppKit

/// One window per note: a borderless-looking tinted window with controls that appear on hover.
@MainActor
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let noteID: UUID
    var onClose: ((NoteWindowController) -> Void)?
    var onNewNote: (() -> Void)?
    var onBecomeKey: ((NoteWindowController) -> Void)?
    var onFrameChange: (() -> Void)?
    var onPinChange: ((NoteWindowController) -> Void)?
    var onTuckChange: ((NoteWindowController) -> Void)?
    /// Frames of other notes' tabs, so a new tab can avoid them.
    var otherTabFrames: (() -> [NSRect])?
    var onScreenChange: ((NoteWindowController) -> Void)?

    private let store: NoteStore
    private let textStorage = MarkdownTextStorage()
    private let layoutManager = NoteLayoutManager()
    private let textView: NoteTextView
    private var buttons: [NSButton] = []
    private var pinButton: NSButton!
    private var colorButton: NSButton!
    private var tuckButton: NSButton!
    private var tab: TuckTab?
    private var isAnimatingTuck = false
    private var isHovering = false
    private var isBeingDeleted = false
    private var timerButton: NSButton!
    private var ticker: Timer?
    private var pomodoro: Pomodoro? { didSet { pomodoroChanged() } }

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
        configurePomodoro(window)
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
        tuckButton = makeButton(TuckTab.side == .right ? "arrow.right.to.line" : "arrow.left.to.line",
                                "Tuck Away", #selector(tuckClicked))
        buttons = [newButton, colorButton, pinButton, tuckButton]

        let stack = NSStackView(views: buttons)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 122, height: 28))
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

    private func configurePomodoro(_ window: NSWindow) {
        textView.onStartPomodoro = { [weak self] marker in self?.startPomodoro(marker: marker) }
        textView.onWillMove = { [weak self] map in
            // A moved item carries its running timer along.
            guard let self, var p = pomodoro, p.phase == .focus, let moved = map(p.marker) else { return }
            p.marker = moved
            pomodoro = p
        }
        textView.onWillEdit = { [weak self] range, newLength in
            // Keep the timer on its item when text above it grows or shrinks.
            guard let self, var p = pomodoro, p.phase == .focus, range.upperBound <= p.marker else { return }
            p.marker += newLength - range.length
            pomodoro = p
        }

        timerButton = NSButton(title: "", target: self, action: #selector(togglePomodoroPause))
        timerButton.translatesAutoresizingMaskIntoConstraints = false
        timerButton.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        timerButton.imagePosition = .imageLeading
        timerButton.controlSize = .small
        if #available(macOS 26.0, *) {
            timerButton.bezelStyle = .glass
            timerButton.borderShape = .capsule
        } else {
            timerButton.bezelStyle = .inline
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Pause / Resume", action: #selector(togglePomodoroPause), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Stop", action: #selector(stopPomodoro), keyEquivalent: "").target = self
        timerButton.menu = menu
        timerButton.isHidden = true

        // The titlebar view sits above the content view, so the pill goes in it to receive clicks.
        guard let close = window.standardWindowButton(.closeButton), let titlebar = close.superview else { return }
        titlebar.addSubview(timerButton)
        NSLayoutConstraint.activate([
            timerButton.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
            timerButton.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
    }

    // MARK: - Public actions

    func focus() {
        if isTucked { untuck(); return }
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
        onPinChange?(self)
    }

    var hasPomodoro: Bool { pomodoro != nil }

    /// ⌘T: starts a pomodoro on the item at the caret, or pauses/resumes the one already on it.
    func startPomodoroAtCaret() {
        guard let item = textView.pomodoroItemAtCaret else { NSSound.beep(); return }
        if let p = pomodoro, p.phase == .focus, p.marker == item.marker.location {
            togglePomodoroPause()
        } else {
            startPomodoro(marker: item.marker.location)
        }
    }

    private func startPomodoro(marker: Int) {
        PomodoroAlert.requestPermission()
        let previous = pomodoro
        // Start the new timer first so that writing the previous item's time (which may change
        // text above the new item) shifts the new timer's position along with it.
        pomodoro = Pomodoro(phase: .focus, marker: marker)
        if let previous { recordFocusTime(previous) }
    }

    /// Stops the timer, recording the time spent so far. Also called on close and quit.
    @objc func stopPomodoro() {
        let previous = pomodoro
        pomodoro = nil
        if let previous { recordFocusTime(previous) }
    }

    /// Adds a finished or interrupted focus session to its item's `⏱` total.
    private func recordFocusTime(_ p: Pomodoro, deferred: Bool = false) {
        guard p.phase == .focus, p.elapsed >= 30 else { return }
        let write: () -> Void = { [weak self] in self?.textView.addFocusTime(p.elapsed, toItemAt: p.marker) }
        // From inside a text change notification, edit on the next turn instead of re-entering.
        if deferred { DispatchQueue.main.async(execute: write) } else { write() }
    }

    /// The item's total focus minutes, including the running session.
    private func totalFocusMinutes(_ p: Pomodoro) -> Int {
        textView.focusMinutes(forItemAt: p.marker) + Int((p.elapsed / 60).rounded(.down))
    }

    private func itemTitle(at marker: Int) -> String {
        let ns = textView.string as NSString
        return ns.substring(with: Markdown.line(in: ns, at: marker))
            .replacingOccurrences(of: #"^\s*[-*+] \[[ xX]\] "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(⏱\S+|🍅)"#, with: "", options: .regularExpression)
    }

    @objc private func togglePomodoroPause() {
        pomodoro?.togglePause()
    }

    private func pomodoroChanged() {
        ticker?.invalidate()
        ticker = nil
        if let p = pomodoro, !p.isPaused {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common) // keep counting during menus and resizes
            ticker = t
        }
        refreshPomodoro()
    }

    private func tick() {
        guard let p = pomodoro else { return }
        if p.remaining <= 0 { finishPomodoro(); return }
        if p.phase == .focus, !p.warned, totalFocusMinutes(p) >= FocusTime.warnMinutes {
            pomodoro?.warned = true
            PomodoroAlert.post(title: "\(FocusTime.format(totalFocusMinutes(p))) on this task",
                               body: "\(itemTitle(at: p.marker))\nMaybe time to switch to something else?")
        }
        refreshPomodoro()
    }

    private func refreshPomodoro() {
        let p = pomodoro
        timerButton.isHidden = p == nil
        if let p {
            let symbol = p.isPaused ? "play.fill" : p.phase == .focus ? "timer" : "cup.and.saucer.fill"
            // Colored explicitly: glass buttons don't reliably apply contentTintColor.
            timerButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
                    .applying(.init(paletteColors: [color.accent])))
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let title = NSMutableAttributedString(string: p.label, attributes: [.font: font, .foregroundColor: color.accent])
            if p.phase == .focus {
                let total = totalFocusMinutes(p)
                if total > 0 {
                    let over = total >= FocusTime.warnMinutes
                    title.append(NSAttributedString(string: " · " + FocusTime.format(total), attributes: [
                        .font: font, .foregroundColor: over ? NSColor.systemOrange : NSColor.secondaryLabelColor,
                    ]))
                }
            }
            timerButton.attributedTitle = title
            timerButton.toolTip = p.phase == .focus
                ? (p.isPaused ? "Paused — click to resume" : "Focus — click to pause, right-click to stop")
                : "Break — right-click to skip"
        }
        let focus = p.flatMap { $0.phase == .focus ? $0 : nil }
        textView.timedMarker = focus?.marker
        layoutManager.timer = focus.map { ($0.marker, $0.progress, $0.isPaused) }
        layoutManager.timerBlock = focus.map {
            let ns = textView.string as NSString
            return Markdown.itemBlock(in: ns, line: Markdown.line(in: ns, at: $0.marker))
        }
        textView.needsDisplay = true
    }

    private func finishPomodoro() {
        guard let p = pomodoro else { return }
        switch p.phase {
        case .focus:
            let item = itemTitle(at: p.marker)
            pomodoro = Pomodoro(phase: .rest, marker: p.marker)
            recordFocusTime(p)
            textView.addTomato(toItemAt: p.marker)
            PomodoroAlert.post(title: "Pomodoro done 🍅", body: "\(item)\nTake a \(Int(Pomodoro.restLength / 60)) minute break.")
        case .rest:
            PomodoroAlert.post(title: "Break's over", body: "Ready for the next one?")
            pomodoro = nil
        }
    }

    /// Ends the focus timer if its item was deleted or checked off; otherwise redraws its block,
    /// which may have gained or lost subtasks.
    private func validatePomodoro() {
        guard let p = pomodoro, p.phase == .focus else { return }
        let ns = textView.string as NSString
        let line = Markdown.line(in: ns, at: p.marker)
        guard p.marker < ns.length, let item = Markdown.listPrefix(in: ns, line: line), item.isCheckbox,
              item.marker.location == p.marker else {
            pomodoro = nil // the item is gone, so there's nowhere to record its time
            return
        }
        if item.isChecked {
            pomodoro = nil
            recordFocusTime(p, deferred: true)
            return
        }
        refreshPomodoro()
    }

    // MARK: - Tucking away

    var isTucked: Bool { note?.tucked == true }
    var tabFrame: NSRect? { tab?.resting }

    @objc private func tuckClicked() { tuck() }

    /// Slides the note off the screen edge and a tab in. Without animation it just leaves the
    /// tab (used to restore tucked notes at launch, before the window was ever shown).
    func tuck(animated: Bool = true) {
        guard let window, tab == nil else { return }
        store.update(noteID) { $0.tucked = true }
        let saved = window.frame
        let side = TuckTab.side
        let tab = TuckTab(title: Markdown.styledTitle(of: note?.text ?? ""), color: color, side: side)
        tab.onClick = { [weak self] in self?.untuck() }
        tab.onMove = { [weak self] frame in
            guard let self else { return }
            store.update(noteID) { $0.tabOrigin = frame.origin }
        }
        // As tall as the note is wide, within reason; where it was last dragged to, if anywhere.
        tab.place(at: tabRect(near: saved, height: min(max(saved.width, 72), 320).rounded(), side: side,
                              preferred: note?.tabOrigin))
        self.tab = tab
        onTuckChange?(self) // leaves the anchor so hiding it doesn't disturb the other notes

        guard animated, window.isVisible else {
            window.orderOut(nil)
            tab.orderFront(nil)
            return
        }
        isAnimatingTuck = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(offscreen(saved, side: side), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                window.orderOut(nil)
                window.setFrame(saved, display: false)
                self?.isAnimatingTuck = false
                tab.setFrame(self?.offscreen(tab.resting, side: side) ?? tab.resting, display: false)
                tab.orderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    tab.animator().setFrame(tab.resting, display: true)
                }
            }
        })
    }

    /// Slides the tab away and the note back in to where it was.
    func untuck() {
        guard let window, let tab else { return }
        // Activate now, while the click on the tab is still being handled: macOS only lets an app
        // bring itself forward in response to the user's own input, so asking later (after the
        // animation) is quietly refused and ⌘W/⌘Q would still go to the previous app.
        NSApp.activate()
        self.tab = nil
        store.update(noteID) { $0.tucked = nil }
        let target = frame(onScreenOf: tab, from: note?.frame ?? window.frame)
        let side = tab.side

        isAnimatingTuck = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            tab.animator().setFrame(offscreen(tab.resting, side: side), display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                tab.orderOut(nil)
                window.setFrame(self.offscreen(target, side: side), display: false)
                self.onTuckChange?(self) // rejoins the anchor
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(self.textView)
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(target, display: true)
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        self?.isAnimatingTuck = false
                        self?.saveFrame()
                    }
                })
            }
        })
    }

    /// Where the note should come back: where it was, or, if its tab was dragged to another
    /// display, the same distance from the edge on that display, level with the tab.
    private func frame(onScreenOf tab: TuckTab, from saved: NSRect) -> NSRect {
        guard let tabScreen = tab.screen,
              let oldScreen = NSScreen.screens.first(where: { $0.frame.intersects(saved) }),
              tabScreen != oldScreen else { return saved }
        let old = oldScreen.visibleFrame, new = tabScreen.visibleFrame
        var f = saved
        f.origin.x = tab.side == .right ? new.maxX - (old.maxX - saved.minX) : new.minX + (saved.minX - old.minX)
        f.origin.y = tab.resting.midY - f.height / 2
        f.origin.x = min(max(f.minX, new.minX), new.maxX - f.width)
        f.origin.y = min(max(f.minY, new.minY), new.maxY - f.height)
        return f
    }

    /// `frame` moved horizontally just past the screen edge on `side`.
    private func offscreen(_ frame: NSRect, side: TuckTab.Side) -> NSRect {
        let screen = (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.frame ?? frame
        let x = side == .right ? screen.maxX + 4 : screen.minX - frame.width - 4
        return NSRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// A spot on the screen edge level with the note, below any tabs already there.
    private func tabRect(near frame: NSRect, height: CGFloat, side: TuckTab.Side, preferred: CGPoint? = nil) -> NSRect {
        // A dragged-to spot picks its display; otherwise use the note's.
        let dragged = preferred.flatMap { p in
            NSScreen.screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(NSPoint(x: p.x + TuckTab.width / 2, y: p.y + 1)) }
        }
        let screen = (dragged ?? NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let preferredY = dragged == nil ? nil : preferred?.y
        let x = side == .right ? screen.maxX - TuckTab.width : screen.minX
        let y = min(max(preferredY ?? frame.midY - height / 2, screen.minY + 4), screen.maxY - height - 4)
        var rect = NSRect(x: x, y: y, width: TuckTab.width, height: height)
        let others = (otherTabFrames?() ?? []).filter { abs($0.minX - x) < TuckTab.width }
        for _ in 0..<others.count + 1 {
            guard let hit = others.first(where: { $0.insetBy(dx: 0, dy: -6).intersects(rect) }) else { break }
            rect.origin.y = hit.minY - 8 - height
            if rect.minY < screen.minY + 8 { rect.origin.y = screen.maxY - height - 8 }
        }
        return rect
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
        // A real swatch rather than a tinted symbol: glass buttons don't reliably honor the tint.
        colorButton.image = Self.swatch(for: color, size: 13)
        if timerButton != nil { refreshPomodoro() }
        textView.needsDisplay = true
    }

    private func apply(pinned: Bool) {
        window?.level = pinned ? .floating : .normal
        // Lets Stage Manager show the note over every app's stage instead of hiding it with ours.
        window?.collectionBehavior = pinned ? [.canJoinAllApplications, .fullScreenAuxiliary] : []
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
            (tuckButton, visible),
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

    static func swatch(for color: NoteColor, size: CGFloat = 14) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
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
        validatePomodoro()
    }

    func windowDidBecomeKey(_ notification: Notification) { onBecomeKey?(self) }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidChangeScreen(_ notification: Notification) { onScreenChange?(self) }

    private func saveFrame() {
        guard !isAnimatingTuck, let frame = window?.frame else { return }
        store.update(noteID) { $0.frame = frame }
        onFrameChange?()
    }

    func windowWillClose(_ notification: Notification) {
        tab?.orderOut(nil)
        tab = nil
        stopPomodoro()
        if !isBeingDeleted {
            // A note closed with nothing in it isn't worth keeping.
            if note?.isEmpty ?? false { store.remove(noteID) } else { store.saveNow() }
        }
        onClose?(self)
    }
}
