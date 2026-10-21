// The model layer's pure text handling: a reasoning model's working stripped
// off, JSON pulled out of a chatty reply, and which part of a lecture a check
// is made against.
//
// None of this needs a model. What it guards is the reading: a reply misread
// is a wrong answer shown as right.

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

// MARK: the server's refusals read as sentences

ok(LLMError.http(409, "This subscription is already linked to another Stethoscore account.").errorDescription
   == "This subscription is already linked to another Stethoscore account.",
   "a subscription refusal is shown as the server wrote it, not behind an HTTP code")
ok(LLMError.http(402, "Stethoscore Cloud is part of Pro.").errorDescription == "Stethoscore Cloud is part of Pro.",
   "the Pro refusal likewise")
ok(LLMError.http(403, "{\"error\":\"x\"}").errorDescription?.contains("HTTP 403") == true,
   "an unreadable body still says what failed")
ok(LLMError.http(500, "boom").errorDescription?.contains("HTTP 500") == true, "a server fault keeps its code")

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

// MARK: a long lecture, a window at a time (audits #85, #90)
let windowParagraph: String = String(repeating: "Warfarin is reversed by prothrombin complex concentrate and vitamin K. ", count: 20)
let windowLecture: String = (0..<40).map { "Section \($0). " + windowParagraph }.joined(separator: "\n\n")
let lectureWindows: [String] = TextSlicing.windows(windowLecture, maxChars: 4_000)
ok(lectureWindows.count > 1 && lectureWindows.allSatisfy { $0.count <= 4_000 }, "a long lecture becomes windows that each fit (\(lectureWindows.count))")
ok(lectureWindows.allSatisfy { $0.hasPrefix("Section") }, "each window starts at a paragraph, not mid-sentence")
ok((0..<40).allSatisfy { n in lectureWindows.contains { $0.contains("Section \(n). ") } }, "every section is in some window: nothing past the first window is lost")
ok(TextSlicing.windows("Short notes.", maxChars: 4_000) == ["Short notes."], "a short source is one window, unchanged")
ok(TextSlicing.window(["a", "b", "c"], round: 0) == "a" && TextSlicing.window(["a", "b", "c"], round: 4) == "b" && TextSlicing.window([], round: 2) == "",
   "batches take the windows in turn, round and round")
let unbroken: String = String(repeating: "x", count: 9_000)
ok(TextSlicing.windows(unbroken, maxChars: 4_000).map(\.count) == [4_000, 4_000, 1_000], "text with no break is cut hard, and nothing is lost")


// a sample of parts, spread first to last (audit #89)
ok(TextSlicing.spread(3, upTo: 8) == [0, 1, 2], "every part is checked when there are few enough")
ok(TextSlicing.spread(20, upTo: 4) == [0, 6, 13, 19], "a sample runs first to last, not the opening only: \(TextSlicing.spread(20, upTo: 4))")
ok(TextSlicing.spread(9, upTo: 1) == [0] && TextSlicing.spread(0, upTo: 4).isEmpty, "edge counts")

print(failures == 0 ? "ALL LLM TESTS PASS" : "\(failures) LLM TEST(S) FAILED")
exit(failures == 0 ? 0 : 1)
