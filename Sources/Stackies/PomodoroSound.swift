import AppKit

/// The sounds played when a focus session or break ends: recordings bundled with the app plus
/// the built-in macOS alert sounds. Chosen in Settings and stored by name under `Event.key`.
@MainActor
enum PomodoroSound {
    enum Event: String {
        case focusDone, breakDone

        var key: String { rawValue + "Sound" }
        /// A deep bowl to ease into the break, a brighter chime to call you back.
        var defaultSound: String { self == .focusDone ? "Deep Bowl" : "Glass" }
    }

    static let none = "None"
    /// The recordings in `Resources/Sounds` (all CC0; see the README's credits), as
    /// display name and file name, in menu order.
    private static let recordingFiles: KeyValuePairs = [
        "Deep Bowl": "deep-bowl",
        "Low Bowl": "low-bowl",
        "Soft Bowl": "soft-bowl",
        "Brass Bowl": "brass-bowl",
        "Singing Bowl": "singing-bowl",
    ]
    static let recordings = recordingFiles.map(\.key)
    static let system = ["Glass", "Hero", "Ping", "Submarine", "Tink", "Purr", "Funk", "Blow", "Bottle",
                         "Frog", "Morse", "Pop", "Sosumi", "Basso"]

    static func name(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.key) ?? event.defaultSound
    }

    /// Resets choices of sounds that no longer exist (e.g. ones removed in an update) to the default.
    static func dropUnavailable() {
        let available = Set(recordings + system + [none])
        for event in [Event.focusDone, .breakDone] where !available.contains(name(for: event)) {
            UserDefaults.standard.removeObject(forKey: event.key)
        }
    }

    /// The sound playing now, kept so it isn't freed mid-play and so a new one replaces it.
    private static var playing: NSSound?

    static func play(_ name: String) {
        playing?.stop()
        if let file = recordingFiles.first(where: { $0.key == name })?.value {
            playing = Bundle.main.url(forResource: file, withExtension: "m4a")
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
        } else {
            playing = NSSound(named: name)
        }
        playing?.play()
    }
}
