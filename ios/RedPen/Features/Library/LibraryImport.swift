import SwiftUI
import UniformTypeIdentifiers
#if canImport(ImageIO)
import ImageIO
#endif

/// Where the material in New set's "Open a file" step comes from. The choice
/// only sets what the file picker offers and what the step explains; a file
/// is read by what it is, whichever was picked.
enum ImportSource: String, CaseIterable, Identifiable {
    case anki, table, appFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anki: return "Anki deck"
        case .table: return "Quizlet / CSV"
        case .appFile: return "\(Brand.name) file"
        }
    }

    var symbol: String {
        switch self {
        case .anki: return "rectangle.stack"
        case .table: return "tablecells"
        case .appFile: return "doc.badge.arrow.up"
        }
    }

    /// What the step says under the picker.
    var help: String {
        switch self {
        case .anki:
            return "An .apkg deck or .colpkg collection from Anki, AnkiDroid or AnkiMobile \u{2014} AnKing too. Subdecks become sets, tags and pictures come with the cards, and so does where each card was in Anki\u{2019}s schedule. You\u{2019}ll see what\u{2019}s inside before anything is added."
        case .table:
            return "A table with a card on each row: Quizlet\u{2019}s export (term, tab, definition), a CSV from Google Sheets, Excel or Brainscape, or Anki\u{2019}s \u{201C}Notes in Plain Text\u{201D}. Columns named Front, Back, Tags \u{2014} or Question, A, B, C, D, Answer for questions \u{2014} are recognised."
        case .appFile:
            return "A .json set exported from \(Brand.name) (formerly Vignette or CramDown) or the Red Pen web app. It goes straight into your library."
        }
    }

    static let apkg: UTType = UTType(filenameExtension: "apkg") ?? .data
    static let colpkg: UTType = UTType(filenameExtension: "colpkg") ?? .data
    static let tsv: UTType = UTType(filenameExtension: "tsv") ?? .tabSeparatedText

    /// What the file picker offers.
    var types: [UTType] {
        switch self {
        case .anki: return [ImportSource.apkg, ImportSource.colpkg, .zip, .data]
        case .table: return [.commaSeparatedText, .tabSeparatedText, ImportSource.tsv, .plainText, .utf8PlainText, .text]
        case .appFile: return [.json]
        }
    }

    /// What a file is, by its name and first bytes.
    static func of(_ url: URL) -> ImportSource {
        let ext = url.pathExtension.lowercased()
        if ["apkg", "colpkg", "anki2", "anki21", "zip"].contains(ext) { return .anki }
        if ext == "json" { return .appFile }
        if ["csv", "tsv", "txt", "tab", "text"].contains(ext) { return .table }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .table }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 16)) ?? Data()
        if head.starts(with: [0x50, 0x4B]) || head.starts(with: Array("SQLite format 3".utf8)) { return .anki }
        if head.first == UInt8(ascii: "{") { return .appFile }
        return .table
    }
}

/// One figure on the preview: "412" over "cards".
struct ImportFact: Hashable {
    var value: String
    var label: String
    var symbol: String
}

/// What a picked file will add - shown in a glass sheet before anything in
/// the library changes.
struct ImportPreview: Identifiable {
    let id = UUID()
    var title: String
    var source: ImportSource
    var sets: [StudySet]
    /// The folder each set goes in, by name; parallel to `sets`.
    var folderNames: [String?]
    /// Anki's schedule for the cards that had one, by the card's id.
    var progress: [UUID: AnkiProgress] = [:]
    var facts: [ImportFact] = []
    /// Plain sentences about anything left out or changed on the way in.
    var notes: [String] = []

    var itemCount: Int { sets.reduce(0) { $0 + $1.itemCount } }
}

/// Reading a picked file into a preview (off the main actor) and adding a
/// preview to the library (on it, in one change).
enum LibraryImport {

    enum Failure: LocalizedError {
        case nothingReadable, unreadableText
        var errorDescription: String? {
            switch self {
            case .nothingReadable:
                return "Nothing in that file could be read as cards or questions. Each row needs a front and a back \u{2014} or a question, its options and the answer."
            case .unreadableText: return "That file isn\u{2019}t text this app can read."
            }
        }
    }

