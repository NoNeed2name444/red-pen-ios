import Foundation

/// Plain-text import/export shape for a quick hand-authored or scripted set,
/// independent of the JSON `Codable` layout above so it's easy to type by
/// hand. One line per question:
///   Stem | OptionA; OptionB; OptionC; OptionD | correctLetter | Explanation
/// or, for Anki QA cards:
///   Front | bullet1; bullet2 | why (optional)
enum PlainTextImport {

    /// The text's lines, whichever line endings it was written with.
    ///
    /// In Swift "\r\n" is ONE character, so splitting on "\n" does not split
    /// a Windows file at all: a pasted list became one question whose
    /// explanation held the rest of the file, and everything else was lost.
    static func lines(_ text: String, keepingEmpty: Bool = false) -> [Substring] {
        let unix = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unix.split(separator: "\n", omittingEmptySubsequences: !keepingEmpty)
    }

    /// The option a letter names: A is 0, B is 1. Nil for anything that is
    /// not a letter from A to Z, rather than quietly A - a blank or a
    /// full-width letter keyed as A marks the student wrong for the right answer.
    static func optionIndex(_ field: String) -> Int? {
        guard let first = field.trimmingCharacters(in: .whitespaces).first,
              first.isLetter, let ascii = first.asciiValue else { return nil }
        // lower-cased by its bit, so "b" and "B" are both 1
        return Int(ascii | 0x20) - 97
    }

    static func parseMCQ(_ text: String) -> [MCQQuestion] {
        lines(text).compactMap { rawLine -> MCQQuestion? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            let options = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let correctIndex = optionIndex(parts[2]) else { return nil }
            let explanation = parts.count >= 4 ? parts[3] : ""
            guard !options.isEmpty, correctIndex < options.count else { return nil }
            return MCQQuestion(stem: parts[0], options: options, correctIndex: correctIndex, explanation: explanation)
        }
    }

