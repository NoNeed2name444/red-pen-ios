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

    /// OSCE: one or more stations, each a "## Title" line followed by one
    /// step per line until the next "## " heading or the end of the text.
    static func parseOsce(_ text: String) -> [OsceChecklist] {
        var checklists: [OsceChecklist] = []
        var title = ""
        var steps: [String] = []
        func flush() {
            let t = title.trimmingCharacters(in: .whitespaces)
            let s = steps.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !t.isEmpty, !s.isEmpty { checklists.append(OsceChecklist(title: t, steps: s)) }
            steps = []
        }
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("##") {
                flush()
                title = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")).trimmingCharacters(in: .whitespaces)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                steps.append(line)
            }
        }
        flush()
        return checklists
    }

    /// Narrate: one line per segment — "en|Text" or "ar|النص"; the language
    /// tag is optional and defaults to "en".
    static func parseNarrate(_ text: String) -> [NarrateSegment] {
        text.split(separator: "\n").compactMap { rawLine -> NarrateSegment? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|")
            if parts.count >= 2, ["en", "ar"].contains(parts[0].trimmingCharacters(in: .whitespaces).lowercased()) {
                let body = parts.dropFirst().joined(separator: "|").trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return nil }
                return NarrateSegment(text: body, lang: parts[0].trimmingCharacters(in: .whitespaces).lowercased())
            }
            return NarrateSegment(text: line, lang: "en")
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
