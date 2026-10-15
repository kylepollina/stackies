import AppKit

/// Text view with checklist clicking, smart list continuation, and markdown formatting commands.
final class NoteTextView: NSTextView {
    private var noteLayout: NoteLayoutManager? { layoutManager as? NoteLayoutManager }
    private var ns: NSString { (textStorage?.string ?? "") as NSString }

    /// Called with an item's marker location when its pomodoro button is clicked.
    var onStartPomodoro: ((Int) -> Void)?
    /// Called before every text change with the affected range and the replacement's length.
    var onWillEdit: ((NSRange, Int) -> Void)?
    /// Marker of the item that already has a running pomodoro (it gets no start button).
    var timedMarker: Int? { didSet { if timedMarker != nil { setHoverMarker(nil) } } }

    // MARK: - Checkbox clicking

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let marker = timerButtonMarker(at: point) {
            onStartPomodoro?(marker)
            setHoverMarker(nil)
            return
        }
        if let marker = checkboxMarker(at: point) {
            toggleCheckbox(marker: marker)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoverMarker(pomodoroItemMarker(at: point))
        if checkboxMarker(at: point) != nil || timerButtonMarker(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        setHoverMarker(nil)
        super.mouseExited(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if !trackingAreas.contains(where: { $0.owner === self && $0.userInfo?["hover"] != nil }) {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: ["hover": true]))
        }
    }

    // MARK: - Pomodoro

    private func setHoverMarker(_ marker: Int?) {
        guard let lm = noteLayout, lm.hoverMarker != marker else { return }
        lm.hoverMarker = marker
        needsDisplay = true
    }

