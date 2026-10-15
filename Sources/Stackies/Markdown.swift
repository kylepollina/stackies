import AppKit

extension NSAttributedString.Key {
    /// Marks the `- [ ]` characters of a checklist item; value is a Bool (checked).
    static let checkbox = NSAttributedString.Key("StackiesCheckbox")
    /// Marks the `-` of a bullet item.
    static let bullet = NSAttributedString.Key("StackiesBullet")
}

/// The list/quote marker at the start of a line, e.g. `  - [x] `, `- `, `3. `, `> `.
struct ListPrefix {
    enum Kind {
        case checkbox(checked: Bool)
        case bullet(String)
        case ordered(Int, String)
        case quote
    }

    var kind: Kind
    var indent: NSRange
    var marker: NSRange
    /// Index where the line's content begins (after the marker and one space).
    var end: Int

    var isCheckbox: Bool {
        if case .checkbox = kind { return true }
        return false
    }

    var isChecked: Bool {
        if case .checkbox(let checked) = kind { return checked }
        return false
    }

    /// Checkbox and bullet markers are drawn as graphics, so their characters are invisible.
    var hidesMarker: Bool {
        switch kind {
        case .checkbox, .bullet: return true
        case .ordered, .quote: return false
        }
    }
}

enum Markdown {
    static let bodySize: CGFloat = 14
    static let bodyFont = NSFont.systemFont(ofSize: bodySize)
    static let markerColor = NSColor.tertiaryLabelColor
    static let doneColor = NSColor.secondaryLabelColor
    static let codeBackground = NSColor.labelColor.withAlphaComponent(0.07)

