import Foundation

/// Turns a deck you already have into a quiz, using the deck as the distractors.
///
/// Two things follow, and both matter more than they sound. The first is
/// alignment: a question generated separately from the lecture can test
/// something you never made a card for, so getting it wrong tells you nothing
/// about your deck. A question built from card 14 tests card 14.
///
/// The second is the distractors, which are the hard part of writing a
/// question. Invented ones are why generated questions are easy: asked for four
/// wrong answers a model gives four obviously wrong answers, and you learn to
/// pick the plausible one without knowing the medicine. Here the wrong answers
/// are the RIGHT answers to other cards in the same deck - real terms, same
/// lecture, same level of detail. Nothing is invented and nothing is phrased by
/// a model, so a question can never be more wrong than the deck it came from.
///
/// A port of pipeline/tools/quiz_from_cards.py; the two must agree.
enum QuizFromCards {

    struct Skipped: Identifiable, Hashable {
        let id = UUID()
        var cardID: UUID
        var why: String
    }

    /// Two answers this alike cannot both be on one question: one would be
    /// defensibly correct, and an unfair question teaches you to distrust the
    /// deck rather than learn from it.
    static let tooAlike = 0.8
    /// Tells that make a question answerable without the medicine. A
    /// near-duplicate is not one of them: a deck about one topic repeats
    /// itself, and that is the deck's business, not the question's.
    static let fatal: Set<String> = [
        "key-is-longest", "only-key-hedges", "stem-word-only-in-key",
        "absolute-in-key", "duplicate-option", "non-answer-option",
        "stem-not-a-question", "stem-too-thin", "option-count", "no-key"]

    /// The single thing a card asks you to produce, or nil if it asks for more
    /// than one - a card with three bullets has no single answer, so it makes
    /// no question.
    static func answer(of card: AnkiCard) -> String? {
        if card.type == .cloze {
            // the first deletion is the card's subject; later ones are detail
            return CardQuality.clozeHoles(card.clozeText).first?.text
                .trimmingCharacters(in: .whitespaces)
        }
        let bullets = card.bullets
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return bullets.count == 1 ? bullets[0] : nil
    }

    static func stem(of card: AnkiCard) -> String {
        if card.type == .cloze {
            let holes = CardQuality.clozeHoles(card.clozeText)
            guard let first = holes.first else { return "" }
            // The sentence with the answer blanked, which reads as a question.
            // Every hole with the first one's number is blanked, as Anki hides
            // a repeated c1 together: "{{c1::Warfarin}} ... {{c1::warfarin}}
            // dosing" left the second one showing, and the answer with it.
            let text = NSMutableString(string: card.clozeText)
            let same: [NSRange] = holes.filter { $0.number == first.number }
                .map { NSRange($0.range, in: card.clozeText) }
            // last first, so the earlier ranges still point where they did
            for range in same.reversed() {
                text.replaceCharacters(in: range, with: "______")
            }
            return CardQuality.clozeBare(text as String).trimmingCharacters(in: .whitespaces)
        }
        return card.front.trimmingCharacters(in: .whitespaces)
    }

    /// The card's reasoning, with the thing it reasons about named.
    ///
    /// A card's "why" is written to be read beside its answer, so it says "it
    /// lowers flares and damage accrual" - which, pasted under a question,
    /// never tells you WHAT lowers them. Both halves are the card's; this only
    /// puts them in an order that reads on its own.
    static func explanation(answer: String, why: String) -> String {
        let why = why.trimmingCharacters(in: .whitespacesAndNewlines)
        if why.isEmpty { return answer }
        if !CardQuality.terms(answer).isDisjoint(with: CardQuality.terms(why)) {
            return why                       // it already names the answer
        }
        return answer + " \u{2014} " + lowercasingFirstWord(why)
    }

    /// "Lowers flares" reads "lowers flares" after a dash; "ACE inhibitors",
    /// "CT", "HIV" and "Addison disease" keep their capitals. Only an
    /// ordinary capitalised word - more than one letter, the second one lower
    /// case - is lower-cased, and not one that names something: followed by
    /// "'s" or by "disease", "syndrome", "sign" and the like, it is an eponym.
    static func lowercasingFirstWord(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let firstWord = text.prefix { $0.isLetter }
        // "A diuretic..." reads "a diuretic"; "I" stays as it is
        if firstWord == "A" { return "a" + String(text.dropFirst()) }
        guard firstWord.count > 1 else { return text }
        let second: Character = firstWord[firstWord.index(after: firstWord.startIndex)]
        guard second.isLowercase else { return text }
        let rest = text.dropFirst(firstWord.count)
        if rest.hasPrefix("'s") || rest.hasPrefix("\u{2019}s") { return text }
        let next: String = rest.drop { $0 == " " || $0 == "-" }.prefix { $0.isLetter }.lowercased()
        let named: Set<String> = ["disease", "syndrome", "sign", "triad", "test", "reflex", "phenomenon",
                                  "criteria", "score", "classification", "law", "node", "palsy", "ulcer",
                                  "fracture", "tumour", "tumor", "manoeuvre", "maneuver", "lesion"]
        if named.contains(next) { return text }
        return first.lowercased() + String(text.dropFirst())
    }

