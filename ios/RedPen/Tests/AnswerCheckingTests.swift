// Every place an answer is judged right or wrong. The one failure that matters
// here is the one a student notices at once and never forgives: a right answer
// marked wrong, or a wrong one marked right. So each check below picks an
// answer by what it SAYS - the text on the button, the word spoken, the side
// swiped to - and asserts the verdict, rather than trusting an index.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: - shuffled options: slot on screen vs index in the question

/// Every ordering of 0..<n.
func permutations(_ n: Int) -> [[Int]] {
    if n == 0 { return [[]] }
    var out: [[Int]] = []
    for smaller in permutations(n - 1) {
        for i in 0...smaller.count {
            var p = smaller
            p.insert(n - 1, at: i)
            out.append(p)
        }
    }
    return out
}

let question = MCQQuestion(stem: "Which drug is first line for trigeminal neuralgia?",
                           options: ["Amitriptyline", "Carbamazepine", "Gabapentin", "Sumatriptan", "Pregabalin"],
                           correctIndex: 1, explanation: "Carbamazepine.")
var everyOrderRight = true
var everyWrongWrong = true
var summaryAgrees = true
var pickedIsOriginal = true
for order in permutations(5) {
    // what the student sees in each slot, and taps by its text
    let shown: [String] = order.map { question.options[$0] }
    guard let rightSlot = shown.firstIndex(of: "Carbamazepine") else { everyOrderRight = false; continue }
    if !OptionOrder.isCorrect(slot: rightSlot, correctIndex: question.correctIndex, order: order) {
        everyOrderRight = false
    }
    if OptionOrder.slot(of: question.correctIndex, in: order) != rightSlot { everyOrderRight = false }
    for slot in shown.indices where slot != rightSlot {
        if OptionOrder.isCorrect(slot: slot, correctIndex: question.correctIndex, order: order) {
            everyWrongWrong = false
        }
    }
    // the answer handed to the summary and the store is in the question's
    // own numbering, and marks the same way
    for slot in shown.indices {
        let original = OptionOrder.original(ofSlot: slot, in: order)
        if original.map({ question.options[$0] }) != shown[slot] { pickedIsOriginal = false }
        let handedOver = MCQAnswer(selected: original, checked: true)
        let quizSaid = OptionOrder.isCorrect(slot: slot, correctIndex: question.correctIndex, order: order)
        if handedOver.isCorrect(for: question) != quizSaid { summaryAgrees = false }
    }
}
check("the right option is marked right in all 120 orders", everyOrderRight)
check("every other option is marked wrong in all 120 orders", everyWrongWrong)
check("the summary marks exactly as the quiz did", summaryAgrees)
check("the option recorded as picked is the one tapped, in the question's own numbering", pickedIsOriginal)

check("no answer is not right", !OptionOrder.isCorrect(slot: nil, correctIndex: 1, order: [0, 1, 2]))
check("a slot past the end is not right", !OptionOrder.isCorrect(slot: 7, correctIndex: 1, order: [0, 1, 2]))
check("a checked but unanswered question is wrong in the summary",
      !MCQAnswer(selected: nil, checked: true).isCorrect(for: question))
check("a right answer that was never checked does not score",
      !MCQAnswer(selected: 1, checked: false).isCorrect(for: question))

// a saved order that no longer fits the question (it was edited) is not used
check("a valid saved order is kept", OptionOrder.valid([2, 0, 1], count: 3) == [2, 0, 1])
check("an order for fewer options falls back to the written order",
      OptionOrder.valid([1, 0], count: 3) == [0, 1, 2])
