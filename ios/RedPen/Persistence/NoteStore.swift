import Foundation
import Combine

/// What a note is for. A page is somewhere to write at length - a topic, a
/// lecture's worth of thoughts; an idea is one line dumped in passing, to be
/// found again later and joined up with the rest.
enum NoteKind: String, Codable, CaseIterable, Identifiable {
    case page, idea
    var id: String { rawValue }
    var label: String {
        switch self {
        case .page: return "Page"
        case .idea: return "Idea"
        }
    }
    var symbol: String {
        switch self {
        case .page: return "doc.text"
        case .idea: return "lightbulb"
        }
    }
}

/// One note in the idea dump. The body is Markdown, and any `[[Title]]` in it
/// links to the note of that title, the way it does in Obsidian.
struct Note: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var body: String = ""
    var folderId: UUID? = nil
    var kind: NoteKind = .idea
    /// Connections made by hand - on the board, or with "Link to…" - as
    /// opposed to the ones written into the body as `[[Title]]`.
    var links: [UUID] = []
    var tags: [String] = []
    /// Where the note sits on the idea board, in board points from its centre.
    var boardX: Double = 0
    var boardY: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

/// A folder of notes. Folders nest: a folder with a parent sits inside it.
struct NoteFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentId: UUID? = nil
    var createdAt: Date = Date()
}

/// Read tolerantly, like the library: a file written by an older or newer
/// version may lack a field this one has, and a missing field should take its
/// default rather than lose every note in the file.
extension Note {
    private enum Keys: String, CodingKey {
        case id, title, body, folderId, kind, links, tags, boardX, boardY, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(title: try c.decodeIfPresent(String.self, forKey: .title) ?? "")
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        // an unknown kind from a newer version is read as an idea rather than
        // refused
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)).flatMap(NoteKind.init(rawValue:)) ?? .idea
        links = try c.decodeIfPresent([UUID].self, forKey: .links) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        boardX = try c.decodeIfPresent(Double.self, forKey: .boardX) ?? 0
        boardY = try c.decodeIfPresent(Double.self, forKey: .boardY) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? createdAt
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

extension NoteFolder {
    private enum Keys: String, CodingKey {
        case id, name, parentId, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Folder")
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? createdAt
    }
}

