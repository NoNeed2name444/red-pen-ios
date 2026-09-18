import Foundation

/// Which study mode a saved set belongs to. The web app's `state.library`
/// holds both kinds together, distinguished by a `kind` field the same way.
enum StudySetKind: String, Codable, CaseIterable, Identifiable {
    case mcq, anki, book, qa, osce, narrate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mcq: return "MCQ"
        case .anki: return "Anki"
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
        case .book: return BookPages.split(bookMarkdown).count
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
