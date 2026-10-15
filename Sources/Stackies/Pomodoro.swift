import AppKit
import UserNotifications

/// A focus timer on one top-level checklist item, followed by a short break.
struct Pomodoro {
    enum Phase { case focus, rest }

    /// Lengths in minutes, overridable with e.g. `defaults write local.stackies.app focusMinutes 50`.
    static var focusLength: TimeInterval { minutes("focusMinutes", default: 25) }
    static var restLength: TimeInterval { minutes("breakMinutes", default: 5) }

    private static func minutes(_ key: String, default value: Double) -> TimeInterval {
        let stored = UserDefaults.standard.double(forKey: key)
        return (stored > 0 ? stored : value) * 60
    }

    let phase: Phase
    /// Location of the item's `- [ ]` marker, kept in step with edits above it.
    var marker: Int
    let duration: TimeInterval
    private(set) var endsAt: Date?
    private var pausedRemaining: TimeInterval

    init(phase: Phase, marker: Int) {
        self.phase = phase
        self.marker = marker
        duration = phase == .focus ? Self.focusLength : Self.restLength
        endsAt = Date().addingTimeInterval(duration)
        pausedRemaining = duration
    }

    var isPaused: Bool { endsAt == nil }
    var remaining: TimeInterval { endsAt.map { max(0, $0.timeIntervalSinceNow) } ?? pausedRemaining }
    var progress: CGFloat { CGFloat(1 - remaining / duration) }

    var label: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    mutating func togglePause() {
        if let endsAt {
            pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
            self.endsAt = nil
        } else {
            endsAt = Date().addingTimeInterval(pausedRemaining)
        }
    }
}

/// Sound plus a system notification when a focus session or break ends.
enum PomodoroAlert {
    // UNUserNotificationCenter traps outside an app bundle (e.g. a bare `swift run` binary).
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
