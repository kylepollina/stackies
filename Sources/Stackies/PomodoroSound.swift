import AppKit

/// The sounds played when a focus session or break ends: a few synthesized chimes plus the
/// built-in macOS alert sounds. Chosen in Note ▸ Pomodoro Sounds and stored by name, e.g.
/// `defaults write local.stackies.app focusDoneSound Hero`.
@MainActor
enum PomodoroSound {
    enum Event: String {
        case focusDone, breakDone

        var key: String { rawValue + "Sound" }
        /// A low gong to ease into the break, a brighter bell to call you back.
        var defaultSound: String { self == .focusDone ? "Gong" : "Bell" }
    }

    static let none = "None"
    static let chimes = Chime.allCases.map(\.rawValue)
    static let system = ["Glass", "Hero", "Ping", "Submarine", "Tink", "Purr", "Funk", "Blow", "Bottle",
                         "Frog", "Morse", "Pop", "Sosumi", "Basso"]

    static func name(for event: Event) -> String {
        UserDefaults.standard.string(forKey: event.key) ?? event.defaultSound
    }

    static func set(_ name: String, for event: Event) {
        UserDefaults.standard.set(name, forKey: event.key)
    }

    /// The sound playing now, kept so it isn't freed mid-play and so a new one replaces it.
    private static var playing: NSSound?

    static func play(_ name: String) {
        playing?.stop()
        playing = Chime(rawValue: name).flatMap { NSSound(data: $0.wav) } ?? NSSound(named: name)
        playing?.play()
    }
}

/// Struck-metal sounds made from scratch. A bell or gong is a set of sine waves ("partials") at
/// inharmonic ratios to the lowest one, each dying away at its own rate, the high ones fastest.
/// Splitting a partial into two slightly detuned copies makes them beat, the slow wobble of a
/// big gong or bowl.
@MainActor
enum Chime: String, CaseIterable {
    case bell = "Bell", gong = "Gong", bowl = "Singing Bowl"

    private struct Partial {
        var ratio: Double, amplitude: Double, decay: Double, beat: Double = 0
    }

    private var spec: (fundamental: Double, attack: Double, length: Double, partials: [Partial]) {
        switch self {
        case .bell:
            // Church-bell partials (hum, prime, minor-third tierce, quint, nominal, ...) on G5.
            return (784, 0.002, 4, [
                Partial(ratio: 0.5, amplitude: 0.35, decay: 3.5, beat: 0.4),
                Partial(ratio: 1.0, amplitude: 0.6, decay: 2.5, beat: 0.6),
                Partial(ratio: 1.19, amplitude: 0.45, decay: 2.0),
                Partial(ratio: 1.5, amplitude: 0.22, decay: 1.6),
                Partial(ratio: 2.0, amplitude: 0.5, decay: 1.6, beat: 0.9),
                Partial(ratio: 2.51, amplitude: 0.18, decay: 0.9),
                Partial(ratio: 2.66, amplitude: 0.16, decay: 0.8),
                Partial(ratio: 3.01, amplitude: 0.13, decay: 0.6),
                Partial(ratio: 4.1, amplitude: 0.09, decay: 0.35),
                Partial(ratio: 5.4, amplitude: 0.06, decay: 0.2),
                Partial(ratio: 7.2, amplitude: 0.08, decay: 0.05), // the "ting" of the strike
            ])
        case .gong:
            // A low, soft-mallet gong: slower attack, long shimmering tail.
            return (110, 0.012, 7, [
                Partial(ratio: 0.5, amplitude: 0.25, decay: 0.8),
                Partial(ratio: 1.0, amplitude: 0.7, decay: 6, beat: 0.7),
                Partial(ratio: 1.52, amplitude: 0.45, decay: 4.5, beat: 1.1),
                Partial(ratio: 2.23, amplitude: 0.35, decay: 3.5, beat: 1.6),
                Partial(ratio: 2.94, amplitude: 0.25, decay: 2.8, beat: 1.3),
                Partial(ratio: 3.71, amplitude: 0.2, decay: 2.2, beat: 2.1),
                Partial(ratio: 4.56, amplitude: 0.14, decay: 1.6),
                Partial(ratio: 5.8, amplitude: 0.1, decay: 1.1),
                Partial(ratio: 7.3, amplitude: 0.06, decay: 0.7),
            ])
        case .bowl:
            // A Tibetan singing bowl's few, widely spaced modes, each a beating pair.
            return (294, 0.005, 7, [
                Partial(ratio: 1.0, amplitude: 1.0, decay: 7, beat: 1.2),
                Partial(ratio: 2.76, amplitude: 0.45, decay: 4.5, beat: 2.1),
                Partial(ratio: 5.4, amplitude: 0.2, decay: 2.5, beat: 3.0),
                Partial(ratio: 8.9, amplitude: 0.08, decay: 1.2, beat: 4.0),
            ])
        }
    }

    /// Mono 16-bit PCM samples, normalized to a comfortable peak.
    var samples: [Int16] {
        let rate = 44_100.0, spec = spec
        let count = Int(spec.length * rate)
        let fade = Int(0.3 * rate) // ease out the tail so it doesn't click
        var out = [Double](repeating: 0, count: count)
        for (i, p) in spec.partials.enumerated() {
            let f = spec.fundamental * p.ratio
            let phase = Double(i) * 1.3 // staggered so the peaks don't all line up at the strike
            for n in 0..<count {
                let t = Double(n) / rate
                var wave = sin(2 * .pi * f * t + phase)
                if p.beat > 0 { wave = (wave + 0.6 * sin(2 * .pi * (f + p.beat) * t + phase * 2)) / 1.6 }
                out[n] += p.amplitude * exp(-t / p.decay) * wave
            }
        }
        let peak = out.lazy.map(abs).max() ?? 1
        return out.indices.map { n in
            let t = Double(n) / rate
            var v = out[n] / peak * 0.7 * (1 - exp(-t / spec.attack))
            if n > count - fade { v *= Double(count - n) / Double(fade) }
            return Int16(v * Double(Int16.max))
        }
    }

    /// The samples wrapped as a WAV file, which NSSound can play from memory. Built on first use.
    var wav: Data {
        if let cached = Self.cache[self] { return cached }
        let pcm = samples
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))         // PCM, mono
        append(UInt32(44_100)); append(UInt32(88_200)) // sample rate, bytes per second
        append(UInt16(2)); append(UInt16(16))        // block align, bits per sample
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        pcm.forEach(append)
        Self.cache[self] = data
        return data
    }

    private static var cache: [Chime: Data] = [:]
}
