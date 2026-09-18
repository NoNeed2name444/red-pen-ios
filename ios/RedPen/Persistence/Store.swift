import Foundation
import Combine

/// The library, on this device.
///
/// Everything lives in one JSON file in the app's Documents directory. It is
/// the source of truth for what the student has; SyncEngine reconciles it with
/// the server rather than replacing it, so the app works exactly as well with
/// no account and no signal.
///
/// Two things here exist only for sync's sake, and both are the kind of thing
/// that has to be designed in rather than added later.
///
/// **updatedAt is stamped only on a real change.** Several screens re-save a
/// set on every small interaction; if that counted as an edit, every device
/// would see the whole library move every time somebody opened a deck.
///
/// **Deletions leave a tombstone.** A row that merely vanishes is a row the
/// other device cheerfully uploads again, for ever.
@MainActor
final class Store: ObservableObject {
    @Published var library: [StudySet] = []
    @Published var folders: [StudyFolder] = []
    /// In-progress MCQ sessions keyed by set id — the web app's
    /// `resumeBanner` / `el.resumeBtn` state, so a quiz closed halfway can be
    /// picked up where it was left.
    @Published var quizProgress: [UUID: QuizProgress] = [:]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.fileURL = dir.appendingPathComponent("redpen-library.json")
        }
        load()
    }

    /// Ids of things deleted here, and when. Kept so the deletion can be told
    /// to the other devices; forgotten once every device has been told, which
    /// SyncEngine decides.
    /// Written by Store and StoreSync only - `private(set)` would keep the
    /// sync half out, and it is the half that needs to clear them.
    @Published var tombstones: [UUID: Date] = [:]

    private struct Snapshot: Codable {
        var library: [StudySet]
        var folders: [StudyFolder]
        var quizProgress: [UUID: QuizProgress]? // added later; older files simply lack it
        var tombstones: [UUID: Date]?           // likewise
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.redPen.decode(Snapshot.self, from: data) else { return }
        library = snapshot.library
        folders = snapshot.folders
        quizProgress = snapshot.quizProgress ?? [:]
        tombstones = snapshot.tombstones ?? [:]
    }

    func save() {
        let snapshot = Snapshot(library: library, folders: folders,
                                quizProgress: quizProgress, tombstones: tombstones)
        guard let data = try? JSONEncoder.redPen.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addSet(_ set: StudySet) {
        library.append(set)
        save()
    }

    func deleteSet(_ id: UUID) {
        library.removeAll { $0.id == id }
        quizProgress[id] = nil
        tombstones[id] = Date()
        pruneEmptyFolders()
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = library.firstIndex(where: { $0.id == id }), library[idx].name != name
        else { return }
        library[idx].name = name
        library[idx].updatedAt = Date()
        save()
    }

    /// Replaces a set, and stamps it ONLY if something about it really differs.
    ///
    /// Narrate saves the whole set after every corrected word, and the review
    /// screens save after every rating. Treating those as edits would have the
    /// library churning against every other device all day.
    func update(_ set: StudySet) {
        guard let idx = library.firstIndex(where: { $0.id == set.id }) else { return }
        var incoming = set
        incoming.updatedAt = library[idx].updatedAt
        guard incoming != library[idx] else { return }
        incoming.updatedAt = Date()
        library[idx] = incoming
        save()
    }

    func addFolder(name: String) {
        folders.append(StudyFolder(name: name))
        save()
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        tombstones[id] = Date()
        for idx in library.indices where library[idx].folderId == id {
            library[idx].folderId = nil
            library[idx].updatedAt = Date()
        }
        save()
    }

    // MARK: folders — mirrors createLibFolder() / ungroupLibFolder()

    /// Puts `ids` into a new folder called `name`. Any folder a set leaves
    /// that is now empty is removed, same as the web app's auto-cleanup.
    @discardableResult
    func group(_ ids: Set<UUID>, into name: String) -> StudyFolder {
        let folder = StudyFolder(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Folder" : name)
        folders.append(folder)
        for idx in library.indices where ids.contains(library[idx].id) {
            library[idx].folderId = folder.id
            library[idx].updatedAt = Date()
        }
        pruneEmptyFolders()
        save()
        return folder
    }

    /// Moves one set into a folder (or out of every folder with `nil`).
    func move(_ id: UUID, to folderId: UUID?) {
        guard let idx = library.firstIndex(where: { $0.id == id }),
              library[idx].folderId != folderId else { return }
        library[idx].folderId = folderId
        library[idx].updatedAt = Date()
        pruneEmptyFolders()
        save()
    }

    /// Clears the folder on every member and removes the folder — never
    /// deletes the sets themselves.
    func ungroup(_ folderId: UUID) {
        for idx in library.indices where library[idx].folderId == folderId {
            library[idx].folderId = nil
            library[idx].updatedAt = Date()
        }
        folders.removeAll { $0.id == folderId }
        tombstones[folderId] = Date()
        save()
    }

    func renameFolder(_ id: UUID, to name: String) {
        guard let idx = folders.firstIndex(where: { $0.id == id }), folders[idx].name != name
        else { return }
        folders[idx].name = name
        folders[idx].updatedAt = Date()
        save()
    }

    private func pruneEmptyFolders() {
        let used = Set(library.compactMap(\.folderId))
        folders.removeAll { !used.contains($0.id) }
    }

    // MARK: combine — mirrors the library's "Combine N selected" flow

    /// Merges two or more sets of the same kind into one new set named
    /// `name`, re-basing every image index into the combined image pool.
    /// The originals are left untouched, as in the web app.
    @discardableResult
    func combine(_ ids: [UUID], name: String) -> StudySet? {
        let members = ids.compactMap { id in library.first { $0.id == id } }
        guard let first = members.first, members.count >= 2,
              members.allSatisfy({ $0.kind == first.kind }) else { return nil }
        var out = StudySet(name: name, subject: first.subject, kind: first.kind)
        for m in members {
            let base = out.images.count
            out.images.append(contentsOf: m.images)
            switch m.kind {
            case .mcq:
                out.questions.append(contentsOf: m.questions.map { q in
                    var q = q; q.id = UUID(); if let i = q.imageIndex { q.imageIndex = i + base }; return q
                })
            case .anki:
                out.cards.append(contentsOf: m.cards.map { c in
                    var c = c; c.id = UUID(); if let i = c.imageIndex { c.imageIndex = i + base }; return c
                })
            case .book:
                out.bookMarkdown += (out.bookMarkdown.isEmpty ? "" : "\n\n") + m.bookMarkdown
            case .qa:
                out.qaCards.append(contentsOf: m.qaCards.map { var c = $0; c.id = UUID(); return c })
            case .osce:
                out.osceChecklists.append(contentsOf: m.osceChecklists.map { var c = $0; c.id = UUID(); return c })
            case .narrate:
                out.narrateSegments.append(contentsOf: m.narrateSegments.map { var s = $0; s.id = UUID(); return s })
            }
        }
        library.append(out)
        save()
        return out
    }

    // MARK: quiz resume — mirrors the web app's resume banner

    func saveProgress(_ progress: QuizProgress, for setId: UUID) {
        quizProgress[setId] = progress
        save()
    }

    func clearProgress(for setId: UUID) {
        guard quizProgress[setId] != nil else { return }
        quizProgress[setId] = nil
        save()
    }
}

/// A half-finished MCQ session: which question was up and every answer so
/// far. The (possibly shuffled) question order is kept too, so resuming
/// shows the same options in the same places.
struct QuizProgress: Codable, Hashable {
    var current: Int
    var answers: [MCQAnswer]
    var questionIds: [UUID]
    var optionOrders: [[Int]]
    var savedAt: Date = Date()
}

extension JSONDecoder {
    static let redPen: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let redPen: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
