import Foundation

/// The copies a store puts aside before it writes over a file it could not
/// fully read, and the lossy reading that makes those copies rarer.
///
/// A copy nobody can reach is no better than none: they sit in the app's own
/// folders, which the Files app does not show. Settings > Your data lists
/// them and shares them (LibraryDataSettingsSection), so a student can save
/// them or send them with a support message.
enum RecoveryFiles {

    /// The names the stores give their copies (Store.setAside, ReviewStore,
    /// NoteStore), each followed by "-<seconds>.json".
    static let prefixes: [String] = [
        "library-unreadable-", "library-partly-unreadable-", "progress-unreadable-",
        "reviews-unreadable-", "reviews-partly-unreadable-",
        "notes-unreadable-", "notes-partly-unreadable-",
    ]

    /// Where the stores keep their files: Documents (library, progress,
    /// schedule) and Application Support (notes).
    static var folders: [URL] {
        let manager = FileManager.default
        return [manager.urls(for: .documentDirectory, in: .userDomainMask)[0],
                manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]]
    }

    /// Every copy in those folders, newest first.
    static func copies(in folders: [URL] = folders) -> [URL] {
        var found: [(url: URL, stamp: Int)] = []
        for folder in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names {
                guard let prefix = prefixes.first(where: { name.hasPrefix($0) }), name.hasSuffix(".json") else { continue }
                let stamp = Int(name.dropFirst(prefix.count).dropLast(".json".count)) ?? 0
                found.append((folder.appendingPathComponent(name), stamp))
            }
        }
        return found.sorted { $0.stamp > $1.stamp }.map(\.url)
    }

    /// A copy of `url` beside it, named for what it is, before anything can
    /// write over it. Not again when a copy of the same size is already there,
    /// so a file that stays partly unreadable is not copied every launch.
    @discardableResult
    static func putAside(_ url: URL, as name: String, now: Date = Date()) -> URL? {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int
        let earlier = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        if let size, earlier.contains(where: { file in
            file.hasPrefix(name + "-")
                && (try? manager.attributesOfItem(atPath: folder.appendingPathComponent(file).path))?[.size] as? Int == size
        }) { return nil }
        let aside = folder.appendingPathComponent("\(name)-\(Int(now.timeIntervalSince1970)).json")
        return (try? manager.copyItem(at: url, to: aside)) != nil ? aside : nil
    }

    /// A value read if it can be, and nil - not a failure of everything
    /// around it - if it cannot.
    struct Kept<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// A dictionary by id, read one entry at a time: an entry this version
    /// cannot read costs only itself. Nil when the file is not such a
    /// dictionary at all.
    static func records<V: Decodable>(_ type: V.Type, from data: Data,
                                      decoder: JSONDecoder) -> (values: [UUID: V], skipped: Int)? {
        guard let all = try? decoder.decode([UUID: Kept<V>].self, from: data) else { return nil }
        let values = all.compactMapValues(\.value)
        return (values, all.count - values.count)
    }

    /// A list read one element at a time, the same way.
    static func list<V: Decodable>(_ kept: [Kept<V>]?) -> (values: [V], skipped: Int) {
        let all = kept ?? []
        let values = all.compactMap(\.value)
        return (values, all.count - values.count)
    }
}
