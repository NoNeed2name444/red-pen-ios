// The same cases as pipeline/tests/test_card_quality.py, asserted against the
// Swift port. Two implementations judging one deck differently would make both
// worthless, so they are checked against the same examples with the same
// expected verdicts.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func rules(_ problems: [CardQuality.Problem]) -> Set<String> {
    Set(problems.map(\.rule))
}

let good = MCQQuestion(
    stem: "A 24-year-old woman has a facial rash that spares the nasolabial folds. "
        + "Which finding would best support a diagnosis of SLE?",
    options: ["Positive antinuclear antibody", "Elevated serum ferritin",
              "Positive rheumatoid factor", "Raised serum amylase",
              "Positive monospot test"],
    correctIndex: 0,
    explanation: "A positive antinuclear antibody is the entry criterion for SLE classification.")
check("a sound question passes clean", CardQuality.check(good).isEmpty,
      "\(rules(CardQuality.check(good)))")

var longest = good
longest.options = ["A positive antinuclear antibody test, which is the entry criterion and is "
                   + "present in almost every patient with the disease",
                   "Ferritin", "Amylase", "Monospot", "Glucose"]
check("the longest option is caught", rules(CardQuality.check(longest)).contains("key-is-longest"),
      "\(rules(CardQuality.check(longest)))")

var hedged = good
hedged.options = ["Antinuclear antibody may be positive", "Ferritin is always elevated",
                  "Rheumatoid factor is always positive", "Amylase is always raised",
                  "Monospot is always positive"]
check("only the key hedging is caught", rules(CardQuality.check(hedged)).contains("only-key-hedges"),
      "\(rules(CardQuality.check(hedged)))")

var clang = good
clang.stem = "Which drug is the hydroxychloroquine-sparing agent of choice?"
clang.options = ["Hydroxychloroquine dosing", "Ferritin", "Amylase", "Monospot", "Glucose"]
clang.explanation = "Hydroxychloroquine dosing is weight based."
check("a word shared only by stem and key is caught",
      rules(CardQuality.check(clang)).contains("stem-word-only-in-key"),
      "\(rules(CardQuality.check(clang)))")

var nonAnswer = good
nonAnswer.options = ["Positive antinuclear antibody", "Ferritin", "Amylase", "Monospot",
                     "All of the above"]
check("'all of the above' is caught",
      rules(CardQuality.check(nonAnswer)).contains("non-answer-option"),
      "\(rules(CardQuality.check(nonAnswer)))")

var topic = good
topic.stem = "SLE"
check("a topic is not a stem",
      !rules(CardQuality.check(topic)).isDisjoint(with: ["stem-not-a-question", "stem-too-thin"]),
      "\(rules(CardQuality.check(topic)))")

var stray = good
stray.explanation = "Aspirin is given after myocardial infarction."
check("an explanation about something else is caught",
      rules(CardQuality.check(stray)).contains("explanation-misses-the-key"),
      "\(rules(CardQuality.check(stray)))")

// MARK: cards

let goodCard = AnkiCard(type: .qa, front: "What does the malar rash spare?",
                        bullets: ["The nasolabial folds"],
                        why: "Sparing the nasolabial folds separates it from rosacea.")
check("a sound card passes clean", CardQuality.check(goodCard).isEmpty,
      "\(rules(CardQuality.check(goodCard)))")

var stuffed = goodCard
stuffed.bullets = ["One", "Two", "Three", "Four", "Five"]
check("a card carrying five facts is caught",
      rules(CardQuality.check(stuffed)).contains("too-many-facts"),
      "\(rules(CardQuality.check(stuffed)))")

let swallowed = AnkiCard(type: .cloze,
                         clozeText: "{{c1::Systemic lupus erythematosus is a multisystem autoimmune disease}}.")
check("a cloze that deletes the sentence is caught",
      rules(CardQuality.check(swallowed)).contains("cloze-swallows-the-sentence"),
      "\(rules(CardQuality.check(swallowed)))")

