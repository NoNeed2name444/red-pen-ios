import Foundation

/// Making a long set actually cover the material.
///
/// Questions are written a few at a time, and until now each batch was written
/// with no knowledge of the ones before it. Ask an on-device model for sixty
/// questions on one lecture in ten batches of six and it writes about the same
/// eight facts ten times over, because every batch independently picks the most
/// obvious thing in the source. The set looks long and tests almost nothing.
///
/// Two defences, because either alone leaks. The model is TOLD what has already
/// been asked, which is what actually spreads the coverage; and whatever it
/// writes anyway is CHECKED against what is already collected, because a model
/// asked not to repeat itself will still sometimes rephrase.
///
/// Pure Foundation, so all of it is tested.
enum MCQCoverage {

    /// One question already written, reduced to what identifies the fact it
    /// tests: the stem, and the answer to it.
    struct Asked: Equatable {
        var stem: String
        var key: String
    }

    /// How many questions a source of this size can actually support.
    ///
    /// The old fixed cap of sixty was the thing standing between a forty-page
    /// lecture and a set that covers it. A question needs roughly a paragraph
    /// of material behind it; below that the model starts inventing, which rule
    /// 7 of the prompt forbids, or repeating, which this file forbids.
    static func suggestedCount(forCharacters characters: Int,
                               perQuestion: Int = 320,
                               floor: Int = 5, ceiling: Int = 200) -> Int {
        guard characters > 0 else { return floor }
        return min(ceiling, max(floor, characters / perQuestion))
    }

    /// Words that carry the meaning of a stem.
    ///
    /// The scaffolding of an exam question - "a 54-year-old man presents with",
    /// "which of the following is the most likely" - is identical in every
    /// question ever written, so leaving it in makes two questions about
    /// completely different organs look 60% alike.
    static let scaffolding: Set<String> = [
        "a", "an", "the", "of", "in", "to", "with", "for", "is", "are", "and",
        "or", "on", "at", "by", "from", "as", "that", "this", "it", "be", "was",
        "were", "has", "have", "had", "after", "before", "which", "what", "who",
        "most", "likely", "best", "next", "step", "following", "patient",
        "presents", "presenting", "year", "years", "old", "man", "woman",
        "male", "female", "his", "her", "their", "you", "would", "should",
        "management", "appropriate", "initial", "than", "about", "into",
    ]

    static func contentWords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 && !scaffolding.contains($0) })
    }

    /// How much two stems have in common, 0 to 1.
    static func overlap(_ a: String, _ b: String) -> Double {
        let left = contentWords(a), right = contentWords(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = Double(left.intersection(right).count)
        return shared / Double(min(left.count, right.count))
    }

    /// Whether this question tests something already tested.
    ///
    /// The bar is lower when the ANSWER is the same: two stems that share only
    /// a third of their words but land on "amiodarone" are one fact asked
    /// twice, and that is the shape repetition usually takes - the model varies
    /// the vignette and keeps the answer.
    static func isRepeat(stem: String, key: String, of asked: [Asked],
                         stemThreshold: Double = 0.6,
                         sameKeyThreshold: Double = 0.3) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for previous in asked {
            let sameKey = !trimmedKey.isEmpty
                && previous.key.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() == trimmedKey
            let similarity = overlap(stem, previous.stem)
            if similarity >= stemThreshold { return true }
            if sameKey && similarity >= sameKeyThreshold { return true }
        }
        return false
    }

    /// The block of prompt telling the model what not to ask again.
    ///
    /// Only the most recent are listed and each is cut short: the whole point
    /// of batching is that the on-device model has a small context, and a
    /// hundred full stems pasted back in would crowd out the source material
    /// the questions are supposed to come from.
    static func avoidanceNote(_ asked: [Asked], limit: Int = 40,
                              stemLength: Int = 90) -> String {
        guard !asked.isEmpty else { return "" }
        let recent = asked.suffix(limit)
        var lines = [
            "",
            "ALREADY ASKED in this set - \(asked.count) question(s) so far. Do NOT test any of these facts again, and do not rewrite them as a different vignette with the same answer. Move on to parts of the source material the list below does not touch:",
        ]
        for item in recent {
            let stem = item.stem.trimmingCharacters(in: .whitespacesAndNewlines)
            let shortened = stem.count > stemLength
                ? String(stem.prefix(stemLength)) + "\u{2026}" : stem
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("- \(shortened)" + (key.isEmpty ? "" : "  [answer: \(key)]"))
        }
        return lines.joined(separator: "\n")
    }
}
