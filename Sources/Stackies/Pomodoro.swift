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
    /// Whether this session already sent the "too long on this task" alert.
    var warned = false
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
    var elapsed: TimeInterval { duration - remaining }

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

/// Total focus time on an item, stored in its text as a tag like `⏱1h40m`.
enum FocusTime {
    static let pattern = try! NSRegularExpression(pattern: #"⏱(?=\d)(?:(\d+)h)?(?:(\d+)m)?"#)

    /// Totals at or above this many minutes are flagged; `defaults write local.stackies.app warnHours 3`.
    static var warnMinutes: Int {
        let hours = UserDefaults.standard.double(forKey: "warnHours")
        return Int((hours > 0 ? hours : 2) * 60)
    }

    static func minutes(in match: NSTextCheckingResult, of ns: NSString) -> Int {
        func group(_ i: Int) -> Int {
            let r = match.range(at: i)
            return r.location == NSNotFound ? 0 : Int(ns.substring(with: r)) ?? 0
        }
        return group(1) * 60 + group(2)
    }

    /// The tag on `line`, if any.
    static func tag(in ns: NSString, line: NSRange) -> (range: NSRange, minutes: Int)? {
        guard let m = pattern.firstMatch(in: ns as String, range: line) else { return nil }
        return (m.range, minutes(in: m, of: ns))
    }

    static func format(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

/// Sound plus a system notification when a focus session or break ends.
@MainActor
enum PomodoroAlert {
    // UNUserNotificationCenter traps outside an app bundle (e.g. a bare `swift run` binary).
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, sound: String) {
        PomodoroSound.play(sound)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
