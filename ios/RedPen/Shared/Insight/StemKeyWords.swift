import Foundation

/// The words in a question stem that change the answer, for the slow reading
/// drill: what is being asked ("most likely", "next best step", "NOT"),
/// negatives that are easy to skim past ("denies", "without"), time course,
/// and the numbers - ages, durations, results.
///
/// Deliberately simple: a list of patterns, no model. It is there to slow the
/// eye down on the words that are usually misread, not to understand the
/// question.
enum StemKeyWords {

    private static let patterns: [String] = [
        // what is being asked
        #"\b(most likely|most appropriate|most common|next best|next step|best initial|initial|first[- ]line|definitive|gold standard|least likely|contraindicated|except|not|least)\b"#,
        // negatives and time course that flip the picture
        #"\b(no|denies|without|never|absent|normal|sudden|acute|chronic|recurrent|bilateral|unilateral|painless|painful|pregnant)\b"#,
        // ages and numbers with units
        #"\b\d+(\.\d+)?[- ]?(year|month|week|day|hour)s?[- ]old\b"#,
        #"\b\d+(\.\d+)?\s?(%|mmHg|mg/dL|mmol/L|\x{00B5}mol/L|g/L|g/dL|bpm|/min|\x{00B0}C|\x{00B0}F|kg|years?|months?|weeks?|days?|hours?|minutes?)"#
    ]

    private static let expressions: [NSRegularExpression] = patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    /// The ranges of `stem` to highlight, in order, not overlapping.
    static func ranges(in stem: String) -> [Range<String.Index>] {
        let whole = NSRange(stem.startIndex..<stem.endIndex, in: stem)
        var found: [Range<String.Index>] = []
        for expression in expressions {
            for match in expression.matches(in: stem, options: [], range: whole) {
                guard let range = Range(match.range, in: stem) else { continue }
                if found.contains(where: { $0.overlaps(range) }) { continue }
                found.append(range)
            }
        }
        return found.sorted { $0.lowerBound < $1.lowerBound }
    }
}
