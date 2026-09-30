import Foundation
import SQLite3
import Compression

/// Reading an Anki package - `.apkg` (a deck) or `.colpkg` (a whole
/// collection) - into sets of cards.
///
/// Every generation of the format is read:
///   * `collection.anki2` / `collection.anki21`: the SQLite collection, with
///     note types and decks as JSON in the `col` row (Anki 2.0 - 2.1.49, and
///     "Support older Anki versions" exports);
///   * `collection.anki21b`: the same collection compressed with zstd, with
///     note types, fields, templates and decks in tables of their own and
///     protobuf in their config columns; the media list and every picture
///     are zstd frames too (Anki 2.1.50 and later - the default today). A
///     package like that also carries a stub `collection.anki2` holding one
///     note, "Please update to the latest Anki version", which is exactly
///     what an importer that did not look for the newer file would bring in.
///
/// What becomes what: Basic-style notes (any note type, any template - the
/// fields a template shows on the front are the question, the first field it
/// adds on the back is the answer, the rest the "why"), Cloze notes (one card
/// per note, every cN kept), Anki's own image occlusion (23.10+) and the older
/// Image Occlusion Enhanced add-on (one occlusion card per mask, the other
/// masks kept as its covers). Subdecks become sets (AnkiNoteText.plan), tags
/// are kept on every card, and each card's place in Anki's schedule can come
/// with it (AnkiProgress).
///
/// Built for AnKing-sized decks (~35,000 notes, thousands of pictures): the
/// collection is streamed to disk rather than inflated in memory, only the
/// pictures cards actually show are taken out of the archive, and only up to
/// a budget - the library keeps its pictures inside its own file, so thirty
/// thousand of them would make every save of it crawl. Callers run this off
/// the main actor.
enum ApkgImport {

    enum Failure: LocalizedError, Equatable {
        case notAPackage, noCollection, unreadable, empty, tooLarge
        var errorDescription: String? {
            switch self {
            case .notAPackage: return "That file isn\u{2019}t an Anki deck (.apkg) or collection (.colpkg)."
            case .noCollection: return "That Anki file has no cards in it."
            case .unreadable: return "That Anki file couldn\u{2019}t be read \u{2014} it may be damaged. Try exporting it again."
            case .empty: return "Nothing in that deck could be turned into cards."
            case .tooLarge: return "That Anki file is too large to open on this device."
            }
        }
    }

    struct Options {
        /// Pictures on ordinary cards. Occlusion cards always bring theirs -
        /// they are nothing without it.
        var includePictures = true
        /// The most picture bytes one import may add to the library.
        var pictureBudget = 48 << 20
        var maxSets = 60
        var maxCardsPerSet = 3_000
        /// Used for a deck Anki calls "Default".
        var fallbackName = "Anki deck"

        init() {}
    }

    /// What a package holds, ready for the preview and then for the library.
    struct Package {
        var sets: [AnkiNoteText.PlannedSet]
        var noteCount = 0
        var ankiCardCount = 0
        var madeCards = 0
        var skippedNotes = 0
        var pictureCount = 0
        var picturesLeftOut = 0
        var occlusionCardsLeftOut = 0
        var tagCount = 0
        var deckCount = 0
        var reviewedCards = 0
        var format = ""
        /// Picture files taken out of the package, by their Anki name.
        var media: [String: URL] = [:]
        /// Where those files are; `discard()` removes it.
        var folder: URL

        var cardCount: Int { sets.reduce(0) { $0 + $1.deck.cards.count } }

        func discard() { try? FileManager.default.removeItem(at: folder) }
    }

    /// Reads a package file. The URL must already be readable (security
    /// scope is the caller's).
    static func read(_ url: URL, options: Options = Options()) throws -> Package {
        let data: Data
        do { data = try Data(contentsOf: url, options: .alwaysMapped) } catch { throw Failure.unreadable }
        var options = options
        if options.fallbackName == "Anki deck" {
            let stem = url.deletingPathExtension().lastPathComponent
            if !stem.isEmpty { options.fallbackName = stem }
        }
        return try read(data: data, options: options)
    }

