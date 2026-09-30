// The model layer's pure text handling: MedVAL's prompt and how its grade is
// read, a reasoning model's working stripped off, JSON pulled out of a chatty
// reply, and which part of a lecture a check is made against.
//
// None of this needs a model. What it guards is the reading: a risk grade
// misread as "no risk" is a wrong answer shown as checked.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

// MARK: reasoning is not the answer

ok(LLMText.stripThinking("<think>The patient is 54...</think>\n\nI've had it for two days.") == "I've had it for two days.",
   "the <think> block is dropped")
ok(LLMText.stripThinking("<think>still working when the limit hit") == "",
   "a reply cut off mid-thought has no answer in it")
ok(LLMText.stripThinking("  Plain answer.\n") == "Plain answer.", "a reply with no thinking is kept, trimmed")
ok(LLMText.stripThinking("<think>a</think>x<think>b</think> final") == "final",
   "only what follows the last </think> counts")

// MARK: JSON out of prose

if let data = LLMText.jsonObject(in: "Sure! Here you go:\n```json\n{\"covered\":[1,3]}\n```\nHope that helps."),
   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    ok((object["covered"] as? [Int]) == [1, 3], "JSON inside a code fence and chatter is found")
} else { ok(false, "JSON inside a code fence and chatter is found") }
ok(LLMText.jsonObject(in: "no braces here") == nil, "no object, no data")

// one bad item costs only itself, not the reply
let mixed = """
{"questions": [
 {"stem": "Good one", "options": ["a","b","c","d","e"], "correctIndex": 1, "explanation": "x"},
 {"stem": "Null explanation", "options": ["a","b","c","d","e"], "correctIndex": "2", "explanation": null},
 {"stem": "Lettered key", "options": ["a","b","c","d","e"], "correctIndex": "C"}
]}
"""
let mixedItems = LLMText.jsonItems(in: mixed, list: "questions")
ok(mixedItems.count == 3, "every item of a reply is read, whatever its fields")
ok(mixedItems.compactMap { LLMText.keyIndex($0["correctIndex"], options: ["a", "b", "c", "d", "e"]) } == [1, 2, 2],
   "a key written 1, \"2\" or \"C\" is read as the option it names")
ok(LLMText.keyIndex(-1, options: ["a", "b"]) == nil && LLMText.keyIndex(5, options: ["a", "b"]) == nil,
   "a key that names no option is none")
ok(LLMText.keyIndex("b", options: ["a", "B"]) == 1, "a key written as the option's own text is found")
// cut off by the length limit mid-array: the complete items survive
let cutOff = """
Here you go: {"questions": [{"stem": "One {with a brace}", "options": ["a"], "correctIndex": 0},
{"stem": "Two \\"quoted\\"", "options": ["b"], "correctIndex": 0}, {"stem": "Three, cut o
"""
let survivors = LLMText.jsonItems(in: cutOff, list: "questions")
ok(survivors.count == 2, "a reply cut off mid-array keeps every complete item (\(survivors.count))")
ok((survivors.first?["stem"] as? String) == "One {with a brace}", "braces inside strings do not confuse the reading")
ok(LLMText.jsonItems(in: "{\"stations\": []}", list: "questions").isEmpty, "a reply with another list has none of these")

// MARK: MedVAL's prompt

let prompt = MedVAL.prompt(instruction: "Reply as the patient.", input: "Chest pain for 2 hours.", output: "Since yesterday.")
ok(prompt.contains("[[ ## instruction ## ]]\nReply as the patient."), "the instruction goes in its field")
ok(prompt.contains("[[ ## input ## ]]\nChest pain for 2 hours."), "the input goes in its field")
ok(prompt.contains("[[ ## output ## ]]\nSince yesterday."), "the output goes in its field")
ok(prompt.contains("Level 4 (High Risk)") && prompt.contains("11) Other:"),
   "the risk scale and all eleven error categories are there")

// MARK: reading MedVAL's grade

let failing = """
[[ ## reasoning ## ]]
The patient says the pain began yesterday; the case file says two hours ago.

[[ ## errors ## ]]
Error 1: Fabricated claim - 'since yesterday' contradicts 'two hours'.
Error 2: Missing claim - radiation to the left arm is not mentioned.

[[ ## risk_level ## ]]
Level 3 (Moderate Risk)

[[ ## completed ## ]]
"""
let v = MedVAL.parse(failing, checkedBy: "MedVAL-4B")
ok(v.riskLevel == 3, "Level 3 is read as 3")
ok(!v.passed, "and does not pass")
ok(v.findings.count == 2, "both errors are found")
ok(v.categories == [.hallucination, .omission], "fabricated → hallucination, missing → omission")
ok(v.reasoning.hasPrefix("The patient says"), "the reasoning is kept for the sheet")
ok(v.checkedBy == "MedVAL-4B", "and who checked it")

