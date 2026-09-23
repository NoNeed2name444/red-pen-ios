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