    static func read(data: Data, options: Options = Options()) throws -> Package {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("anki-import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            return try readPackage(data, work: work, options: options)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private static func readPackage(_ data: Data, work: URL, options: Options) throws -> Package {
        let database = work.appendingPathComponent("collection.sqlite")
        var archive: Archive?
        var format = ""
        if data.starts(with: Array("SQLite format 3".utf8)) {
            // a bare collection file, handed over as it is
            try data.write(to: database)
            format = "Anki collection"
        } else {
            let opened = Archive(data: data)
            guard !opened.entries.isEmpty else { throw Failure.notAPackage }
            if let entry = opened.entries["collection.anki21b"] {
                let packed = try opened.bytes(of: entry, limit: 1 << 30)
                do { try Zstd.decompress(packed, to: database) } catch { throw Failure.unreadable }
                format = "Anki 2.1.50 or later"
            } else if let entry = opened.entries["collection.anki21"] ?? opened.entries["collection.anki2"] {
                try opened.extract(entry, to: database)
                format = "Anki 2.1"
            } else {
                throw Failure.noCollection
            }
            archive = opened
        }

        // Anki 2.1.50+ leaves its collection in WAL mode, which a read-only
        // open can't read on Apple's SQLite without its -shm file: this is
        // our own copy, so mark it as a plain rollback-journal database
        CollectionReader.leaveWALMode(database)
        let reader = try CollectionReader(path: database.path)
        let media = MediaShelf(archive: archive, folder: work)
        var mapper = NoteMapper(reader: reader, media: media, options: options)
        try mapper.run()
        guard mapper.made > 0 else { throw Failure.empty }
        var package = try mapper.finish(format: format, folder: work)
        package.media = media.extracted
        return package
    }

    // MARK: - the archive

    /// The zip, with each entry's bytes read only when asked for.
    final class Archive {
        let data: Data
        var entries: [String: Zip.Entry] = [:]
        /// The media list: Anki's name for each picture, by entry name.
        lazy var manifest: [String: String] = readManifest()
        /// Real sizes where the list states them (the zstd entries' own sizes
        /// are compressed ones).
        var statedSizes: [String: Int] = [:]
        var modern: Bool { entries["collection.anki21b"] != nil }

        init(data: Data) {
            self.data = data
            for entry in Zip.directory(of: data) where entries[entry.name] == nil {
                entries[entry.name] = entry
            }
        }

        /// One entry whole, in memory: the small ones only.
        func bytes(of entry: Zip.Entry, limit: Int) throws -> Data {
            guard entry.dataEnd <= data.count else { throw Failure.unreadable }
            if entry.method == 0 {
                guard entry.compressed <= limit else { throw Failure.tooLarge }
                return data[entry.dataStart..<entry.dataEnd]
            }
            let limits = Zip.Limits(entryBytes: limit, totalBytes: limit, ratio: 1_100)
            let read = Zip.contents(of: entry, in: data, limits: limits, budget: limit)
            guard let body = read.body else { throw Failure.unreadable }
            return body
        }

        /// One entry to a file, a piece at a time.
        func extract(_ entry: Zip.Entry, to url: URL) throws {
            guard entry.dataEnd <= data.count else { throw Failure.unreadable }
            try? FileManager.default.removeItem(at: url)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw Failure.unreadable }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            if entry.method == 0 {
                var at = entry.dataStart
                while at < entry.dataEnd {
                    let stop = min(at + (4 << 20), entry.dataEnd)
                    try handle.write(contentsOf: data[at..<stop])
                    at = stop
                }
                return
            }
            guard entry.method == 8 else { throw Failure.unreadable }
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let slice = UnsafeRawBufferPointer(rebasing: raw[entry.dataStart..<entry.dataEnd])
                try ApkgImport.inflate(slice, to: handle, limit: 8 << 30)
            }
        }

