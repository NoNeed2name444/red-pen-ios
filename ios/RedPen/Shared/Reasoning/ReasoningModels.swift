import Foundation

// What the Reasoning tools are made of: cases told a clue at a time, pairs of
// conditions that get mixed up, and one-screen illness scripts. Foundation
// only, like the rest of the model layer, so the parsing can be tested
// without a phone.

/// The three ways of practising diagnostic reasoning on a set.
enum ReasoningTool: String, Codable, CaseIterable, Identifiable {
    case cases, duels, scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cases: return "Clue-by-clue cases"
        case .duels: return "Lookalike duels"
        case .scripts: return "Disease scripts"
        }
    }

    var symbol: String {
        switch self {
        case .cases: return "text.magnifyingglass"
        case .duels: return "arrow.left.arrow.right"
        case .scripts: return "rectangle.stack"
        }
    }

    var blurb: String {
        switch self {
        case .cases: return "Clues arrive one at a time. Commit as early as you dare."
        case .duels: return "Two conditions people confuse. Whose feature is it?"
        case .scripts: return "Who gets it, how it runs, what clinches it, what to do."
        }
    }

    /// One of what this tool makes, for "Writing 5 cases".
    var noun: String {
        switch self {
        case .cases: return "case"
        case .duels: return "duel"
        case .scripts: return "script"
        }
    }

    /// How many to write when the student does not say.
    var defaultCount: Int {
        switch self {
        case .cases: return 5
        case .duels: return 4
        case .scripts: return 6
        }
    }
}

/// One case told clue by clue, from the vaguest detail to the one that
/// settles it.
struct ClueCase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Least specific first: age and sex, complaint, history, examination,
    /// bedside test, key investigation, decisive result.
    var clues: [String]
    var diagnosis: String
    /// Three conditions that fit the early clues just as well.
    var differentials: [String]
    var teachingPoint: String
    /// The clue, counting from 1, after which the diagnosis is clear - as the
    /// writer judged it.
    var decisiveClue: Int
}

extension ClueCase {
    /// A diagnosis as compared: case, spacing and trailing full stops do not
    /// make two answers different.
    static func normalized(_ name: String) -> String {
        let lowered: String = name.lowercased()
        let words: [Substring] = lowered.split { $0.isWhitespace }
        let joined: String = words.joined(separator: " ")
        return joined.trimmingCharacters(in: CharacterSet(charactersIn: ".;:,"))
    }