    /// Other cards' answers, nearest first, minus any that could also be right.
    ///
    /// Nearest first is deliberate: the useful wrong answer is the one you have
    /// to think to reject, while a distractor from another topic is free marks.
    /// One sharing the stem's own vocabulary is better still, because it denies
    /// the question the shortcut of matching words.
    static func distractors(for answer: String, stem: String,
                            pool: [String], want: Int) -> [String] {
        let stemWords = CardQuality.terms(stem)
        let answerWords = CardQuality.terms(answer)
        let value: Bool = isValue(answer)
        // Same shape first: a value is answered among values, a term among
        // terms. "140 mmol/L" among four disease names is answered by its
        // format, not by knowing the sodium.
        let ranked = pool
            .filter { !$0.isEmpty && $0.lowercased() != answer.lowercased() }
            .filter { CardQuality.similarity(answer, $0) < tooAlike }
            .map { other -> (shape: Bool, Int, Int, Double, String) in
                (isValue(other) == value,
                 answerWords.intersection(CardQuality.terms(other)).count,
                 stemWords.intersection(CardQuality.terms(other)).count,
                 CardQuality.similarity(answer, other), other)
            }
            .sorted { a, b in
                if a.shape != b.shape { return a.shape }
                if a.1 != b.1 { return a.1 > b.1 }
                if a.2 != b.2 { return a.2 > b.2 }
                return a.3 > b.3
            }

        var chosen: [String] = []
        var seen = Set<String>()
        for candidate in ranked {
            let other = candidate.4
            if seen.contains(other.lowercased()) { continue }
            // never two distractors that are near-twins of each other either
            if chosen.contains(where: { CardQuality.similarity(other, $0) >= tooAlike }) {
                continue
            }
            chosen.append(other)
            seen.insert(other.lowercased())
            if chosen.count == want { break }
        }
        return chosen
    }

    /// An answer that is a value - "140 mmol/L", "3.5", "> 10 points" - as
    /// against a term that merely has a digit in its name ("Complement C3
    /// and C4", "Type 1 diabetes").
    static func isValue(_ text: String) -> Bool {
        let lead = text.drop { $0.isWhitespace || "<>\u{2264}\u{2265}~\u{2248}".contains($0) }
        return lead.first?.isNumber == true
    }

    /// The key is the one value among terms, or the one term among values:
    /// answerable from the format alone.
    static func keyStandsOut(answer: String, distractors: [String]) -> Bool {
        let value: Bool = isValue(answer)
        return !distractors.isEmpty && distractors.allSatisfy { isValue($0) != value }
    }

    /// Build the quiz. `skipped` says WHY, so a thin deck explains itself
    /// instead of silently producing three questions.
    static func build(from cards: [AnkiCard], optionCount: Int = 5,
                      seed: UInt64 = 0) -> (questions: [MCQQuestion], skipped: [Skipped]) {
        var rng = SeededGenerator(seed: seed == 0 ? 0x9E3779B97F4A7C15 : seed)
        let answers = cards.map { answer(of: $0) }
        let pool = answers.compactMap { $0 }
        var questions: [MCQQuestion] = []
        var skipped: [Skipped] = []

        for (card, answerText) in zip(cards, answers) {
            guard let answerText, !answerText.isEmpty else {
                skipped.append(Skipped(cardID: card.id, why: "no single answer to ask for"))
                continue
            }
            let stemText = stem(of: card)
            guard stemText.split(separator: " ").count >= 3 else {
                skipped.append(Skipped(cardID: card.id, why: "nothing to make a stem from"))
                continue
            }
            let wrong = distractors(for: answerText, stem: stemText,
                                    pool: pool, want: optionCount - 1)
            guard wrong.count == optionCount - 1 else {
                // Padding with invented text is exactly the failure this avoids.
                skipped.append(Skipped(cardID: card.id,
                                       why: "only \(wrong.count) usable distractors in this deck"))
                continue
            }
            guard !keyStandsOut(answer: answerText, distractors: wrong) else {
                skipped.append(Skipped(cardID: card.id,
                                       why: isValue(answerText)
                                           ? "the only answer that is a number"
                                           : "the only answer that is not a number"))
                continue
            }
            var choices = wrong + [answerText]
            choices.shuffle(using: &rng)
            let question = MCQQuestion(
                stem: stemText.hasSuffix("?") || stemText.contains("______")
                      ? stemText
                      : stemText.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "?",
                options: choices,
                correctIndex: choices.firstIndex(of: answerText) ?? 0,
                explanation: explanation(answer: answerText, why: card.why),
                imageIndex: nil)

            // It faces the same judgement as any other question. What is caught
            // here is a question you could answer by reading it, and a small
            // deck often cannot supply a distractor that repairs one.
            let tells = Set(CardQuality.check(question).map(\.rule)).intersection(fatal)
            if !tells.isEmpty {
                skipped.append(Skipped(cardID: card.id,
                                       why: "gives itself away (\(tells.sorted().joined(separator: ", ")))"))
                continue
            }
            questions.append(question)
        }
        return (questions, skipped)
    }
}

/// Shuffling has to be reproducible: the same deck must give the same quiz
/// twice, or a question you got wrong cannot be found again.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
