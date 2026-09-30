import Foundation

/// Making and restoring the whole-library backup (LibraryBackup) for the app:
/// a snapshot of the stores taken on the main actor - cheap, they are values -
/// and every byte encoded, copied, zipped or unzipped off it.
///
/// Files travel as files: lecture PDFs and recordings are streamed into the
/// zip and back out a piece at a time (MiniZip, LibraryBackup.Archive), never
/// read into memory whole.
@MainActor
enum LibraryBackupRunner {

    enum Failure: LocalizedError {
        case tooLarge
        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "Everything together is too big for one backup file. Turn off \u{201C}Include lecture files and recordings\u{201D} and back up again \u{2014} your sets, schedule and notes are small."
            }
        }
    }

    /// Where "Include lecture files and recordings" is kept.
    static let includeFilesKey = "backup.includeFiles"

    static var lastBackup: Date? {
        let stamp = UserDefaults.standard.double(forKey: LibraryBackup.lastBackupKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// What a restore brought in, for the message afterwards.
    struct Report {
        var added = 0
        var returned = 0
        var copies = 0
        var unchanged = 0
        var schedules = 0
        var notes = 0
        var files = 0
        var settings = 0

        var summary: String {
            var parts: [String] = []
            let sets: Int = added + returned
            if sets > 0 { parts.append("\(sets) set\(sets == 1 ? "" : "s") added") }
            if copies > 0 { parts.append("\(copies) that differ kept beside yours as \u{201C}(from backup)\u{201D}") }
            if unchanged > 0 { parts.append("\(unchanged) already here") }
            if schedules > 0 { parts.append("\(schedules) card schedules") }
            if notes > 0 { parts.append("\(notes) notes") }
            if files > 0 { parts.append("\(files) lecture files") }
            if settings > 0 { parts.append("\(settings) settings") }
            if parts.isEmpty { return "Everything in that backup is already on this phone." }
            return parts.joined(separator: ", ") + ". Nothing on this phone was replaced."
        }
    }

    /// The notes file inside a backup.
    struct NoteBackup: Codable {
        var notes: [Note]
        var folders: [NoteFolder]
    }

    // MARK: - backing up

    /// Writes the backup and returns the zip, ready to share or save.
    static func makeBackup(store: Store, reviews: ReviewStore, notes: NoteStore,
                           includeFiles: Bool) async throws -> URL {
        let snapshot = Snapshot(
            library: LibraryBackup.Library(library: store.library, folders: store.folders,
                                           unread: store.unreadSets.isEmpty ? nil : store.unreadSets),
            progress: store.studyBackup(),
            records: reviews.records,
            notes: NoteBackup(notes: notes.notes, folders: notes.folders),
            days: StudyLog.shared.days,
            settings: settingsData(),
            includeFiles: includeFiles,
            app: Brand.name,
            now: Date())
        let url = try await Task.detached(priority: .userInitiated) {
            try write(snapshot)
        }.value
        UserDefaults.standard.set(snapshot.now.timeIntervalSince1970, forKey: LibraryBackup.lastBackupKey)
        return url
    }

    private static func settingsData() -> Data? {
        let kept = LibraryBackup.settings(from: UserDefaults.standard.dictionaryRepresentation())
        return try? PropertyListSerialization.data(fromPropertyList: kept, format: .binary, options: 0)
    }

    struct Snapshot: @unchecked Sendable {
        var library: LibraryBackup.Library
        var progress: Data?
        var records: [UUID: ReviewRecord]
        var notes: NoteBackup
        var days: [String: Int]
        var settings: Data?
        var includeFiles: Bool
        var app: String
        var now: Date
    }

    // MARK: where the app keeps its files

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    nonisolated static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    /// SourceFiles' folder (lecture files, by hash).
    nonisolated static var sourcesFolder: URL { support.appendingPathComponent("RedPenSources", isDirectory: true) }
    /// LectureAudio's folder (recordings, by set id).
    nonisolated static var lecturesFolder: URL { documents.appendingPathComponent("lectures", isDirectory: true) }
    /// BlobCache's folder (pictures by hash, for sets holding references).
    nonisolated static var blobsFolder: URL { support.appendingPathComponent("RedPenBlobs", isDirectory: true) }
    /// The smaller stores: carried for completeness, put back only where
    /// this phone has none.
    nonisolated static var otherFiles: [URL] {
        [documents.appendingPathComponent("vignette-voice-attempts.json"),
         documents.appendingPathComponent("redpen-pronunciations.tsv"),
         support.appendingPathComponent("vignette-reasoning.json"),
         support.appendingPathComponent("accuracy-ledger.json")]
    }

    nonisolated static func write(_ snapshot: Snapshot) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var entries: [(name: String, file: URL)] = []
        func put(_ name: String, _ data: Data?) throws {
            guard let data else { return }
            let file = work.appendingPathComponent("part\(entries.count)")
            try data.write(to: file)
            entries.append((name, file))
        }
        // pictures a sync left as references are put back, so the backup
        // stands on its own
        var library = snapshot.library
        library.library = library.library.map(withPictures)
        let encoder = LibraryBackup.encoder
        try put(LibraryBackup.Name.library, try encoder.encode(library))
        try put(LibraryBackup.Name.progress, snapshot.progress)
        try put(LibraryBackup.Name.reviews, try encoder.encode(snapshot.records))
        try put(LibraryBackup.Name.notes, try encoder.encode(snapshot.notes))
        try put(LibraryBackup.Name.studyLog, try encoder.encode(snapshot.days))
        try put(LibraryBackup.Name.settings, snapshot.settings)
        var fileCount = 0
        if snapshot.includeFiles {
            for (folder, prefix) in [(sourcesFolder, LibraryBackup.Name.sources),
                                     (lecturesFolder, LibraryBackup.Name.lectures)] {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for name in names.sorted() where LibraryBackup.isSafeFileName(name) {
                    entries.append((prefix + name, folder.appendingPathComponent(name)))
                    fileCount += 1
                }
            }
        }
        for file in otherFiles where FileManager.default.fileExists(atPath: file.path) {
            entries.append((LibraryBackup.Name.other + file.lastPathComponent, file))
        }
        let counts = LibraryBackup.counts(of: library.library, notes: snapshot.notes.notes.count,
                                          scheduled: snapshot.records.count, studyDays: snapshot.days.count,
                                          files: fileCount)
        let manifest = LibraryBackup.Manifest(createdAt: snapshot.now, app: snapshot.app, counts: counts)
        let manifestFile = work.appendingPathComponent("manifest")
        try encoder.encode(manifest).write(to: manifestFile)
        entries.insert((LibraryBackup.Name.manifest, manifestFile), at: 0)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(LibraryBackup.fileName(app: snapshot.app, date: snapshot.now))
        do {
            try MiniZip.write(files: entries, to: out)
        } catch MiniZip.Failure.tooLarge {
            throw Failure.tooLarge
        } catch MiniZip.Failure.tooMany {
            throw Failure.tooLarge
        }
        return out
    }

    /// A set with every picture reference filled in from the picture cache.
    nonisolated static func withPictures(_ set: StudySet) -> StudySet {
        guard set.images.contains(where: BlobRefs.isRef) else { return set }
        var blobs: [String: Data] = [:]
        for ref in set.images {
            guard let name = BlobRefs.hash(fromRef: ref) else { continue }
            let file = blobsFolder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: file) { blobs[name] = data }
        }
        var out = set
        out.images = BlobRefs.unpack(set.images, blobs: blobs)
        return out
    }

    // MARK: - restoring

    struct Loaded: @unchecked Sendable {
        var manifest: LibraryBackup.Manifest
        var plan: LibraryBackup.Plan
        var records: [UUID: ReviewRecord]
        var notes: NoteBackup?
        var days: [String: Int]
        var progress: Data?
        var settings: Data?
        var files: Int
    }

    /// Reads a backup and merges it in. The file's parts are read and planned
    /// off the main actor; the library, schedule, notes and log take them on
    /// it, each in one change.
    static func restore(from url: URL, store: Store, reviews: ReviewStore, notes: NoteStore) async throws -> Report {
        let current = store.library
        let folders = store.folders
        let deleted = Set(store.tombstones.keys)
        let loaded = try await Task.detached(priority: .userInitiated) { () throws -> Loaded in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return try load(url, current: current, folders: folders, deleted: deleted)
        }.value

        var report = Report()
        report.added = loaded.plan.added
        report.returned = loaded.plan.returned
        report.copies = loaded.plan.copies
        report.unchanged = loaded.plan.unchanged
        report.files = loaded.files
        let haveFolders = Set(store.folders.map(\.id))
        let newFolders = loaded.plan.folders.filter { !haveFolders.contains($0.id) }
        if !newFolders.isEmpty { store.folders.append(contentsOf: newFolders) }
        store.addSets(loaded.plan.sets)
        let schedule = LibraryBackup.schedule(loaded.records, plan: loaded.plan)
        let before = reviews.records.count
        reviews.merge(schedule)
        report.schedules = max(0, reviews.records.count - before)
        if let backup = loaded.notes {
            report.notes = notes.restore(notes: backup.notes, folders: backup.folders)
        }
        StudyLog.shared.merge(loaded.days)
        if let progress = loaded.progress {
            store.mergeStudy(from: progress, renamed: loaded.plan.setIDs)
        }
        report.settings = applySettings(loaded.settings)
        return report
    }

    nonisolated static func load(_ url: URL, current: [StudySet], folders: [StudyFolder],
                                 deleted: Set<UUID>) throws -> Loaded {
        let archive = try LibraryBackup.Archive(url: url)
        guard let library = archive.decode(LibraryBackup.Library.self, LibraryBackup.Name.library) else {
            throw LibraryBackup.Failure.unreadable
        }
        let plan = LibraryBackup.plan(backup: library, library: current, folders: folders, deleted: deleted,
                                      samePictures: BlobRefs.samePictures)
        let records = archive.decode([UUID: ReviewRecord].self, LibraryBackup.Name.reviews) ?? [:]
        let notes = archive.decode(NoteBackup.self, LibraryBackup.Name.notes)
        let days = archive.decode([String: Int].self, LibraryBackup.Name.studyLog) ?? [:]
        let files = restoreFiles(archive, plan: plan)
        return Loaded(manifest: archive.manifest, plan: plan, records: records, notes: notes, days: days,
                      progress: archive.part(LibraryBackup.Name.progress),
                      settings: archive.part(LibraryBackup.Name.settings, limit: 8 << 20), files: files)
    }

    /// Lecture files and recordings this phone lacks, written out; a
    /// recording follows its set to the id it came back under.
    nonisolated static func restoreFiles(_ archive: LibraryBackup.Archive, plan: LibraryBackup.Plan) -> Int {
        let manager = FileManager.default
        var written = 0
        try? manager.createDirectory(at: sourcesFolder, withIntermediateDirectories: true)
        try? manager.createDirectory(at: lecturesFolder, withIntermediateDirectories: true)
        for file in archive.files(under: LibraryBackup.Name.sources) {
            let target = sourcesFolder.appendingPathComponent(file.name)
            guard !manager.fileExists(atPath: target.path) else { continue }
            if (try? archive.extract(file.entry, to: target)) != nil { written += 1 }
        }
        for file in archive.files(under: LibraryBackup.Name.lectures) {
            var name = file.name
            let stem = (name as NSString).deletingPathExtension
            if let old = UUID(uuidString: stem), let now = plan.setIDs[old] {
                name = now.uuidString + "." + (name as NSString).pathExtension
            }
            let target = lecturesFolder.appendingPathComponent(name)
            guard !manager.fileExists(atPath: target.path) else { continue }
            if (try? archive.extract(file.entry, to: target)) != nil { written += 1 }
        }
        let others = Dictionary(otherFiles.map { ($0.lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
        for file in archive.files(under: LibraryBackup.Name.other) {
            guard let target = others[file.name], !manager.fileExists(atPath: target.path) else { continue }
            try? archive.extract(file.entry, to: target)
        }
        return written
    }

    /// The backup's settings this phone has no value for.
    static func applySettings(_ data: Data?) -> Int {
        guard let data,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: PropertyListSerialization.ReadOptions(), format: nil),
              let backup = plist as? [String: Any] else { return 0 }
        let defaults = UserDefaults.standard
        let existing = Set(defaults.dictionaryRepresentation().keys)
        let apply = LibraryBackup.settingsToApply(backup, existing: existing)
        for (key, value) in apply { defaults.set(value, forKey: key) }
        return apply.count
    }

    // MARK: - export all as Anki

    /// Every card set as one Anki package, a deck per set.
    ///
    /// Only the list is taken on the main thread; every picture file is read
    /// in the background, so a library full of pictures does not freeze the
    /// screen while it is gathered.
    static func exportAllAsAnki(store: Store) async throws -> URL {
        let cache = BlobCache()
        let decks: [StudySet] = store.library.filter { $0.kind == .anki && !$0.cards.isEmpty }
        let folders: [StudyFolder] = store.folders
        let name = "\(Brand.name) - all cards"
        let sets: [StudySet] = await Task.detached(priority: .userInitiated) { () -> [StudySet] in
            decks.map { set in set.images.contains(where: BlobRefs.isRef) ? cache.restore(set) : set }
        }.value
        return try await ApkgExporter.exportAllInBackground(sets, folders: folders, fileName: name)
    }
}
