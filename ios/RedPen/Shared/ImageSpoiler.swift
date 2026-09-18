import Foundation

/// Which page a card's picture belongs on.
///
/// A picture normally belongs with the question - it is usually the thing being
/// asked about, and an ECG or a radiograph printed overleaf is useless. But some
/// pictures carry the answer in them: a labelled diagram whose labels are what
/// you were asked to name, a slide with the diagnosis written across it. Printed
/// on the question page, those turn a test into a reading exercise, and the
/// student does not find out until they have already seen it.
///
/// So the picture goes with the question unless it gives the answer away, and
/// then it goes with the answer.
///
/// The decision is made on what the picture actually SAYS - the text recognised
/// inside it - against what the answer says that the question does not. That
/// last part is the whole trick. A diagram of a kidney labelled "kidney", on a
/// question that already says kidney, reveals nothing. The same diagram
/// labelled "membranous nephropathy", when that is the answer and the stem
/// never mentions it, reveals everything.
enum ImageSpoiler {

    enum Placement: String, Equatable {
        /// With the question, where a picture is normally most use.
        case question
        /// Held back, because the picture says what the answer says.
        case answer
    }

    /// How much of the answer's own vocabulary a picture may show before it
    /// counts as giving it away.
    ///
    /// Low on purpose. Being wrong in the two directions costs very different
    /// amounts: a picture needlessly held back is a small inconvenience, and a
    /// spoiled question is a card that can never be used to test anything
    /// again. One distinctive word - a diagnosis, a drug, a named sign - is
    /// usually the whole answer.
    static let threshold = 0.34

    /// Where to put it.
    ///
    /// `imageText` is what was recognised inside the picture; empty when
    /// nothing was read, which is the common case for a photograph or a trace,
    /// and which correctly leaves the picture with the question.
    static func placement(imageText: String, question: String, answer: String) -> Placement {
        giveaway(imageText: imageText, question: question, answer: answer).isEmpty
            ? .question : .answer
    }

    /// The words that decide it - useful for saying WHY a picture was held
    /// back, and for testing the judgement rather than only its verdict.
    static func giveaway(imageText: String, question: String, answer: String) -> Set<String> {
        let shown = words(imageText)
        guard !shown.isEmpty else { return [] }

        // What the answer contributes that the question did not already say.
        // Anything the question says is fair game for the picture to repeat.
        let told = words(answer).subtracting(words(question))
        guard !told.isEmpty else { return [] }

        let revealed = shown.intersection(told)
        guard !revealed.isEmpty else { return [] }

        // Either a decent share of what the answer adds, or - for a short
        // answer, where one word IS the answer - any of it at all.
        let share = Double(revealed.count) / Double(told.count)
        if told.count <= 3 { return revealed }
        return share >= threshold ? revealed : []
    }

    /// Content words, normalised: lowercased, stripped of accents and
    /// punctuation, short and everyday words dropped.
    ///
    /// The stop list is doing real work. Without it a picture captioned
    /// "Figure 3: the patient" shares "the" and "patient" with every answer in
    /// the deck, and every picture in the set ends up hidden overleaf.
    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US"))
        let parts = folded.split { !$0.isLetter && !$0.isNumber }
        var out = Set<String>()
        for part in parts {
            let word = String(part)
            guard word.count >= 4, !stopWords.contains(word) else { continue }
            out.insert(singular(word))
        }
        return out
    }

    /// Crude plural folding, so "cells" and "cell" are the same word.
    /// Deliberately not a stemmer: turning "diabetes" into "diabete" invents a
    /// word, and the only thing being compared here is one text against another.
    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ses"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 4 { return String(word.dropLast()) }
        return word
    }

    private static let stopWords: Set<String> = [
        "this", "that", "these", "those", "with", "from", "into", "which", "what",
        "when", "where", "there", "their", "them", "then", "than", "have", "been",
        "being", "does", "will", "would", "could", "should", "about", "above",
        "after", "before", "between", "because", "while", "also", "other", "each",
        "most", "more", "less", "some", "such", "only", "over", "under", "both",
        "figure", "image", "picture", "diagram", "slide", "page", "label",
        "labelled", "labeled", "shown", "show", "shows", "following", "above",
        "patient", "case", "question", "answer", "true", "false", "none",
    ]
}