let clean = MedVAL.parse("[[ ## errors ## ]]\nNone\n\n[[ ## risk_level ## ]]\n1\n[[ ## completed ## ]]", checkedBy: "x")
ok(clean.riskLevel == 1 && clean.findings.isEmpty && clean.passed, "'None' and 1 is a clean pass")

let contradictory = MedVAL.parse("[[ ## errors ## ]]\nError 1: Overstating intensity - 'always fatal'.\n[[ ## risk_level ## ]]\n1", checkedBy: "x")
ok(contradictory.riskLevel == 2, "errors listed with a grade of 1 are read as at least low risk")
ok(contradictory.categories == [.certainty], "overstating is a certainty error")

ok(MedVAL.parse("I think this is level 4 overall.", checkedBy: "x").riskLevel == 4,
   "without the field, the number after 'level' is used")
ok(MedVAL.parse("Error 1: something. Looks fine to me.", checkedBy: "x").riskLevel == 3,
   "no readable grade is moderate - never a pass, and 'Error 1' is not a grade")
ok(!MedVAL.parse("", checkedBy: "x").passed, "an empty reply does not pass")

// "None." and the prompt's own "`None'" are no errors, not a finding that
// lifts a clean Level 1 to Level 2
for nothing in ["None.", "`None'", "None found.", "Error 1: None", "- None", "No errors found."] {
    let v = MedVAL.parse("[[ ## errors ## ]]\n\(nothing)\n[[ ## risk_level ## ]]\n1\n[[ ## completed ## ]]", checkedBy: "x")
    ok(v.riskLevel == 1 && v.findings.isEmpty, "errors \"\(nothing)\" is no error and stays Level 1")
}
ok(MedVAL.parse("[[ ## errors ## ]]\nError 1: Missing claim: none of the doses is given.\n[[ ## risk_level ## ]]\n1", checkedBy: "x").findings.count == 1,
   "an error that merely starts its explanation with 'none' is still an error")

// without the header, the grade after "risk level" - not the last "level"
let hosted = "Risk level: 4 (High). The dose is ten times the source's. This is clearly not a Level 1 output."
ok(MedVAL.parse(hosted, checkedBy: "x").riskLevel == 4, "a later 'not a Level 1' does not turn a Level 4 into a pass")
ok(MedVAL.parse("Considering the risk level carefully: the claim changes management.\nRisk level: 3", checkedBy: "x").riskLevel == 3,
   "a 'risk level' with no grade after it is passed over for the one that has one")
ok(MedVAL.parse("This reads as Level 4, not a Level 1 output.", checkedBy: "x").riskLevel == 4,
   "with only bare levels, the highest one named is taken")
ok(MedVAL.parse("risk_level: 2 - a minor wording issue", checkedBy: "x").riskLevel == 2,
   "risk_level written inline is read")

// reasoning_issues that fill in every kind with "None" report nothing
let filledIn = MedVAL.parse("""
[[ ## errors ## ]]
None
[[ ## risk_level ## ]]
1
[[ ## reasoning_issues ## ]]
Contradicting finding: None
Can't miss: None.
Unsupported claim: `None'
[[ ## completed ## ]]
""", checkedBy: "x")
ok(filledIn.riskLevel == 1 && filledIn.passed && filledIn.reasoningIssues == nil,
   "'Contradicting finding: None' and the rest are no issue, and Level 1 stays a pass")
let realIssue = MedVAL.parse("[[ ## risk_level ## ]]\n1\n[[ ## reasoning_issues ## ]]\nContradicting finding: None\nCan't miss: aortic dissection is not excluded.", checkedBy: "x")
ok(realIssue.riskLevel == 3 && realIssue.reasoningIssues?.count == 1,
   "beside a filled-in None, a real can't-miss issue still counts")

ok(MedVAL.category(of: "Error 3: Understating intensity") == .certainty, "understating is certainty")
ok(MedVAL.category(of: "Error 1: Incorrect recommendation - CT not indicated") == .hallucination,
   "an incorrect recommendation is a hallucination")
ok(MedVAL.category(of: "Error 1: Missing context") == .omission, "missing context is an omission")

// MARK: which part of the lecture a check reads

let lecture = [
    "Asthma is reversible airway obstruction. Salbutamol relieves bronchospasm.",
    "Heart failure: furosemide for congestion, ACE inhibitors reduce mortality.",
    "Diabetes: metformin first line, HbA1c target 48 mmol/mol.",
].joined(separator: "\n\n")
let near = TextSlicing.nearest(lecture, to: "Which drug reduces mortality in heart failure? ACE inhibitors", limit: 90)
ok(near.contains("ACE inhibitors") && !near.contains("metformin"), "the matching paragraph is chosen")
ok(TextSlicing.nearest(lecture, to: "anything", limit: 10_000) == lecture, "a short source is used whole")
ok(TextSlicing.nearest(lecture, to: "zzzz qqqq", limit: 20).count == 20, "no overlap falls back to the start, within the limit")

