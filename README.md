# Stackies

A small, modern sticky-notes app for macOS: quick scratchpads for todos and short-lived reminders.

- Autosaves everything (text, position, size, color) — no save button
- Live markdown styling: headings, **bold**, _italic_, ~~strike~~, `code`, links, lists, quotes
- `- [ ]` checklists with clickable checkboxes
- Per-note colors and "keep on top" pinning
- Pomodoro timers on checklist items, shown in the note and the menu bar, with bell, gong, or
  singing-bowl chimes (lengths and sounds in Settings, ⌘,)
- Plays nicely with Stage Manager: all notes share one stage

## Build

Requires macOS 14+ and Xcode (or the Swift toolchain).

```sh
./scripts/build.sh            # builds build/Stackies.app
./scripts/build.sh --install  # also copies it to /Applications
```

Notes are stored in `~/Library/Application Support/Stackies/notes.json`.

## Shortcuts

| Action | Shortcut |
|---|---|
| New note | ⌘N |
| Toggle checklist | ⌘L |
| Mark done | ⌘↩ |
| Bold / Italic / Strikethrough | ⌘B / ⌘I / ⇧⌘X |
| Move item (with subtasks) up / down | ⌘↑ / ⌘↓ |
| Keep on top | ⌘P |
| Tuck away to the screen edge (click the tab to bring it back) | ⌘J |
| Tuck all notes away / bring them all back | ⇧⌘J |
| Start or pause a pomodoro on the item at the caret | ⌘T |
| Note color | ⌘1–⌘7 (⌘0 for random) |
| Delete note | ⇧⌘⌫ |
| Reopen last closed or deleted note | ⇧⌘T |
