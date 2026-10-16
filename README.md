# Stackies

A small, modern sticky-notes app for macOS: quick scratchpads for todos and short-lived reminders.

- Autosaves everything (text, position, size, color) — no save button
- Live markdown styling: headings, **bold**, _italic_, ~~strike~~, `code`, links, lists, quotes
- `- [ ]` checklists with clickable checkboxes
- Per-note colors and "keep on top" pinning
- Pomodoro timers on checklist items, shown in the note and the menu bar, with recorded singing-bowl
  chimes or any system sound (lengths and sounds in Settings, ⌘,)
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

## Credits

Pomodoro sounds are CC0 recordings, trimmed for use as alerts:

- Deep Bowl: [Singing Bowl - Soft Stick Meditative Hit](https://freesound.org/people/Rimych/sounds/616335/) by Rimych
- Low Bowl: [Singing bowl, low and quiet](https://freesound.org/people/eliasheuninck/sounds/170672/) by eliasheuninck
- Soft Bowl: [singing bowl - single strike 6](https://freesound.org/people/s-light/sounds/415141/) by s-light
- Brass Bowl: [ChaliceChime](https://freesound.org/people/ChaliceAV/sounds/509926/) by ChaliceAV
- Singing Bowl: [Tibetan bowl struck #3](https://bigsoundbank.com/sound-2554-bol-tibetain-frappe-3.html) by Joseph Sardin (BigSoundBank)
