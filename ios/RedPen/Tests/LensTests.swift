// Study Lens: finding questions in what the camera reads, keeping one chip per
// question as the camera moves, reading the model's answer for every type, and
// turning a capture into each study mode.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// Lines laid out top to bottom in one column, as the recogniser gives them.
func column(_ lines: [String], x: Double = 0.05, top: Double = 0.05, width: Double = 0.85,
            step: Double = 0.03, height: Double = 0.022) -> [LensTextBlock] {
    var out: [LensTextBlock] = []
    var y: Double = top
    for line in lines {
        if line.isEmpty { y += step; continue }
        out.append(LensTextBlock(line, x: x, y: y, w: width, h: height))
        y += step
    }
    return out
}

func types(_ qs: [DetectedQuestion]) -> [LensQuestionType] { qs.map(\.type) }

// MARK: - typed MCQ, A-E

let typed = column([
    "1. Which drug is first-line for anaphylaxis in adults?",
    "A. Chlorphenamine",
    "B. Intramuscular adrenaline",
    "C. Hydrocortisone",
    "D. Salbutamol",
    "E. Intravenous fluids",
])
let q1 = QuestionDetector.detect(typed)
check("typed MCQ: one question", q1.count == 1, "\(q1.count)")
if let q = q1.first {
    check("typed MCQ: five options", q.options.count == 5, "\(q.options)")
    check("typed MCQ: stem without its number", q.stem == "Which drug is first-line for anaphylaxis in adults?", q.stem)
    check("typed MCQ: number kept", q.number == "1")
    check("typed MCQ: 'first-line' reads as single best answer", q.type == .bestAnswer, q.type.rawValue)
    check("typed MCQ: option text", q.options[1].text == "Intramuscular adrenaline", q.options[1].text)
    check("typed MCQ: box covers every line", q.box.maxY > 0.2 && q.box.minY < 0.06, "\(q.box)")
    check("typed MCQ: full text lettered", q.fullText.contains("\nE. Intravenous fluids"))
}

// MARK: - several markers styles

let styles = column([
    "Q2 Which of these nerves supplies the deltoid?",
    "(A) Radial",
    "(B) Axillary",
    "(C) Musculocutaneous",
    "(D) Ulnar",
    "",
    "Question 3: Which enzyme is deficient in classic PKU?",
    "a) Tyrosinase",
    "b) Phenylalanine hydroxylase",
    "c) Homogentisate oxidase",
    "",
    "4) Which of the following is an ACE inhibitor?",
    "\u{24B6} Losartan",
    "\u{24B7} Ramipril",
    "\u{24B8} Amlodipine",
])
let q2 = QuestionDetector.detect(styles)
check("marker styles: three questions", q2.count == 3, "\(q2.map(\.stem))")
check("marker styles: all MCQ", types(q2) == [.mcq, .mcq, .mcq], "\(types(q2))")
check("marker styles: option counts 4/3/3", q2.map(\.options.count) == [4, 3, 3], "\(q2.map(\.options.count))")
check("marker styles: Q2 numbered", q2.first?.number == "2")
check("marker styles: circled option text", q2.last?.options[1].text == "Ramipril", "\(String(describing: q2.last?.options))")

// MARK: - numbered options

let numbered = column([
    "Which of the following causes a raised anion gap acidosis?",
    "1. Diarrhoea",
    "2. Diabetic ketoacidosis",
    "3. Renal tubular acidosis type 2",
    "4. Acetazolamide",
])
let q3 = QuestionDetector.detect(numbered)
check("numbered options: one question", q3.count == 1, "\(q3.map(\.stem))")
check("numbered options: four options", q3.first?.options.count == 4, "\(String(describing: q3.first?.options))")
check("numbered options: markers are numbers", q3.first?.options.first?.marker == "1")

// numbered questions are not taken for options
let numberedQs = column([
    "1. What is the commonest cause of community-acquired pneumonia?",
    "2. Which organism causes typhoid fever?",
    "3. Define sepsis.",
])
let q3b = QuestionDetector.detect(numberedQs)
check("numbered questions stay separate", q3b.count == 3, "\(q3b.map(\.stem))")
check("numbered questions: short answer", types(q3b) == [.shortAnswer, .shortAnswer, .shortAnswer], "\(types(q3b))")

// MARK: - two columns

