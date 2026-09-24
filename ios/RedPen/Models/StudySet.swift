import Foundation

/// Which study mode a saved set belongs to. The web app's `state.library`
/// holds both kinds together, distinguished by a `kind` field the same way.
enum StudySetKind: String, Codable, CaseIterable, Identifiable {
    case mcq, anki, book, qa, osce, narrate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mcq: return "MCQ"
        case .anki: return "Cards"
        case .book: return "Textbook"
        case .qa: return "Cases"
        case .osce: return "OSCE"
        case .narrate: return "Narrate"
        }
    }
    var emoji: String {
        switch self {
        case .mcq: return "📝"
        case .anki: return "🗂️"
        case .book: return "📖"
        case .qa: return "🩺"
        case .osce: return "✅"
        case .narrate: return "🎙️"
        }
    }
}

/// One saved set in the library — the native equivalent of one entry in the
/// web app's `state.library` array (see `loadLibrary()` / `renderLibrary()`).
/// A set owns either `questions` (mcq) or `cards` (anki), never both, plus
/// the shared image pool either mode's items may reference by index.
struct StudySet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var subject: String = "General"
    var kind: StudySetKind
    var createdAt: Date = Date()
    /// When this set's contents last actually changed, on the device that
    /// changed them. Sync uses it to settle which of two edits is the later
    /// one; it is stamped only when something really differs, so re-saving an
    /// unchanged set does not make every other device think it moved.
    var updatedAt: Date = Date()
    var folderId: UUID? = nil

    var questions: [MCQQuestion] = []
    var cards: [AnkiCard] = []
    /// "book": the whole textbook as Markdown; split into pages at headings
    /// the way `splitBookIntoPages()` does in the web app.
    var bookMarkdown: String = ""
    /// "qa": the Cases cards.
    var qaCards: [QACard] = []
    /// "osce": one or more station checklists, worked through in order.
    var osceChecklists: [OsceChecklist] = []
    /// "narrate": a lecture transcript read line by line at a reading pace.
    var narrateSegments: [NarrateSegment] = []
    /// Base64-encoded image data (`data:` URI payloads), indexed the same
    /// way `state.images` / `state.ankiImages` are in the web app.
    var images: [String] = []
    /// The lectures this set was made from, kept so they can be read again.
    /// Empty for every set made before sources were kept, and for any set typed
    /// in by hand - so nothing may assume there is one.
    var sources: [SourceDoc] = []

    var itemCount: Int {
        switch kind {
        case .mcq: return questions.count
        case .anki: return cards.count
        case .book: return BookPages.pageCount(bookMarkdown)
        case .qa: return qaCards.count
        case .osce: return osceChecklists.reduce(0) { $0 + $1.steps.count }
        case .narrate: return narrateSegments.count
        }
    }
    var itemNoun: String {
        switch kind {
        case .book: return "page"
        case .mcq: return "question"
        case .osce: return "step"
        case .narrate: return "line"
        default: return "card"
        }
    }
}

/// A library folder — mirrors `state.folders` / `folderId` grouping in the
/// web app's library view. Only a flat one-level grouping, same as there.
struct StudyFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var updatedAt: Date = Date()
}

/// Read tolerantly: a set written by an older or newer version of the app -
/// on this device, or arriving by sync from the other one - may lack a field
/// this version has. Swift's own decoding would then refuse the whole set
/// (and a whole library with it); here a missing field takes its default.
extension StudySet {
    private enum Keys: String, CodingKey {
        case id, name, subject, kind, createdAt, updatedAt, folderId, questions, cards,
             bookMarkdown, qaCards, osceChecklists, narrateSegments, images, sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled",
                  kind: try c.decode(StudySetKind.self, forKey: .kind))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? id
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? subject
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? createdAt
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        questions = try c.decodeIfPresent([MCQQuestion].self, forKey: .questions) ?? []
        cards = try c.decodeIfPresent([AnkiCard].self, forKey: .cards) ?? []
        bookMarkdown = try c.decodeIfPresent(String.self, forKey: .bookMarkdown) ?? ""
        qaCards = try c.decodeIfPresent([QACard].self, forKey: .qaCards) ?? []
        osceChecklists = try c.decodeIfPresent([OsceChecklist].self, forKey: .osceChecklists) ?? []
        narrateSegments = try c.decodeIfPresent([NarrateSegment].self, forKey: .narrateSegments) ?? []
        images = try c.decodeIfPresent([String].self, forKey: .images) ?? []
        sources = try c.decodeIfPresent([SourceDoc].self, forKey: .sources) ?? []
    }
}