    static var baseParagraph: NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2.5
        p.paragraphSpacing = 3
        p.defaultTabInterval = 24
        p.tabStops = []
        return p
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: baseParagraph]
    }

    // MARK: - Patterns

    private static func rx(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    // Groups: 1 indent, 2 checkbox marker, 3 check char, 4 bullet char, 5 number, 6 delimiter, 7 quote
    private static let listPattern = rx(
        #"^([ \t]*)(?:([-*+][ \t]\[([ xX])\])(?=[ \t]|$)|([-*+])(?=[ \t])|(\d{1,9})([.)])(?=[ \t])|(>))[ \t]?"#)
    private static let heading = rx(#"^(#{1,3})([ \t]+)"#)
    private static let code = rx(#"`([^`\n]+)`"#)
    private static let bold = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = rx(#"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![*\w])"#)
    private static let italicUnderscore = rx(#"(?<![_\w])_(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?![_\w])"#)
    private static let strike = rx(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let link = rx(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    private static let bareURL = rx(#"(?<![(\w])https?://[^\s<>()\]]+"#)

    // MARK: - Line helpers

    /// Range of the line containing `index`, excluding its line terminator.
    static func line(in ns: NSString, at index: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        let location = min(max(index, 0), ns.length)
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    static func listPrefix(in ns: NSString, line: NSRange) -> ListPrefix? {
        guard let m = listPattern.firstMatch(in: ns as String, range: line) else { return nil }
        let indent = m.range(at: 1)
        let end = m.range.upperBound
        if m.range(at: 2).location != NSNotFound {
            let checked = ns.substring(with: m.range(at: 3)) != " "
            return ListPrefix(kind: .checkbox(checked: checked), indent: indent, marker: m.range(at: 2), end: end)
        }
        if m.range(at: 4).location != NSNotFound {
            return ListPrefix(kind: .bullet(ns.substring(with: m.range(at: 4))), indent: indent, marker: m.range(at: 4), end: end)
        }
        if m.range(at: 5).location != NSNotFound {
            let number = Int(ns.substring(with: m.range(at: 5))) ?? 1
            let marker = NSUnionRange(m.range(at: 5), m.range(at: 6))
            return ListPrefix(kind: .ordered(number, ns.substring(with: m.range(at: 6))), indent: indent, marker: marker, end: end)
        }
        return ListPrefix(kind: .quote, indent: indent, marker: m.range(at: 7), end: end)
    }

    /// The item on `line` plus the lines nested under it: every following line indented deeper,
    /// up to the first blank line or line at the same or a shallower indent.
    static func itemBlock(in ns: NSString, line: NSRange) -> NSRange {
        func indentWidth(_ l: NSRange) -> Int {
            var width = 0
            for i in 0..<l.length {
                switch ns.character(at: l.location + i) {
                case 32: width += 1
                case 9: width += 4
                default: return width
                }
            }
            return width
        }
        let base = indentWidth(line)
        var end = line.upperBound
        while end < ns.length {
            let next = self.line(in: ns, at: end + 1)
            guard next.location > end, next.length > 0,
                  ns.substring(with: next).contains(where: { !$0.isWhitespace }),
                  indentWidth(next) > base else { break }
            end = next.upperBound
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    static func listPrefix(of line: String) -> ListPrefix? {
        let ns = line as NSString
        return listPrefix(in: ns, line: NSRange(location: 0, length: ns.length))
    }

    // MARK: - Styling

    /// Restyles every line touched by `range`. All supported syntax is line-local,
    /// so restyling just the edited paragraphs is always correct.
    static func style(_ s: NSMutableAttributedString, range: NSRange) {
        let ns = s.string as NSString
        s.setAttributes(baseAttributes, range: range)
        ns.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            styleLine(s, ns, line)
        }
    }

    private static func styleLine(_ s: NSMutableAttributedString, _ ns: NSString, _ line: NSRange) {
        guard line.length > 0 else { return }
        let str = ns as String

        if let m = heading.firstMatch(in: str, range: line) {
            let level = m.range(at: 1).length
            s.addAttribute(.font, value: headingFont(level), range: line)
            let p = baseParagraph
            p.paragraphSpacingBefore = level == 1 ? 6 : 4
            s.addAttribute(.paragraphStyle, value: p, range: line)
            s.addAttribute(.foregroundColor, value: markerColor, range: m.range)
        } else if let p = listPrefix(in: ns, line: line) {
            styleListLine(s, ns, line, p)
        }

        styleInline(s, str, line)
    }

    private static func styleListLine(_ s: NSMutableAttributedString, _ ns: NSString, _ line: NSRange, _ p: ListPrefix) {
        switch p.kind {
        case .checkbox(let checked):
            s.addAttributes([.checkbox: checked, .foregroundColor: NSColor.clear], range: p.marker)
            // Kern the `x` so `[x]` is exactly as wide as `[ ]` and checked items don't shift.
            let mark = NSRange(location: p.marker.upperBound - 2, length: 1)
            let width = { (c: String) in (c as NSString).size(withAttributes: [.font: bodyFont]).width }
            s.addAttribute(.kern, value: width(" ") - width(ns.substring(with: mark)), range: mark)
            let rest = NSRange(location: p.end, length: line.upperBound - p.end)
            if checked && rest.length > 0 {
                s.addAttributes([.foregroundColor: doneColor,
                                 .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                 .strikethroughColor: doneColor], range: rest)
            }
        case .bullet:
            s.addAttributes([.bullet: true, .foregroundColor: NSColor.clear], range: p.marker)
        case .ordered:
            s.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: bodySize, weight: .medium)], range: p.marker)
        case .quote:
            s.addAttribute(.foregroundColor, value: markerColor, range: p.marker)
            let rest = NSRange(location: p.end, length: line.upperBound - p.end)
            s.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: rest)
        }

        // Hanging indent so wrapped lines align with the item's text, not its marker.
        let prefix = s.attributedSubstring(from: NSRange(location: line.location, length: p.end - line.location))
        let para = baseParagraph
        para.headIndent = prefix.size().width
        s.addAttribute(.paragraphStyle, value: para, range: line)
    }

    private static func styleInline(_ s: NSMutableAttributedString, _ str: String, _ line: NSRange) {
        for m in code.matches(in: str, range: line) {
            s.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: bodySize - 1, weight: .regular),
                             .backgroundColor: codeBackground], range: m.range)
            dimEnds(s, m.range, 1)
        }
        for m in bold.matches(in: str, range: line) {
            addTrait(.bold, s, m.range(at: 2))
            dimEnds(s, m.range, 2)
        }
        for m in italicStar.matches(in: str, range: line) + italicUnderscore.matches(in: str, range: line) {
            addTrait(.italic, s, m.range(at: 1))
            dimEnds(s, m.range, 1)
        }
        for m in strike.matches(in: str, range: line) {
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: doneColor], range: m.range(at: 1))
            dimEnds(s, m.range, 2)
        }
        for m in link.matches(in: str, range: line) {
            let url = (str as NSString).substring(with: m.range(at: 2))
            s.addAttribute(.foregroundColor, value: markerColor, range: m.range)
            if let u = URL(string: url) { s.addAttribute(.link, value: u, range: m.range(at: 1)) }
        }
        for m in FocusTime.pattern.matches(in: str, range: line) {
            let over = FocusTime.minutes(in: m, of: str as NSString) >= FocusTime.warnMinutes
            s.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: bodySize - 2.5, weight: .medium),
                             .foregroundColor: over ? NSColor.systemOrange : NSColor.secondaryLabelColor,
                             .strikethroughStyle: 0], range: m.range)
        }
        for m in bareURL.matches(in: str, range: line) {
            if let u = URL(string: (str as NSString).substring(with: m.range)) {
                s.addAttribute(.link, value: u, range: m.range)
            }
        }
    }

    private static func dimEnds(_ s: NSMutableAttributedString, _ range: NSRange, _ length: Int) {
        s.addAttribute(.foregroundColor, value: markerColor, range: NSRange(location: range.location, length: length))
        s.addAttribute(.foregroundColor, value: markerColor, range: NSRange(location: range.upperBound - length, length: length))
    }

    private static func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, _ s: NSMutableAttributedString, _ range: NSRange) {
        s.enumerateAttribute(.font, in: range) { value, r, _ in
            let font = (value as? NSFont) ?? bodyFont
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
            s.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: r)
        }
    }

    private static func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: return .systemFont(ofSize: 22, weight: .bold)
        case 2: return .systemFont(ofSize: 18, weight: .bold)
        default: return .systemFont(ofSize: 15.5, weight: .semibold)
        }
    }
}