var twoCol: [LensTextBlock] = [LensTextBlock("Cardiology - Practice paper", x: 0.2, y: 0.02, w: 0.6, h: 0.025)]
twoCol += column([
    "5. A 64-year-old man has crushing central",
    "chest pain for 40 minutes. ECG shows ST",
    "elevation in II, III and aVF. Which artery",
    "is most likely occluded?",
    "A. Left anterior descending",
    "B. Right coronary",
    "C. Left circumflex",
    "D. Left main stem",
], x: 0.04, top: 0.08, width: 0.42)
twoCol += column([
    "6. Which drug reduces mortality in heart",
    "failure with reduced ejection fraction?",
    "A. Digoxin",
    "B. Furosemide",
    "C. Bisoprolol",
    "D. Amlodipine",
], x: 0.54, top: 0.08, width: 0.42)
let q4 = QuestionDetector.detect(twoCol)
check("two columns: two questions", q4.count == 2, "\(q4.map(\.stem))")
if q4.count == 2 {
    check("two columns: left first", q4[0].number == "5" && q4[1].number == "6")
    check("two columns: wrapped stem joined", q4[0].stem.hasSuffix("Which artery is most likely occluded?"), q4[0].stem)
    check("two columns: nothing from the other column", !q4[0].stem.contains("heart"), q4[0].stem)
    check("two columns: four options each", q4[0].options.count == 4 && q4[1].options.count == 4)
    check("two columns: vignette with options is SBA", q4[0].type == .bestAnswer, q4[0].type.rawValue)
    check("two columns: boxes in their columns", q4[0].box.maxX < 0.5 && q4[1].box.minX > 0.5)
}
check("gutter found between the columns", (QuestionDetector.gutter(twoCol) ?? 0) > 0.45)
check("no gutter in one column", QuestionDetector.gutter(typed) == nil)

// options printed two across stay one question
var grid: [LensTextBlock] = column(["7. Which vitamin deficiency causes scurvy?"])
grid.append(LensTextBlock("A. Vitamin A", x: 0.05, y: 0.08, w: 0.3, h: 0.022))
grid.append(LensTextBlock("B. Vitamin C", x: 0.55, y: 0.08, w: 0.3, h: 0.022))
grid.append(LensTextBlock("C. Vitamin D", x: 0.05, y: 0.11, w: 0.3, h: 0.022))
grid.append(LensTextBlock("D. Vitamin K", x: 0.55, y: 0.11, w: 0.3, h: 0.022))
let q5 = QuestionDetector.detect(grid)
check("options in a grid: one question", q5.count == 1, "\(q5.map(\.stem))")
check("options in a grid: in order A-D", q5.first?.options.map(\.marker) == ["A", "B", "C", "D"], "\(String(describing: q5.first?.options))")

// options run on one line
let inline = column(["Which is a loop diuretic? A. Furosemide B. Spironolactone C. Bendroflumethiazide"])
let q6 = QuestionDetector.detect(inline)
check("inline options: split", q6.first?.options.count == 3, "\(String(describing: q6.first))")
check("inline options: stem alone", q6.first?.stem == "Which is a loop diuretic?", q6.first?.stem ?? "")

// MARK: - case vignette

let vignette = column([
    "A 23-year-old woman presents with fever, neck stiffness and a",
    "non-blanching purpuric rash on her legs. She is drowsy. Her",
    "blood pressure is 85/50 mmHg. What is the most likely diagnosis",
    "and what is the next step?",
])
let q7 = QuestionDetector.detect(vignette)
check("vignette: one question", q7.count == 1, "\(q7.count)")
check("vignette: clinical case", q7.first?.type == .clinicalCase, q7.first?.type.rawValue ?? "none")
check("vignette: lines joined", q7.first?.stem.contains("fever, neck stiffness and a non-blanching") == true, q7.first?.stem ?? "")

// MARK: - true/false, cloze, calculation, OSCE, image

let tf = QuestionDetector.detect(column(["True or false: Metformin causes hypoglycaemia when used alone."]))
check("true/false by its words", tf.first?.type == .trueFalse, tf.first?.type.rawValue ?? "none")
let tfOptions = QuestionDetector.detect(column([
    "Aspirin irreversibly inhibits COX-1.", "A. True", "B. False",
]))
check("true/false by its options", tfOptions.first?.type == .trueFalse, tfOptions.first?.type.rawValue ?? "none")

let cloze = QuestionDetector.detect(column(["The first-line treatment for absence seizures is ________."]))
check("fill in the blank", cloze.first?.type == .cloze, cloze.first?.type.rawValue ?? "none")

