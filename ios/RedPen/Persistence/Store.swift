import Foundation
import Combine

/// On-device library storage — the native equivalent of the web app's
/// `state.library` + its IndexedDB persistence (`loadLibrary()` /
/// `saveSetToLibrary()`). Everything lives in a single JSON file in the
/// app's Documents directory; there's no account or sync in this phase,
/// same as the artifact today (localStorage-backed, per browser).
@MainActor
final class Store: ObservableObject {
    @Published var library: [StudySet] = []
    @Published var folders: [StudyFolder] = []

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

    private struct Snapshot: Codable {
        var library: [StudySet]
        var folders: [StudyFolder]
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let snapshot = try? JSONDecoder.redPen.decode(Snapshot.self, from: data) else { return }
        library = snapshot.library
        folders = snapshot.folders
    }

    func save() {
        let snapshot = Snapshot(library: library, folders: folders)
        guard let data = try? JSONEncoder.redPen.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addSet(_ set: StudySet) {
        library.append(set)
        save()
    }

    func deleteSet(_ id: UUID) {
        library.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = library.firstIndex(where: { $0.id == id }) else { return }
        library[idx].name = name
        save()
    }

    func update(_ set: StudySet) {
        guard let idx = library.firstIndex(where: { $0.id == set.id }) else { return }
        library[idx] = set
        save()
    }

    func addFolder(name: String) {
        folders.append(StudyFolder(name: name))
        save()
    }

    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for idx in library.indices where library[idx].folderId == id {
            library[idx].folderId = nil
        }
        save()
    }
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