let goodCloze = AnkiCard(type: .cloze,
                         clozeText: "SLE is classified at {{c1::10}} points on the EULAR/ACR criteria.")
check("a sound cloze passes clean", CardQuality.check(goodCloze).isEmpty,
      "\(rules(CardQuality.check(goodCloze)))")

let emptyCloze = AnkiCard(type: .cloze, clozeText: "Somebody removed the braces")
check("a cloze with no deletion is caught",
      rules(CardQuality.check(emptyCloze)).contains("cloze-without-a-deletion"))

// MARK: the quiz built from a deck

func card(_ front: String, _ answer: String, _ why: String) -> AnkiCard {
    AnkiCard(type: .qa, front: front, bullets: [answer], why: why)
}

let deck = [
    card("Which drug lowers mortality in SLE?", "Hydroxychloroquine",
         "It lowers flares and damage accrual."),
    card("Which antibody is the entry criterion for SLE?", "Antinuclear antibody",
         "Required before points are counted."),
    card("Which antibody is most specific for SLE?", "Anti-double-stranded DNA",
         "Specific, and tracks nephritis."),
    card("Which drug is used for lupus nephritis induction?", "Mycophenolate mofetil",
         "As effective as cyclophosphamide."),
    card("Which test monitors disease activity in SLE?", "Complement C3 and C4",
         "They fall in active disease."),
    card("Which skin sign spares the nasolabial folds?", "The malar rash",
         "Sparing separates it from rosacea."),
]
let built = QuizFromCards.build(from: deck, seed: 1)

// The antibody card's answer is the only option containing the word "antibody",
// which is a question you can win without knowing any medicine. No other card
// here supplies a distractor that repairs it, so it must be dropped, not shipped.
let answered = Set(built.questions.map(\.stem))
check("a question that gives itself away is dropped",
      !answered.contains(where: { $0.contains("entry criterion") })
      && built.skipped.contains { $0.why.contains("gives itself away") },
      built.skipped.map(\.why).joined(separator: " / "))
check("every other card became a question", built.questions.count == 5,
      "\(built.questions.count)")

let deckAnswers = Set(deck.compactMap { QuizFromCards.answer(of: $0) })
check("every option came from the deck, none invented",
      built.questions.allSatisfy { Set($0.options).isSubset(of: deckAnswers) })
check("each key is its own card's answer",
      built.questions.allSatisfy { deckAnswers.contains($0.options[$0.correctIndex]) })
check("no question repeats an option",
      built.questions.allSatisfy { Set($0.options).count == $0.options.count })

if let drug = built.questions.first(where: { $0.stem.contains("lowers mortality") }) {
    check("the explanation names what it is explaining",
          drug.explanation.hasPrefix("Hydroxychloroquine")
          && drug.explanation.contains("lowers flares"), drug.explanation)
} else {
    check("the explanation names what it is explaining", false, "question missing")
}
check("an explanation that already names the answer is left alone",
      QuizFromCards.explanation(answer: "The malar rash",
                                why: "The malar rash spares the nasolabial folds.")
      == "The malar rash spares the nasolabial folds.")

// the questions it ships must themselves survive the quality rules
let shipped = Set(CardQuality.review(questions: built.questions).map(\.rule))
check("the shipped questions pass the quality rules",
      shipped.subtracting(["near-duplicate"]).isEmpty, "\(shipped)")

let thin = QuizFromCards.build(from: Array(deck.prefix(2)), seed: 1)
check("a thin deck refuses rather than inventing distractors",
      thin.questions.isEmpty && thin.skipped.allSatisfy { $0.why.contains("distractors") },
      thin.skipped.map(\.why).joined(separator: " / "))

let multi = AnkiCard(type: .qa, front: "Describe SLE",
                     bullets: ["Multisystem", "Autoimmune", "Relapsing"])
let withMulti = QuizFromCards.build(from: [multi] + deck, seed: 1)
check("a multi-fact card makes no question",
      withMulti.skipped.contains { $0.cardID == multi.id })