let calc = QuestionDetector.detect(column([
    "Calculate the maintenance fluid requirement for a 24 kg child",
    "using the 4-2-1 rule. Give your answer in mL/h.",
]))
check("calculation with units", calc.first?.type == .calculation, calc.first?.type.rawValue ?? "none")
let calc2 = QuestionDetector.detect(column([
    "Na 140 mmol/L, Cl 100 mmol/L, HCO3 12 mmol/L. What is the anion gap?",
]))
check("calculation from values", calc2.first?.type == .calculation, calc2.first?.type.rawValue ?? "none")

let osce = QuestionDetector.detect(column([
    "Station 4. You have 8 minutes. Take a focused history from this",
    "patient who has come in with chest pain.",
]))
check("OSCE instruction", osce.first?.type == .osce, osce.first?.type.rawValue ?? "none")
let osce2 = QuestionDetector.detect(column(["Examine this patient's cranial nerves."]))
check("OSCE: examine", osce2.first?.type == .osce, osce2.first?.type.rawValue ?? "none")

let image = QuestionDetector.detect(column(["Name the structure labelled X in the diagram."]))
check("image labelling", image.first?.type == .imageLabel, image.first?.type.rawValue ?? "none")
let narrow = QuestionDetector.detect(column(["What causes narrowing of the aortic valve in the elderly?"]))
check("'narrowing' is not an arrow", narrow.first?.type == .shortAnswer, narrow.first?.type.rawValue ?? "none")

// MARK: - OCR noise

let noisy = column([
    "Page 12",
    "8",
    "Which antibiotic is associated with a",
    "disulfi-",
    "ram-like reaction?",
    "A) Amoxicillin",
    "8. Metronidazole",
    "C) Doxycycline",
    "\u{00A9} 2024 Exam Press",
])
let q8 = QuestionDetector.detect(noisy)
check("noise: page number and footer dropped", q8.count == 1, "\(q8.map(\.stem))")
check("noise: hyphenated wrap rejoined", q8.first?.stem.contains("disulfiram-like") == true, q8.first?.stem ?? "")
check("noise: '8.' read as B", q8.first?.options.map(\.text) == ["Amoxicillin", "Metronidazole", "Doxycycline"],
      "\(String(describing: q8.first?.options))")

let prose = QuestionDetector.detect(column([
    "Chapter 3. Renal physiology",
    "The kidney filters about 180 L of plasma every day.",
]))
check("prose is not a question", prose.isEmpty, "\(prose.map(\.stem))")

let ecoli = QuestionDetector.detect(column([
    "E. coli is the commonest cause of which infection?",
    "A. Cellulitis", "B. Urinary tract infection", "C. Meningitis in adults",
]))
check("'E. coli' at the start is not option E", ecoli.first?.options.count == 3 && ecoli.first?.stem.hasPrefix("E. coli") == true,
      "\(String(describing: ecoli.first))")

// MARK: - keys and tracking

let a = QuestionDetector.detect(typed).first!
var shifted: [LensTextBlock] = typed.map { LensTextBlock($0.text, $0.box.offsetBy(dx: 0.02, dy: 0.03)) }
let b = QuestionDetector.detect(shifted).first!
check("same words, same key wherever they are", a.key == b.key)
shifted[2] = LensTextBlock("B. Intramuscu1ar adrenaline", shifted[2].box)
let c = QuestionDetector.detect(shifted).first!
check("a misread letter changes the key", a.key != c.key)
check("but the words mostly agree", LensHash.similarity(a.fullText, c.fullText) > 0.7)

var tracker = LensTracker()
tracker.update([a])
check("not shown after one sighting", tracker.visible.isEmpty)
tracker.update([b])
check("shown after two", tracker.visible.count == 1)
let firstID: Int = tracker.visible.first?.id ?? -1
tracker.update([c])
check("a misread keeps the same chip", tracker.tracks.count == 1 && tracker.visible.first?.id == firstID, "\(tracker.tracks.count)")
let before: CGRect = tracker.tracks[0].box
var far = a
far.box = a.box.offsetBy(dx: 0, dy: 0.1)
tracker.update([far])
let after: CGRect = tracker.tracks[0].box
check("the box eases, not jumps", after.minY > before.minY && after.minY < far.box.minY, "\(before.minY) \(after.minY)")
for _ in 0..<5 { tracker.update([]) }
check("gone after it leaves the frame", tracker.tracks.isEmpty)

