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
    /// Marker location of the checklist item whose "start pomodoro" button is showing.
    var hoverMarker: Int?
    /// The item with a running pomodoro; its checkbox is drawn as a progress ring.
    var timer: (marker: Int, progress: CGFloat, paused: Bool)?
    /// Characters of the timed item and its subtasks, drawn on a tinted background.
    var timerBlock: NSRange?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let block = timerBlock, block.length > 0, let marker = timer?.marker,
           let box = checkboxRect(forMarker: NSRange(location: marker, length: 5), origin: origin) {
            let first = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: block.location), effectiveRange: nil)
            let last = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: block.upperBound - 1), effectiveRange: nil)
            let rect = NSRect(x: box.minX - 6, y: origin.y + first.minY - 1,
                              width: origin.x + first.maxX - 2 - (box.minX - 6),
                              height: last.maxY - first.minY - 1)
            accentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.checkbox, in: chars) { value, range, _ in
            guard let checked = value as? Bool, let box = checkboxRect(forMarker: range, origin: origin) else { return }
            let ring = timer.flatMap { $0.marker == range.location ? ($0.progress, $0.paused) : nil }
            drawCheckbox(in: box, checked: checked, timer: ring)
            if hoverMarker == range.location, let button = timerButtonRect(forMarker: range, origin: origin) {
                drawTimerButton(in: button)
            }
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

    /// The "start pomodoro" button at the right end of the item's first line.
    func timerButtonRect(forMarker range: NSRange, origin: NSPoint) -> NSRect? {
        guard let g = markerGeometry(range, origin: origin) else { return nil }
        let glyph = glyphIndexForCharacter(at: range.location)
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let padding = textContainer(forGlyphAt: glyph, effectiveRange: nil)?.lineFragmentPadding ?? 0
        let d: CGFloat = 18
        return NSRect(x: (origin.x + line.maxX - padding - d).rounded(), y: (g.midY - d / 2).rounded(), width: d, height: d)
    }

    private func drawTimerButton(in r: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(.init(paletteColors: [accentColor]))
        guard let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Start Pomodoro")?
            .withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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

    private func drawCheckbox(in r: NSRect, checked: Bool, timer: (progress: CGFloat, paused: Bool)?) {
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
        } else if let timer {
            // Progress ring: a faint track, then the elapsed share clockwise from 12 o'clock.
            // (The text view is flipped, so increasing angles run clockwise on screen.)
            accentColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: r).fill()
            let center = NSPoint(x: r.midX, y: r.midY), radius = r.width / 2 - 1
            let track = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            track.lineWidth = 2
            accentColor.withAlphaComponent(0.3).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: -90,
                          endAngle: -90 + 360 * max(timer.progress, 0.001), clockwise: false)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            accentColor.withAlphaComponent(timer.paused ? 0.5 : 1).setStroke()
            arc.stroke()
        } else {
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
            circle.lineWidth = 1.5
            NSColor.labelColor.withAlphaComponent(0.35).setStroke()
            circle.stroke()
        }
    }
}
