import Foundation

/// Arranging an MCQ explanation into the two things it is actually saying.
///
/// A good explanation does two jobs at once: it says why the right answer is
/// right, and it says why the tempting wrong ones are wrong. Run together as
/// one paragraph those two jobs are indistinguishable, and six lines of
/// unbroken text reads as a wall to be got through rather than as something to
/// learn from.
///
/// Separated from the drawing code so the judgement can be tested without a
/// PDF context: what belongs in which half is a decision about text, and the
/// only way to know it is right is to run it over real explanations.
enum Explanation {

    /// The sentences that discuss another option, and everything else.
    struct Split {
        var core: String
        var traps: [String]
    }

    /// How much of an option's own vocabulary a sentence must repeat before it
    /// counts as being about that option.
    ///
    /// Not an exact match, because an explanation writes "radial-radial delay"
    /// where the option said "Radial-radial pulse delay". A substring test
    /// misses that and leaves the sentence in the wrong half, silently, which
    /// is worse than not splitting at all.
    static let overlap = 0.6

    static func split(_ text: String, options blocks: [DeckBlock]) -> Split {
        var others: [Set<String>] = []
        var right: Set<String> = []
        for block in blocks {
            guard case .option(_, let optionText, let correct) = block else { continue }
            let words = ImageSpoiler.words(optionText)
            guard !words.isEmpty else { continue }
            if correct { right = words } else { others.append(words) }
        }
        let pieces = sentences(text)
        guard !others.isEmpty, pieces.count > 1 else {
            return Split(core: text.trimmingCharacters(in: .whitespacesAndNewlines), traps: [])
        }

        var core: [String] = []
        var traps: [String] = []
        for sentence in pieces {
            let said = ImageSpoiler.words(sentence)
            let best = others.map { share(of: $0, in: said) }.max() ?? 0
            // More like the distractor than like the right answer. The overlap
            // on its own is not enough: "...the classic finding of an atrial
            // septal defect, caused by delayed pulmonary valve closure" shares
            // two words in three with the option "Pulmonary valve stenosis",
            // and was filed as a sentence about that option when it is plainly
            // about the right answer's own mechanism.
            if best >= overlap, best > share(of: right, in: said) {
                traps.append(sentence)
            } else {
                core.append(sentence)
            }
        }

        // A core left empty means every sentence names another option, and then
        // there is nothing to separate - the card keeps its wall rather than
        // being given a heading that explains nothing.
        guard !traps.isEmpty, !core.isEmpty else {
            return Split(core: text.trimmingCharacters(in: .whitespacesAndNewlines), traps: [])
        }
        return Split(core: core.joined(separator: " "), traps: traps)
    }

    /// How much of one phrase's vocabulary a sentence repeats.
    static func share(of words: Set<String>, in said: Set<String>) -> Double {
        words.isEmpty ? 0 : Double(words.intersection(said).count) / Double(words.count)
    }

    /// Sentences, by the punctuation that ends them.
    ///
    /// Abbreviations will occasionally split a sentence in two ("S. aureus"),
    /// which costs a line break in the middle of a thought and nothing else.
    /// The alternative - a list of medical abbreviations to protect - is a list
    /// that would be wrong the first time somebody wrote one it did not have.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}