/// Every note and folder in the idea dump, kept on this device.
///
/// A file of its own in Application Support rather than part of the library
/// snapshot: the library carries whole decks and their images, and rewriting
/// all of that because an idea moved an inch on the board would be absurd.
/// The file is written off the main thread, so dragging a card never waits on
/// the disk.
@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var folders: [NoteFolder] = []

    private let fileURL: URL
    /// One queue, so two quick saves land in the order they were made.
    private let writer = DispatchQueue(label: "vignette.notes.save", qos: .utility)

    private struct Snapshot: Codable {
        var notes: [Note]?
        var folders: [NoteFolder]?
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let manager = FileManager.default
            let dir = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // Application Support is not there until something makes it
            try? manager.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("vignette-notes.json")
        }
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.redPen.decode(Snapshot.self, from: data) else {
            // the next save would otherwise write an empty list over notes this
            // version could not read; put the file aside first so they can be
            // recovered
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("notes-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: aside)
            return
        }
        notes = snapshot.notes ?? []
        folders = snapshot.folders ?? []
    }

    private func save() {
        let snapshot = Snapshot(notes: notes, folders: folders)
        guard let data = try? JSONEncoder.redPen.encode(snapshot) else { return }
        let url = fileURL
        writer.async { try? data.write(to: url, options: .atomic) }
    }

    // MARK: finding notes

    func note(_ id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    /// Notes whose title, body or tags contain every word of the query,
    /// newest first.
    func search(_ query: String) -> [Note] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return notes.sorted { $0.updatedAt > $1.updatedAt } }
        return notes.filter { note in
            let haystack = ([note.title, note.body] + note.tags).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The notes directly in a folder (nil: the ones in no folder), newest first.
    func contents(of folderId: UUID?) -> [Note] {
        notes.filter { $0.folderId == folderId }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: making and changing notes

    /// Makes a note and returns it. Without a board position it is placed on
    /// a slow spiral out from the centre, so a run of quick ideas does not
    /// land in one pile.
    @discardableResult
    func create(title: String, body: String = "", kind: NoteKind = .idea,
                folderId: UUID? = nil, at point: (x: Double, y: Double)? = nil) -> Note {
        var note = Note(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        body: body, folderId: folderId, kind: kind)
        let spot = point ?? nextBoardSpot()
        note.boardX = spot.x
        note.boardY = spot.y
        notes.append(note)
        save()
        return note
    }

    /// Replaces the stored note with this one. The time is stamped only when
    /// something really differs, so opening and closing a note does not make
    /// it jump to the top of the list.
    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var changed = note
        changed.updatedAt = notes[index].updatedAt
        guard changed != notes[index] else { return }
        changed.updatedAt = Date()
        notes[index] = changed
        save()
    }

    /// Deletes a note and every hand-made link to it. `[[Title]]` links in
    /// other notes are left as written: they simply point nowhere until a note
    /// of that name exists again.
    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        for index in notes.indices where notes[index].links.contains(id) {
            notes[index].links.removeAll { $0 == id }
        }
        save()
    }

    func move(_ id: UUID, to folderId: UUID?) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].folderId != folderId else { return }
        notes[index].folderId = folderId
        notes[index].updatedAt = Date()
        save()
    }

    /// Where a card was dropped on the board. Not an edit to the note, so its
    /// time is left alone.
    func setPosition(_ id: UUID, x: Double, y: Double) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].boardX = x
        notes[index].boardY = y
        save()
    }

    // MARK: links

    /// Joins two notes by hand. A link is kept on the first of the two only;
    /// connections are read both ways, so one copy is enough.
    func link(_ a: UUID, _ b: UUID) {
        guard a != b, let index = notes.firstIndex(where: { $0.id == a }),
              !isLinked(a, b) else { return }
        notes[index].links.append(b)
        save()
    }

    /// Removes a hand-made link between two notes, whichever of them holds it.
    func unlink(_ a: UUID, _ b: UUID) {
        var changed = false
        for index in notes.indices {
            let id = notes[index].id
            if id == a, notes[index].links.contains(b) {
                notes[index].links.removeAll { $0 == b }; changed = true
            } else if id == b, notes[index].links.contains(a) {
                notes[index].links.removeAll { $0 == a }; changed = true
            }
        }
        if changed { save() }
    }

    /// Whether two notes are joined by hand, in either direction.
    func isLinked(_ a: UUID, _ b: UUID) -> Bool {
        (note(a)?.links.contains(b) ?? false) || (note(b)?.links.contains(a) ?? false)
    }

    /// Every note's id by its title, lowercased: what `[[Title]]` is looked up
    /// in. Where two notes share a title the older one wins, so a link does
    /// not jump to a note made later.
    func titleIndex() -> [String: UUID] {
        var index: [String: UUID] = [:]
        for note in notes.sorted(by: { $0.createdAt < $1.createdAt }) {
            let key = note.title.trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty, index[key] == nil { index[key] = note.id }
        }
        return index
    }

    /// The notes that `[[Title]]`s in this text name, in the order written,
    /// each once.
    func resolve(wikiLinksIn text: String, index: [String: UUID]? = nil) -> [UUID] {
        let index = index ?? titleIndex()
        var seen = Set<UUID>()
        return NoteStore.wikiTitles(in: text).compactMap { title in
            guard let id = index[title.lowercased()], seen.insert(id).inserted else { return nil }
            return id
        }
    }

    /// The notes one note points to: its hand-made links, then its `[[Title]]`s.
    func outgoing(of id: UUID, index: [String: UUID]? = nil) -> [UUID] {
        guard let note = self.note(id) else { return [] }
        let known = Set(notes.map(\.id))
        var seen = Set<UUID>([id])
        let wiki = resolve(wikiLinksIn: note.body, index: index)
        return (note.links + wiki).filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// The notes that point to this one, by hand or by `[[Title]]`.
    func backlinks(of id: UUID) -> [UUID] {
        let index = titleIndex()
        return notes.filter { other in
            other.id != id && (other.links.contains(id)
                || resolve(wikiLinksIn: other.body, index: index).contains(id))
        }
        .map(\.id)
    }

    /// Everything a note is connected to: its own links, its `[[Title]]`s, and
    /// the notes that link to it.
    func connections(of id: UUID) -> Set<UUID> {
        Set(outgoing(of: id)).union(backlinks(of: id)).subtracting([id])
    }

    /// Every connection in the dump, each once, whichever way it was made -
    /// what the board and the 3D space draw.
    func allEdges() -> [(UUID, UUID)] {
        let index = titleIndex()
        var seen = Set<String>()
        var edges: [(UUID, UUID)] = []
        for note in notes {
            for other in outgoing(of: note.id, index: index) {
                let pair = note.id.uuidString < other.uuidString ? (note.id, other) : (other, note.id)
                if seen.insert(pair.0.uuidString + pair.1.uuidString).inserted {
                    edges.append(pair)
                }
            }
        }
        return edges
    }

    /// The titles written as `[[Title]]` in a body, trimmed. `[[Title|shown
    /// text]]` counts as a link to Title, as in Obsidian.
    nonisolated static func wikiTitles(in text: String) -> [String] {
        var titles: [String] = []
        let pieces = text.components(separatedBy: "[[")
        for piece in pieces.dropFirst() {
            guard let close = piece.range(of: "]]") else { continue }
            let inner = piece[piece.startIndex..<close.lowerBound]
            guard !inner.contains("\n") else { continue }
            let target = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            let title = target.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { titles.append(title) }
        }
        return titles
    }

    // MARK: folders

    @discardableResult
    func createFolder(name: String, parentId: UUID? = nil) -> NoteFolder {
        let folder = NoteFolder(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                parentId: parentId)
        folders.append(folder)
        save()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        save()
    }

    /// Deletes a folder but nothing in it: its notes and folders move up into
    /// its parent, so deleting a folder never deletes an idea.
    func deleteFolder(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        for index in notes.indices where notes[index].folderId == id {
            notes[index].folderId = folder.parentId
        }
        for index in folders.indices where folders[index].parentId == id {
            folders[index].parentId = folder.parentId
        }
        folders.removeAll { $0.id == id }
        save()
    }

    func folder(_ id: UUID?) -> NoteFolder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    /// The folders directly inside one (nil: the top level), by name.
    func subfolders(of parentId: UUID?) -> [NoteFolder] {
        folders.filter { $0.parentId == parentId }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A folder and the folders it sits in, outermost first.
    func path(to id: UUID?) -> [NoteFolder] {
        var path: [NoteFolder] = []
        var seen = Set<UUID>()
        var current = folder(id)
        // a guard against a loop in the parents, which a hand-edited or
        // half-synced file could contain
        while let folder = current, seen.insert(folder.id).inserted {
            path.insert(folder, at: 0)
            current = self.folder(folder.parentId)
        }
        return path
    }

    /// The top-level folder a note's folder sits in - what its colour comes from.
    func rootFolder(of id: UUID?) -> UUID? {
        path(to: id).first?.id
    }

    /// Every folder with its depth, in outline order - for "Move to" menus.
    func folderOutline() -> [(folder: NoteFolder, depth: Int)] {
        var result: [(folder: NoteFolder, depth: Int)] = []
        var seen = Set<UUID>()
        func walk(_ parent: UUID?, _ depth: Int) {
            for folder in subfolders(of: parent) where seen.insert(folder.id).inserted {
                result.append((folder: folder, depth: depth))
                walk(folder.id, depth + 1)
            }
        }
        walk(nil, 0)
        return result
    }

    /// The number of notes in a folder and everything inside it.
    func count(in folderId: UUID) -> Int {
        var ids = Set<UUID>([folderId])
        var grew = true
        while grew {
            let more = folders.filter { f in f.parentId.map { ids.contains($0) } ?? false }.map(\.id)
            let before = ids.count
            ids.formUnion(more)
            grew = ids.count > before
        }
        return notes.filter { n in n.folderId.map { ids.contains($0) } ?? false }.count
    }

    // MARK: the board

    /// The next free-looking spot on the board: a golden-angle spiral out
    /// from the centre, one turn step per note.
    private func nextBoardSpot() -> (x: Double, y: Double) {
        let n = Double(notes.count)
        let angle = n * 2.399963
        let radius = 90 * n.squareRoot()
        return (radius * cos(angle), radius * sin(angle))
    }
}
