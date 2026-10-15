# Stackies ideas

Ideas for future work, roughly in priority order within each group.
Top picks: **global hotkey**, **menu bar timer**, **Today view**.

## First up
1. **Global hotkey to summon Stackies.** E.g. ⌃⌥Space shows/hides all notes from any app; another key creates a new note instantly. Needs Carbon `RegisterEventHotKey` or the KeyboardShortcuts package (menu shortcuts only work while Stackies is active).
2. **Menu bar timer.** Show the running pomodoro (`🍅 18:32`) in the menu bar so it's visible while the note is tucked or buried; click to pause or jump to the task.
3. **Archive finished notes.** When every checkbox in a note is checked, offer "All done ✓ Archive?" instead of deleting.

## To-dos
4. **Today view.** One list gathering every unchecked item across all notes; checking one there checks it in its note.
5. **Sink completed items.** Optionally move checked items below unchecked ones (reuse the ⌘↑/⌘↓ block logic so subtasks move along).
6. **Due dates / reminders.** `@3pm` or `@tomorrow` on an item schedules a notification, shown as a small badge like the `⏱` tag.
7. **Smart paste.** Pasted lists with `•`, `*`, or numbers become checkboxes.

## Pomodoro & time
8. **Weekly time summary.** Roll up the `⏱` totals into a "Time this week" panel by note.
9. **Focus mode.** While a pomodoro runs, dim or tuck the other notes.

## Windows
10. **Tidy / snap to grid.** Arrange notes neatly using the existing free-slot placement code.
11. **Collapse to title bar.** Double-click the titlebar to shade a note to one line, as an in-place alternative to tucking.
12. **Tuck all / untuck all.** One key to clear the screen (e.g. before screen sharing).

## Quality of life
13. **Quick search (⌘K).** Fuzzy-find any note, open or closed, and jump to it.
14. **Export / sync to Markdown files.** Mirror notes as `.md` in a folder (iCloud Drive, Obsidian vault).
15. **Shortcuts app actions.** "Add item to note…" so Siri or automations can add todos.
