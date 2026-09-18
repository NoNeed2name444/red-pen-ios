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
   == "Bold opening words of a", "a missing topic is taken from the opening words, unmarked")
ok(DeckBuilder.topic(from: "   ") == "Untitled", "and an empty one is still labelled")

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

print(failures == 0 ? "\nALL DECK TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