        private func readManifest() -> [String: String] {
            guard let entry = entries["media"], let raw = try? bytes(of: entry, limit: 64 << 20) else { return [:] }
            if Zstd.isZstd(raw) {
                guard let plain = try? Zstd.decompress(raw, limit: 64 << 20) else { return [:] }
                let listed = ApkgImport.mediaEntries(plain)
                var names: [String: String] = [:]
                for item in listed {
                    names[item.zipName] = item.name
                    statedSizes[item.zipName] = item.size
                }
                return names
            }
            guard let object = try? JSONSerialization.jsonObject(with: raw) as? [String: String] else { return [:] }
            return object
        }
    }

    /// The newer media list: a protobuf `MediaEntries` - repeated entries of
    /// name (1), size (2), sha1 (3) and, rarely, the zip entry's name (255).
    /// An entry's name in the zip is otherwise its position in the list.
    static func mediaEntries(_ data: Data) -> [(zipName: String, name: String, size: Int)] {
        var found: [(zipName: String, name: String, size: Int)] = []
        let bytes = [UInt8](data)
        var reader = Protobuf(bytes: bytes[...])
        var index = 0
        while let field = reader.next() {
            defer { if field.number == 1 { index += 1 } }
            guard field.number == 1, let body = field.bytes else { continue }
            var inner = Protobuf(bytes: body)
            var name = ""
            var size = 0
            var zipName = String(index)
            while let part = inner.next() {
                switch part.number {
                case 1: name = String(decoding: part.bytes ?? [], as: UTF8.self)
                case 2: size = part.varint
                case 255: zipName = String(part.varint)
                default: break
                }
            }
            if !name.isEmpty { found.append((zipName, name, size)) }
        }
        return found
    }

    /// Raw deflate to a file, a chunk at a time.
    static func inflate(_ source: UnsafeRawBufferPointer, to handle: FileHandle, limit: Int) throws {
        guard let base = source.baseAddress, !source.isEmpty else { return }
        let chunk = 1 << 20
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else { throw Failure.unreadable }
        defer { compression_stream_destroy(stream) }
        stream.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
        stream.pointee.src_size = source.count
        var produced = 0
        let finish = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
        while true {
            let unread = stream.pointee.src_size
            stream.pointee.dst_ptr = buffer
            stream.pointee.dst_size = chunk
            let status = compression_stream_process(stream, finish)
            let made = chunk - stream.pointee.dst_size
            produced += made
            if status == COMPRESSION_STATUS_ERROR { throw Failure.unreadable }
            if produced > limit { throw Failure.tooLarge }
            if made > 0 { try handle.write(contentsOf: Data(bytes: buffer, count: made)) }
            if status == COMPRESSION_STATUS_END { return }
            if made == 0 && stream.pointee.src_size == unread { return }
        }
    }

    // MARK: - pictures

    /// The package's pictures, taken out one at a time as cards ask for them.
    final class MediaShelf {
        let archive: Archive?
        let folder: URL
        private(set) var extracted: [String: URL] = [:]
        private var failed: Set<String> = []
        /// Anki's name for a picture → the zip entry holding it.
        private lazy var entryFor: [String: String] = {
            var map: [String: String] = [:]
            for (entry, name) in archive?.manifest ?? [:] { map[name] = entry }
            return map
        }()

        init(archive: Archive?, folder: URL) {
            self.archive = archive
            self.folder = folder.appendingPathComponent("media", isDirectory: true)
            try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        }

        func has(_ name: String) -> Bool { entryFor[name] != nil }

        /// How big a picture really is, without taking it out.
        func size(of name: String) -> Int {
            guard let archive, let key = entryFor[name] else { return 0 }
            if let stated = archive.statedSizes[key], stated > 0 { return stated }
            return archive.entries[key]?.uncompressed ?? 0
        }

        /// The picture as a file, taken out of the archive the first time.
        func file(_ name: String) -> URL? {
            if let done = extracted[name] { return done }
            guard !failed.contains(name), let archive, let key = entryFor[name],
                  let entry = archive.entries[key] else { return nil }
            // named by position, never by the name in the package, which
            // could be "../../Documents/..."
            let ext = (name as NSString).pathExtension.lowercased()
            let safeExt = ext.allSatisfy { $0.isLetter || $0.isNumber } ? ext : "bin"
            let url = folder.appendingPathComponent("m\(extracted.count)").appendingPathExtension(safeExt)
            do {
                if archive.modern {
                    let packed = try archive.bytes(of: entry, limit: 64 << 20)
                    if Zstd.isZstd(packed) {
                        try Zstd.decompress(packed, to: url, limit: 64 << 20)
                    } else {
                        try packed.write(to: url)
                    }
                } else {
                    try archive.extract(entry, to: url)
                }
                extracted[name] = url
                return url
            } catch {
                failed.insert(name)
                return nil
            }
        }

        func text(_ name: String) -> String? {
            guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func pixelSize(_ name: String) -> (w: Double, h: Double)? {
            guard let url = file(name), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 64 * 1024) else { return nil }
            return AnkiNoteText.pixelSize(of: head)
        }
    }

    // MARK: - the collection

    struct NoteType {
        var name: String
        var cloze: Bool
        var fields: [String]
        var templates: [(front: String, back: String)]
    }

    /// The SQLite collection, read only.
    final class CollectionReader {
        let db: OpaquePointer
        var created = Date()
        var noteTypes: [Int64: NoteType] = [:]
        var decks: [Int64: String] = [:]

        init(path: String) throws {
            var handle: OpaquePointer?
            guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
                if let handle { sqlite3_close_v2(handle) }
                throw Failure.unreadable
            }
            db = handle
            // Anki's own collation for names (decks, note types, tags):
            // without it any statement touching those tables fails
            sqlite3_create_collation_v2(handle, "unicase", SQLITE_UTF8, nil,
                                        CollectionReader.unicase, nil)
            do {
                try query("SELECT count(*) FROM notes") { _ in }
                try readCollection()
            } catch {
                throw Failure.unreadable
            }
        }

        deinit { sqlite3_close_v2(db) }

        /// Case-insensitive comparison, as Anki's "unicase" collation.
        static let unicase: @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeRawPointer?,
                                             Int32, UnsafeRawPointer?) -> Int32 = { _, count1, bytes1, count2, bytes2 in
            let first: String = CollectionReader.string(bytes1, count1)
            let second: String = CollectionReader.string(bytes2, count2)
            let order: ComparisonResult = first.caseInsensitiveCompare(second)
            if order == .orderedAscending { return -1 }
            if order == .orderedDescending { return 1 }
            return 0
        }

        private static func string(_ bytes: UnsafeRawPointer?, _ count: Int32) -> String {
            guard let bytes, count > 0 else { return "" }
            let buffer = UnsafeRawBufferPointer(start: bytes, count: Int(count))
            return String(decoding: buffer, as: UTF8.self)
        }

        /// Sets the header's write and read versions (bytes 18 and 19) to 1,
        /// rollback journal, so the file opens read-only without WAL files.
        static func leaveWALMode(_ url: URL) {
            guard let handle = try? FileHandle(forUpdating: url) else { return }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 20), head.count == 20,
                  head.starts(with: Array("SQLite format 3".utf8)) else { return }
            let wal: Bool = head[18] == 2 || head[19] == 2
            guard wal else { return }
            try? handle.seek(toOffset: 18)
            try? handle.write(contentsOf: Data([1, 1]))
        }

        func tableExists(_ name: String) -> Bool {
            var found = false
            try? query("SELECT name FROM sqlite_master WHERE type='table' AND name='\(name)'") { _ in found = true }
            return found
        }

        private func readCollection() throws {
            try query("SELECT crt FROM col LIMIT 1") { row in
                let crt = row.int(0)
                if crt > 0 { self.created = Date(timeIntervalSince1970: TimeInterval(crt)) }
            }
            if tableExists("notetypes") {
                try readModernTypes()
                try query("SELECT id, name FROM decks") { row in
                    self.decks[row.int64(0)] = row.text(1)
                }
            } else {
                try readLegacyTypes()
            }
        }

        private func readModernTypes() throws {
            try query("SELECT id, name, config FROM notetypes") { row in
                let config = row.blob(2)
                var reader = Protobuf(bytes: config[...])
                var kind = 0
                while let field = reader.next() {
                    if field.number == 1 && field.bytes == nil { kind = field.varint }
                }
                self.noteTypes[row.int64(0)] = NoteType(name: row.text(1), cloze: kind == 1, fields: [], templates: [])
            }
            try query("SELECT ntid, ord, name FROM fields ORDER BY ntid, ord") { row in
                self.noteTypes[row.int64(0)]?.fields.append(row.text(2))
            }
            try query("SELECT ntid, ord, config FROM templates ORDER BY ntid, ord") { row in
                var reader = Protobuf(bytes: row.blob(2)[...])
                var front = "", back = ""
                while let field = reader.next() {
                    if field.number == 1 { front = String(decoding: field.bytes ?? [], as: UTF8.self) }
                    if field.number == 2 { back = String(decoding: field.bytes ?? [], as: UTF8.self) }
                }
                self.noteTypes[row.int64(0)]?.templates.append((front, back))
            }
        }

        private func readLegacyTypes() throws {
            var modelsJSON = "", decksJSON = ""
            try query("SELECT models, decks FROM col LIMIT 1") { row in
                modelsJSON = row.text(0)
                decksJSON = row.text(1)
            }
            if let models = (try? JSONSerialization.jsonObject(with: Data(modelsJSON.utf8))) as? [String: Any] {
                for (key, value) in models {
                    guard let model = value as? [String: Any], let id = Int64(key) else { continue }
                    let fields = (model["flds"] as? [[String: Any]] ?? [])
                        .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                        .compactMap { $0["name"] as? String }
                    let templates = (model["tmpls"] as? [[String: Any]] ?? [])
                        .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                        .map { (front: $0["qfmt"] as? String ?? "", back: $0["afmt"] as? String ?? "") }
                    let cloze: Bool = (model["type"] as? Int ?? 0) == 1
                    noteTypes[id] = NoteType(name: model["name"] as? String ?? "", cloze: cloze,
                                             fields: fields, templates: templates)
                }
            }
            if let decks = (try? JSONSerialization.jsonObject(with: Data(decksJSON.utf8))) as? [String: Any] {
                for (key, value) in decks {
                    guard let deck = value as? [String: Any], let id = Int64(key) else { continue }
                    self.decks[id] = deck["name"] as? String ?? ""
                }
            }
        }

        struct Row {
            let statement: OpaquePointer
            func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }
            func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
            func text(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(statement, i) else { return "" }
                return String(cString: c)
            }
            func blob(_ i: Int32) -> [UInt8] {
                let count = Int(sqlite3_column_bytes(statement, i))
                guard count > 0, let p = sqlite3_column_blob(statement, i) else { return [] }
                return [UInt8](UnsafeRawBufferPointer(start: p, count: count))
            }
        }

        func query(_ sql: String, _ each: (Row) throws -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw Failure.unreadable
            }
            defer { sqlite3_finalize(statement) }
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { return }
                guard step == SQLITE_ROW else { throw Failure.unreadable }
                try each(Row(statement: statement))
            }
        }
    }

    // MARK: - notes into cards

    /// One Anki card row, with its note.
    struct CardRow {
        var noteID: Int64
        var deckID: Int64
        var ord: Int
        var type: Int
        var queue: Int
        var due: Int
        var interval: Int
        var reps: Int
        var lapses: Int
        var model: Int64
        var fields: String
        var tags: String
    }

    struct NoteMapper {
        let reader: CollectionReader
        let media: MediaShelf
        let options: Options
        var decks: [Int64: AnkiNoteText.Deck] = [:]
        var deckOrder: [Int64] = []
        /// Pictures occlusion cards need: kept ahead of the rest in the budget.
        var needed: Set<String> = []
        var notes = 0
        var rows = 0
        var made = 0
        var skipped = 0
        var reviewed = 0
        var tags: Set<String> = []
        /// Which fields each template shows, worked out once per note type.
        var shown: [String: (front: [String], back: [String])] = [:]
        var clozeFields: [Int64: String] = [:]

        init(reader: CollectionReader, media: MediaShelf, options: Options) {
            self.reader = reader
            self.media = media
            self.options = options
        }

        mutating func run() throws {
            let sql = """
            SELECT c.nid, CASE WHEN c.odid != 0 THEN c.odid ELSE c.did END, c.ord, c.type, c.queue, c.due, \
            c.ivl, c.reps, c.lapses, n.mid, n.flds, n.tags FROM cards c JOIN notes n ON n.id = c.nid \
            ORDER BY c.nid, c.ord
            """
            var group: [CardRow] = []
            try reader.query(sql) { row in
                let card = CardRow(noteID: row.int64(0), deckID: row.int64(1), ord: row.int(2), type: row.int(3),
                                   queue: row.int(4), due: row.int(5), interval: row.int(6), reps: row.int(7),
                                   lapses: row.int(8), model: row.int64(9), fields: row.text(10), tags: row.text(11))
                if let first = group.first, first.noteID != card.noteID {
                    self.note(group)
                    group.removeAll(keepingCapacity: true)
                }
                group.append(card)
            }
            if !group.isEmpty { note(group) }
        }

        /// One note, with every card Anki made of it.
        mutating func note(_ cards: [CardRow]) {
            guard let first = cards.first else { return }
            notes += 1
            rows += cards.count
            let values = first.fields.components(separatedBy: "\u{1f}")
            guard let type = reader.noteTypes[first.model] else { skipped += 1; return }
            var named: [String: String] = [:]
            for (index, name) in type.fields.enumerated() where index < values.count {
                named[name] = values[index]
            }
            let noteTags = AnkiNoteText.tags(first.tags)
            tags.formUnion(noteTags)
            let before = made
            if type.fields.contains("Question Mask") && type.fields.contains("Image") {
                enhancedOcclusion(cards, named: named, type: type, tags: noteTags)
            } else if isOcclusion(type, named: named) {
                occlusion(cards, named: named, type: type, tags: noteTags)
            } else if type.cloze {
                cloze(cards, named: named, type: type, tags: noteTags)
            } else {
                basic(cards, named: named, type: type, tags: noteTags)
            }
            if made == before { skipped += 1 }
        }

        func isOcclusion(_ type: NoteType, named: [String: String]) -> Bool {
            guard type.cloze else { return false }
            if let field = named["Occlusion"], field.contains("image-occlusion:") { return true }
            return named.values.contains { $0.contains("image-occlusion:") }
        }

        // Basic, reversed, custom: the template says what is asked

        mutating func basic(_ cards: [CardRow], named: [String: String], type: NoteType, tags: [String]) {
            for row in cards {
                let names = fieldNames(type, model: row.model, ord: row.ord)
                let frontNames = names.front
                let backNames = names.back
                var pictures: [String] = []
                var frontLines: [String] = []
                for name in frontNames {
                    let plain = AnkiNoteText.plain(named[name] ?? "")
                    pictures += plain.images
                    if !plain.text.isEmpty { frontLines.append(plain.text) }
                }
                let front = frontLines.joined(separator: "\n")
                guard !front.isEmpty || !pictures.isEmpty else { continue }
                var answer: [String] = []
                var why: [String] = []
                for name in backNames {
                    let plain = AnkiNoteText.plain(named[name] ?? "")
                    pictures += plain.images
                    guard !plain.text.isEmpty else { continue }
                    if answer.isEmpty {
                        let split = AnkiNoteText.bullets(plain.text)
                        answer = split.bullets
                        if !split.rest.isEmpty { why.append(split.rest) }
                    } else {
                        why.append(plain.text)
                    }
                }
                if answer.isEmpty && pictures.isEmpty { continue }
                var card = AnkiCard(type: .qa, front: front.isEmpty ? "What is shown here?" : front,
                                    bullets: answer.isEmpty ? ["(see the picture)"] : answer)
                card.why = AnkiNoteText.clipped(why.joined(separator: "\n"))
                card.tags = tags.isEmpty ? nil : tags
                add(card, row: row, pictures: pictures)
            }
        }

        /// The fields a card's template shows on each side, from the cache.
        mutating func fieldNames(_ type: NoteType, model: Int64, ord: Int) -> (front: [String], back: [String]) {
            let key = "\(model)/\(ord)"
            if let known = shown[key] { return known }
            let template = type.templates.indices.contains(ord) ? type.templates[ord]
                : (type.templates.first ?? (front: "{{\(type.fields.first ?? "")}}", back: ""))
            let front = AnkiNoteText.fieldsShown(in: template.front, front: true)
            let back = AnkiNoteText.fieldsShown(in: template.back, front: false).filter { !front.contains($0) }
            shown[key] = (front, back)
            return (front, back)
        }

        // Cloze: one card per note, every cN in it

        mutating func cloze(_ cards: [CardRow], named: [String: String], type: NoteType, tags: [String]) {
            guard let first = cards.first else { return }
            let template = type.templates.first ?? (front: "", back: "")
            let field: String
            if let known = clozeFields[first.model] {
                field = known
            } else {
                field = AnkiNoteText.clozeField(in: template.front) ?? type.fields.first ?? ""
                clozeFields[first.model] = field
            }
            let plain = AnkiNoteText.plain(named[field] ?? "")
            guard plain.text.contains("{{c"), plain.text.contains("::") else { return }
            var pictures = plain.images
            var why: [String] = []
            let backNames = fieldNames(type, model: first.model, ord: 0).back
            for name in backNames where name != field {
                let extra = AnkiNoteText.plain(named[name] ?? "")
                pictures += extra.images
                if !extra.text.isEmpty && why.count < 2 { why.append(extra.text) }
            }
            var card = AnkiCard(type: .cloze, clozeText: plain.text)
            card.why = AnkiNoteText.clipped(why.joined(separator: "\n"))
            card.tags = tags.isEmpty ? nil : tags
            // the schedule of the card Anki shows first
            let lead = cards.min { $0.ord < $1.ord } ?? first
            add(card, row: lead, pictures: pictures)
        }

        // Anki's own image occlusion: a cloze number per mask

        mutating func occlusion(_ cards: [CardRow], named: [String: String], type: NoteType, tags: [String]) {
            let picture = AnkiNoteText.plain(named["Image"] ?? "").images.first
                ?? named.values.lazy.compactMap { AnkiNoteText.plain($0).images.first }.first
            guard let picture, media.has(picture) else { return }
            let field = named["Occlusion"] ?? named.values.first { $0.contains("image-occlusion:") } ?? ""
            var shapes = AnkiNoteText.occlusions(field)
            if shapes.isEmpty, field.contains("image-occlusion:") {
                // written in pixels, by the earliest version
                shapes = AnkiNoteText.occlusions(field, pixelSize: media.pixelSize(picture))
            }
            guard !shapes.isEmpty else { return }
            var boxes: [Int: OcclusionBox] = [:]
            for (number, parts) in shapes {
                if let box = AnkiNoteText.union(parts) { boxes[number] = box }
            }
            let header = AnkiNoteText.plain(named["Header"] ?? "").text
            let extra = AnkiNoteText.plain(named["Back Extra"] ?? "").text
            let comments = AnkiNoteText.plain(named["Comments"] ?? "").text
            let why = [extra, comments].filter { !$0.isEmpty }.joined(separator: "\n")
            for row in cards {
                let number = row.ord + 1
                guard let target = boxes[number] else { continue }
                var card = AnkiCard(type: .occlusion, front: header)
                card.occlusion = target
                card.siblings = boxes.filter { $0.key != number }.sorted { $0.key < $1.key }.map { $0.value }
                card.why = AnkiNoteText.clipped(why)
                card.tags = tags.isEmpty ? nil : tags
                needed.insert(picture)
                add(card, row: row, pictures: [picture])
            }
        }

        // The Image Occlusion Enhanced add-on: an SVG mask per card

        mutating func enhancedOcclusion(_ cards: [CardRow], named: [String: String], type: NoteType,
                                        tags: [String]) {
            guard let picture = AnkiNoteText.plain(named["Image"] ?? "").images.first, media.has(picture),
                  let maskName = AnkiNoteText.plain(named["Question Mask"] ?? "").images.first,
                  let svg = media.text(maskName), let mask = AnkiNoteText.svgMask(svg) else { return }
            let header = AnkiNoteText.plain(named["Header"] ?? "").text
            var why: [String] = []
            for name in ["Footer", "Remarks", "Sources", "Extra 1", "Extra 2"] {
                let text = AnkiNoteText.plain(named[name] ?? "").text
                if !text.isEmpty { why.append(text) }
            }
            guard let row = cards.first else { return }
            var card = AnkiCard(type: .occlusion, front: header)
            card.occlusion = mask.target
            card.siblings = mask.others
            card.why = AnkiNoteText.clipped(why.joined(separator: "\n"))
            card.tags = tags.isEmpty ? nil : tags
            needed.insert(picture)
            add(card, row: row, pictures: [picture])
        }

        mutating func add(_ card: AnkiCard, row: CardRow, pictures: [String]) {
            var card = card
            if decks[row.deckID] == nil {
                deckOrder.append(row.deckID)
                decks[row.deckID] = AnkiNoteText.Deck(path: path(for: row.deckID))
            }
            guard var deck = decks[row.deckID] else { return }
            decks[row.deckID] = nil
            let shown = pictures.first { media.has($0) }
            if let shown {
                if let at = deck.pictures.firstIndex(of: shown) {
                    card.imageIndex = at
                } else {
                    card.imageIndex = deck.pictures.count
                    deck.pictures.append(shown)
                }
            }
            if let progress = AnkiProgress.from(type: row.type, queue: row.queue, due: row.due,
                                                interval: row.interval, reps: row.reps, lapses: row.lapses,
                                                created: reader.created) {
                deck.progress[card.id] = progress
                reviewed += 1
            }
            deck.cards.append(card)
            decks[row.deckID] = deck
            made += 1
        }

        func path(for deckID: Int64) -> [String] {
            let name = reader.decks[deckID] ?? ""
            var path = AnkiNoteText.deckPath(name)
            if path.isEmpty || path == ["Default"] { path = [options.fallbackName] }
            return path
        }

        /// The pictures kept within the budget, the rest let go, and the decks
        /// planned into sets.
        mutating func finish(format: String, folder: URL) throws -> Package {
            var all: [AnkiNoteText.Deck] = deckOrder.compactMap { decks[$0] }
            // what fits: occlusion pictures first, then the rest in order
            var kept: Set<String> = []
            var spent = 0
            var names: [String] = []
            for deck in all { names += deck.pictures }
            let ordered = names.filter { needed.contains($0) } + names.filter { !needed.contains($0) }
            for name in ordered where !kept.contains(name) {
                let isNeeded = needed.contains(name)
                guard isNeeded || options.includePictures else { continue }
                let size = media.size(of: name)
                guard spent + size <= options.pictureBudget else { continue }
                spent += size
                kept.insert(name)
            }
            var leftOut = Set(names).subtracting(kept).count
            var droppedCards = 0
            for index in all.indices {
                let result = keepOnly(kept, in: all[index])
                all[index] = result.deck
                droppedCards += result.dropped
            }
            // the kept pictures, out of the archive now, before the preview
            for name in kept where media.file(name) == nil { leftOut += 1 }
            var package = Package(sets: AnkiNoteText.plan(all, maxSets: options.maxSets,
                                                          maxCards: options.maxCardsPerSet),
                                  folder: folder)
            guard package.cardCount > 0 else { throw Failure.empty }
            package.noteCount = notes
            package.ankiCardCount = rows
            package.madeCards = package.cardCount
            package.skippedNotes = skipped
            package.pictureCount = kept.count
            package.picturesLeftOut = leftOut
            package.occlusionCardsLeftOut = droppedCards
            package.tagCount = tags.count
            package.deckCount = all.filter { !$0.cards.isEmpty }.count
            package.reviewedCards = all.reduce(0) { $0 + $1.progress.count }
            package.format = format
            return package
        }

        /// A deck with only the pictures in `kept`; an occlusion card whose
        /// picture went is left out, any other card just loses its picture.
        func keepOnly(_ kept: Set<String>, in deck: AnkiNoteText.Deck) -> (deck: AnkiNoteText.Deck, dropped: Int) {
            var out = AnkiNoteText.Deck(path: deck.path)
            var moved: [Int: Int] = [:]
            for (index, name) in deck.pictures.enumerated() where kept.contains(name) {
                moved[index] = out.pictures.count
                out.pictures.append(name)
            }
            var dropped = 0
            for card in deck.cards {
                var copy = card
                if let old = card.imageIndex { copy.imageIndex = moved[old] }
                if card.type == .occlusion && copy.imageIndex == nil { dropped += 1; continue }
                out.cards.append(copy)
                if let progress = deck.progress[card.id] { out.progress[card.id] = progress }
            }
            return (out, dropped)
        }
    }
}