    /// The preview of a picked file, worked out off the main actor: a deck
    /// of thirty-five thousand notes takes a few seconds and must not freeze
    /// the screen that is showing its progress.
    static func preview(of url: URL, kind: StudySetKind, subject: String) async throws -> ImportPreview {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            switch ImportSource.of(url) {
            case .anki: return try anki(url, subject: subject)
            case .table, .appFile: return try table(url, kind: kind, subject: subject)
            }
        }.value
    }

    /// A file opened from another app, with no kind chosen: a table that
    /// holds questions comes in as questions, anything else as cards.
    static func preview(detecting url: URL, subject: String) async throws -> ImportPreview {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            switch ImportSource.of(url) {
            case .anki: return try anki(url, subject: subject)
            case .table, .appFile: return try table(url, kind: tableKind(url), subject: subject)
            }
        }.value
    }

    /// Questions when the table has question, option and answer columns.
    static func tableKind(_ url: URL) -> StudySetKind {
        guard let data = try? Data(contentsOf: url), let text = decodeText(data) else { return .anki }
        return PlainTextImport.holdsQuestions(text) ? .mcq : .anki
    }

    // MARK: Anki

    static func anki(_ url: URL, subject: String) throws -> ImportPreview {
        let package = try ApkgImport.read(url)
        defer { package.discard() }
        var sets: [StudySet] = []
        var folders: [String?] = []
        var progress: [UUID: AnkiProgress] = [:]
        var cache: [String: String] = [:]
        let stem = url.deletingPathExtension().lastPathComponent
        for planned in package.sets {
            let set = AnkiNoteText.studySet(planned, subject: subject.isEmpty ? "General" : subject,
                                            folderId: nil) { name in
                if let done = cache[name] { return done }
                guard let file = package.media[name], let stored = storedPicture(file) else { return nil }
                cache[name] = stored
                return stored
            }
            guard !set.cards.isEmpty else { continue }
            for card in set.cards {
                if let known = planned.deck.progress[card.id] { progress[card.id] = known }
            }
            sets.append(set)
            folders.append(planned.folder)
        }
        guard !sets.isEmpty else { throw ApkgImport.Failure.empty }
        var preview = ImportPreview(title: stem.isEmpty ? "Anki deck" : stem, source: .anki,
                                    sets: sets, folderNames: folders, progress: progress)
        let cards: Int = sets.reduce(0) { $0 + $1.cards.count }
        let pictures: Int = sets.reduce(0) { $0 + $1.images.count }
        preview.facts.append(ImportFact(value: number(cards), label: cards == 1 ? "card" : "cards", symbol: "rectangle.stack"))
        if pictures > 0 {
            preview.facts.append(ImportFact(value: number(pictures), label: pictures == 1 ? "picture" : "pictures", symbol: "photo"))
        }
        let deckWord: String = package.deckCount == 1 ? "deck" : "subdecks"
        let setWord: String = sets.count == 1 ? "set" : "sets"
        preview.facts.append(ImportFact(value: "\(package.deckCount) \u{2192} \(sets.count)",
                                        label: "\(deckWord) \u{2192} \(setWord)", symbol: "folder"))
        if package.tagCount > 0 {
            preview.facts.append(ImportFact(value: number(package.tagCount), label: "tags", symbol: "tag"))
        }
        if !progress.isEmpty {
            preview.facts.append(ImportFact(value: number(progress.count), label: "with progress", symbol: "calendar"))
        }
        preview.notes = ankiNotes(package, sets: sets, pictures: pictures)
        return preview
    }

    static func ankiNotes(_ package: ApkgImport.Package, sets: [StudySet], pictures: Int) -> [String] {
        var notes: [String] = []
        notes.append("Read as \(package.format): \(number(package.noteCount)) notes, \(number(package.ankiCardCount)) Anki cards. A cloze note is one card here, with every blank in it.")
        let missing: Int = package.pictureCount - pictures
        let leftOut: Int = package.picturesLeftOut + max(0, missing)
        if leftOut > 0 {
            notes.append("\(number(leftOut)) pictures were left out to keep your library quick to open. Their cards keep all their words.")
        }
        if package.occlusionCardsLeftOut > 0 {
            notes.append("\(number(package.occlusionCardsLeftOut)) picture cards were left out because their picture didn\u{2019}t fit.")
        }
        if package.skippedNotes > 0 {
            notes.append("\(number(package.skippedNotes)) notes had nothing this app can show \u{2014} empty, or sound only \u{2014} and were skipped.")
        }
        if sets.contains(where: { $0.name.contains(" of ") && $0.name.hasSuffix(")") }) {
            notes.append("Big decks are split into parts of 3,000 cards so each one opens quickly.")
        }
        return notes
    }

    // MARK: spreadsheets

    static func table(_ url: URL, kind: StudySetKind, subject: String) throws -> ImportPreview {
        guard let data = try? Data(contentsOf: url), let text = decodeText(data) else { throw Failure.unreadableText }
        let name = url.deletingPathExtension().lastPathComponent
        var set = StudySet(name: name.isEmpty ? "Imported" : name, subject: subject.isEmpty ? "General" : subject,
                           kind: kind == .mcq ? .mcq : .anki)
        if kind == .mcq { set.questions = PlainTextImport.parseAnyMCQ(text) }
        if set.questions.isEmpty {
            set.kind = .anki
            set.cards = PlainTextImport.parseAnyCards(text)
        }
        guard set.itemCount > 0 else { throw Failure.nothingReadable }
        var preview = ImportPreview(title: set.name, source: .table, sets: [set], folderNames: [nil])
        let noun: String = set.kind == .mcq ? "questions" : "cards"
        preview.facts.append(ImportFact(value: number(set.itemCount), label: noun, symbol: set.kind == .mcq ? "list.bullet.rectangle" : "rectangle.stack"))
        let tagged: Int = set.cards.filter { $0.tags != nil }.count + set.questions.filter { $0.tags != nil }.count
        if tagged > 0 { preview.facts.append(ImportFact(value: number(tagged), label: "tagged", symbol: "tag")) }
        let rows: Int = PlainTextImport.table(text)?.rows.count ?? set.itemCount
        if rows > set.itemCount {
            preview.notes.append("\(number(rows - set.itemCount)) rows had no front or no back and were skipped.")
        }
        if kind == .mcq && set.kind == .anki {
            preview.notes.append("No question and answer columns were found, so these came in as flashcards.")
        }
        return preview
    }

    /// Text in whatever encoding a spreadsheet saved it in.
    static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: pictures

    /// The longest side a picture is kept at - the size the app's own
    /// diagrams are stored at.
    static let pictureSide = 1_400

    /// A picture as the library stores it: JPEG, no side over 1,400 pixels,
    /// as base64. Nil for anything that is not a picture (a sound, an SVG).
    static func storedPicture(_ file: URL) -> String? {
        #if canImport(ImageIO)
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, options as CFDictionary) else { return nil }
        let thumb: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pictureSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (out as Data).base64EncodedString()
        #else
        return (try? Data(contentsOf: file))?.base64EncodedString()
        #endif
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number)
    }

    // MARK: into the library

    /// Adds a preview's sets to the library in one change, with their
    /// folders (one already here with the same name is used) and Anki's
    /// schedule for the cards that had one. Returns how many sets came in.
    @MainActor
    @discardableResult
    static func commit(_ preview: ImportPreview, store: Store, reviews: ReviewStore, into folder: UUID? = nil) -> Int {
        var folderIDs: [String: UUID] = [:]
        var newFolders: [StudyFolder] = []
        for name in preview.folderNames.compactMap({ $0 }) where folderIDs[name] == nil {
            if let here = store.folders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                folderIDs[name] = here.id
            } else {
                let made = StudyFolder(name: name)
                newFolders.append(made)
                folderIDs[name] = made.id
            }
        }
        if !newFolders.isEmpty { store.folders.append(contentsOf: newFolders) }
        var sets: [StudySet] = []
        for (index, set) in preview.sets.enumerated() {
            var placed = set
            let name: String? = preview.folderNames.indices.contains(index) ? preview.folderNames[index] : nil
            placed.folderId = name.flatMap { folderIDs[$0] } ?? folder
            sets.append(placed)
        }
        store.addSets(sets)
        if !preview.progress.isEmpty {
            reviews.merge(records(preview.progress))
        }
        return sets.count
    }

    /// Anki's schedule as the app's own records. A card counts as introduced
    /// when it was last seen, not today, so bringing a reviewed deck over
    /// never uses up today's new-card allowance.
    static func records(_ progress: [UUID: AnkiProgress], now: Date = Date()) -> [UUID: ReviewRecord] {
        var out: [UUID: ReviewRecord] = [:]
        for (id, known) in progress {
            let intervalMin: Double = known.intervalDays * 1_440
            var record = ReviewRecord(due: known.due, intervalMin: intervalMin,
                                      reviews: known.reviews, lapses: known.lapses, ratedAt: now)
            let seen: Date = known.due.addingTimeInterval(-known.intervalDays * 86_400)
            record.introducedAt = min(seen, now.addingTimeInterval(-86_400))
            if known.suspended { record.suspended = true }
            out[id] = record
        }
        return out
    }
}