// the same deck must give the same quiz twice, or a question you got wrong
// cannot be found again
let again = QuizFromCards.build(from: deck, seed: 1)
check("the quiz is reproducible",
      again.questions.map(\.options) == built.questions.map(\.options))

// MARK: a second right answer is never a distractor

check("case and a hyphen do not make a different answer",
      CardQuality.similarity("Beta blockers", "beta-blockers") == 1, "\(CardQuality.similarity("Beta blockers", "beta-blockers"))")
check("nor a plural", CardQuality.similarity("ACE inhibitor", "ace inhibitors") == 1)
check("so a restated key is not offered as a wrong answer",
      !QuizFromCards.distractors(for: "Beta blockers", stem: "Which drug class lowers mortality in heart failure?",
                                 pool: ["beta-blockers", "Loop diuretics", "Digoxin", "Nitrates", "Ivabradine"],
                                 want: 4).contains("beta-blockers"))

// MARK: numbers are answers, not noise

check("two values in the same unit are different answers",
      CardQuality.similarity("140 mmol/L", "3.5 mmol/L") < QuizFromCards.tooAlike,
      "\(CardQuality.similarity("140 mmol/L", "3.5 mmol/L"))")
check("type 1 and type 2 are different answers", CardQuality.similarity("Type 1", "Type 2") < QuizFromCards.tooAlike)
let labValues = ["140 mmol/L", "3.5 mmol/L", "5.5 mmol/L", "2.2 mmol/L", "Addison disease", "Spironolactone", "Conn syndrome"]
let valueDistractors = QuizFromCards.distractors(for: "140 mmol/L", stem: "What is the lower limit of normal serum sodium?",
                                                 pool: labValues, want: 4)
check("a value draws values first", valueDistractors.prefix(3).allSatisfy { QuizFromCards.isValue($0) },
      "\(valueDistractors)")
check("a key that is the only value among terms gives itself away",
      QuizFromCards.keyStandsOut(answer: "140 mmol/L", distractors: ["Addison disease", "Spironolactone", "Conn syndrome", "Hypokalaemia"]))
check("a term with a digit in its name is still a term",
      !QuizFromCards.isValue("Complement C3 and C4") && QuizFromCards.isValue("> 10 points"))

// MARK: a repeated cloze number is hidden everywhere

let repeated = AnkiCard(type: .cloze,
                        clozeText: "{{c1::Warfarin}} is reversed with vitamin K; {{c1::warfarin}} dosing is guided by {{c2::INR}}.")
let repeatedStem = QuizFromCards.stem(of: repeated)
check("every hole with the first one's number is blanked",
      !repeatedStem.lowercased().contains("warfarin") && repeatedStem.components(separatedBy: "______").count == 3,
      repeatedStem)
check("other numbers are shown as words", repeatedStem.contains("INR"), repeatedStem)

// MARK: the capitals of what follows the answer

check("an acronym keeps its capitals",
      QuizFromCards.explanation(answer: "Lisinopril", why: "ACE inhibitors reduce proteinuria.")
      == "Lisinopril \u{2014} ACE inhibitors reduce proteinuria.")
check("so does CT", QuizFromCards.lowercasingFirstWord("CT shows a hyperdense lesion.") == "CT shows a hyperdense lesion.")
check("and an eponym", QuizFromCards.lowercasingFirstWord("Addison disease causes it.") == "Addison disease causes it."
      && QuizFromCards.lowercasingFirstWord("Cushing's syndrome is the opposite.") == "Cushing's syndrome is the opposite.")
check("an ordinary first word is still lower-cased",
      QuizFromCards.lowercasingFirstWord("Lowers flares.") == "lowers flares."
      && QuizFromCards.lowercasingFirstWord("A diuretic.") == "a diuretic.")

print(failures.isEmpty ? "\nALL CARD QUALITY TESTS PASS"
                       : "\n\(failures.count) CARD QUALITY TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
