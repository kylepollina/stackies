# Stackies ideas

Ideas for future work. Updated 2026-10-16 after a review pass.

## Done
- **Menu bar timer.** The running pomodoro shows in the menu bar; its menu pauses, stops, or jumps to the task.
- **Tuck all / untuck all.** ⇧⌘J.
- **Smart paste.** Pasting a list onto a checklist or bullet line continues that list (no more `- [ ] - [ ]`); `•`, `☐`, `✓` lists from other apps become checkboxes.
- **Archive** (new). ⌃⌘A files a note away whole (text, color, size); Window ▸ Archive (⌥⌘A) lists archived notes newest first with search and a full-color preview, and can restore or delete them.
- **Pomodoro sounds**. Five recorded singing bowls (CC0, Freesound and BigSoundBank) plus the system sounds, chosen separately for end of focus and end of break in a Settings window (⌘,), along with timer lengths.

## Bugs
- **Autocorrect doesn't work in notes.** Kyle tested the installed build (84ec899) on 2026-10-16: typing "teh " did not become "the", and he reported that it doesn't work overall. What's known:
  - `NoteWindowController.configureTextView` leaves `isAutomaticSpellingCorrectionEnabled` on (it follows the system setting, which is on), and the text view's `enabledTextCheckingTypes` includes correction. 84ec899 also turned on `isContinuousSpellCheckingEnabled`.
  - `NSSpellChecker` does return "the" for "teh".
  - It has never been tested with Stackies as the frontmost app. Test runs stayed in the background to avoid taking keyboard focus, and in that setup even a plain `NSTextView` didn't autocorrect, so those runs showed nothing either way.
  - The 84ec899 change doesn't fix it in real use. Start by reproducing with Stackies frontmost, and compare against a plain `NSTextView` in the same app.

- **Emoji can't be entered in notes.** Reported 2026-10-21: the emoji picker opens, but choosing an emoji inserts nothing, and pasting an emoji copied from another editor inserts nothing either (emoji work fine in other apps). Not reproduced yet. What's known:
  - In a test harness built from the app's own sources (real `NoteTextView`, `MarkdownTextStorage`, `NoteLayoutManager`, same text view settings, and the full `AppDelegate`/window stack), `paste(_:)` and `insertText(_:replacementRange:)` with 😀 and 🎉 both worked and the emoji drew correctly. Plain-text paste worked too.
  - Code read found no filter that drops emoji: `smartPaste` only special-cases ✅, and markdown styling only touches marker characters.
  - Not covered: real ⌘V / Edit ▸ Paste through the menu (a programmatic `sendAction` returned false with no key window), and the real picker's events.
  - Next steps: (1) reproduce in a live, isolated copy with a seeded notes folder, using the real picker and ⌘V, and compare an unpinned note with a pinned one; (2) check whether the installed build predates `main` (rebuild with `./scripts/build.sh --install` and retry); (3) check whether it shares a cause with the autocorrect bug above, since both go through system text input. The app has no Edit ▸ "Emoji & Symbols" item, which is worth trying.
  - Testing gotcha: to isolate a test copy from the real notes, set `CFFIXED_USER_HOME`; overriding `HOME` does not move `~/Library/Application Support/Stackies/notes.json`.

## Later
1. **Today view.** One list gathering every unchecked item across all notes; checking one there checks it in its note.
2. **Offer to archive finished notes.** When every checkbox in a note is checked, offer "All done ✓ Archive?" (the archive itself now exists).
3. **Due dates / reminders.** `@3pm` or `@tomorrow` on an item schedules a notification, shown as a small badge like the `⏱` tag.
4. **Weekly time summary.** Roll up the `⏱` totals into a "Time this week" panel by note.
5. **Focus mode.** While a pomodoro runs, dim or tuck the other notes.
6. **Tidy / snap to grid.** Arrange notes neatly using the existing free-slot placement code.
7. **Collapse to title bar.** Double-click the titlebar to shade a note to one line, as an in-place alternative to tucking.
8. **Quick search (⌘K).** Fuzzy-find any note, open or closed, and jump to it.
9. **Export / sync to Markdown files.** Mirror notes as `.md` in a folder (iCloud Drive, Obsidian vault).
10. **Shortcuts app actions.** "Add item to note…" so Siri or automations can add todos.

## Decided against
- **Global hotkey to summon Stackies.** Not wanted.
- **Sink completed items** below unchecked ones. Not wanted.
