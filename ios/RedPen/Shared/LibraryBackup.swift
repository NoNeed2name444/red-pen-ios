import Foundation

/// One file that holds everything: every set, the review schedule, the
/// progress and answer history, the notes, the study log, the settings, and
/// (if wanted) the lecture files and recordings - so a lost phone, a reset or
/// a move to another device costs nothing, with no account and no Pro.
///
/// The file is an ordinary zip (MiniZip, stored), with JSON inside that any
/// computer can open - which is also what "take my data with me" means:
///
///     manifest.json      what this is, when it was made, what is in it
///     library.json       sets, folders (and any set a newer version wrote)
///     progress.json      quiz positions, flags, answer history, mistakes, rules
///     reviews.json       the schedule, by card id
///     notes.json         the Ideas notes and folders
///     studylog.json      how much was done each day
///     settings.plist     this app's own preferences (never sign-in or keys)
///     files/sources/     lecture files (PDF, Word, PowerPoint)
///     files/lectures/    lecture recordings, by set id
///     files/other/       the smaller stores (reasoning, voice, accuracy...)
///
/// Restoring MERGES, the way a shared set is received (SetImport): nothing on
/// this phone is overwritten or deleted. A set already here unchanged is left
/// alone; one that differs comes in beside it as "(from backup)"; one that was
/// deleted here comes back under a new id, so the deletion that is still
/// travelling to other devices cannot take it away again. Schedules follow
/// their cards; notes, settings and files fill in only what is missing.
///
/// This file is the pure part - the format and the merge - so it is tested.
/// LibraryBackupRunner does the reading and writing for the app.
enum LibraryBackup {

    static let format = "stethoscore-backup"

    /// Dates as ISO 8601, the way every file of the app writes them.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let version = 1

    /// Where the date of the last backup is kept.
    static let lastBackupKey = "backup.lastDate"

    enum Name {
        static let manifest = "manifest.json"
        static let library = "library.json"
        static let progress = "progress.json"
        static let reviews = "reviews.json"
        static let notes = "notes.json"
        static let studyLog = "studylog.json"
        static let settings = "settings.plist"
        static let sources = "files/sources/"
        static let lectures = "files/lectures/"
        static let other = "files/other/"
    }

    enum Failure: LocalizedError, Equatable {
        case notABackup, newerVersion, unreadable
        var errorDescription: String? {
            switch self {
            case .notABackup: return "That file isn\u{2019}t a backup made by this app."
            case .newerVersion: return "That backup was made by a newer version of the app. Update the app, then restore it."
            case .unreadable: return "That backup couldn\u{2019}t be read \u{2014} it may be damaged or incomplete."
            }
        }
    }

    struct Counts: Codable, Equatable {
        var sets = 0
        var cards = 0
        var questions = 0
        var notes = 0
        var scheduled = 0
        var studyDays = 0
        var files = 0
    }

    struct Manifest: Codable, Equatable {
        var format: String = LibraryBackup.format
        var version: Int = LibraryBackup.version
        var createdAt: Date
        var app: String
        var counts: Counts
    }

    /// The library as a backup holds it.
    struct Library: Codable {
        var library: [StudySet]
        var folders: [StudyFolder]
        /// Sets a newer version of the app wrote, kept as their JSON.
        var unread: [String]?

        init(library: [StudySet], folders: [StudyFolder], unread: [String]? = nil) {
            self.library = library
            self.folders = folders
            self.unread = unread
        }

        private enum Keys: String, CodingKey { case library, folders, unread }

