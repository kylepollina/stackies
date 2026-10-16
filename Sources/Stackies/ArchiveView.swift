import AppKit
import SwiftUI

/// What the Archive window shows. The app delegate owns the notes, so this only reads them
/// through `load` and calls back to restore or delete one, then `reload`s.
@MainActor
final class ArchiveModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    private let load: () -> [Note]
    let restore: (UUID) -> Void
    let delete: (UUID) -> Void

    init(load: @escaping () -> [Note], restore: @escaping (UUID) -> Void, delete: @escaping (UUID) -> Void) {
        self.load = load
        self.restore = restore
        self.delete = delete
    }

    func reload() { notes = load() }
}

/// Window ▸ Archive (⌥⌘A). Archived notes, newest first, each previewed as it looked on screen.
struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel
    @State private var selection: UUID?
    @State private var search = ""
    @State private var confirmingDelete: Note?

    private var shown: [Note] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.notes }
        return model.notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var selected: Note? { model.notes.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            List(shown, selection: $selection) { note in
                row(note)
                    .tag(note.id)
                    .contextMenu {
                        Button("Restore") { model.restore(note.id) }
                        Divider()
                        Button("Delete…", role: .destructive) { confirmingDelete = note }
                    }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
            .searchable(text: $search, placement: .sidebar, prompt: "Search archive")
            .overlay {
                if model.notes.isEmpty {
                    ContentUnavailableView("No Archived Notes", systemImage: "archivebox",
                                           description: Text("Archive a note with ⌃⌘A to keep it here."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        } detail: {
            if let note = selected {
                ArchivedNotePreview(note: note)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ToolbarItemGroup {
                            Button {
                                model.restore(note.id)
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .help("Put this note back on screen")
                            Button(role: .destructive) {
                                confirmingDelete = note
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .help("Delete this note for good")
                        }
                    }
            } else {
                Text(model.notes.isEmpty ? "" : "Select a note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = shown.first?.id } }
        .onChange(of: model.notes.map(\.id)) { _, ids in
            // Restored or deleted: move on to the next note rather than leaving a blank pane.
            if let selection, !ids.contains(selection) { self.selection = shown.first?.id }
        }
        .confirmationDialog("Delete this note for good?", isPresented: Binding(
            get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }
        ), presenting: confirmingDelete) { note in
            Button("Delete", role: .destructive) { model.delete(note.id) }
        } message: { note in
            Text("“\(note.title)” will be removed from the archive. This can't be undone.")
        }
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NoteWindowController.swatch(for: note.color))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).lineLimit(1)
                if let archived = note.archived {
                    Text(archived, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// A read-only copy of a note's text view: same markdown styling, checkboxes, and color.
private struct ArchivedNotePreview: NSViewRepresentable {
    let note: Note

    final class Coordinator {
        let storage = MarkdownTextStorage()
        let layoutManager = NoteLayoutManager()
        var shownID: UUID?
        var shownText: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        c.layoutManager.addTextContainer(container)
        c.storage.addLayoutManager(c.layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 20, height: 16)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        guard c.shownID != note.id || c.shownText != note.text,
              let textView = scrollView.documentView as? NSTextView else { return }
        c.shownID = note.id
        c.shownText = note.text
        scrollView.backgroundColor = note.color.background
        c.layoutManager.accentColor = note.color.accent
        textView.linkTextAttributes = [.foregroundColor: note.color.accent,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        c.storage.replaceCharacters(in: NSRange(location: 0, length: c.storage.length), with: note.text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}
