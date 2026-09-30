// Turning a set of one mode into another. The instant conversions promise
// that nothing is invented and nothing of the original is lost or changed, so
// that is what is asserted: every item arrives, with its own words, and the
// set it came from is left as it was.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let folder = UUID()
var quiz = StudySet(name: "Nephrology", subject: "Renal", kind: .mcq)
quiz.folderId = folder
quiz.images = ["aGVsbG8="]
quiz.sources = [SourceDoc(name: "Glomerular disease", kind: .pdf,
                          pages: [SourceDoc.Page(number: 1, text: "Nephrotic syndrome in adults")])]
quiz.questions = [
    MCQQuestion(stem: "A 34-year-old has frothy urine, periorbital oedema and 6 g/day of proteinuria, with an albumin of 22 g/L and normal renal function on admission to the ward. Which finding is most likely on light microscopy?",
                options: ["Normal glomeruli", "Segmental sclerosis", "Crescents", "IgA deposits"],
                correctIndex: 1,
                explanation: "FSGS is the commonest primary nephrotic syndrome in adults."),
    MCQQuestion(stem: "Anti-PLA2R antibodies are most specific for which condition?",
                options: ["Membranous nephropathy", "Lupus nephritis", "IgA nephropathy", "Anti-GBM disease"],
                correctIndex: 0,
                explanation: "Found in most primary membranous nephropathy.",
                source: "Glomerular disease, p.1"),
    // a broken question - its answer points past the options - is left out
    MCQQuestion(stem: "Broken?", options: ["A"], correctIndex: 3, explanation: ""),
]

// MCQ -> Cards
let deck = ModeConversion.convert(quiz, to: .anki)
check("MCQ turns into Cards instantly", deck != nil)
if let deck {
    check("the new set is a deck", deck.kind == .anki)
    check("it is named after the original", deck.name == "Nephrology \u{2013} Cards", deck.name)
    check("it is a new set, not the old one", deck.id != quiz.id)
    check("subject, folder, pictures and lectures come with it",
          deck.subject == "Renal" && deck.folderId == folder
              && deck.images == quiz.images && deck.sources == quiz.sources)
    check("one card per sound question", deck.cards.count == 2, "\(deck.cards.count)")
    check("the stem is the front", deck.cards.first?.front == quiz.questions[0].stem)
    check("the right answer is the back", deck.cards.first?.bullets == ["Segmental sclerosis"])
    check("the explanation is the why", deck.cards.first?.why == quiz.questions[0].explanation)
    check("the citation is kept", deck.cards.last?.source == "Glomerular disease, p.1")
}
check("the original is untouched", quiz.questions.count == 3 && quiz.cards.isEmpty)

// MCQ -> Cases
let cases = ModeConversion.convert(quiz, to: .qa)
check("MCQ turns into Cases instantly", cases?.qaCards.count == 2, "\(cases?.qaCards.count ?? -1)")
check("a long stem is a clinical case", cases?.qaCards.first?.type == .case)
check("a short stem is recall", cases?.qaCards.last?.type == .recall)
check("the answer leads, then why", cases?.qaCards.first?.answer.first == "Segmental sclerosis"
      && cases?.qaCards.first?.answer.count == 2)

// MCQ -> anything else is written, not rearranged
check("MCQ into OSCE needs writing", ModeConversion.convert(quiz, to: .osce) == nil)
check("MCQ into Textbook needs writing", ModeConversion.convert(quiz, to: .book) == nil)
check("a set is never turned into itself", ModeConversion.convert(quiz, to: .mcq) == nil)
check("nothing turns into Narrate", !ModeConversion.canTurn(quiz, into: .narrate))

// Cards -> MCQ: the deck's own answers are the distractors. The same deck
// CardQualityTests builds a quiz from, so the count is known: five of six.
func qa(_ front: String, _ answer: String, _ why: String) -> AnkiCard {
    AnkiCard(type: .qa, front: front, bullets: [answer], why: why)
}
var cardsSet = StudySet(name: "Lupus", subject: "Rheumatology", kind: .anki)
cardsSet.cards = [
    qa("Which drug lowers mortality in SLE?", "Hydroxychloroquine", "It lowers flares and damage accrual."),
    qa("Which antibody is the entry criterion for SLE?", "Antinuclear antibody", "Required before points are counted."),
    qa("Which antibody is most specific for SLE?", "Anti-double-stranded DNA", "Specific, and tracks nephritis."),
    qa("Which drug is used for lupus nephritis induction?", "Mycophenolate mofetil", "As effective as cyclophosphamide."),
    qa("Which test monitors disease activity in SLE?", "Complement C3 and C4", "They fall in active disease."),
    qa("Which skin sign spares the nasolabial folds?", "The malar rash", "Sparing separates it from rosacea."),
]
let answers = cardsSet.cards.compactMap { $0.bullets.first }
let fromCards = ModeConversion.convert(cardsSet, to: .mcq)
check("a deck turns into a quiz instantly", fromCards?.questions.count == 5,
      "\(fromCards?.questions.count ?? -1)")