        /// Read tolerantly: a set this version cannot decode is kept as text
        /// rather than failing the whole restore.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            let raw = (try? c.decode([Tolerant<StudySet>].self, forKey: .library)) ?? []
            library = raw.compactMap { $0.value }
            folders = ((try? c.decodeIfPresent([Tolerant<StudyFolder>].self, forKey: .folders)) ?? nil)?
                .compactMap { $0.value } ?? []
            unread = (try? c.decodeIfPresent([String].self, forKey: .unread)) ?? nil
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(library, forKey: .library)
            try c.encode(folders, forKey: .folders)
            try c.encodeIfPresent(unread, forKey: .unread)
        }
    }

    struct Tolerant<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    static func counts(of library: [StudySet], notes: Int, scheduled: Int, studyDays: Int, files: Int) -> Counts {
        var counts = Counts()
        counts.sets = library.count
        counts.cards = library.reduce(0) { $0 + $1.cards.count }
        counts.questions = library.reduce(0) { $0 + $1.questions.count }
        counts.notes = notes
        counts.scheduled = scheduled
        counts.studyDays = studyDays
        counts.files = files
        return counts
    }

    /// Whether a manifest is one this version can restore.
    static func check(_ manifest: Manifest) throws {
        guard manifest.format == format else { throw Failure.notABackup }
        guard manifest.version <= version else { throw Failure.newerVersion }
    }

    // MARK: - settings

    /// The preferences worth carrying over: this app's own, by the prefixes
    /// its keys use. Never the sign-in session, API keys or provider lists
    /// (which can hold a key), sync bookkeeping, or the backup date itself.
    static let settingPrefixes: [String] = [
        "exam", "reminder.", "learn.", "vignette.", "cramdown.", "anki.", "accuracy.", "voice.",
        "study.", "graphics", "notesReadAsMarkdown", "llm.choice.", "llm.checkGenerated", "examples.",
        "review.", "stethoscore.",
    ]
    static let settingBlocklist: [String] = [
        "session", "token", "secret", "password", "apikey", "api_key", "llm.providers", "sync",
        "account", "backup.", "device", "owner",
    ]

    static func keepsSetting(_ key: String) -> Bool {
        let lower = key.lowercased()
        if settingBlocklist.contains(where: { lower.contains($0) }) { return false }
        return settingPrefixes.contains { key.hasPrefix($0) }
    }

    /// The settings to back up, from everything in the defaults.
    static func settings(from all: [String: Any]) -> [String: Any] {
        var kept: [String: Any] = [:]
        for (key, value) in all where keepsSetting(key) && PropertyListSerialization.propertyList(value, isValidFor: .binary) {
            kept[key] = value
        }
        return kept
    }

    /// Which backed-up settings to apply: those this phone has no value for.
    /// A restore adds; it does not undo choices made here since.
    static func settingsToApply(_ backup: [String: Any], existing: Set<String>) -> [String: Any] {
        backup.filter { keepsSetting($0.key) && !existing.contains($0.key) }
    }

    // MARK: - merging a library

    struct Plan {
        /// Sets to add, ready as they are.
        var sets: [StudySet] = []
        /// Folders to add.
        var folders: [StudyFolder] = []
        /// Sets that came back under a new id (deleted here, or a copy):
        /// old id → new, for their recordings and resume positions.
        var setIDs: [UUID: UUID] = [:]
        /// Cards and questions whose id changed: old → new, so their
        /// schedule follows them.
        var itemIDs: [UUID: UUID] = [:]
        /// Items whose schedule stays with the copy already here.
        var sharedItems: Set<UUID> = []
        var unchanged = 0
        var copies = 0
        var returned = 0
        var added = 0
    }

    /// How a backup's sets and folders join this library.
    ///
    /// `samePictures` compares two sets' pictures (BlobRefs.samePictures in
    /// the app - a picture filled in by sync is still the same picture).
    static func plan(backup: Library, library: [StudySet], folders: [StudyFolder],
                     deleted: Set<UUID>, now: Date = Date(),
                     samePictures: ([String], [String]) -> Bool = { $0 == $1 }) -> Plan {
        var plan = Plan()
        // folders: by id, or onto a folder here with the same name
        var folderIDs: [UUID: UUID] = [:]
        var known = Set(folders.map(\.id))
        for folder in backup.folders {
            if known.contains(folder.id) {
                folderIDs[folder.id] = folder.id
            } else if let same = folders.first(where: { $0.name.caseInsensitiveCompare(folder.name) == .orderedSame }) {
                folderIDs[folder.id] = same.id
            } else if deleted.contains(folder.id) {
                // deleted here: back under a new id, so the tombstone that
                // is still syncing cannot delete it again
                var fresh = folder
                fresh.id = UUID()
                plan.folders.append(fresh)
                folderIDs[folder.id] = fresh.id
                known.insert(fresh.id)
            } else {
                plan.folders.append(folder)
                folderIDs[folder.id] = folder.id
                known.insert(folder.id)
            }
        }
        var taken = Set<UUID>()
        for set in library { taken.formUnion(set.itemIDs) }
        let current = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for incoming in backup.library {
            var set = incoming
            set.folderId = set.folderId.flatMap { folderIDs[$0] }
            if let here = current[set.id] {
                if same(set, here, samePictures: samePictures) {
                    plan.unchanged += 1
                    continue
                }
                // both kept: the backup's version beside this one
                let copy = renewed(set, avoiding: taken, plan: &plan)
                var named = copy
                named.id = UUID()
                named.name = set.name + " (from backup)"
                named.updatedAt = now
                plan.setIDs[set.id] = named.id
                taken.formUnion(named.itemIDs)
                plan.sets.append(named)
                plan.copies += 1
                continue
            }
            var fresh = renewed(set, avoiding: taken, plan: &plan)
            if deleted.contains(set.id) {
                fresh.id = UUID()
                fresh.updatedAt = now
                plan.setIDs[set.id] = fresh.id
                plan.returned += 1
            } else {
                plan.added += 1
            }
            taken.formUnion(fresh.itemIDs)
            plan.sets.append(fresh)
        }
        return plan
    }

    /// Two versions of one set alike, their stamps aside.
    static func same(_ a: StudySet, _ b: StudySet, samePictures: ([String], [String]) -> Bool) -> Bool {
        var left = a
        let right = b
        left.updatedAt = right.updatedAt
        left.createdAt = right.createdAt
        left.folderId = right.folderId
        guard samePictures(left.images, right.images) else { return false }
        left.images = right.images
        return left == right
    }

    /// The set with a new id for every item already in this library - and
    /// the change written down, so each schedule follows its card or stays
    /// where it is.
    static func renewed(_ set: StudySet, avoiding taken: Set<UUID>, plan: inout Plan) -> StudySet {
        var out = set
        func fresh(_ id: UUID) -> UUID {
            guard taken.contains(id) else { return id }
            let new = UUID()
            plan.itemIDs[id] = new
            plan.sharedItems.insert(id)
            return new
        }
        out.cards = set.cards.map { var c = $0; c.id = fresh(c.id); return c }
        out.questions = set.questions.map { var q = $0; q.id = fresh(q.id); return q }
        out.qaCards = set.qaCards.map { var c = $0; c.id = fresh(c.id); return c }
        out.osceChecklists = set.osceChecklists.map { var c = $0; c.id = fresh(c.id); return c }
        out.narrateSegments = set.narrateSegments.map { var s = $0; s.id = fresh(s.id); return s }
        return out
    }

    /// A backup's schedule for the cards it brought: records for cards
    /// already here (the copy here keeps its own) left out.
    static func schedule<Record>(_ records: [UUID: Record], plan: Plan) -> [UUID: Record] {
        var out: [UUID: Record] = [:]
        for (id, record) in records where !plan.sharedItems.contains(id) {
            out[id] = record
        }
        return out
    }

    /// Items from a backup that this list does not have yet, by id.
    static func missing<T: Identifiable>(_ backup: [T], in mine: [T]) -> [T] {
        let have = Set(mine.map(\.id))
        return backup.filter { !have.contains($0.id) }
    }

    /// Two study logs as one: the larger count for each day.
    static func mergeDays(_ mine: [String: Int], _ backup: [String: Int]) -> [String: Int] {
        mine.merging(backup) { max($0, $1) }
    }

    /// Names inside the zip for a folder of files - only plain file names,
    /// never a path that climbs out of the folder it is restored into.
    static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255, name != ".", name != ".." else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }

    /// "Stethoscore Backup 2026-09-25.stethoscorebackup" - the app's own
    /// document type, so Files, Mail and AirDrop offer "Open in Stethoscore".
    /// (Restore still reads backups made as .zip.)
    /// The backup document type's extension (ImportKind.backupExtension,
    /// declared in project.yml).
    static let fileExtension = "stethoscorebackup"

    static func fileName(app: String, date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let cleaned = app.replacingOccurrences(of: "[^A-Za-z0-9 ]", with: "", options: .regularExpression)
        let base = cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "Library" : cleaned
        return "\(base) Backup \(day).\(fileExtension)"
    }

    // MARK: - the archive

    /// A backup, opened: its manifest checked, its parts read on request.
    struct Archive {
        let data: Data
        let entries: [String: Zip.Entry]
        let manifest: Manifest

        init(url: URL) throws {
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { throw Failure.unreadable }
            try self.init(data: data)
        }

        init(data: Data) throws {
            self.data = data
            var entries: [String: Zip.Entry] = [:]
            for entry in Zip.directory(of: data) where entries[entry.name] == nil { entries[entry.name] = entry }
            self.entries = entries
            guard let entry = entries[Name.manifest] else { throw Failure.notABackup }
            let body = Archive.read(entry, in: data, limit: 1 << 20)
            guard let body, let manifest = try? LibraryBackup.decoder.decode(Manifest.self, from: body) else {
                throw Failure.notABackup
            }
            try LibraryBackup.check(manifest)
            self.manifest = manifest
        }

        func part(_ name: String, limit: Int = 1 << 30) -> Data? {
            guard let entry = entries[name] else { return nil }
            return Archive.read(entry, in: data, limit: limit)
        }

        func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let body = part(name) else { return nil }
            return try? LibraryBackup.decoder.decode(type, from: body)
        }

        /// The files under a folder in the zip, by their plain file name.
        func files(under prefix: String) -> [(name: String, entry: Zip.Entry)] {
            entries.compactMap { key, entry -> (name: String, entry: Zip.Entry)? in
                guard key.hasPrefix(prefix) else { return nil }
                let name = String(key.dropFirst(prefix.count))
                return LibraryBackup.isSafeFileName(name) ? (name, entry) : nil
            }.sorted { $0.name < $1.name }
        }

        /// One file written out, a piece at a time for a stored entry.
        func extract(_ entry: Zip.Entry, to url: URL) throws {
            guard entry.dataEnd <= data.count else { throw Failure.unreadable }
            if entry.method != 0 {
                guard let body = Archive.read(entry, in: data, limit: 2 << 30) else { throw Failure.unreadable }
                try body.write(to: url, options: .atomic)
                return
            }
            let temp = url.deletingLastPathComponent()
                .appendingPathComponent(".restoring-\(UUID().uuidString)")
            guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw Failure.unreadable }
            do {
                let handle = try FileHandle(forWritingTo: temp)
                var at = entry.dataStart
                while at < entry.dataEnd {
                    let stop = min(at + (4 << 20), entry.dataEnd)
                    try handle.write(contentsOf: data[at..<stop])
                    at = stop
                }
                try handle.close()
                try FileManager.default.moveItem(at: temp, to: url)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw Failure.unreadable
            }
        }

        static func read(_ entry: Zip.Entry, in data: Data, limit: Int) -> Data? {
            guard entry.dataEnd <= data.count else { return nil }
            if entry.method == 0 {
                guard entry.compressed <= limit else { return nil }
                return data.subdata(in: entry.dataStart..<entry.dataEnd)
            }
            let limits = Zip.Limits(entryBytes: limit, totalBytes: limit, ratio: 1_100)
            return Zip.contents(of: entry, in: data, limits: limits, budget: limit).body
        }
    }
}