// a Word lecture is one page, one line per paragraph: bigger than the budget,
// it is cut to its nearest lines instead of being passed over
let wordLines: [String] = (1...300).map { "Line \($0) about renal physiology and tubular transport." }
    + ["Furosemide blocks the NKCC2 cotransporter in the thick ascending limb."]
    + (1...300).map { "Line \($0) about cardiac output and preload." }
let wordPage: String = wordLines.joined(separator: "\n")
let fromWord = TextSlicing.nearestPages([(heading: "Diuretics, 1:\n", text: wordPage)],
                                        to: "Which cotransporter does furosemide block?", limit: 8_000)
ok(wordPage.count > 8_000, "the Word page really is bigger than the budget")
ok(fromWord?.contains("NKCC2") == true, "a one-page Word lecture over the budget is still used, at the matching line")
ok((fromWord?.count ?? .max) <= 8_000, "and stays within the budget")
ok(fromWord?.hasPrefix("Diuretics, 1:") == true, "with its page named")
ok(TextSlicing.nearest(wordPage, to: "furosemide cotransporter", limit: 500).contains("NKCC2"),
   "nearest picks a line out of one long paragraph")
let twoPages = TextSlicing.nearestPages([(heading: "L, 1:\n", text: "Asthma: salbutamol relieves bronchospasm."),
                                         (heading: "L, 2:\n", text: "Heart failure: furosemide for congestion.")],
                                        to: "furosemide in heart failure", limit: 1_000)
ok(twoPages?.hasPrefix("L, 2:") == true, "the best page comes first")
ok(TextSlicing.nearestPages([(heading: "L, 1:\n", text: "Asthma.")], to: "zzzz qqqq", limit: 1_000) == nil,
   "no shared word, no reference")

// MARK: what the checker is shown for a question

let six = CheckedQuestion.text(stem: "Which?", options: ["a", "b", "c", "d", "e", "f"], correctIndex: 5, explanation: "Because.")
ok(six.contains("\nF. f") && six.contains("Answer: F"), "a sixth option is F, and the key names it")
ok(!six.contains("E. f"), "no two options share a letter")
let five = CheckedQuestion.text(stem: "Which?", options: ["a", "b", "c", "d", "e"], correctIndex: 1, explanation: "x")
ok(five == "Which?\nA. a\nB. b\nC. c\nD. d\nE. e\nAnswer: B\nExplanation: x", "five options read exactly as before")
let unkeyed = CheckedQuestion.text(stem: "Which?", options: ["a", "b"], correctIndex: -1, explanation: "x")
ok(unkeyed.contains("Answer: none keyed"), "a key of -1 is said to be missing, not read out of range")
ok(CheckedQuestion.text(stem: "Which?", options: ["a"], correctIndex: 7, explanation: "x").contains("Answer: none keyed"),
   "and so is a key past the last option")

// MARK: what a screen says it did

ok(MedVAL.screenNote(total: 10, removed: 1, flagged: 2, unchecked: 0) == " Accuracy checked. 1 removed as high risk. 2 flagged moderate risk.",
   "every item graded: checked")
ok(!MedVAL.screenNote(total: 10, removed: 0, flagged: 0, unchecked: 10).contains("Accuracy checked"),
   "nothing graded (offline, allowance used) is never 'Accuracy checked'")
ok(MedVAL.screenNote(total: 10, removed: 0, flagged: 0, unchecked: 3).contains("3 of 10 could not be checked"),
   "some ungraded: says how many")
ok(MedVAL.uncheckedNote(0, of: 5).isEmpty, "all graded, nothing to add")

// MARK: cutting a lecture into textbook pages

let paragraphs = (1...12).map { "Paragraph \($0): " + String(repeating: "word ", count: 60) }
let long = paragraphs.joined(separator: "\n\n")
let three = TextSlicing.slice(long, into: 3, maxChars: 100_000)
ok(three.count == 3, "asked for three pages, three slices")
ok((1...12).allSatisfy { n in three.contains { $0.contains("Paragraph \(n):") } },
   "every paragraph lands in some page - the end of the lecture is not dropped")
ok(three.first?.contains("Paragraph 1:") == true && three.last?.contains("Paragraph 12:") == true,
   "in order")
ok(TextSlicing.slice("", into: 3, maxChars: 1000).isEmpty, "nothing to slice, no pages")
ok(TextSlicing.slice("One short paragraph.", into: 5, maxChars: 1000).count == 1,
   "a short source is one page, not five empty ones")

print(failures == 0 ? "ALL LLM TESTS PASS" : "\(failures) LLM TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
