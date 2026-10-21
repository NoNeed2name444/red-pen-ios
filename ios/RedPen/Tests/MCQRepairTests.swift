// An explanation that names an option by its place, rewritten to name it by
// its words - since the options are shown shuffled. Every reference form a
// model writes is caught and resolves to the option it meant; clinical
// English that only looks like a reference is left alone; and an explanation
// that contradicts the key is left for the accuracy rules to flag.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let options: [String] = ["Aspirin", "Morphine", "Oxygen", "Nitrates", "Furosemide"]

/// The explanation rewritten for a question keyed on Aspirin.
func fixed(_ text: String, key: Int = 0, options opts: [String] = options) -> MCQRepair.Result {
    MCQRepair.rewrite(text, options: opts, correctIndex: key)
}

func expect(_ label: String, _ text: String, _ want: String, count: Int = 1, key: Int = 0) {
    let got = fixed(text, key: key)
    check(label, got.text == want && got.rewritten == count, "\(got.text) (\(got.rewritten))")
}

func untouched(_ label: String, _ text: String) {
    let got = fixed(text)
    check(label, got.text == text && got.rewritten == 0, got.text)
}

// MARK: every reference form, and the option it meant

expect("option C is Oxygen", "Option C is wrong because it does not reduce mortality.",
       "\"Oxygen\" is wrong because it does not reduce mortality.")
// the transcribe repo's resolver scanned the phrase for its first a-e letter:
// "choice B" was C, "the option B" was E and "answer B" was A
expect("choice B is B, not the c of choice", "Choice B relieves pain only.", "\"Morphine\" relieves pain only.")
expect("the option B is B, not the e of the", "The option B relieves pain only.", "\"Morphine\" relieves pain only.")
expect("answer B is B, not the a of answer", "Answer B is tempting.", "\"Morphine\" is tempting.")
expect("the correct answer is A keeps its words", "The correct answer is A because it reduces mortality.",
       "The correct answer is \"Aspirin\" because it reduces mortality.")
expect("Answer: (A)", "Answer: (A). Aspirin reduces mortality.", "Answer: \"Aspirin\". Aspirin reduces mortality.")
expect("the answer is option A", "The answer is option A.", "The answer is \"Aspirin\".")
expect("options B and C", "Options B and C relieve symptoms only.",
       "\"Morphine\" and \"Oxygen\" relieve symptoms only.", count: 2)
expect("options B, C or D", "options B, C or D are symptomatic.",
       "\"Morphine\", \"Oxygen\" or \"Nitrates\" are symptomatic.", count: 3)
expect("option 2 counts from 1", "Option 2 is symptomatic.", "\"Morphine\" is symptomatic.")
expect("option 3 before a comma", "Unlike option 3, aspirin reduces mortality.", "Unlike \"Oxygen\", aspirin reduces mortality.")
expect("the second option", "The second option is symptomatic.", "\"Morphine\" is symptomatic.")
expect("the last option", "The last option is a diuretic.", "\"Furosemide\" is a diuretic.")
expect("several in one explanation", "Option A reduces mortality; option B and the third option do not.",
       "\"Aspirin\" reduces mortality; \"Morphine\" and \"Oxygen\" do not.", count: 3)

// MARK: what only looks like a reference

untouched("the drug of choice a decade ago", "It was the drug of choice a decade ago.")
untouched("option 0 is not the last option", "Option 0 is wrong.")
untouched("the answer 2 hours later", "Give the answer 2 hours later.")
untouched("the drug of choice 2 weeks after", "Drug of choice 2 weeks after the event.")
untouched("the second choice after metformin", "The second choice after metformin is a sulfonylurea.")
untouched("the first option for hypertension", "The first option for hypertension is a thiazide.")
untouched("the first choice drug", "The first choice drug is aspirin.")
untouched("a letter the question does not have", "Option F is not here.")
untouched("a list with a letter the question does not have", "Options B and F are wrong.")
untouched("C. difficile is not option C", "The antibiotic of choice C. difficile needs is vancomycin.")
untouched("vitamin B12 and hepatitis B", "Vitamin B12 is unrelated; hepatitis B too.")
untouched("a hyphenated word after option", "Option B-blockers are unrelated.")
untouched("a decimal after option", "Option 2.5 mg is a dose.")
untouched("an explanation already by content", "Aspirin reduces mortality; morphine only relieves pain.")
check("a four-option question has no option E",
      fixed("Option E is wrong.", options: Array(options.prefix(4))).rewritten == 0)

// MARK: the names it writes

check("a clause is cut off the name", MCQRepair.shortName("Metformin, which lowers hepatic glucose output") == "Metformin")
check("with as a word, not inside withdrawal",
      MCQRepair.shortName("Alcohol withdrawal delirium") == "Alcohol withdrawal delirium",
      MCQRepair.shortName("Alcohol withdrawal delirium"))
check("never ends on a dangling word",
      MCQRepair.shortName("The malar rash is chronic and spreads across the face") == "The malar rash is chronic",
      MCQRepair.shortName("The malar rash is chronic and spreads across the face"))
check("a full stop is not part of the name", MCQRepair.shortName("Aspirin.") == "Aspirin")
let lookalikes: [String] = ["Hyperkalaemia with peaked T waves", "Hyperkalaemia with flattened T waves",
                            "Hyponatraemia", "Hypocalcaemia"]
check("look-alike options keep their whole words",
      MCQRepair.shortNames(lookalikes) == ["Hyperkalaemia with peaked T waves", "Hyperkalaemia with flattened T waves",
                                           "Hyponatraemia", "Hypocalcaemia"], "\(MCQRepair.shortNames(lookalikes))")
let alike = MCQRepair.rewrite("Option B is wrong: the T waves flatten.", options: lookalikes, correctIndex: 0)
check("so a reference to one is not a reference to both",
      alike.text == "\"Hyperkalaemia with flattened T waves\" is wrong: the T waves flatten.", alike.text)

// MARK: a key the explanation contradicts stays visible

let wrongKey = "Option C is correct because oxygen helps."
check("an explanation naming another answer is left as written",
      fixed(wrongKey, key: 1).text == wrongKey)
let stored = MCQRepair.repaired(MCQQuestion(stem: "Which drug reduces mortality first?", options: options,
                                            correctIndex: 1, explanation: wrongKey))
let item = AccuracyItem(id: "q", kind: .mcq, stem: stored.stem, options: stored.options, key: 1,
                        explanation: stored.explanation)
check("and the accuracy rules still flag it",
      AccuracyRules.hits(item).contains { $0.rule == "key-explanation-conflict" },
      "\(AccuracyRules.hits(item).map(\.rule))")
expect("an explanation agreeing with the key is rewritten", "Option B is correct; option C does not help.",
       "\"Morphine\" is correct; \"Oxygen\" does not help.", count: 2, key: 1)

// MARK: the question as stored

let question = MCQQuestion(stem: "Which drug reduces mortality first?", options: options, correctIndex: 0,
                           explanation: "Option A reduces mortality.")
let repaired = MCQRepair.repaired(question)
check("a repaired question keeps everything but the explanation",
      repaired.id == question.id && repaired.options == question.options && repaired.correctIndex == 0
        && repaired.explanation == "\"Aspirin\" reduces mortality.", repaired.explanation)
check("an empty explanation stays empty", fixed("").text == "" && fixed("").rewritten == 0)

print(failures.isEmpty ? "\nALL MCQ REPAIR TESTS PASS"
                       : "\n\(failures.count) MCQ REPAIR TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
