import Foundation

/// How well the library covers one subtopic.
enum CoverageStatus: String, Codable, CaseIterable {
    /// Plenty of material, some of it practice, and not answered badly.
    case covered
    /// Something is there, but not much, only reading, or answered poorly.
    case thin
    /// Nothing in the library mentions it.
    case notCovered

    var label: String {
        switch self {
        case .covered: return "Covered"
        case .thin: return "Thin"
        case .notCovered: return "Not covered"
        }
    }
}

/// What the engine found for one subtopic.
struct SubtopicCoverage: Identifiable, Hashable {
    let area: String
    let subtopic: SyllabusSubtopic
    /// Items that mention it: questions, cards, cases, stations, pages.
    let evidence: Int
    /// Of those, the ones that test the student rather than being read.
    let practice: Int
    /// Answers given to the matching questions, and how many were right.
    let answered: Int
    let correct: Int
    /// A few of the matching items, shortened, for the AI check to read.
    let samples: [String]
    let status: CoverageStatus

    /// Stable across launches and exams: the area and the subtopic's name.
    var id: String { CoverageEngine.key(area: area, subtopic: subtopic.name) }

    var accuracy: Double? { answered > 0 ? Double(correct) / Double(answered) : nil }
}

/// One area of the blueprint with its subtopics assessed.
struct AreaCoverage: Identifiable, Hashable {
    let area: SyllabusArea
    let subtopics: [SubtopicCoverage]
    var id: String { area.name }

    func count(_ status: CoverageStatus) -> Int { subtopics.filter { $0.status == status }.count }
}

/// Which parts of an exam's blueprint the student's library actually covers.
///
/// Plain keyword matching over everything in the library - set names and
/// subjects, question stems, card fronts, case text, OSCE steps, textbook
/// pages, transcripts and the kept lectures' page text - counted per
/// subtopic, plus how the student did on the matching questions.
///
/// Deliberately simple and explainable: "12 items mention it, 3 of them
/// questions, 58% right" is something a student can check, and a keyword that
/// misfires shows up as an obviously wrong count rather than a mystery.
///
/// Pure Foundation, so it can be tested with a hand-made library.
enum CoverageEngine {

    /// At least this many items, and this many of them practice, to count as
    /// covered.
    static let coveredEvidence = 5
    static let coveredPractice = 3
    /// Answered at least this many times at below this accuracy is thin,
    /// however much material there is.
    static let weakAnswers = 5
    static let weakAccuracy = 0.6

    static func key(area: String, subtopic: String) -> String { area + "/" + subtopic }

    /// One piece of the library, reduced to its words.
    struct Item {
        /// Canonical words, each also without a trailing "s".
        let words: Set<String>
        /// The canonical words in order, space-padded, for phrase matching.
        let phraseText: String
        let isPractice: Bool
        /// The question this is, when it is one, for the answer history.
        let questionId: UUID?
        /// A short version, to show the AI check what the item is.
        let preview: String
    }

    // MARK: - The whole assessment

    static func assess(library: [StudySet],
                       history: [UUID: [Bool]],
                       areas: [SyllabusArea]) -> [AreaCoverage] {
        assess(items: items(from: library), history: history, areas: areas)
    }

    static func assess(items: [Item], history: [UUID: [Bool]], areas: [SyllabusArea]) -> [AreaCoverage] {
        areas.map { area in
            AreaCoverage(area: area, subtopics: area.subtopics.map { sub in
                assess(sub, in: area.name, items: items, history: history)
            })
        }
    }

    static func assess(_ sub: SyllabusSubtopic, in area: String,
                       items: [Item], history: [UUID: [Bool]]) -> SubtopicCoverage {
        let keys = sub.keywords.map(Keyword.init)
        var evidence = 0, practice = 0, answered = 0, correct = 0
        var samples: [String] = []
        for item in items where keys.contains(where: { $0.matches(item) }) {
            evidence += 1
            if item.isPractice { practice += 1 }
            if let id = item.questionId, let past = history[id] {
                answered += past.count
                correct += past.filter { $0 }.count
            }
            // practice first in the samples: a question says more about what
            // is being studied than a page that mentions it in passing
            if samples.count < 5 || (item.isPractice && samples.count < 8) {
                samples.append(item.preview)
            }
        }
        return SubtopicCoverage(area: area, subtopic: sub, evidence: evidence, practice: practice,
                                answered: answered, correct: correct, samples: samples,
                                status: status(evidence: evidence, practice: practice,
                                               answered: answered, correct: correct))
    }

