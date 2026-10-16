import AppKit

/// The running pomodoro in the menu bar, so it stays in sight while its note is tucked away or
/// behind other windows. Only there while a timer is; its menu pauses, stops, or jumps to the task.
@MainActor
final class MenuBarTimer: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    /// The notes that currently have a timer.
    private let timed: () -> [NoteWindowController]

    init(timed: @escaping () -> [NoteWindowController]) {
        self.timed = timed
    }

    /// Redraws the item, adding or removing it as timers start and stop.
    func update() {
        guard let p = Self.shown(among: timed())?.pomodoro else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        let item = statusItem ?? makeStatusItem()
        guard let button = item.button else { return }
        let symbol = p.isPaused ? "pause.fill" : p.phase == .focus ? "timer" : "cup.and.saucer.fill"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        button.image?.isTemplate = true
        button.attributedTitle = NSAttributedString(string: " " + p.label, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
        button.appearsDisabled = p.isPaused
    }

    /// With several timers going, the one that's actually counting and ends soonest.
    private static func shown(among controllers: [NoteWindowController]) -> NoteWindowController? {
        controllers.filter { $0.pomodoro != nil }.min { a, b in
            let pa = a.pomodoro!, pb = b.pomodoro!
            if pa.isPaused != pb.isPaused { return !pa.isPaused }
            return pa.remaining < pb.remaining
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        return item
    }

    // The menu is rebuilt each time it opens: one section per running timer.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for controller in timed() {
            guard let p = controller.pomodoro else { continue }
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            let task = controller.pomodoroTask ?? ""
            menu.addItem(.sectionHeader(title: p.phase == .focus ? task : "Break after “\(task)”"))
            menu.addItem(item(p.isPaused ? "Resume" : "Pause", #selector(togglePause(_:)), controller))
            menu.addItem(item(p.phase == .focus ? "Stop" : "Skip Break", #selector(stop(_:)), controller))
            menu.addItem(item("Show Note", #selector(show(_:)), controller))
        }
    }

    private func item(_ title: String, _ action: Selector, _ controller: NoteWindowController) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = controller
        return item
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        (sender.representedObject as? NoteWindowController)?.togglePomodoroPause()
    }

    @objc private func stop(_ sender: NSMenuItem) {
        (sender.representedObject as? NoteWindowController)?.stopPomodoro()
    }

    @objc private func show(_ sender: NSMenuItem) {
        NSApp.activate()
        (sender.representedObject as? NoteWindowController)?.revealPomodoroItem()
    }
}