    /// What the student chooses from: the diagnosis and the differentials,
    /// each once. A differential that is the diagnosis again under another
    /// case or spacing is left out - otherwise the student could tap the copy,
    /// see the right name, and be marked wrong.
    var choices: [String] {
        var out: [String] = []
        var seen: Set<String> = []
        for name in [diagnosis] + differentials {
            let key: String = Self.normalized(name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            out.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    /// Whether `choice` is this case's diagnosis.
    func isDiagnosis(_ choice: String) -> Bool {
        let key: String = Self.normalized(choice)
        return !key.isEmpty && key == Self.normalized(diagnosis)
    }
}

/// Whose feature a discriminating feature is.
enum LookalikeSide: String, Codable, CaseIterable, Identifiable {
    case a, both, b
    var id: String { rawValue }

    /// The answer buttons, left to right: the first condition on the left,
    /// "Both" in the middle, the second on the right - the same sides the
    /// card is swiped to.
    static let buttonOrder: [LookalikeSide] = [.a, .both, .b]

    /// How far a card has to travel, in points, before a swipe counts.
    static let swipeDistance: Double = 90

    /// The side a swipe means: left for the first condition, right for the
    /// second, up for both. Nil until it is far enough to count, and for a
    /// swipe down. Mostly-up counts as up even if it drifts sideways.
    static func swiped(width: Double, height: Double) -> LookalikeSide? {
        if height < -swipeDistance && abs(height) > abs(width) { return .both }
        if abs(height) > abs(width) { return nil }
        if width < -swipeDistance { return .a }
        if width > swipeDistance { return .b }
        return nil
    }
}

/// One feature in a duel, and which of the two conditions it belongs to.
struct LookalikeFeature: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var side: LookalikeSide
    /// One line on why it points that way.
    var why: String
}

/// Two conditions students confuse, and the features that tell them apart.
struct LookalikePair: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var a: String
    var b: String
    var features: [LookalikeFeature]
    /// The one sentence to remember about telling them apart.
    var bottomLine: String

    /// The comparison as plain text, for sharing: A's features, B's, and the
    /// ones they share.
    var comparisonText: String {
        var lines = ["\(a) vs \(b)", ""]
        let groups: [(String, LookalikeSide)] = [(a, .a), (b, .b), ("Both", .both)]
        for (title, side) in groups {
            let mine = features.filter { $0.side == side }
            guard !mine.isEmpty else { continue }
            lines.append(title.uppercased())
            lines += mine.map { "- " + $0.text + ($0.why.isEmpty ? "" : " (\($0.why))") }
            lines.append("")
        }
        if !bottomLine.isEmpty { lines.append("Bottom line: " + bottomLine) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A one-screen illness script for one disease.
struct IllnessScript: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var disease: String
    /// Epidemiology and risk factors.
    var who: String
    var timeCourse: String
    var keyFeatures: [String]
    var examSigns: [String]
    var decisiveTest: String
    var firstLine: String
    /// The conditions it is most often mistaken for, by name.
    var lookalikes: [String]

    /// The script as a Markdown page for Ideas. Each lookalike is written as
    /// a `[[Title]]` link, so the idea graph joins scripts that name each other.
    var notePage: String {
        var lines: [String] = []
        if !who.isEmpty { lines += ["**Who gets it:** " + who, ""] }
        if !timeCourse.isEmpty { lines += ["**Time course:** " + timeCourse, ""] }
        if !keyFeatures.isEmpty { lines += ["### Key features"] + keyFeatures.map { "- " + $0 } + [""] }
        if !examSigns.isEmpty { lines += ["### Examination"] + examSigns.map { "- " + $0 } + [""] }
        if !decisiveTest.isEmpty { lines += ["**Decisive investigation:** " + decisiveTest, ""] }
        if !firstLine.isEmpty { lines += ["**First-line management:** " + firstLine, ""] }
        if !lookalikes.isEmpty {
            lines += ["### Lookalikes"] + lookalikes.map { "- [[\($0)]]" }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Everything written for one set.
struct ReasoningPack: Codable, Hashable {
    var setId: UUID
    var cases: [ClueCase] = []
    var duels: [LookalikePair] = []
    var scripts: [IllnessScript] = []
    var updatedAt: Date = Date()

    func count(of tool: ReasoningTool) -> Int {
        switch tool {
        case .cases: return cases.count
        case .duels: return duels.count
        case .scripts: return scripts.count
        }
    }
}

/// One play of a clue-by-clue case.
struct CasePlay: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var caseId: UUID
    var setId: UUID
    var date: Date = Date()
    /// How many clues were showing when the student committed.
    var cluesSeen: Int
    var totalClues: Int
    var chosen: String
    var correct: Bool

    /// Right answers score more the earlier they come: 1 plus the share of
    /// clues still hidden. A wrong answer scores nothing.
    var score: Double {
        guard correct, totalClues > 0 else { return 0 }
        return 1 + Double(max(0, totalClues - cluesSeen)) / Double(totalClues)
    }

    /// Committed to the wrong answer on two clues or fewer: the classic
    /// reasoning error of stopping the search too soon.
    var prematureClosure: Bool { !correct && cluesSeen <= 2 }
}

/// One play of a lookalike duel.
struct DuelPlay: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pairId: UUID
    var setId: UUID
    var date: Date = Date()
    var right: Int
    var total: Int
}