/// The few protobuf wire-format pieces Anki's newer files use: varints and
/// length-delimited fields, read without a schema.
struct Protobuf {
    var bytes: ArraySlice<UInt8>

    struct Field {
        var number: Int
        var varint: Int
        var bytes: ArraySlice<UInt8>?
    }

    mutating func readVarint() -> Int? {
        var value = 0
        var shift = 0
        while let b = bytes.first {
            bytes = bytes.dropFirst()
            value |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { return value }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    mutating func next() -> Field? {
        guard !bytes.isEmpty, let key = readVarint() else { return nil }
        let number = key >> 3
        switch key & 7 {
        case 0:
            guard let v = readVarint() else { return nil }
            return Field(number: number, varint: v, bytes: nil)
        case 1:
            guard bytes.count >= 8 else { return nil }
            bytes = bytes.dropFirst(8)
            return Field(number: number, varint: 0, bytes: nil)
        case 2:
            guard let length = readVarint(), length >= 0, length <= bytes.count else { return nil }
            let body = bytes.prefix(length)
            bytes = bytes.dropFirst(length)
            return Field(number: number, varint: 0, bytes: body)
        case 5:
            guard bytes.count >= 4 else { return nil }
            bytes = bytes.dropFirst(4)
            return Field(number: number, varint: 0, bytes: nil)
        default:
            return nil
        }
    }
}
