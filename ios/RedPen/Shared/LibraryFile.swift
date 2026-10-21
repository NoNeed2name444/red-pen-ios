import Foundation

/// The library file, as Store writes and reads it. Foundation only, so its
/// tolerant reading is tested on Linux.
///
/// Read tolerantly: a set this version cannot decode - a newer version's
/// kind, or "qa", the old Cases, now removed - is skipped (and counted)
/// instead of failing the whole library, and `entries(of:at:)` gives it back
/// as the JSON it was written in, for Store to keep (Store.unreadSets).
struct LibraryFile: Codable {
    var library: [StudySet]
    var folders: [StudyFolder]
    var tombstones: [UUID: Date]?
    /// Sets an earlier run could not read, kept as the JSON they were written
    /// in (Store.unreadSets).
    var unread: [String]?
    /// Sets left out on reading because they could not be decoded.
    var skipped = 0
    /// Where in `library` they were, so they can be kept as written.
    var skippedAt: [Int] = []

    enum CodingKeys: String, CodingKey {
        case library, folders, tombstones, unread
    }

    init(library: [StudySet], folders: [StudyFolder], tombstones: [UUID: Date]?, unread: [String]?) {
        self.library = library
        self.folders = folders
        self.tombstones = tombstones
        self.unread = unread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let sets = try c.decode([RecoveryFiles.Kept<StudySet>].self, forKey: .library)
        library = sets.compactMap { $0.value }
        skipped = sets.count - library.count
        skippedAt = sets.indices.filter { sets[$0].value == nil }
        unread = (try? c.decodeIfPresent([String].self, forKey: .unread)) ?? nil
        let kept = (try? c.decodeIfPresent([RecoveryFiles.Kept<StudyFolder>].self, forKey: .folders)) ?? nil
        folders = (kept ?? []).compactMap { $0.value }
        tombstones = (try? c.decodeIfPresent([UUID: Date].self, forKey: .tombstones)) ?? nil
    }

    /// Entries of the file's `library` list, as JSON text - the ones this
    /// version could not read, to be kept as they are.
    static func entries(of data: Data, at indices: [Int]) -> [String] {
        guard !indices.isEmpty,
              let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = top["library"] as? [Any] else { return [] }
        return indices.compactMap { index -> String? in
            guard list.indices.contains(index), JSONSerialization.isValidJSONObject(list[index]),
                  let one = try? JSONSerialization.data(withJSONObject: list[index]) else { return nil }
            return String(data: one, encoding: .utf8)
        }
    }
}
