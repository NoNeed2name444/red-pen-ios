import Foundation

/// Which study mode a saved set belongs to. The web app's `state.library`
/// holds both kinds together, distinguished by a `kind` field the same way.
enum StudySetKind: String, Codable, CaseIterable, Identifiable {
    case mcq, anki, book, qa
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mcq: return "MCQ"
        case .anki: return "Anki"
        case .book: return "Textbook"
        case .qa: return "Cases"
        }
    }
    var emoji: String {
        switch self {
        case .mcq: return "📝"
        case .anki: return "🗂️"
        case .book: return "📖"
        case .qa: return "🩺"
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
    var folderId: UUID? = nil

    var questions: [MCQQuestion] = []
    var cards: [AnkiCard] = []
    /// "book": the whole textbook as Markdown; split into pages at headings
    /// the way `splitBookIntoPages()` does in the web app.
    var bookMarkdown: String = ""
    /// "qa": the Cases cards.
    var qaCards: [QACard] = []
    /// Base64-encoded image data (`data:` URI payloads), indexed the same
    /// way `state.images` / `state.ankiImages` are in the web app.
    var images: [String] = []

    var itemCount: Int {
        switch kind {
        case .mcq: return questions.count
        case .anki: return cards.count
        case .book: return BookPages.split(bookMarkdown).count
        case .qa: return qaCards.count
        }
    }
    var itemNoun: String { kind == .book ? "page" : kind == .mcq ? "question" : "card" }
}

/// A library folder — mirrors `state.folders` / `folderId` grouping in the
/// web app's library view. Only a flat one-level grouping, same as there.
struct StudyFolder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
}

/// Plain-text import/export shape for a quick hand-authored or scripted set,
/// independent of the JSON `Codable` layout above so it's easy to type by
/// hand. One line per question:
///   Stem | OptionA; OptionB; OptionC; OptionD | correctLetter | Explanation
/// or, for Anki QA cards:
///   Front | bullet1; bullet2 | why (optional)
enum PlainTextImport {
    static func parseMCQ(_ text: String) -> [MCQQuestion] {
        text.split(separator: "\n").compactMap { rawLine -> MCQQuestion? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let options = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let letter = parts[2].uppercased().first
            let correctIndex = letter.flatMap { l in
                l.asciiValue.map { Int($0) - Int(Character("A").asciiValue!) }
            } ?? 0
            let explanation = parts.count >= 4 ? parts[3] : ""
            guard !options.isEmpty, correctIndex >= 0, correctIndex < options.count else { return nil }
            return MCQQuestion(stem: parts[0], options: options, correctIndex: correctIndex, explanation: explanation)
        }
    }

    /// Cases: one card per line — Topic | case or recall | Question | answer1; answer2
    static func parseQA(_ text: String) -> [QACard] {
        text.split(separator: "\n").compactMap { rawLine -> QACard? in
            let parts = rawLine.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else { return nil }
            let answers = parts[3].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts[2].isEmpty, !answers.isEmpty else { return nil }
            return QACard(topic: parts[0], type: parts[1].lowercased().hasPrefix("case") ? .case : .recall, stem: parts[2], answer: answers)
        }
    }

    static func parseAnkiQA(_ text: String) -> [AnkiCard] {
        text.split(separator: "\n").compactMap { rawLine -> AnkiCard? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return nil }
            let bullets = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let why = parts.count >= 3 ? parts[2] : ""
            guard !bullets.isEmpty else { return nil }
            return AnkiCard(type: .qa, front: parts[0], bullets: bullets, why: why)
        }
    }
}