    /// Cases: one card per line — Topic | case or recall | Question | answer1; answer2
    /// and, for a clinical case, an optional fifth field: its differential,
    /// `Most likely: X (for: ...; against: ...; test: ...) / Expanded: ... / Can't miss: ...`
    static func parseQA(_ text: String) -> [QACard] {
        lines(text).compactMap { rawLine -> QACard? in
            let parts = rawLine.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4 else { return nil }
            let answers = parts[3].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts[2].isEmpty, !answers.isEmpty else { return nil }
            var card = QACard(topic: parts[0], type: parts[1].lowercased().hasPrefix("case") ? .case : .recall, stem: parts[2], answer: answers)
            if parts.count >= 5 { card.differential = DifferentialTiers.parse(line: parts[4]) }
            return card
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
        for rawLine in lines(text, keepingEmpty: true) {
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
        lines(text).compactMap { rawLine -> NarrateSegment? in
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
        lines(text).compactMap { rawLine -> AnkiCard? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // a cloze line: the sentence with its hidden part as {{c1::...}},
            // then optionally why it matters
            if parts[0].contains("{{c") && parts[0].contains("::") && parts[0].contains("}}") {
                return AnkiCard(type: .cloze, clozeText: parts[0], why: parts.count >= 2 ? parts[1] : "")
            }
            guard parts.count >= 2 else { return nil }
            let bullets = parts[1].components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let why = parts.count >= 3 ? parts[2] : ""
            guard !bullets.isEmpty else { return nil }
            return AnkiCard(type: .qa, front: parts[0], bullets: bullets, why: why)
        }
    }
}

// MARK: - spreadsheets: Quizlet, Brainscape, Google Sheets, Excel, Anki's text export

/// A table of cards pasted or opened as a file: tab-separated (Quizlet's
/// export, a copied spreadsheet), comma- or semicolon-separated (a CSV from
/// Sheets, Excel or Brainscape), with quoted cells that hold commas and line
/// breaks, and Anki's own "Notes in Plain Text" headers (`#separator:tab`,
/// `#tags column:3`). The separator is worked out from the text itself.
///
/// Self-contained on purpose - PlainTextImport is compiled into several test
/// suites, and none of them should need another file for this.
extension PlainTextImport {

    struct Table: Equatable {
        var rows: [[String]]
        var separator: Character
        /// The first row, when it names the columns rather than being a card.
        var header: [String]?
        /// Which column holds tags, when one does.
        var tagsColumn: Int?
    }

    /// The header lines Anki writes at the top of a text export.
    static let ankiHeaderKeys: Set<String> = ["separator", "html", "tags column", "columns", "notetype",
                                             "deck", "notetype column", "deck column", "guid column",
                                             "if matches"]

    /// The separators tried, most specific first.
    static let separators: [Character] = ["\t", ";", ",", "|"]

    /// Whether some text is a table rather than the pipe-separated line
    /// format: most lines hold a tab, or no line holds a pipe and a comma or
    /// semicolon splits every line alike.
    static func looksDelimited(_ text: String) -> Bool {
        let sample = lines(text).prefix(40).map(String.init).filter { !$0.hasPrefix("#") }
        guard !sample.isEmpty else { return false }
        if text.hasPrefix("#separator:") { return true }
        let tabbed = sample.filter { $0.contains("\t") }.count
        if tabbed * 2 >= sample.count { return true }
        if sample.contains(where: { $0.contains("|") }) { return false }
        guard let table = table(text) else { return false }
        return table.separator != "|" && table.rows.contains { $0.count >= 2 }
    }

    /// The text as rows and cells, with its separator and header found.
    static func table(_ text: String) -> Table? {
        var body = text
        if body.hasPrefix("\u{feff}") { body.removeFirst() }
        var declared: Character?
        var tagsColumn: Int?
        var headerNames: [String]?
        // Anki's text export: "#key:value" lines before the notes
        var kept: [Substring] = []
        var inHeader = true
        for line in lines(body, keepingEmpty: true) {
            if inHeader, line.hasPrefix("#"), let colon = line.firstIndex(of: ":"),
               ankiHeaderKeys.contains(line[line.index(after: line.startIndex)..<colon].lowercased()) {
                let key = line[line.index(after: line.startIndex)..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "separator": declared = separatorNamed(value)
                case "tags column": tagsColumn = Int(value).map { $0 - 1 }
                case "columns": headerNames = value.components(separatedBy: CharacterSet(charactersIn: "\t,;|"))
                default: break
                }
                continue
            }
            inHeader = false
            kept.append(line)
        }
        let joined = kept.joined(separator: "\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let separator = declared ?? detectSeparator(joined)
        var rows = cells(joined, separator: separator)
            .map { row in row.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { row in row.contains { !$0.isEmpty } }
        guard !rows.isEmpty else { return nil }
        var header: [String]? = headerNames
        if header == nil, let first = rows.first, rows.count > 1, isHeader(first) {
            header = first
            rows.removeFirst()
        }
        if tagsColumn == nil, let header {
            tagsColumn = header.firstIndex { ["tags", "tag", "labels"].contains(normalized($0)) }
        }
        return Table(rows: rows, separator: separator, header: header, tagsColumn: tagsColumn)
    }

    static func separatorNamed(_ value: String) -> Character? {
        switch value.lowercased() {
        case "tab", "\t": return "\t"
        case "comma", ",": return ","
        case "semicolon", ";": return ";"
        case "pipe", "|": return "|"
        case "colon", ":": return ":"
        case "space", " ": return " "
        default: return value.count == 1 ? value.first : nil
        }
    }

    /// The separator that splits the most lines into the same number of
    /// cells (two or more). Ties go to the earlier in `separators`.
    static func detectSeparator(_ text: String) -> Character {
        var best: Character = "\t"
        var bestScore = -1
        for candidate in separators {
            let rows = cells(text, separator: candidate, limit: 30)
            let counts = rows.map { $0.count }.filter { $0 >= 2 }
            guard !counts.isEmpty else { continue }
            var tally: [Int: Int] = [:]
            for c in counts { tally[c, default: 0] += 1 }
            let common = tally.values.max() ?? 0
            // lines that split alike, less a little for each that did not
            let score = common * 4 - (rows.count - common)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    /// RFC 4180 cells: a quoted cell may hold the separator, line breaks,
    /// and "" for a quote. `limit` stops after that many rows.
    static func cells(_ text: String, separator: Character, limit: Int = .max) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var atCellStart = true
        var chars = text.makeIterator()
        var pending: Character? = nil
        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }
        while let c = nextChar() {
            if quoted {
                if c == "\"" {
                    if let following = nextChar() {
                        if following == "\"" { cell.append("\"") } else { quoted = false; pending = following }
                    } else {
                        quoted = false
                    }
                } else {
                    cell.append(c)
                }
                continue
            }
            if c == "\"" && atCellStart {
                quoted = true
                atCellStart = false
                continue
            }
            if c == separator {
                row.append(cell)
                cell = ""
                atCellStart = true
                continue
            }
            if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(cell)
                rows.append(row)
                if rows.count >= limit { return rows }
                row = []
                cell = ""
                atCellStart = true
                continue
            }
            if !(atCellStart && c == " ") { atCellStart = false }
            cell.append(c)
        }
        if !cell.isEmpty || !row.isEmpty {
            row.append(cell)
            rows.append(row)
        }
        return rows
    }

    private static let headerWords: Set<String> = [
        "front", "back", "term", "definition", "question", "answer", "tags", "tag", "extra", "why",
        "explanation", "notes", "note", "stem", "correct", "key", "options", "choices", "prompt",
        "word", "meaning", "back extra", "text", "a", "b", "c", "d", "e", "option a", "option b",
        "choice a", "choice b", "correct answer", "subject", "topic", "source", "hint",
    ]

    static func normalized(_ cell: String) -> String {
        cell.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":#*"))
    }

    /// A first row that names columns: every cell short, and at least one
    /// of them a column name people use.
    static func isHeader(_ row: [String]) -> Bool {
        let names = row.map(normalized)
        guard names.allSatisfy({ $0.count <= 24 }) else { return false }
        return names.contains { headerWords.contains($0) }
    }

    /// Which column is which, by header name where there is one.
    struct Columns {
        var front = 0
        var back = 1
        var why: Int?
        var tags: Int?
        var question: Int?
        var options: [Int] = []
        var answer: Int?
        var explanation: Int?

        init(_ table: Table) {
            tags = table.tagsColumn
            guard let header = table.header?.map(PlainTextImport.normalized) else { return }
            func find(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
            front = find(["front", "term", "question", "prompt", "word", "stem", "text"]) ?? 0
            back = find(["back", "definition", "answer", "meaning", "correct answer"]) ?? (front == 0 ? 1 : 0)
            why = find(["extra", "why", "explanation", "notes", "note", "back extra", "hint"])
            question = find(["question", "stem", "prompt"])
            answer = find(["correct", "correct answer", "key", "answer"])
            explanation = find(["explanation", "why", "rationale", "notes"])
            let letters = ["a", "b", "c", "d", "e", "f"]
            for (index, name) in header.enumerated() {
                let bare = name.replacingOccurrences(of: "option ", with: "")
                    .replacingOccurrences(of: "choice ", with: "")
                if letters.contains(bare) || name.hasPrefix("option") || name.hasPrefix("choice") {
                    if name != "options" && name != "choices" { options.append(index) }
                }
            }
            if options.isEmpty, let joined = find(["options", "choices"]) { options = [joined] }
        }
    }

    /// A cell as plain text: exported HTML's tags and entities undone.
    static func cellText(_ cell: String) -> String {
        guard cell.contains("<") || cell.contains("&") else { return cell }
        var text = cell
        for br in ["<br>", "<br/>", "<br />", "<BR>", "</div>", "</p>", "</li>"] {
            text = text.replacingOccurrences(of: br, with: "\n")
        }
        text = text.replacingOccurrences(of: "<b>", with: "**").replacingOccurrences(of: "</b>", with: "**")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
                                            ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")]
        for (entity, plain) in entities { text = text.replacingOccurrences(of: entity, with: plain) }
        return text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func tagList(_ cell: String) -> [String]? {
        let splitter: CharacterSet = cell.contains(",") ? CharacterSet(charactersIn: ",") : .whitespaces
        let tags = cell.components(separatedBy: splitter)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return tags.isEmpty ? nil : Array(tags.prefix(20))
    }

    /// Flashcards from a table: front and back (a front holding
    /// `{{c1::...}}` makes a cloze card), the "why", and the tags.
    static func delimitedCards(_ text: String) -> [AnkiCard] {
        guard let table = table(text) else { return [] }
        let columns = Columns(table)
        return table.rows.compactMap { row -> AnkiCard? in
            func cell(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return cellText(row[index])
            }
            let front = cell(columns.front)
            let back = cell(columns.back)
            let why = columns.why == columns.back ? "" : cell(columns.why)
            var card: AnkiCard
            if front.contains("{{c") && front.contains("::") && front.contains("}}") {
                card = AnkiCard(type: .cloze, clozeText: front, why: [back, why].filter { !$0.isEmpty }.joined(separator: "\n"))
            } else {
                let bullets = back.components(separatedBy: "\n").filter { !$0.isEmpty }
                guard !front.isEmpty, !bullets.isEmpty else { return nil }
                card = AnkiCard(type: .qa, front: front, bullets: bullets, why: why)
            }
            if let tags = columns.tags, row.indices.contains(tags) { card.tags = tagList(row[tags]) }
            return card
        }
    }

    /// Questions from a table with a question column, option columns (A, B,
    /// C... or one "options" cell split on ";") and the correct answer as a
    /// letter, a number from 1 or the option's own words.
    static func delimitedQuestions(_ text: String) -> [MCQQuestion] {
        guard let table = table(text) else { return [] }
        let columns = Columns(table)
        guard let stemColumn = columns.question ?? (table.header == nil ? 0 : nil) else { return [] }
        return table.rows.compactMap { row -> MCQQuestion? in
            func cell(_ index: Int?) -> String {
                guard let index, row.indices.contains(index) else { return "" }
                return cellText(row[index])
            }
            let stem = cell(stemColumn)
            var options: [String]
            var answerColumn = columns.answer
            if columns.options.count > 1 {
                options = columns.options.map { cell($0) }.filter { !$0.isEmpty }
            } else if columns.options.count == 1 {
                options = cell(columns.options[0]).components(separatedBy: CharacterSet(charactersIn: ";|\n"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                // no header: stem, options..., answer letter, explanation
                guard table.header == nil, row.count >= 4 else { return nil }
                let letterAt = row.indices.dropFirst(2).first { index in
                    let value = row[index].trimmingCharacters(in: .whitespaces)
                    return value.count == 1 && optionIndex(value) != nil
                }
                guard let letterAt else { return nil }
                options = row[1..<letterAt].map(cellText).filter { !$0.isEmpty }
                answerColumn = letterAt
            }
            guard !stem.isEmpty, options.count >= 2 else { return nil }
            let key = cell(answerColumn)
            var correct: Int?
            if key.count == 1, let letter = optionIndex(key), letter < options.count { correct = letter }
            if correct == nil, let number = Int(key), number >= 1, number <= options.count { correct = number - 1 }
            if correct == nil { correct = options.firstIndex { $0.caseInsensitiveCompare(key) == .orderedSame } }
            guard let correct else { return nil }
            var explanationColumn = columns.explanation
            if table.header == nil, let answerColumn, answerColumn + 1 < row.count { explanationColumn = answerColumn + 1 }
            var question = MCQQuestion(stem: stem, options: options, correctIndex: correct,
                                       explanation: cell(explanationColumn))
            if let tags = columns.tags, row.indices.contains(tags) { question.tags = tagList(row[tags]) }
            return question
        }
    }

    /// Cards from whatever was pasted: the line format when it is that, a
    /// table when it is one.
    static func parseAnyCards(_ text: String) -> [AnkiCard] {
        if looksDelimited(text) {
            let table = delimitedCards(text)
            if !table.isEmpty { return table }
        }
        return parseAnkiQA(text)
    }

    /// Questions from whatever was pasted, the same way.
    /// Whether a table opened from another app is a question sheet (a
    /// question column, options and an answer) rather than front/back
    /// cards - so it comes in as questions, as it would through New set's
    /// Questions. A plain two-column Quizlet file is cards.
    static func holdsQuestions(_ text: String) -> Bool {
        looksDelimited(text) && !delimitedQuestions(text).isEmpty
    }

    static func parseAnyMCQ(_ text: String) -> [MCQQuestion] {
        if looksDelimited(text) {
            let table = delimitedQuestions(text)
            if !table.isEmpty { return table }
        }
        return parseMCQ(text)
    }
}
