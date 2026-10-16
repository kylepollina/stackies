import Foundation

/// Owns all notes and persists them to a single JSON file.
/// Every mutation schedules a debounced save, so nothing ever needs saving by hand.
@MainActor
final class NoteStore {
    private(set) var notes: [Note] = []
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stackies", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("notes.json")
        load()
    }

    /// Notes that aren't archived: the ones shown on screen, tucked away, or closed.
    var activeNotes: [Note] { notes.filter { $0.archived == nil } }

    /// Archived notes, most recently archived first.
    var archivedNotes: [Note] {
        notes.filter { $0.archived != nil }.sorted { $0.archived! > $1.archived! }
    }

    func note(_ id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    func add(_ note: Note) {
        notes.append(note)
        scheduleSave()
    }

    func update(_ id: UUID, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[i])
        scheduleSave()
    }

    func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
        saveNow()
    }

    func removeEmptyNotes() {
        notes.removeAll { $0.isEmpty }
    }

    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(notes).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Stackies: failed to save notes: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([Note].self, from: Data(contentsOf: fileURL))
        } catch {
            // Never overwrite a file we couldn't read — set it aside so it can be recovered.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("notes-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("Stackies: could not read notes (\(error)); moved to \(backup.path)")
        }
    }
}
