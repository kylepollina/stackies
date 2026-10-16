import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private lazy var store = NoteStore()
    private var controllers: [UUID: NoteWindowController] = [:]
    private let closedNotesMenu = NSMenu(title: "Closed Notes")

    /// Invisible parents for the note windows, one per display. Stage Manager keeps child
    /// windows in their parent's stage, so this makes all notes on a display share one stage
    /// instead of each new note getting its own (which pushes the others to the side strip).
    /// A child window also lives in its parent's Space, and each display has its own Space, so a
    /// note dragged to another display must switch to that display's anchor or it vanishes.
    /// Each anchor's frame tracks the bounding box of its notes (see `layoutAnchors`) because
    /// Stage Manager lays out the stage's thumbnail around it.
    private var anchors: [CGDirectDisplayID: NSWindow] = [:]

    private func makeAnchor() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.alphaValue = 0
        w.ignoresMouseEvents = true
        w.isExcludedFromWindowsMenu = true
        w.collectionBehavior = [.ignoresCycle]
        return w
    }

    /// Notes closed or deleted this session, most recent last, for ⇧⌘T. Whole snapshots, so a
    /// deleted note (gone from the store) can be put back as it was.
    private var recentlyClosed: [Note] = []

    private func rememberClosed(_ note: Note) {
        recentlyClosed.removeAll { $0.id == note.id }
        recentlyClosed.append(note)
    }

    private lazy var menuBarTimer = MenuBarTimer { [unowned self] in
        controllers.values.filter(\.hasPomodoro).sorted { ($0.window?.frame.maxY ?? 0) > ($1.window?.frame.maxY ?? 0) }
    }

    private var keyController: NoteWindowController? {
        NSApp.keyWindow?.windowController as? NoteWindowController
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        let notes = store.notes.sorted { $0.modified < $1.modified }
        if notes.isEmpty {
            newNote(nil)
        } else {
            notes.forEach { show($0.id) }
        }
        NSApp.activate()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleAnchorLayout() }
        }
    }

    private var activeSince: Date?
    func applicationDidBecomeActive(_ notification: Notification) { activeSince = Date() }
    func applicationDidResignActive(_ notification: Notification) { activeSince = nil }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // The invisible anchor window counts as "visible", so check for open notes instead of `flag`.
        if controllers.isEmpty { showAllNotes(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.values.forEach { $0.stopPomodoro() } // record running sessions' time
        store.removeEmptyNotes()
        store.saveNow()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Note", action: #selector(newNote(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show All Notes", action: #selector(showAllNotes(_:)), keyEquivalent: ""))
        return menu
    }

    // MARK: - Notes

    private func show(_ id: UUID) {
        if let existing = controllers[id] {
            existing.focus()
            return
        }
        guard let note = store.note(id) else { return }
        let controller = NoteWindowController(note: note, store: store)
        controller.onClose = { [weak self] c in
            guard let self else { return }
            controllers[c.noteID] = nil
            // Empty notes are discarded on close (and deleted ones already captured), so this is
            // only a closed note that still has something in it.
            if let note = store.note(c.noteID) { rememberClosed(note) }
            scheduleAnchorLayout()
        }
        controller.onNewNote = { [weak self] in self?.newNote(nil) }
        controller.onBecomeKey = { [weak self] c in self?.raiseInStage(c.window) }
        controller.onFrameChange = { [weak self] in self?.scheduleAnchorLayout() }
        controller.onPinChange = { [weak self] c in
            guard let self, let window = c.window else { return }
            attachToAnchor(window)
            scheduleAnchorLayout()
        }
        controller.onScreenChange = { [weak self] c in
            if let window = c.window { self?.attachToAnchor(window) }
        }
        controller.onTuckChange = controller.onPinChange
        controller.onPomodoroChange = { [weak self] _ in self?.menuBarTimer.update() }
        controller.otherTabFrames = { [weak self, weak controller] in
            self?.controllers.values.filter { $0 !== controller }.compactMap(\.tabFrame) ?? []
        }
        controllers[id] = controller
        if controller.isTucked {
            controller.tuck(animated: false)
            return
        }
        if let window = controller.window {
            attachToAnchor(window)
            scheduleAnchorLayout()
        }
        controller.focus()
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The display a note belongs to: the one holding most of it, else the nearest sensible one.
    private func screen(for window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.screens.max { a, b in
            a.frame.intersection(window.frame).area < b.frame.intersection(window.frame).area
        } ?? NSScreen.main
    }

    /// Makes `window` a child of its display's anchor, switching anchors if it changed displays
    /// (or detaches it, if the note is pinned).
    /// Only re-parents (never moves an anchor), so it's safe to do in the middle of a drag.
    private func attachToAnchor(_ window: NSWindow) {
        if (window.windowController as? NoteWindowController)?.isTucked == true {
            window.parent?.removeChildWindow(window) // hidden behind its tab; not part of the stage
            return
        }
        if (window.windowController as? NoteWindowController)?.isPinned == true {
            // A child always stays in its parent's stage, so a pinned note must stand alone to
            // float over other apps' stages.
            if let parent = window.parent {
                parent.removeChildWindow(window)
                window.orderFront(nil)
            }
            return
        }
        guard let screen = screen(for: window), let id = displayID(of: screen) else { return }
        let anchor: NSWindow
        if let existing = anchors[id] {
            anchor = existing
        } else {
            anchor = makeAnchor()
            anchor.setFrame(window.frame, display: false)
            anchors[id] = anchor
        }
        guard window.parent !== anchor else { return }
        window.parent?.removeChildWindow(window)
        if !anchor.isVisible { anchor.orderFront(nil) }
        anchor.addChildWindow(window, ordered: .above)
    }

    private var anchorLayoutPending = false
    private var isMovingAnchor = false

    /// Keeps each anchor covering exactly the area spanned by its notes. Coalesced and deferred
    /// until no mouse button is held: moving an anchor mid-drag drags its children with it.
    private func scheduleAnchorLayout() {
        guard !isMovingAnchor, !anchorLayoutPending else { return }
        anchorLayoutPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            anchorLayoutPending = false
            if NSEvent.pressedMouseButtons != 0 {
                scheduleAnchorLayout()
            } else {
                layoutAnchors()
            }
        }
    }

    private func layoutAnchors() {
        let windows = controllers.values.compactMap(\.window)
        windows.forEach(attachToAnchor)
        // (Tucked and pinned notes end up with no parent, so they're left out of the anchors below.)

        for (id, anchor) in anchors {
            let children = windows.filter { $0.parent === anchor }
            guard let first = children.first else {
                // No notes left on this display (or it was disconnected).
                anchor.orderOut(nil)
                anchors[id] = nil
                continue
            }
            let union = children.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            guard anchor.frame != union else { continue }

            // Moving a parent window can drag its children along (and each child move would call
            // back into here), so pin every note back to where it was.
            let origins = children.map { ($0, $0.frame.origin) }
            isMovingAnchor = true
            anchor.setFrame(union, display: false)
            for (window, origin) in origins where window.frame.origin != origin {
                window.setFrameOrigin(origin)
            }
            isMovingAnchor = false
        }
    }

    /// Sibling child windows keep their attach order regardless of focus, so re-attach the
    /// focused note to move it to the top of the stack. A detached window is momentarily up for
    /// grabs by Stage Manager, so only do this once we've been the settled, active app for a
    /// moment — never mid stage-switch, or the note can get adopted into another app's stage.
    private func raiseInStage(_ window: NSWindow?) {
        guard NSApp.isActive, let activeSince, Date().timeIntervalSince(activeSince) > 0.8 else { return }
        guard let window, let anchor = window.parent, anchors.values.contains(anchor),
              anchor.childWindows?.last !== window else { return }
        anchor.removeChildWindow(window)
        anchor.addChildWindow(window, ordered: .above)
    }

    @objc func newNote(_ sender: Any?) {
        let previous = previousNote
        // Random, but never the same color twice in a row so neighboring notes stay distinct.
        let colors = NoteColor.allCases.filter { $0 != previous?.color }
        let note = Note(color: colors.randomElement() ?? .yellow, frame: frameForNewNote(after: previous))
        store.add(note)
        show(note.id)
    }

    /// The note a new one is based on: the focused note, or else the most recently created one.
    private var previousNote: Note? {
        if let id = keyController?.noteID, let note = store.note(id) { return note }
        return store.notes.max { $0.created < $1.created }
    }

    /// ⇧⌘T: reopens the most recently closed (or deleted) note, like reopening a browser tab.
    @objc func reopenClosedNote(_ sender: Any?) {
        while let note = recentlyClosed.popLast() {
            guard controllers[note.id] == nil else { continue } // already reopened some other way
            if store.note(note.id) == nil { store.add(note) }   // it was deleted: restore it
            show(note.id)
            return
        }
        NSSound.beep()
    }

    @objc func showAllNotes(_ sender: Any?) {
        if store.notes.isEmpty { newNote(nil); return }
        store.notes.sorted { $0.modified < $1.modified }.forEach { show($0.id) }
    }

    @objc func openClosedNote(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { show(id) }
    }

    @objc func deleteNote(_ sender: Any?) {
        guard let controller = keyController, let window = controller.window else { return }
        if store.note(controller.noteID)?.isEmpty ?? true {
            delete(controller)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "You can bring it back with ⇧⌘T until you quit Stackies."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.delete(controller) }
        }
    }

    private func delete(_ controller: NoteWindowController) {
        if let note = store.note(controller.noteID), !note.isEmpty { rememberClosed(note) }
        store.remove(controller.noteID)
        controller.closeForDeletion()
    }

    /// ⌘W. Closes the focused note directly: `performClose:` imitates a click on the close
    /// button, which refuses while the button is faded out (i.e. whenever the mouse is elsewhere).
    @objc func closeWindow(_ sender: Any?) {
        if let controller = keyController {
            controller.close()
        } else {
            NSApp.keyWindow?.performClose(sender)
        }
    }

    @objc func randomizeColor(_ sender: Any?) {
        keyController?.randomizeColor()
    }

    @objc func startPomodoro(_ sender: Any?) {
        keyController?.startPomodoroAtCaret()
    }

    @objc func stopPomodoro(_ sender: Any?) {
        keyController?.stopPomodoro()
    }

    @objc func tuckAway(_ sender: Any?) {
        keyController?.tuck()
    }

    /// Tucks every note away, or brings them all back if they're all tucked already.
    @objc func toggleTuckAll(_ sender: Any?) {
        // Top to bottom, so the tabs stack along the edge in the same order as the notes.
        let all = controllers.values.sorted { ($0.window?.frame.maxY ?? 0) > ($1.window?.frame.maxY ?? 0) }
        let open = all.filter { !$0.isTucked }
        if open.isEmpty { all.forEach { $0.untuck() } } else { open.forEach { $0.tuck() } }
    }

    private var settingsWindow: NSWindow?

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePin(_ sender: Any?) {
        keyController?.togglePin()
    }

    @objc func setNoteColor(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let color = NoteColor(rawValue: raw) {
            keyController?.setColor(color)
        }
    }

    /// Places a new note on a grid around `previous` (same size): a random free neighbor slot —
    /// right, left, up or down — spiraling outward ring by ring if those are taken or off screen.
    /// Falls back to a small cascade when no free slot exists.
    private func frameForNewNote(after previous: Note?) -> NSRect {
        let size = previous?.frame.size ?? NSSize(width: 300, height: 320)
        let base = previous?.frame
        let screen = (NSScreen.screens.first { base.map($0.visibleFrame.intersects) ?? false } ?? NSScreen.main)?
            .visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        guard let base else {
            return NSRect(x: screen.maxX - size.width - 40, y: screen.maxY - size.height - 40,
                          width: size.width, height: size.height)
        }

        let gap: CGFloat = 12
        let occupied = controllers.values.compactMap { $0.window?.frame }
        func slot(_ dx: Int, _ dy: Int) -> NSRect {
            NSRect(x: base.minX + CGFloat(dx) * (size.width + gap), y: base.minY + CGFloat(dy) * (size.height + gap),
                   width: size.width, height: size.height)
        }
        func isFree(_ r: NSRect) -> Bool {
            screen.contains(r) && !occupied.contains { $0.insetBy(dx: 1, dy: 1).intersects(r) }
        }

        for ring in 1...8 {
            var cells: [(Int, Int)] = []
            for dx in -ring...ring {
                for dy in -ring...ring where max(abs(dx), abs(dy)) == ring { cells.append((dx, dy)) }
            }
            // Random order, but straight neighbors before diagonals within each ring.
            let ordered = cells.shuffled().sorted { abs($0.0) + abs($0.1) < abs($1.0) + abs($1.1) }
            if let free = ordered.lazy.map(slot).first(where: isFree) { return free }
        }

        var origin = NSPoint(x: base.minX + 28, y: base.maxY - 28 - size.height)
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    // MARK: - Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === closedNotesMenu else { return }
        menu.removeAllItems()
        let closed = store.notes.filter { controllers[$0.id] == nil }.sorted { $0.modified > $1.modified }
        if closed.isEmpty {
            let empty = NSMenuItem(title: "No Closed Notes", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for note in closed {
            let item = NSMenuItem(title: note.title, action: #selector(openClosedNote(_:)), keyEquivalent: "")
            item.representedObject = note.id
            item.image = NoteWindowController.swatch(for: note.color)
            menu.addItem(item)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePin(_:)):
            item.state = keyController?.isPinned == true ? .on : .off
            // AppKit will also match ⇧⌘P to this ⌘P item; leave that combo free for other apps.
            if let event = NSApp.currentEvent, event.type == .keyDown, event.modifierFlags.contains(.shift) {
                return false
            }
            return keyController != nil
        case #selector(setNoteColor(_:)):
            item.state = keyController?.color.rawValue == item.representedObject as? String ? .on : .off
            return keyController != nil
        case #selector(deleteNote(_:)), #selector(randomizeColor(_:)):
            return keyController != nil
        case #selector(tuckAway(_:)):
            return keyController != nil
        case #selector(toggleTuckAll(_:)):
            let allTucked = controllers.values.allSatisfy(\.isTucked)
            item.title = allTucked && !controllers.isEmpty ? "Untuck All" : "Tuck All Away"
            return !controllers.isEmpty
        case #selector(startPomodoro(_:)):
            return keyController != nil
        case #selector(stopPomodoro(_:)):
            return keyController?.hasPomodoro == true
        case #selector(reopenClosedNote(_:)):
            return recentlyClosed.contains { controllers[$0.id] == nil }
        case #selector(closeWindow(_:)):
            return NSApp.keyWindow != nil
        default:
            return true
        }
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        main.addItem(submenu("Stackies", [
            item("About Stackies", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(showSettings(_:)), ","),
            .separator(),
            item("Hide Stackies", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Stackies", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New Note", #selector(newNote(_:)), "n"),
            .separator(),
            item("Close", #selector(closeWindow(_:)), "w"),
            item("Reopen Closed Note", #selector(reopenClosedNote(_:)), "t", [.command, .shift]),
            item("Delete Note…", #selector(deleteNote(_:)), "\u{8}", [.command, .shift]),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu("Find", [
                findItem("Find…", .showFindInterface, "f"),
                findItem("Find Next", .nextMatch, "g"),
                findItem("Find Previous", .previousMatch, "g", [.command, .shift]),
                findItem("Use Selection for Find", .setSearchString, "e"),
            ]),
        ]))

        main.addItem(submenu("Format", [
            item("Checklist", #selector(NoteTextView.toggleChecklist(_:)), "l"),
            item("Mark as Done", #selector(NoteTextView.toggleDone(_:)), "\r"),
            .separator(),
            item("Bold", #selector(NoteTextView.toggleBold(_:)), "b"),
            item("Italic", #selector(NoteTextView.toggleItalic(_:)), "i"),
            item("Strikethrough", #selector(NoteTextView.toggleStrikethrough(_:)), "x", [.command, .shift]),
            .separator(),
            item("Move Up", #selector(NoteTextView.moveItemUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!)),
            item("Move Down", #selector(NoteTextView.moveItemDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!)),
        ]))

        let colorItems = NoteColor.allCases.enumerated().map { index, color in
            let i = item(color.displayName, #selector(setNoteColor(_:)), "\(index + 1)")
            i.representedObject = color.rawValue
            i.image = NoteWindowController.swatch(for: color)
            return i
        }
        main.addItem(submenu("Note", [
            item("Keep on Top", #selector(togglePin(_:)), "p"),
            item("Tuck Away", #selector(tuckAway(_:)), "j"),
            item("Tuck All Away", #selector(toggleTuckAll(_:)), "j", [.command, .shift]),
            submenu("Color", colorItems + [
                .separator(),
                item("Random Color", #selector(randomizeColor(_:)), "0"),
            ]),
            .separator(),
            item("Start Pomodoro", #selector(startPomodoro(_:)), "t"),
            item("Stop Pomodoro", #selector(stopPomodoro(_:))),
        ]))

        closedNotesMenu.delegate = self
        let closedItem = NSMenuItem(title: "Closed Notes", action: nil, keyEquivalent: "")
        closedItem.submenu = closedNotesMenu
        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"),
            .separator(),
            item("Show All Notes", #selector(showAllNotes(_:)), "a", [.command, .shift]),
            closedItem,
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        return main
    }

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func findItem(_ title: String, _ action: NSTextFinder.Action, _ key: String,
                          _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = item(title, #selector(NSTextView.performFindPanelAction(_:)), key, modifiers)
        i.tag = action.rawValue
        return i
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
