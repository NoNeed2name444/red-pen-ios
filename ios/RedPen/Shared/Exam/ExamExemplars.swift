import Foundation

/// One real exam item from an openly licensed bank, kept to show a writer
/// the exam's style: stem, options, key. `id` is a hash of the original stem.
struct ExamExemplar: Codable, Hashable {
    let id: String
    let s: String
    let o: [String]
    let a: Int
}

/// The index server/bench/exam-exemplars.mjs builds: per style source, per
/// topic, a few exemplars.
struct ExamExemplarIndex: Codable {
    var version: String
    var licences: [String]
    var sources: [String: [String: [ExamExemplar]]]

    static let empty = ExamExemplarIndex(version: "empty", licences: [], sources: [:])
}

/// Few-shot exemplars for the question writer: two or three real items in
/// the chosen exam's style, for the topic at hand, different ones each batch.
/// The same choice as server/exams.js exemplarsFor, so a set written on the
/// phone and one written by a cloud job see the same examples.
enum ExamExemplars {

    static let bundled: ExamExemplarIndex = {
        guard let data = ExamExemplarData.json.data(using: .utf8),
              let index = try? JSONDecoder().decode(ExamExemplarIndex.self, from: data) else { return .empty }
        return index
    }()

    /// Up to `count` (at most 3) exemplars: the topic's own first, rotating
    /// with `round`, then the rest of the exam's source in topic order.
    static func pick(for exam: TargetExam, domain: ExamDomain?, count: Int = 2, round: Int = 0,
                     index: ExamExemplarIndex = bundled) -> [ExamExemplar] {
        let bank: [String: [ExamExemplar]] = index.sources[exam.exemplars.rawValue] ?? [:]
        let key: String = domain?.rawValue ?? ""
        let own: [ExamExemplar] = bank[key] ?? []
        let rest: [ExamExemplar] = bank.keys.sorted().filter { $0 != key }.flatMap { bank[$0] ?? [] }
        let poolSize: Int = own.count + rest.count
        guard poolSize > 0 else { return [] }
        let want: Int = min(max(1, count), 3, poolSize)
        var out: [ExamExemplar] = []
        var seen = Set<String>()
        func take(_ list: [ExamExemplar], from start: Int) {
            var k = 0
            while k < list.count && out.count < want {
                let item: ExamExemplar = list[(start + k) % list.count]
                if seen.insert(item.id).inserted { out.append(item) }
                k += 1
            }
        }
        if !own.isEmpty { take(own, from: (max(0, round) * want) % own.count) }
        if !rest.isEmpty { take(rest, from: (max(0, round) * want) % rest.count) }
        return out
    }

    static func letter(_ i: Int) -> String {
        guard i >= 0, i < 26 else { return "?" }
        return String(UnicodeScalar(UInt8(65 + i)))
    }

    /// The exemplars as the writer is shown them (the text server/exams.js
    /// exemplarBlock writes), or "" when there are none.
    static func block(for exam: TargetExam, domain: ExamDomain?, count: Int = 2, round: Int = 0,
                      index: ExamExemplarIndex = bundled) -> String {
        let items: [ExamExemplar] = pick(for: exam, domain: domain, count: count, round: round, index: index)
        guard !items.isEmpty else { return "" }
        var lines: [String] = [
            "STYLE EXAMPLES - real \(exam.name)-style items from openly licensed question banks (MedQA, MIT licence; MedMCQA, Apache-2.0), shown ONLY for tone, length and the way the question is asked. Never copy their patients, numbers, wording or answers, and take every fact from the source material:"
        ]
        for (k, item) in items.enumerated() {
            lines.append("Example \(k + 1): \(item.s)")
            for (i, option) in item.o.enumerated() {
                lines.append("  \(letter(i)). \(option)")
            }
            lines.append("  Answer: \(letter(item.a))")
        }
        return lines.joined(separator: "\n")
    }

    /// For a cloud job: the server fills this in, with different exemplars
    /// for each batch (server/exams.js fillExemplars).
    static func placeholder(for exam: TargetExam, domain: ExamDomain?, count: Int = 2) -> String {
        "{{EXEMPLARS:\(exam.id):\(domain?.rawValue ?? ""):\(min(max(1, count), 3))}}"
    }

    /// Every bundled exemplar's runs of four words, worked out once.
    static let bundledShingles: [Set<String>] = shingleSets(bundled)

    static func shingleSets(_ index: ExamExemplarIndex) -> [Set<String>] {
        index.sources.values.flatMap { bank in
            bank.values.flatMap { list in list.map { shingles(CoverageEngine.canonicalWords($0.s)) } }
        }.filter { !$0.isEmpty }
    }

    /// Whether a generated stem copies an exemplar: over half its runs of
    /// four words the same. Used to drop a question that lifted its example.
    static func copies(_ stem: String, against sets: [Set<String>] = bundledShingles) -> Bool {
        let words: [String] = CoverageEngine.canonicalWords(stem)
        guard words.count >= 8 else { return false }
        let grams: Set<String> = shingles(words)
        for theirs in sets {
            let shared: Int = grams.intersection(theirs).count
            if Double(shared) / Double(max(1, min(grams.count, theirs.count))) > 0.5 { return true }
        }
        return false
    }

    /// Runs of four words.
    private static func shingles(_ words: [String]) -> Set<String> {
        guard words.count >= 4 else { return [] }
        var out = Set<String>()
        for i in 0...(words.count - 4) {
            out.insert(words[i..<(i + 4)].joined(separator: " "))
        }
        return out
    }
}