    /// The rule, on its own so it can be tested and explained.
    static func status(evidence: Int, practice: Int, answered: Int, correct: Int) -> CoverageStatus {
        guard evidence > 0 else { return .notCovered }
        if answered >= weakAnswers, Double(correct) / Double(answered) < weakAccuracy { return .thin }
        if evidence >= coveredEvidence, practice >= coveredPractice { return .covered }
        return .thin
    }

    // MARK: - The library as items

    /// Everything in the library worth matching against, one item per
    /// question, card, case, station, textbook page, stretch of transcript and
    /// lecture page. A lecture kept by more than one set is read once.
    static func items(from library: [StudySet]) -> [Item] {
        var out: [Item] = []
        var seenSources = Set<UUID>()
        for set in library {
            out.append(item(set.name + " " + set.subject, practice: false))
            for q in set.questions {
                let answer = q.options.indices.contains(q.correctIndex) ? q.options[q.correctIndex] : ""
                out.append(item(q.stem + " " + answer, practice: true, question: q.id))
            }
            for c in set.cards {
                out.append(item([c.front, c.clozeText, c.bullets.joined(separator: " ")].joined(separator: " "),
                                practice: true))
            }
            for c in set.qaCards {
                out.append(item([c.topic, c.stem, c.answer.joined(separator: " ")].joined(separator: " "),
                                practice: true))
            }
            for station in set.osceChecklists {
                out.append(item(station.title + " " + station.steps.joined(separator: " "), practice: true))
            }
            if !set.bookMarkdown.isEmpty {
                for page in BookPages.split(set.bookMarkdown) {
                    out.append(item(page.markdown, practice: false))
                }
            }
            // a transcript a line at a time is too little to match; twenty
            // lines is about a minute of lecture
            let lines = set.narrateSegments.map(\.text)
            var start = 0
            while start < lines.count {
                let end = min(lines.count, start + 20)
                out.append(item(lines[start..<end].joined(separator: " "), practice: false))
                start = end
            }
            for source in set.sources where seenSources.insert(source.id).inserted {
                for page in source.pages {
                    out.append(item(page.text, practice: false))
                }
            }
        }
        return out.filter { !$0.words.isEmpty }
    }

    static func item(_ text: String, practice: Bool, question: UUID? = nil) -> Item {
        let tokens = canonicalWords(text)
        var words = Set<String>()
        for w in tokens {
            words.insert(w)
            if w.count > 3, w.hasSuffix("s") { words.insert(fold(String(w.dropLast()))) }
        }
        let preview = text.split(whereSeparator: { $0.isNewline || $0 == " " })
            .joined(separator: " ")
        return Item(words: words,
                    phraseText: " " + tokens.joined(separator: " ") + " ",
                    isPractice: practice,
                    questionId: question,
                    preview: String(preview.prefix(180)))
    }

    // MARK: - Words

    /// A keyword, split into canonical words once.
    struct Keyword {
        let words: [String]
        let phrase: String

        init(_ text: String) {
            words = CoverageEngine.canonicalWords(text)
            phrase = words.joined(separator: " ")
        }

        func matches(_ item: Item) -> Bool {
            guard !words.isEmpty, words.allSatisfy({ item.words.contains($0) }) else { return false }
            if words.count == 1 { return true }
            // every word is there; now check they are there together, in order
            return item.phraseText.contains(" " + phrase + " ")
                || item.phraseText.contains(" " + phrase + "s ")
        }
    }

    /// Lowercase words with British and American spellings folded together:
    /// "haemorrhage" and "hemorrhage", "oesophagus" and "esophagus", "tumour"
    /// and "tumor", "centre" and "center", "immunisation" and "immunization"
    /// all come out the same. Short words are left alone, so "toe" stays "toe".
    static func canonicalWords(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(fold)
    }

    static func fold(_ word: String) -> String {
        guard word.count >= 6 else { return word }
        var w = word.replacingOccurrences(of: "ae", with: "e")
            .replacingOccurrences(of: "oe", with: "e")
            .replacingOccurrences(of: "isation", with: "ization")
        if w.hasSuffix("our") { w = String(w.dropLast(2)) + "r" }
        if w.hasSuffix("ours") { w = String(w.dropLast(3)) + "rs" }
        if w.hasSuffix("tre") { w = String(w.dropLast(3)) + "ter" }
        if w.hasSuffix("tres") { w = String(w.dropLast(4)) + "ters" }
        return w
    }
}