check("an order for more options falls back", OptionOrder.valid([3, 1, 0, 2], count: 3) == [0, 1, 2])
check("an order with a repeat falls back", OptionOrder.valid([0, 0, 1], count: 3) == [0, 1, 2])
check("no saved order is the written order", OptionOrder.valid(nil, count: 4) == [0, 1, 2, 3])
let fresh = OptionOrder.make(count: 5, shuffle: true)
check("a fresh shuffle is an ordering of every option", fresh.sorted() == [0, 1, 2, 3, 4], "\(fresh)")
check("unshuffled is as written", OptionOrder.make(count: 4, shuffle: false) == [0, 1, 2, 3])
check("a key missing from the options is in no slot", OptionOrder.slot(of: 5, in: [0, 1, 2]) == nil)

// MARK: - a deck turned into a quiz: the key is the card's answer

func qa(_ front: String, _ answer: String, why: String = "") -> AnkiCard {
    AnkiCard(type: .qa, front: front, bullets: [answer], why: why)
}
let heartDeck: [AnkiCard] = [
    qa("Which drug is first line for rate control in atrial fibrillation?", "Bisoprolol"),
    qa("Which drug is first line for trigeminal neuralgia pain?", "Carbamazepine"),
    qa("Which drug reverses a warfarin overdose with bleeding quickly?", "Prothrombin complex concentrate"),
    qa("Which drug is given first for anaphylaxis in adults?", "Intramuscular adrenaline"),
    qa("Which drug treats absence seizures in children first line?", "Ethosuximide"),
    qa("Which drug is first line for gout flare prevention long term?", "Allopurinol"),
    qa("Which antibiotic treats community acquired pneumonia first line mildly?", "Amoxicillin"),
    AnkiCard(type: .cloze, clozeText: "The antidote to paracetamol overdose is {{c1::acetylcysteine}} given intravenously."),
]
var keyed = true
var detail = ""
for seed: UInt64 in [1, 2, 3, 42, 99, 1234] {
    let built = QuizFromCards.build(from: heartDeck, seed: seed)
    for q in built.questions {
        guard q.options.indices.contains(q.correctIndex) else { keyed = false; detail = "no key"; continue }
        let key = q.options[q.correctIndex]
        // the card this question was made from
        let card = heartDeck.first { QuizFromCards.stem(of: $0) == q.stem
            || QuizFromCards.stem(of: $0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "?" == q.stem }
        let expected = card.flatMap { QuizFromCards.answer(of: $0) }
        if key != expected { keyed = false; detail = "\(q.stem): key \(key), card says \(expected ?? "nil")" }
        if q.options.filter({ $0 == key }).count != 1 { keyed = false; detail = "key appears twice" }
    }
}
check("every question from a deck has the card's own answer as its key, whatever the shuffle", keyed, detail)

var deckSet = StudySet(name: "Drugs", subject: "Pharmacology", kind: .anki)
deckSet.cards = heartDeck
if let converted = ModeConversion.convert(deckSet, to: .mcq) {
    let allKeyed = converted.questions.allSatisfy { q in
        guard q.options.indices.contains(q.correctIndex) else { return false }
        let key = q.options[q.correctIndex]
        return heartDeck.contains { QuizFromCards.answer(of: $0) == key && q.stem.hasPrefix(String(QuizFromCards.stem(of: $0).prefix(20))) }
    }
    check("Turn into MCQ keys every question to its own card", allKeyed)
} else {
    check("the drug deck turns into a quiz", false, "convert returned nil")
}

// MCQ -> card: the back is the right option, not the one in the same place
let mcqSet: StudySet = {
    var s = StudySet(name: "Neuro", subject: "Neurology", kind: .mcq)
    s.questions = [question]
    return s
}()
let backToCard = ModeConversion.convert(mcqSet, to: .anki)?.cards.first
check("a question turned into a card has the right answer on the back",
      backToCard?.bullets == ["Carbamazepine"], "\(backToCard?.bullets ?? [])")

// MARK: - clue-by-clue cases

let dup = ClueCase(clues: ["a", "b", "c", "d"], diagnosis: "NSTEMI",
                   differentials: ["nstemi", "Unstable angina", "NSTEMI.", "Aortic dissection", "Unstable Angina"],
                   teachingPoint: "", decisiveClue: 4)
check("the diagnosis is offered once, however the differentials repeat it",
      dup.choices.filter { ClueCase.normalized($0) == "nstemi" }.count == 1, "\(dup.choices)")
check("a differential repeated in another case is offered once",
      dup.choices.filter { ClueCase.normalized($0) == "unstable angina" }.count == 1, "\(dup.choices)")
check("the diagnosis is among the choices", dup.choices.contains { dup.isDiagnosis($0) })
check("choosing the diagnosis is right", dup.isDiagnosis("NSTEMI"))
check("the diagnosis with different case or spacing is right", dup.isDiagnosis("  nstemi "))
check("a differential is wrong", !dup.isDiagnosis("Unstable angina"))
check("nothing is not the diagnosis", !dup.isDiagnosis(""))
for item in ReasoningExamples.cases {
    let choices = item.choices
    check("example case \(item.diagnosis): exactly one right choice among four",
          choices.count == 4 && choices.filter { item.isDiagnosis($0) }.count == 1, "\(choices)")
    check("example case \(item.diagnosis): the decisive clue is one of its clues",
          (1...item.clues.count).contains(item.decisiveClue))
}
check("the hernia case is settled by the vessels at operation, not the deep-ring test",
      ReasoningExamples.cases.first { $0.diagnosis == "Indirect inguinal hernia" }?.decisiveClue == 7)
// a play scored from a case: a right answer scores, a wrong one does not
let early = CasePlay(caseId: UUID(), setId: UUID(), cluesSeen: 2, totalClues: 7, chosen: "NSTEMI", correct: true)
let wrongEarly = CasePlay(caseId: UUID(), setId: UUID(), cluesSeen: 2, totalClues: 7, chosen: "PE", correct: false)
check("a right answer on clue 2 of 7 scores 1 + 5/7", abs(early.score - (1 + 5.0 / 7.0)) < 0.0001)
check("a wrong answer scores nothing", wrongEarly.score == 0 && wrongEarly.prematureClosure)

// MARK: - lookalike duels: the side swiped or tapped is the side marked

check("the buttons run first condition, both, second", LookalikeSide.buttonOrder == [.a, .both, .b])
check("swipe left is the first condition", LookalikeSide.swiped(width: -120, height: 10) == .a)
check("swipe right is the second condition", LookalikeSide.swiped(width: 120, height: -10) == .b)
check("swipe up is both", LookalikeSide.swiped(width: 30, height: -140) == .both)
check("up and a little left is still both", LookalikeSide.swiped(width: -100, height: -130) == .both)
check("a short drag is nothing", LookalikeSide.swiped(width: 60, height: -40) == nil)
check("a drag mostly downwards is nothing, not a side",
      LookalikeSide.swiped(width: -95, height: 160) == nil)
check("left and a little up is the first condition", LookalikeSide.swiped(width: -150, height: -100) == .a)

let a = "Diabetic ketoacidosis", b = "Hyperosmolar hyperglycaemic state"
check("side A", ReasoningWriter.sideOf("A", a: a, b: b) == .a)
check("side b, lower case", ReasoningWriter.sideOf("b", a: a, b: b) == .b)
check("both", ReasoningWriter.sideOf("Both", a: a, b: b) == .both)
check("\"Side A\" is A", ReasoningWriter.sideOf("Side A", a: a, b: b) == .a)
check("\"B only\" is B", ReasoningWriter.sideOf("B only", a: a, b: b) == .b)
check("\"Condition B\" is B", ReasoningWriter.sideOf("Condition B", a: a, b: b) == .b)
check("the first condition's name is A", ReasoningWriter.sideOf("diabetic ketoacidosis", a: a, b: b) == .a)
check("the second condition's name is B", ReasoningWriter.sideOf("Hyperosmolar hyperglycaemic state.", a: a, b: b) == .b)
check("\"neither\" is no side, not a guess", ReasoningWriter.sideOf("neither", a: a, b: b) == nil)

// the example duels: the facts a student is marked against
func side(_ pair: String, _ text: String) -> LookalikeSide? {
    ReasoningExamples.duels.first { $0.a == pair }?.features.first { $0.text == text }?.side
}
check("lateral to the inferior epigastrics is indirect",
      side("Indirect inguinal hernia", "Sac lateral to the inferior epigastric vessels") == .a)
check("Hesselbach's triangle is direct",
      side("Indirect inguinal hernia", "Bulges through Hesselbach's triangle") == .b)
check("above and medial to the pubic tubercle is every inguinal hernia",
      side("Indirect inguinal hernia", "Emerges above and medial to the pubic tubercle") == .both)
check("a thrill on tapping is the saphena varix",
      side("Femoral hernia", "Thrill when the saphenous vein below is tapped") == .b)
check("strangulation risk is the femoral hernia", side("Femoral hernia", "High risk of strangulation") == .a)
check("osmolality of 320 or more is HHS", side(a, "Serum osmolality \u{2265}320 mOsm/kg") == .b)
check("ketones of 3 or more is DKA", side(a, "Blood ketones \u{2265}3.0 mmol/L") == .a)
check("insulin held back is HHS", side(a, "Insulin held back until fluids alone stop the glucose falling") == .b)
for pair in ReasoningExamples.duels {
    check("\(pair.a) duel: every feature has its own id", Set(pair.features.map(\.id)).count == pair.features.count)
    check("\(pair.a) duel: features on both sides and shared", Set(pair.features.map(\.side)).count == 3)
}

// MARK: - spoken letters

let options = ["Bisoprolol", "Amiodarone", "Digoxin", "Flecainide", "Verapamil"]
func said(_ heard: String, _ opts: [String] = options) -> Int? { SpokenAnswer.option(in: heard, options: opts) }
check("\"B\" is B", said("B") == 1)
check("\"bee\" is B", said("bee") == 1)
check("\"be\" alone is B", said("be") == 1)
check("\"see\" is C", said("see") == 2)
check("\"sea\" is C", said("Sea.") == 2)
check("\"dee\" is D", said("dee") == 3)
check("\"echo\" is E", said("echo") == 4)
check("\"it's A\" is A", said("It's A") == 0)
check("\"a\" is A", said("a") == 0)
check("\"it must be D\" is D, not B", said("it must be D") == 3, "\(String(describing: said("it must be D")))")
check("\"I think it would be C\" is C", said("I think it would be C") == 2)
check("\"I see, it's B\" is B, not C", said("I see, it's B") == 1, "\(String(describing: said("I see, it's B")))")
check("\"B - no, D\" is the last one said", said("B no D") == 3)
check("\"answer delta\" is D", said("answer delta") == 3)
check("\"number two\" is B", said("number two") == 1)
check("the option read out is understood", said("digoxin") == 2)
check("the option read out with its letter is understood", said("C, digoxin") == 2)
check("a letter and an option that disagree is not an answer", said("A, digoxin") == nil)
check("nothing said is not an answer", said("") == nil)
check("something unrelated is not an answer", said("I have no idea what this is about") == nil)
check("only as many letters as options", said("E", ["Yes", "No"]) == nil)

let hernias = ["Direct inguinal hernia", "Indirect inguinal hernia", "Femoral hernia", "Hydrocele"]
check("\"indirect inguinal hernia\" read out is B", said("indirect inguinal hernia", hernias) == 1,
      "\(String(describing: said("indirect inguinal hernia", hernias)))")
check("\"direct inguinal hernia\" read out is A, not the indirect one", said("direct inguinal hernia", hernias) == 0)
check("a word every option shares is not an answer", said("hernia", hernias) == nil)
check("\"inguinal hernia\" fits two options, so it is not an answer", said("inguinal hernia", hernias) == nil)
let murmurs = ["Ejection systolic murmur radiating to the carotids", "Early diastolic murmur at the left sternal edge",
               "Pansystolic murmur radiating to the axilla", "Mid-diastolic rumble at the apex"]
check("\"ejection systolic\" is the carotid murmur", said("ejection systolic", murmurs) == 0)
check("\"pansystolic\" is not the ejection systolic murmur", said("pansystolic", murmurs) == 2)
check("\"murmur\" alone is no answer", said("murmur", murmurs) == nil)
let bugs = ["E. coli", "Klebsiella", "Pseudomonas", "Proteus"]
check("\"E coli\" read out is the option, not letter E", said("E coli", bugs) == 0)
let hep = ["Hepatitis A", "Hepatitis B", "Hepatitis C", "Hepatitis E"]
check("\"C\" on its own is C even when options have letters in them", said("C", hep) == 2)
check("\"B, hepatitis B\" is B", said("B, hepatitis B", hep) == 1)
check("\"the one with the delta wave\" is not A",
      said("the one with the delta wave", ["Atrial flutter", "WPW with a delta wave", "AV block"]) == 1)

// commute mode reads the options in the question's own order, A first, and
// marks the index it hears against correctIndex: wherever the key sits, its
// letter and its words must both come back as that index
let rateDrugs = ["Amiodarone", "Digoxin", "Flecainide", "Verapamil"]
var commuteKeyed = true
for slot in 0...rateDrugs.count {
    var opts = rateDrugs
    opts.insert("Bisoprolol", at: slot)
    let letter = SpokenAnswer.letters[slot]
    if said(letter, opts) != slot { commuteKeyed = false }
    if said("It's \(letter)", opts) != slot { commuteKeyed = false }
    if said("bisoprolol", opts) != slot { commuteKeyed = false }
    for other in opts.indices where other != slot {
        if said(SpokenAnswer.letters[other], opts) == slot { commuteKeyed = false }
    }
}
check("commute mode: the key's letter and its name are right wherever the key sits", commuteKeyed)

// MARK: - spoken card answers

func hears(_ heard: String, _ answer: [String]) -> Bool { SpokenAnswer.matches(heard, answer: answer) }
check("the answer said is right", hears("bisoprolol", ["Bisoprolol"]))
check("the answer in a sentence is right", hears("I think it's bisoprolol", ["**Bisoprolol**"]))
check("a different drug is wrong", !hears("amiodarone", ["Bisoprolol"]))
check("Cushing's is not Addison's for sharing \"disease\"", !hears("Cushing's disease", ["Addison's disease"]))
check("Addison's disease said is right", hears("Addisons disease", ["Addison's disease"]))
check("direct is not indirect", !hears("direct inguinal hernia", ["Indirect inguinal hernia"]))
check("indirect is not direct", !hears("indirect inguinal hernia", ["Direct inguinal hernia"]))
check("hypokalaemia is not hyperkalaemia", !hears("hypokalaemia", ["Hyperkalaemia"]))
check("hypertension is not hyperthyroidism", !hears("hypertension", ["Hyperthyroidism"]))
check("carcinoid is not carcinoma", !hears("small cell carcinoid", ["Small cell carcinoma"]))
check("the left coronary is not the right", !hears("left coronary artery", ["Right coronary artery"]))
check("the right coronary artery said is right", hears("right coronary artery", ["Right coronary artery"]))
check("American spelling is fine", hears("hyperkalemia", ["Hyperkalaemia"]))
check("a plural is fine", hears("kidney", ["Kidneys"]))
check("an ending is fine", hears("ischemic stroke", ["Ischaemia"]) || hears("ischaemic", ["Ischaemia"]))
check("one shared word of three is not enough", !hears("streptococcus", ["Staphylococcus aureus bacteraemia"]))
check("a number in the answer must be said", !hears("type diabetes", ["Type 1 diabetes"]))
check("the right number is right", hears("type 1 diabetes", ["Type 1 diabetes"]))
check("the number as a word is right", hears("type one diabetes", ["Type 1 diabetes"]))
check("the wrong number is wrong", !hears("type 2 diabetes", ["Type 1 diabetes"]))
check("a short answer must be said as a word, not found inside one", !hears("perhaps pepper", ["PE"]))
check("a short answer said is right", hears("it's a PE", ["PE"]))
check("an abbreviation said is right", hears("SLE", ["SLE"]))
check("half of a list is enough", hears("beta blockers and SGLT 2 inhibitors",
                                        ["ACEi / ARB / ARNI", "Beta-blockers", "MRA", "SGLT2 inhibitors"]))
check("one word of a four-line list is not", !hears("inhibitors",
                                                    ["ACEi / ARB / ARNI", "Beta-blockers", "MRA", "SGLT2 inhibitors"]))
check("nothing said is wrong", !hears("", ["Bisoprolol"]))
check("a Latin ending is fine", hears("staphylococcal", ["Staphylococcus"]))
check("a drug with its ending dropped is fine", hears("amiodaron", ["Amiodarone"]))
check("haemorrhagic stroke said the American way is right", hears("hemorrhagic stroke", ["Haemorrhagic stroke"]))
check("a different drug with the same start is wrong", !hears("carbimazole", ["Carbamazepine"]))
check("\"I don't know\" is not an answer", !hears("I don't know", ["Bisoprolol"]))
// one condition said with another of its endings is the same answer
check("\"infarct\" for infarction is right", hears("myocardial infarct", ["Myocardial infarction"]))
check("\"embolus\" for embolism is right", hears("pulmonary embolus", ["Pulmonary embolism"]))
check("\"hypertensive\" for hypertension is right", hears("hypertensive crisis", ["Hypertension crisis"]))
check("\"thrombotic\" for thrombosis is right", hears("thrombotic stroke", ["Thrombosis stroke"]))
check("carcinoid is still not carcinoma", !hears("carcinoid", ["Carcinoma"]))
check("hypertension is still not hypotension", !hears("hypotension", ["Hypertension"]))
// the recogniser writes digits for numerals
check("type 2 for Type II is right", hears("type 2 hypersensitivity", ["Type II hypersensitivity"]))
check("type two for Type II is right", hears("type two hypersensitivity", ["Type II hypersensitivity"]))
check("type 3 for Type II is wrong", !hears("type 3 hypersensitivity", ["Type II hypersensitivity"]))
check("CN 7 for CN VII is right", hears("CN 7", ["CN VII"]))
check("factor 8 for Factor VIII is right", hears("factor eight deficiency", ["Factor VIII deficiency"]))
check("Mobitz 2 for Mobitz II is right", hears("mobitz 2", ["Mobitz II"]))
check("factor 5 for Factor V Leiden is right", hears("factor 5 leiden", ["Factor V Leiden"]))
check("X-linked is a letter, not ten", hears("x linked recessive", ["X-linked recessive"]))
check("IV on its own is intravenous, not four", hears("iv fluids", ["IV fluids"]))
check("\"I\" said in passing is not Type I", !hears("I think type 2 diabetes", ["Type I diabetes"]))

// MARK: - numbers in a marker's reply

check("\"72\" is 72", MarkNumber.percent(from: "72") == 72)
check("\"72/100\" is 72, not 100", MarkNumber.percent(from: "72/100") == 72)
check("\"8/10\" is 80", MarkNumber.percent(from: "8/10") == 80)
check("\"72.5%\" is 73", MarkNumber.percent(from: "72.5%") == 73)
check("\"3/5\" communication is 3, not 35", MarkNumber.first(in: "3/5") == 3)
check("\"Step 4\" is 4", MarkNumber.first(in: "Step 4") == 4)
check("\"1-3\" is 1, not 13", MarkNumber.first(in: "1-3") == 1)
check("no number is none", MarkNumber.first(in: "good") == nil)

print(failures.isEmpty ? "\nALL ANSWER CHECKING TESTS PASS"
                       : "\n\(failures.count) ANSWER CHECKING TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