var many = LensTracker(minHits: 1)
var eight: [DetectedQuestion] = []
for i in 0..<8 {
    var q = a
    q.key = "k\(i)"
    q.stem = "Question number \(i) about something entirely different \(i * 7)"
    q.box = CGRect(x: 0.1, y: Double(i) * 0.11, width: 0.8, height: 0.08)
    eight.append(q)
}
many.update(eight)
check("at most six chips", many.visible.count == 6, "\(many.visible.count)")
let ys: [CGFloat] = many.visible.map { $0.box.minY }
check("chips in reading order", ys == ys.sorted())
check("the six nearest the middle", !many.visible.contains { $0.question.key == "k0" || $0.question.key == "k1" })

var gate = LensActivityGate(smooth: false)
check("reads at first", gate.shouldRead(at: 0))
gate.noteRead(changed: true, at: 0)
check("waits for the interval", !gate.shouldRead(at: 0.1) && gate.shouldRead(at: 0.4))
gate.noteRead(changed: false, at: 1)
check("still active soon after a change", gate.isActive(at: 2.5))
check("pauses when nothing moves", !gate.isActive(at: 3.5))
gate.noteMotion(0.02, at: 3.6)
check("a tremor does not wake it", !gate.isActive(at: 3.7))
gate.noteMotion(0.5, at: 3.8)
check("moving wakes it", gate.shouldRead(at: 3.9))
check("smooth reads less often", LensActivityGate.interval(smooth: true) > LensActivityGate.interval(smooth: false))

let origins: [CGPoint] = LensLayout.chipOrigins([CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1),
                                                 CGRect(x: 0.1, y: 0.205, width: 0.5, height: 0.1)],
                                                chip: CGSize(width: 100, height: 30), in: CGSize(width: 400, height: 800))
check("overlapping chips pushed apart", origins.count == 2 && abs(origins[1].y - origins[0].y) >= 30, "\(origins)")
let filled: CGRect = LensLayout.fill(CGRect(x: 0, y: 0, width: 1, height: 1), image: CGSize(width: 1080, height: 1920),
                                     view: CGSize(width: 390, height: 844))
check("aspect fill covers the view", filled.width >= 390 && filled.height >= 844, "\(filled)")
check("vision boxes flipped", LensLayout.flipped(CGRect(x: 0, y: 0.7, width: 1, height: 0.2)).minY - 0.1 < 0.0001)

// MARK: - reading replies

