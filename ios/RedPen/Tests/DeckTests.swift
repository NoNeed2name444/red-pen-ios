// Building a printable deck, and deciding which page a picture belongs on.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

// MARK: which page a picture goes on
//
// The rule: a picture belongs with the question unless it gives the answer
// away. What decides it is what the picture SAYS against what the answer says
// that the question does not.

let stem = "A 24-year-old returns with facial swelling. What is the diagnosis?"

ok(ImageSpoiler.placement(imageText: "", question: stem,
                          answer: "Membranous nephropathy") == .question,
   "a picture with no readable text stays with the question")

ok(ImageSpoiler.placement(imageText: "II aVF V1 V5 25mm/s", question: stem,
                          answer: "Membranous nephropathy") == .question,
   "an ECG's own furniture is not the answer, so it stays with the question")

ok(ImageSpoiler.placement(imageText: "Membranous nephropathy \u{2014} silver stain",
                          question: stem,
                          answer: "Membranous nephropathy") == .answer,
   "a picture captioned with the diagnosis is held back")

// The case that makes the "what the question did not already say" part matter.
// The picture is captioned with the organ, which the question already named,
// so it tells the student nothing they were not already told.
ok(ImageSpoiler.placement(imageText: "Kidney \u{2014} as shown",
                          question: "Label the layers of the kidney shown here.",
                          answer: "Kidney cortex, medulla, pelvis") == .question,
   "a picture repeating words the question already used reveals nothing")

// But one label out of three IS a third of the answer, and a student who sees
// it has been handed part of what they were asked to produce.
ok(ImageSpoiler.placement(imageText: "Kidney, cortex",
                          question: "Label the layers of the kidney shown here.",
                          answer: "Kidney cortex, medulla, pelvis") == .answer,
   "showing even one of the labels being asked for is enough to hold it back")

ok(ImageSpoiler.placement(imageText: "medulla and renal pelvis",
                          question: "Label the layers of the kidney shown here.",
                          answer: "Kidney cortex, medulla, pelvis") == .answer,
   "but one showing the labels being asked for is held back")

// Long answers should not be tripped by a single incidental word.
let longAnswer = """
Ascites from portal hypertension, confirmed by a serum-ascites albumin \
gradient above 1.1, managed with salt restriction, spironolactone and \
large-volume paracentesis with albumin cover
"""
ok(ImageSpoiler.placement(imageText: "Figure 3: abdominal ultrasound, spironolactone",
                          question: "How is this managed?",
                          answer: longAnswer) == .question,
   "one incidental word out of a long answer is not a spoiler")

ok(ImageSpoiler.placement(imageText: "portal hypertension gradient albumin paracentesis spironolactone",
                          question: "How is this managed?",
                          answer: longAnswer) == .answer,
   "but a picture carrying most of the answer's vocabulary is")

ok(ImageSpoiler.giveaway(imageText: "membranous nephropathy", question: stem,
                         answer: "Membranous nephropathy").contains("membranou")
   || ImageSpoiler.giveaway(imageText: "membranous nephropathy", question: stem,
                            answer: "Membranous nephropathy").contains("membranous"),
   "and it can say which word gave it away")

// MARK: normalising

ok(ImageSpoiler.words("The patient's figure") .isEmpty,
   "everyday and layout words are not evidence of anything")
ok(ImageSpoiler.words("Sjogren") == ImageSpoiler.words("Sj\u{00F6}gren"),
   "accents do not make a different word")
ok(ImageSpoiler.singular("cells") == "cell" && ImageSpoiler.singular("arteries") == "artery",
   "plurals fold to the singular")
ok(ImageSpoiler.singular("diabetes") == "diabete" || ImageSpoiler.singular("diabetes") == "diabetes",
   "and folding never has to be clever, only consistent")

// MARK: the palette

let mcq = DeckPalette.of(.mcq)
ok(mcq.shade().luminance < mcq.luminance, "shading darkens")
ok(mcq.tint().luminance > mcq.luminance, "tinting lightens")
ok(DeckPalette(red: 2, green: -1, blue: 0.5) == DeckPalette(red: 1, green: 0, blue: 0.5),
   "components outside the range are clamped rather than producing a colour that cannot exist")
ok(DeckPalette(red: 0, green: 0, blue: 0).hex == "#000000"
   && DeckPalette(red: 1, green: 1, blue: 1).hex == "#FFFFFF", "hex is hex")

