import AppKit

/// Text storage that restyles edited paragraphs as markdown on every change.
final class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()

    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("init(pasteboardPropertyList:ofType:) is not supported")
    }

    override var string: String { backing.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        // Style here (not in replaceCharacters) so it runs after NSTextView applies typing attributes.
        // The backing store is restyled directly, leaving the edited range/length untouched so
        // NSTextView's selection bookkeeping stays exact; layout for the restyled paragraphs is
        // invalidated explicitly instead.
        var restyled: NSRange?
        if editedMask.contains(.editedCharacters) {
            let paragraphs = (backing.string as NSString).paragraphRange(for: editedRange)
            Markdown.style(backing, range: paragraphs)
            restyled = paragraphs
        }
        super.processEditing()
        if let restyled {
            for manager in layoutManagers {
                manager.invalidateLayout(forCharacterRange: restyled, actualCharacterRange: nil)
                manager.invalidateDisplay(forCharacterRange: restyled)
            }
        }
    }
}

/// Draws checkboxes and bullet dots in place of their (invisible) markdown characters.
final class NoteLayoutManager: NSLayoutManager {
    var accentColor: NSColor = .controlAccentColor

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.checkbox, in: chars) { value, range, _ in
            guard let checked = value as? Bool, let box = checkboxRect(forMarker: range, origin: origin) else { return }
            drawCheckbox(in: box, checked: checked)
        }
        storage.enumerateAttribute(.bullet, in: chars) { value, range, _ in
            guard value != nil, let g = markerGeometry(range, origin: origin) else { return }
            let d: CGFloat = 5.5
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: g.rect.midX - d / 2, y: g.midY - d / 2, width: d, height: d)).fill()
        }
    }

    /// The on-screen circle for the checkbox whose `- [ ]` characters span `range`.
    func checkboxRect(forMarker range: NSRange, origin: NSPoint) -> NSRect? {
        guard let g = markerGeometry(range, origin: origin) else { return nil }
        let d = (Markdown.bodySize * 1.1).rounded()
        return NSRect(x: (g.rect.midX - d / 2).rounded(), y: (g.midY - d / 2).rounded(), width: d, height: d)
    }

    private func markerGeometry(_ range: NSRange, origin: NSPoint) -> (rect: NSRect, midY: CGFloat)? {
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0, let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else {
            return nil
        }
        let rect = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
        let lineRect = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let baseline = origin.y + lineRect.minY + location(forGlyphAt: glyphs.location).y
        let font = textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? Markdown.bodyFont
        // Center on the midpoint between x-height and cap-height so it sits visually level with the text.
        return (rect, baseline - (font.xHeight + font.capHeight) / 4)
    }

    private func drawCheckbox(in r: NSRect, checked: Bool) {
        if checked {
            accentColor.setFill()
            NSBezierPath(ovalIn: r).fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.52))
            check.line(to: NSPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.68))
            check.line(to: NSPoint(x: r.minX + r.width * 0.73, y: r.minY + r.height * 0.34))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
            circle.lineWidth = 1.5
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            circle.stroke()
        }
    }
}