let mcqQ: DetectedQuestion = q1.first!
let mcqReply = """
<think>adrenaline is first line</think>
Here you go:
```json
{"answer": "B", "explanation": "IM adrenaline 0.5 mg reverses bronchospasm and hypotension.",
 "why": {"A": "An antihistamine; adjunct only.", "B": "First-line.", "C": "Slow; prevents biphasic reaction at best.",
 "D": "Treats wheeze only.", "E": "Supportive."}, "key_points": ["0.5 mg IM, anterolateral thigh"]}
```
"""
let mcqA = LensAnswerParser.parse(mcqReply, for: mcqQ)
check("MCQ reply read", mcqA?.correctIndex == 1, "\(String(describing: mcqA))")
check("MCQ reply: a note per option", mcqA?.optionNotes.count == 5 && mcqA?.optionNotes[0].contains("antihistamine") == true)
check("MCQ reply: answer text", mcqA?.answer == "Intramuscular adrenaline")
check("MCQ reply: key points", mcqA?.keyPoints.first?.contains("IM") == true)
let mcqList = LensAnswerParser.parse(#"{"correct_answer":"(b) Intramuscular adrenaline","why":["no","yes","no","no","no"]}"#, for: mcqQ)
check("MCQ reply: key written as '(b) ...' and notes as a list", mcqList?.correctIndex == 1 && mcqList?.optionNotes[1] == "yes",
      "\(String(describing: mcqList))")
let mcqProse = LensAnswerParser.parse("The correct answer is B because adrenaline works fastest.", for: mcqQ)
check("MCQ reply without JSON still read", mcqProse?.correctIndex == 1)
check("MCQ reply naming no option refused", LensAnswerParser.parse(#"{"answer":"Z"}"#, for: mcqQ) == nil)

let tfQ: DetectedQuestion = tf.first!
let tfA = LensAnswerParser.parse(#"{"verdict": false, "explanation": "It does not stimulate insulin.", "correction": "Metformin alone rarely causes hypoglycaemia."}"#, for: tfQ)
check("T/F reply read", tfA?.verdict == false && tfA?.answer == "False" && tfA?.correction.isEmpty == false)
let tfString = LensAnswerParser.parse(#"{"verdict": "True", "explanation": "x"}"#, for: tfQ)
check("T/F verdict as a string", tfString?.verdict == true)

let clozeQ: DetectedQuestion = cloze.first!
let clozeA = LensAnswerParser.parse(#"{"answer":"ethosuximide","explanation":"Blocks T-type calcium channels.","distractors":["carbamazepine","phenytoin","gabapentin"]}"#, for: clozeQ)
check("cloze reply read", clozeA?.answer == "ethosuximide")
check("cloze filled in when the model did not", clozeA?.filled == "The first-line treatment for absence seizures is ethosuximide.", clozeA?.filled ?? "")

let calcQ: DetectedQuestion = calc.first!
let calcA = LensAnswerParser.parse(#"{"steps":["First 10 kg: 4 mL/kg/h = 40 mL/h","Next 10 kg: 2 mL/kg/h = 20 mL/h","Remaining 4 kg: 1 mL/kg/h = 4 mL/h"],"answer":"64 mL/h","explanation":"4-2-1 rule.","distractors":["60 mL/h","72 mL/h","48 mL/h"]}"#, for: calcQ)
check("calculation reply: steps and result", calcA?.steps.count == 3 && calcA?.answer == "64 mL/h")

let caseQ: DetectedQuestion = q7.first!
let caseA = LensAnswerParser.parse("""
{"diagnosis":"Meningococcal septicaemia","differential":{"most_likely":[{"name":"Meningococcal septicaemia","supporting":["purpuric rash","hypotension"],"against":[],"test":"blood cultures, PCR"}],"cant_miss":[{"name":"Toxic shock syndrome"}]},
"next_step":"IV ceftriaxone immediately","explanation":"Fever, meningism and a non-blanching rash.","distractors":["ITP","HSP","Viral meningitis"]}
""", for: caseQ)
check("case reply: diagnosis and next step", caseA?.diagnosis == "Meningococcal septicaemia" && caseA?.nextStep.hasPrefix("IV") == true)
check("case reply: differential read in tiers", caseA?.differential?.mostLikely.first?.supporting.count == 2 && caseA?.differential?.cantMiss.count == 1,
      "\(String(describing: caseA?.differential))")

let osceQ: DetectedQuestion = osce.first!
let osceA = LensAnswerParser.parse(#"{"title":"Chest pain history","steps":["Introduce yourself and confirm identity","Gain consent","SOCRATES for the pain","Associated symptoms","Risk factors","Summarise and thank"],"explanation":"Structure."}"#, for: osceQ)
check("OSCE reply: steps in order", osceA?.steps.count == 6 && osceA?.steps.first?.hasPrefix("Introduce") == true)
check("OSCE reply without steps refused", LensAnswerParser.parse(#"{"title":"x"}"#, for: osceQ) == nil)

let shortQ: DetectedQuestion = q3b.first!
let shortA = LensAnswerParser.parse(#"{"answer":"Streptococcus pneumoniae","explanation":"Commonest in every age group.","key_points":["Gram-positive diplococcus"],"distractors":["Haemophilus influenzae","Staphylococcus aureus","Mycoplasma pneumoniae"]}"#, for: shortQ)
check("short answer reply", shortA?.answer == "Streptococcus pneumoniae" && shortA?.distractors.count == 3)
check("garbage refused for a case", LensAnswerParser.parse("sorry", for: caseQ) == nil)

let prompt: String = LensPrompt.user(for: mcqQ)
check("prompt holds the lettered question", prompt.contains("E. Intravenous fluids") && prompt.contains("\"E\":"))
check("prompt for an image says the picture is not sent", LensPrompt.user(for: image.first!).contains("not its picture"))

// MARK: - into each mode

if let mcqA {
    let question = LensConversion.question(mcqQ, mcqA)
    check("into Questions: keyed and tagged", question?.correctIndex == 1 && question?.tags == ["Lens"] && question?.source == "Study Lens")
    check("into Questions: wrong options explained", question?.explanation.contains("Chlorphenamine is not the answer") == true,
          question?.explanation ?? "")
    let deck = LensConversion.cards(mcqQ, mcqA)
    check("into Cards: one card with the right answer", deck.count == 1 && deck.first?.bullets == ["Intramuscular adrenaline"])
    check("into Cards: tagged", deck.first?.tags == ["Lens"])
    let caseCard = LensConversion.caseCard(mcqQ, mcqA, topic: "Emergency")
    check("into Cases", caseCard?.answer.first == "Intramuscular adrenaline")
    let note = LensConversion.note(mcqQ, mcqA)
    check("into Ideas: linked to the hub note", note.body.contains("[[Lens captures]]") && note.body.contains("**Answer:** Intramuscular adrenaline"))
    let script = LensConversion.narration(mcqQ, mcqA)
    check("into Audio: question, options, answer", script.count >= 7 && script.contains { $0.text == "The answer is Intramuscular adrenaline." })
    check("into OSCE: too little to make a station", LensConversion.station(mcqQ, mcqA) == nil)
    var set = LensConversion.newSet(for: .questions)!
    check("new set is 'Lens captures', tagged", set.name == "Lens captures" && set.kind == .mcq && set.tags == ["Lens"])
    set = LensConversion.adding(mcqQ, mcqA, to: set)!
    check("added to the set", set.questions.count == 1)
    var existing = StudySet(name: "Emergency", kind: .anki)
    existing.tags = ["Step 2"]
    existing = LensConversion.adding(mcqQ, mcqA, to: existing)!
    check("added to an existing deck, its tags kept", existing.cards.count == 1 && existing.tags == ["Step 2", "Lens"])
    check("no textbook pages from a capture", LensConversion.adding(mcqQ, mcqA, to: StudySet(name: "B", kind: .book)) == nil)
}
if let tfA {
    let question = LensConversion.question(tfQ, tfA)
    check("T/F into Questions: True/False keyed False", question?.options == ["True", "False"] && question?.correctIndex == 1)
    let card = LensConversion.cards(tfQ, tfA).first
    check("T/F into Cards: the correction on the back", card?.bullets.first?.contains("rarely causes") == true, "\(String(describing: card))")
}
if let clozeA {
    let card = LensConversion.cards(clozeQ, clozeA).first
    check("cloze into Cards: a cloze card", card?.type == .cloze && card?.clozeText == "The first-line treatment for absence seizures is {{c1::ethosuximide}}.",
          card?.clozeText ?? "")
    let question = LensConversion.question(clozeQ, clozeA)
    check("cloze into Questions: answer among its distractors", question?.options.count == 4 && question?.options[question!.correctIndex] == "ethosuximide")
    let again = LensConversion.question(clozeQ, clozeA)
    check("same order every time", question?.options == again?.options)
}
if let calcA {
    let card = LensConversion.cards(calcQ, calcA).first
    check("calc into Cards: result on the back, working as why", card?.bullets == ["**64 mL/h**"] && card?.why.contains("\u{2192}") == true)
    check("calc into OSCE: its steps as a station", LensConversion.station(calcQ, calcA)?.steps.count == 3)
}
if let caseA {
    let card = LensConversion.caseCard(caseQ, caseA, topic: "General")
    check("case into Cases: a clinical case with its differential", card?.type == .case && card?.differential != nil && card?.topic == "")
    check("case into Questions: diagnosis among distractors", LensConversion.question(caseQ, caseA)?.options.contains("Meningococcal septicaemia") == true)
}
if let osceA {
    let station = LensConversion.station(osceQ, osceA)
    check("OSCE into OSCE: titled station", station?.title == "Chest pain history" && station?.steps.count == 6)
    let cards = LensConversion.cards(osceQ, osceA)
    check("OSCE into Cards: one card per step", cards.count == 6)
    check("OSCE cannot be a question", LensConversion.question(osceQ, osceA) == nil)
    check("the picker knows it", !LensConversion.can(osceQ, osceA, goTo: .questions) && LensConversion.can(osceQ, osceA, goTo: .osce))
}
check("suggested destinations", LensDestination.suggested(for: .clinicalCase) == .cases && LensDestination.suggested(for: .cloze) == .cards)
check("sentences keep 'E. coli' whole", LensConversion.sentences("E. coli causes it. Treat early.").count == 2)

print(failures.isEmpty ? "\nall lens checks passed" : "\n\(failures.count) FAILED: \(failures)")
exit(failures.isEmpty ? 0 : 1)