// Amber is the bright one: white on it is close to unreadable in print, so its
// bar has to darken rather than carry white text as drawn.
let amber = DeckPalette.of(.qa)
ok(!amber.carriesWhiteText, "a bright tint is not asked to carry white text")
ok(amber.barFill.luminance < amber.luminance, "so its bar is filled with a darker shade")
ok(DeckPalette.of(.mcq).carriesWhiteText, "a dark tint carries white text as it is")

// MARK: building cards

let questions = [
    MCQQuestion(stem: "Which drug is first line?",
                options: ["Aspirin", "Warfarin", "Heparin"],
                correctIndex: 1, explanation: "Because of the indication."),
]
let fromMCQ = DeckBuilder.mcq(questions)
ok(fromMCQ.count == 1, "one card per question")
ok(fromMCQ[0].question.contains(.option(letter: "A", text: "Aspirin", correct: false)),
   "the options are on the question page")
ok(!fromMCQ[0].question.contains(where: {
    if case .option(_, _, let correct) = $0 { return correct }
    return false
}), "and none of them is marked correct there, which would give the game away")
ok(fromMCQ[0].answer.contains(.option(letter: "B", text: "Warfarin", correct: true)),
   "the answer page marks the right one")
ok(fromMCQ[0].answer.contains(.note(label: "Why", text: "Because of the indication.")),
   "and carries the explanation")

let stations = [OsceChecklist(title: "Cardiovascular examination",
                              steps: ["Introduce yourself", "Wash hands", "Expose the chest"])]
let fromOsce = DeckBuilder.osce(stations)
ok(fromOsce.count == 3, "a station becomes one card per step")
ok(fromOsce[0].answer == [.bullet(lead: "Step 1", text: "Introduce yourself")],
   "each answer is the step itself")
ok(fromOsce[0].topic == "Cardiovascular examination", "filed under the station")

ok(DeckBuilder.letter(0) == "A" && DeckBuilder.letter(25) == "Z", "options are lettered")
ok(DeckBuilder.letter(26) == "27", "and an implausible number of options does not crash")

ok(DeckBuilder.topic(from: "**Bold** opening words of a long stem that goes on")
   == "Bold opening words of a long stem that", "a stem with no ask falls back to its words, unmarked")
ok(DeckBuilder.topic(from: "   ") == "Untitled", "and an empty one is still labelled")

// The point of the label: two vignettes that open identically must not end up
// as the same index row, which is what taking the first few words did.
let firstStem = "A 24-year-old man presents with crushing chest pain. "
    + "Which coronary artery is most likely occluded?"
let secondStem = "A 24-year-old man presents with crushing chest pain. "
    + "What is the immediate next investigation?"
ok(DeckBuilder.topic(from: firstStem) != DeckBuilder.topic(from: secondStem),
   "two stems with the same opening do not collapse to one row")
ok(DeckBuilder.topic(from: firstStem) == "Coronary artery is most likely occluded",
   "the label is the ask, with its scaffolding words dropped")
ok(!DeckBuilder.topic(from: firstStem).lowercased().contains("24-year-old"),
   "and not the vignette every card in the deck shares")

// MARK: numbering and the contents index

var set = StudySet(name: "Deck", kind: .osce)
set.osceChecklists = stations
let numbered = DeckBuilder.cards(for: set)
ok(numbered.map(\.number) == [1, 2, 3], "cards are numbered from one, in order")

let rows = DeckIndex.rows(numbered)
ok(rows.count == 1, "consecutive cards on one topic collapse to a single row")
ok(rows[0].range == "1\u{2013}3", "shown as a range")

var mixed = numbered
mixed.append(DeckCard(number: 4, topic: "Abdominal examination", kindLabel: "STEP",
                      question: [], answer: []))
ok(DeckIndex.rows(mixed).count == 2, "a new topic starts a new row")
ok(DeckIndex.rows(mixed)[1].range == "4", "a single card shows one number, not a range")

// An Anki set exports as .apkg, so it must not quietly produce a PDF instead.
ok(!DeckBuilder.printsAsPDF(.anki), "an Anki set does not print as a PDF")
ok(StudySetKind.allCases.filter { !DeckBuilder.printsAsPDF($0) } == [.anki],
   "and it is the only mode that does not")

// MARK: a second copy of a set gets its own items

// A conflict copy or a re-imported file that kept its cards' ids shared one
// schedule with the original, since the schedule is kept by card id.
var original = StudySet(name: "Lupus", kind: .anki)
original.cards = [AnkiCard(type: .qa, front: "Malar rash spares?", bullets: ["Nasolabial folds"]),
                  AnkiCard(type: .qa, front: "Entry criterion?", bullets: ["ANA"])]
