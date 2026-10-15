import AppKit

enum NoteColor: String, Codable, CaseIterable {
    case yellow, peach, pink, lavender, blue, mint, graphite

    var displayName: String { rawValue.capitalized }

    /// Window background. Soft pastels in light mode, deep muted tones in dark mode.
    var background: NSColor {
        switch self {
        case .yellow:   return Self.dynamic(light: (255, 244, 194), dark: (56, 50, 30))
        case .peach:    return Self.dynamic(light: (255, 227, 207), dark: (60, 43, 34))
        case .pink:     return Self.dynamic(light: (253, 222, 233), dark: (58, 36, 46))
        case .lavender: return Self.dynamic(light: (232, 224, 255), dark: (43, 39, 64))
        case .blue:     return Self.dynamic(light: (216, 233, 255), dark: (30, 43, 62))
        case .mint:     return Self.dynamic(light: (211, 243, 226), dark: (28, 51, 41))
        case .graphite: return Self.dynamic(light: (240, 240, 242), dark: (40, 40, 44))
        }
    }

    /// Stronger tint used for checkboxes, the caret, and links.
    var accent: NSColor {
        switch self {
        case .yellow:   return Self.dynamic(light: (204, 145, 0), dark: (240, 190, 60))
        case .peach:    return Self.dynamic(light: (226, 110, 50), dark: (245, 150, 100))
        case .pink:     return Self.dynamic(light: (214, 70, 125), dark: (240, 120, 165))
        case .lavender: return Self.dynamic(light: (120, 90, 225), dark: (170, 150, 255))
        case .blue:     return Self.dynamic(light: (30, 115, 230), dark: (100, 165, 255))
        case .mint:     return Self.dynamic(light: (25, 150, 95), dark: (90, 205, 145))
        case .graphite: return Self.dynamic(light: (100, 100, 110), dark: (170, 170, 180))
        }
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        }
    }
}

struct Note: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var color: NoteColor = .yellow
    var frame: CGRect
    var isPinned = false
    /// Tucked away to a tab at the screen edge. Optional so notes saved before this existed still load.
    var tucked: Bool?
    /// Where the user dragged the tucked tab to (its origin, which also picks the display), if they did.
    var tabOrigin: CGPoint?
    var created = Date()
    var modified = Date()

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// First meaningful line with markdown syntax stripped, used for window titles and menus.
    var title: String {
        for raw in text.components(separatedBy: .newlines) {
            var s = raw.trimmingCharacters(in: .whitespaces)
            s = s.replacingOccurrences(of: #"^(#{1,6}\s+|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|\d+[.)]\s+|>\s*)"#,
                                       with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"[*_~`]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s.count > 40 ? String(s.prefix(40)) + "…" : s }
        }
        return "Empty Note"
    }
}