if let fromCards {
    check("every option is one of the deck's own answers",
          fromCards.questions.allSatisfy { q in q.options.allSatisfy { answers.contains($0) } })
    check("every key is right", fromCards.questions.allSatisfy { q in
        cardsSet.cards.contains { $0.bullets.first == q.options[q.correctIndex] }
    })
}
var thin = cardsSet
thin.cards = Array(cardsSet.cards.prefix(2))
check("too thin a deck is written instead", ModeConversion.convert(thin, to: .mcq) == nil)

// Cards -> Cases, Cases -> Cards
let cardCases = ModeConversion.convert(cardsSet, to: .qa)
check("cards turn into Cases", cardCases?.qaCards.count == answers.count)
var cloze = StudySet(name: "HF", kind: .anki)
cloze.cards = [AnkiCard(type: .cloze, clozeText: "An ejection fraction of {{c1::40% or less}} defines HFrEF."),
               AnkiCard(type: .occlusion, imageIndex: 0)]
let clozeCases = ModeConversion.convert(cloze, to: .qa)
check("a cloze card asks its first gap", clozeCases?.qaCards.first?.answer == ["40% or less"],
      "\(clozeCases?.qaCards.first?.answer ?? [])")
check("a picture card is left out", clozeCases?.qaCards.count == 1)

var casesSet = StudySet(name: "Resp", kind: .qa)
casesSet.qaCards = [QACard(topic: "Asthma", type: .recall, stem: "Features of life-threatening asthma?",
                           answer: ["PEF < 33%", "Silent chest"]),
                    QACard(stem: "Nothing to say", answer: [])]
let casesDeck = ModeConversion.convert(casesSet, to: .anki)
check("Cases turn into cards", casesDeck?.cards.count == 1)
check("the answer points are the bullets", casesDeck?.cards.first?.bullets == ["PEF < 33%", "Silent chest"])
check("the topic already in the question is not repeated",
      casesDeck?.cards.first?.front == "Features of life-threatening asthma?")

// OSCE -> Cards, OSCE -> Cases
var osce = StudySet(name: "Skills", kind: .osce)
osce.osceChecklists = [OsceChecklist(title: "Venepuncture",
                                     steps: ["Wash hands", "Confirm identity", "Apply tourniquet"])]
let drill = ModeConversion.convert(osce, to: .anki)
check("a station turns into one card per step", drill?.cards.count == 3)
check("the first card asks for the first step",
      drill?.cards.first?.front == "Venepuncture: what is the first step?")
check("later cards ask what comes next",
      drill?.cards.last?.front == "Venepuncture: what comes after \u{201C}Confirm identity\u{201D}?"
          && drill?.cards.last?.bullets == ["Apply tourniquet"])
let talk = ModeConversion.convert(osce, to: .qa)
check("a station turns into one talk-through case", talk?.qaCards.first?.answer == osce.osceChecklists[0].steps)

// Textbook: always written
var book = StudySet(name: "Thyroid", kind: .book)
book.bookMarkdown = "# Thyroid\nHashimoto's is the commonest cause of hypothyroidism."
for kind in [StudySetKind.mcq, .anki, .qa, .osce] {
    check("a textbook into \(kind.label) is written", ModeConversion.convert(book, to: kind) == nil)
}

// the writer's material
check("the kept lecture is the material", ModeConversion.lecture(of: quiz)?.name == "Glomerular disease")
check("no lecture, no material from one", ModeConversion.lecture(of: cardsSet) == nil)
let quizText = ModeConversion.sourceText(of: quiz)
check("a quiz's text has its stems, answers and explanations",
      quizText.contains("Anti-PLA2R") && quizText.contains("Answer: Membranous nephropathy")
          && quizText.contains("FSGS"))
check("a station's text keeps its steps in order",
      ModeConversion.sourceText(of: osce) == "## Venepuncture\n- Wash hands\n- Confirm identity\n- Apply tourniquet")
check("a textbook's text is the book", ModeConversion.sourceText(of: book) == book.bookMarkdown)
check("a cloze card's text has its words, not its braces",
      ModeConversion.sourceText(of: cloze) == "An ejection fraction of 40% or less defines HFrEF.")

print(failures.isEmpty ? "\nALL MODE CONVERSION TESTS PASS"
                       : "\n\(failures.count) MODE CONVERSION TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