original.questions = [MCQQuestion(stem: "Which?", options: ["A", "B"], correctIndex: 1, explanation: "")]
let copy = original.withNewItemIDs()
ok(Set(copy.cards.map(\.id)).isDisjoint(with: Set(original.cards.map(\.id))),
   "a copy's cards have ids of their own, so it has a schedule of its own")
ok(Set(copy.questions.map(\.id)).isDisjoint(with: Set(original.questions.map(\.id))),
   "and so do its questions")
ok(copy.cards.map(\.front) == original.cards.map(\.front) && copy.questions[0].correctIndex == 1,
   "with everything else as it was")

// A conflict copy beside the version that won: only the cards both hold get
// new ids. A card added on this device alone keeps its id - and its schedule.
var losing = original
losing.cards.append(AnkiCard(type: .qa, front: "Only here?", bullets: ["Yes"]))
let kept = losing.withNewItemIDs(sharedWith: original)
ok(Set(kept.cards.prefix(2).map(\.id)).isDisjoint(with: original.itemIDs),
   "a conflict copy's cards shared with the winner are renewed")
ok(kept.cards[2].id == losing.cards[2].id,
   "and a card only the copy has keeps its id, so its schedule stays with it")
ok(kept.itemIDs.isDisjoint(with: original.itemIDs),
   "so no card is in both decks, and deleting one never forgets the other's schedule")


// MARK: the explanation, arranged

let asdOptions: [DeckBlock] = [
    .option(letter: "A", text: "Pulmonary valve stenosis", correct: false),
    .option(letter: "B", text: "Ventricular septal defect", correct: false),
    .option(letter: "E", text: "Atrial septal defect", correct: true),
]
let asdWhy = "Fixed splitting of S2 that doesn't vary with respiration is the classic "
    + "finding of an atrial septal defect. Ventricular septal defect is tempting because "
    + "it is also a left-to-right shunt, but it produces a pansystolic murmur."
let arranged = Explanation.split(asdWhy, options: asdOptions)

ok(arranged.traps.count == 1, "the sentence about another option is lifted out")
ok(arranged.core.contains("Fixed splitting") && !arranged.core.contains("tempting"),
   "and what makes the right answer right is left behind")
ok(arranged.traps.first?.hasPrefix("Ventricular septal defect") == true,
   "the lifted sentence is the whole sentence, not a fragment")

// The match is on words, because an explanation rarely repeats an option
// verbatim - this is the case that a substring test got wrong.
let looseOptions: [DeckBlock] = [
    .option(letter: "B", text: "Radial-radial pulse delay", correct: false),
    .option(letter: "D", text: "Femoral pulses", correct: true),
]
let looseWhy = "Femoral pulses must be palpated on every examination. "
    + "Radial-radial delay is a tempting near-miss, but the finding described is weak."
ok(Explanation.split(looseWhy, options: looseOptions).traps.count == 1,
   "a near-miss worded differently is still recognised")

ok(Explanation.split("One sentence only.", options: asdOptions).traps.isEmpty,
   "a single sentence is never split")
ok(Explanation.split(asdWhy, options: []).core == asdWhy,
   "and with no other options to talk about, nothing is lifted")

let allTraps = "Ventricular septal defect is wrong. Pulmonary valve stenosis is wrong."
ok(Explanation.split(allTraps, options: asdOptions).traps.isEmpty,
   "an explanation that is nothing but traps keeps its own shape")

ok(Explanation.sentences("A. B! C?").count == 3, "sentences end where punctuation says")

// The false positive that an overlap test alone produces: this sentence is
// about the right answer's mechanism, but shares "pulmonary" and "valve" with
// one of the distractors.
let mechanismOptions: [DeckBlock] = [
    .option(letter: "A", text: "Pulmonary valve stenosis", correct: false),
    .option(letter: "E", text: "Atrial septal defect", correct: true),
]
let mechanismWhy = "Fixed splitting is the classic finding of an atrial septal defect, "
    + "caused by delayed pulmonary valve closure. Pulmonary valve stenosis gives an "
    + "ejection click instead."
let mechanism = Explanation.split(mechanismWhy, options: mechanismOptions)
ok(mechanism.traps.count == 1,
   "a sentence is a trap only when it looks more like the distractor than like the answer")
ok(mechanism.core.contains("delayed pulmonary valve closure"),
   "so the right answer's own mechanism stays in the core")

print(failures == 0 ? "\nALL DECK TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