    /// An unchecked checklist item at `point` (anywhere on its first line) that could get a timer.
    private func pomodoroItemMarker(at point: NSPoint) -> Int? {
        guard let lm = noteLayout, let container = textContainer, ns.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: containerPoint, in: container)
        let line = Markdown.line(in: ns, at: lm.characterIndexForGlyph(at: glyph))
        guard let p = pomodoroItem(onLine: line), p.marker.location != timedMarker else { return nil }
        let firstLine = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: p.marker.location), effectiveRange: nil)
        guard containerPoint.y >= firstLine.minY, containerPoint.y < firstLine.maxY else { return nil }
        return p.marker.location
    }

    private func timerButtonMarker(at point: NSPoint) -> Int? {
        guard let lm = noteLayout, let marker = lm.hoverMarker,
              let p = pomodoroItem(onLine: Markdown.line(in: ns, at: marker)),
              let r = lm.timerButtonRect(forMarker: p.marker, origin: textContainerOrigin),
              r.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return marker
    }

    /// The prefix of `line` if it's an unchecked checklist item (at any nesting level).
    func pomodoroItem(onLine line: NSRange) -> ListPrefix? {
        guard let p = Markdown.listPrefix(in: ns, line: line), p.isCheckbox, !p.isChecked else { return nil }
        return p
    }

    /// The pomodoro-able item at the caret, if any.
    var pomodoroItemAtCaret: ListPrefix? {
        pomodoroItem(onLine: Markdown.line(in: ns, at: selectedRange().location))
    }

    /// Appends a 🍅 to the item whose marker is at `marker`.
    func addTomato(toItemAt marker: Int) {
        let line = Markdown.line(in: ns, at: marker)
        let text = ns.substring(with: line)
        let suffix = text.hasSuffix(" ") || text.hasSuffix("🍅") ? "🍅" : " 🍅"
        replaceKeepingSelection(NSRange(location: line.upperBound, length: 0), with: suffix)
    }

    /// Minutes already recorded in the item's `⏱` tag.
    func focusMinutes(forItemAt marker: Int) -> Int {
        FocusTime.tag(in: ns, line: Markdown.line(in: ns, at: marker))?.minutes ?? 0
    }

    /// Adds `seconds` to the item's `⏱` tag, creating the tag if needed.
    func addFocusTime(_ seconds: TimeInterval, toItemAt marker: Int) {
        let line = Markdown.line(in: ns, at: marker)
        guard marker < ns.length, Markdown.listPrefix(in: ns, line: line)?.marker.location == marker else { return }
        let existing = FocusTime.tag(in: ns, line: line)
        let total = (existing?.minutes ?? 0) + Int((seconds / 60).rounded())
        guard total > 0 else { return }
        let tag = "⏱" + FocusTime.format(total)
        if let existing {
            replaceKeepingSelection(existing.range, with: tag)
        } else {
            let endsWithSpace = line.length > 0 && ns.character(at: line.upperBound - 1) == 32
            replaceKeepingSelection(NSRange(location: line.upperBound, length: 0), with: (endsWithSpace ? "" : " ") + tag)
        }
    }

    /// Replaces text without moving the user's caret/selection relative to the text around it.
    private func replaceKeepingSelection(_ range: NSRange, with string: String) {
        let delta = (string as NSString).length - range.length
        let selection = selectedRanges.map { value -> NSValue in
            var r = value.rangeValue
            if r.location >= range.upperBound && !(range.length == 0 && r.location == range.location) {
                r.location += delta
            } else if r.upperBound > range.location && r.location < range.upperBound {
                r = NSRange(location: min(r.location, range.location), length: 0)
            }
            return NSValue(range: r)
        }
        replace(range, with: string)
        selectedRanges = selection
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        // A nil string means an attributes-only change, so the length stays the same.
        onWillEdit?(affectedCharRange, replacementString.map { ($0 as NSString).length } ?? affectedCharRange.length)
        return true
    }

    private func checkboxMarker(at point: NSPoint) -> NSRange? {
        guard let lm = noteLayout, let container = textContainer, ns.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: containerPoint, in: container)
        let line = Markdown.line(in: ns, at: lm.characterIndexForGlyph(at: glyph))
        guard let p = Markdown.listPrefix(in: ns, line: line), p.isCheckbox,
              let box = lm.checkboxRect(forMarker: p.marker, origin: textContainerOrigin),
              box.insetBy(dx: -5, dy: -4).contains(point) else { return nil }
        return p.marker
    }

    private func toggleCheckbox(marker: NSRange) {
        let inner = NSRange(location: marker.upperBound - 2, length: 1)
        let selection = selectedRanges
        replace(inner, with: ns.substring(with: inner) == " " ? "x" : " ")
        selectedRanges = selection
    }

    // MARK: - Keep the caret out of hidden markers

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        guard !stillSelecting, ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0 else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        let line = Markdown.line(in: ns, at: r.location)
        guard let p = Markdown.listPrefix(in: ns, line: line), p.hidesMarker, r.location < p.end else {
            super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
            return
        }
        // Moving left from the start of an item's text jumps to the previous line; otherwise snap past the marker.
        let old = selectedRange()
        var target = p.end
        if old.length == 0, old.location == p.end, r.location < old.location, line.location > 0 {
            target = line.location - 1
        }
        super.setSelectedRanges([NSValue(range: NSRange(location: target, length: 0))],
                                affinity: affinity, stillSelecting: false)
    }

    // MARK: - List editing

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let line = Markdown.line(in: ns, at: sel.location)
        guard !hasMarkedText(), let p = Markdown.listPrefix(in: ns, line: line), sel.location >= p.end else {
            super.insertNewline(sender)
            return
        }

        let content = ns.substring(with: NSRange(location: p.end, length: line.upperBound - p.end))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Return on an empty item ends the list (or outdents a nested item).
            if p.indent.length > 0 {
                outdent(line: line)
            } else {
                replace(NSRange(location: line.location, length: line.length), with: "",
                        select: NSRange(location: line.location, length: 0))
            }
            return
        }

        let indent = ns.substring(with: p.indent)
        let next: String
        switch p.kind {
        case .checkbox: next = indent + ns.substring(with: NSRange(location: p.marker.location, length: 1)) + " [ ] "
        case .bullet(let c): next = indent + c + " "
        case .ordered(let n, let delimiter): next = indent + "\(n + 1)\(delimiter) "
        case .quote: next = indent + "> "
        }
        let insertion = "\n" + next
        replace(sel, with: insertion, select: NSRange(location: sel.location + (insertion as NSString).length, length: 0))
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 {
            let line = Markdown.line(in: ns, at: sel.location)
            if let p = Markdown.listPrefix(in: ns, line: line), sel.location == p.end {
                // Backspace right after a marker removes the whole marker, not one hidden character.
                replace(NSRange(location: p.marker.location, length: p.end - p.marker.location), with: "",
                        select: NSRange(location: p.marker.location, length: 0))
                return
            }
        }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let line = Markdown.line(in: ns, at: sel.location)
        guard sel.length == 0, Markdown.listPrefix(in: ns, line: line) != nil else {
            super.insertTab(sender)
            return
        }
        replace(NSRange(location: line.location, length: 0), with: "\t",
                select: NSRange(location: sel.location + 1, length: 0))
    }

    override func insertBacktab(_ sender: Any?) {
        let line = Markdown.line(in: ns, at: selectedRange().location)
        guard Markdown.listPrefix(in: ns, line: line) != nil else {
            super.insertBacktab(sender)
            return
        }
        outdent(line: line)
    }

    private func outdent(line: NSRange) {
        var n = 0
        if line.length > 0 && ns.character(at: line.location) == 9 {
            n = 1
        } else {
            while n < 4 && n < line.length && ns.character(at: line.location + n) == 32 { n += 1 }
        }
        guard n > 0 else { return }
        let sel = selectedRange()
        replace(NSRange(location: line.location, length: n), with: "",
                select: NSRange(location: max(line.location, sel.location - n), length: 0))
    }

    // MARK: - Format menu commands

    @objc func toggleChecklist(_ sender: Any?) {
        transformSelectedLines { lines in
            let allChecklists = lines.allSatisfy { Markdown.listPrefix(of: $0)?.isCheckbox ?? false }
            return lines.map { line in
                let s = line as NSString
                if let p = Markdown.listPrefix(of: line) {
                    let rest = s.substring(from: p.end)
                    let indent = s.substring(with: p.indent)
                    if allChecklists { return indent + rest }
                    return p.isCheckbox ? line : indent + "- [ ] " + rest
                }
                let indentLength = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
                return s.substring(to: indentLength) + "- [ ] " + s.substring(from: indentLength)
            }
        }
    }

    @objc func toggleDone(_ sender: Any?) {
        transformSelectedLines { lines in
            let prefixes = lines.map { Markdown.listPrefix(of: $0) }
            let checkboxes = prefixes.compactMap { $0 }.filter(\.isCheckbox)
            guard !checkboxes.isEmpty else { return lines }
            let newMark = checkboxes.contains { !$0.isChecked } ? "x" : " "
            return zip(lines, prefixes).map { line, p in
                guard let p, p.isCheckbox else { return line }
                let inner = NSRange(location: p.marker.upperBound - 2, length: 1)
                return (line as NSString).replacingCharacters(in: inner, with: newMark)
            }
        }
    }

    @objc func toggleBold(_ sender: Any?) { wrapSelection(with: "**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection(with: "_") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection(with: "~~") }

    private func wrapSelection(with token: String) {
        let sel = selectedRange()
        let t = (token as NSString).length
        let before = NSRange(location: sel.location - t, length: t)
        let after = NSRange(location: sel.upperBound, length: t)
        if before.location >= 0, after.upperBound <= ns.length,
           ns.substring(with: before) == token, ns.substring(with: after) == token {
            replace(NSRange(location: before.location, length: sel.length + 2 * t), with: ns.substring(with: sel),
                    select: NSRange(location: before.location, length: sel.length))
        } else {
            replace(sel, with: token + ns.substring(with: sel) + token,
                    select: NSRange(location: sel.location + t, length: sel.length))
        }
    }

    /// Replaces the lines touched by the selection with `transform(lines)` as a single undoable edit.
    private func transformSelectedLines(_ transform: ([String]) -> [String]) {
        let sel = selectedRange()
        let first = Markdown.line(in: ns, at: sel.location)
        let last = Markdown.line(in: ns, at: sel.length > 0 ? sel.upperBound - 1 : sel.location)
        let block = NSRange(location: first.location, length: last.upperBound - first.location)
        let oldText = ns.substring(with: block)
        let newText = transform(oldText.components(separatedBy: "\n")).joined(separator: "\n")
        guard newText != oldText else { return }

        let delta = (newText as NSString).length - (oldText as NSString).length
        let newSelection = sel.length == 0
            ? NSRange(location: max(block.location, sel.location + delta), length: 0)
            : NSRange(location: block.location, length: (newText as NSString).length)
        replace(block, with: newText, select: newSelection)
    }

    // MARK: - Editing primitive

    /// Undoable replacement that notifies the delegate (which triggers autosave).
    private func replace(_ range: NSRange, with string: String, select: NSRange? = nil) {
        guard shouldChangeText(in: range, replacementString: string) else { return }
        textStorage?.replaceCharacters(in: range, with: string)
        didChangeText()
        if let select { setSelectedRange(select) }
    }
}
