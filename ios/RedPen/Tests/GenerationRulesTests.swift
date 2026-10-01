// A new generation never stops the one running: it is refused, with words
// that say what is running and how to stop it; and closing a screen stops
// only what that screen started (audit #94).

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

func refusal(_ admission: GenerationRules.Admission) -> String? {
    if case .refuse(let why) = admission { return why }
    return nil
}

// MARK: nothing running

ok(GenerationRules.admit(running: nil) == .start, "with nothing running, a generation starts")

// MARK: something running

let questions = GenerationRules.admit(running: "Writing 40 questions")
ok(questions != .start, "with a generation running, a new one is refused, not started over it")
let said = refusal(questions) ?? ""
ok(said.contains("Still writing 40 questions"), "and the student is told what is running: \(said)")
ok(said.contains("Cancel"), "and how to stop it")
ok(!said.contains("Writing Writing"), "the title is not repeated")

for title in ["Writing 12 cards", "Writing 1 page", "Writing 3 stations", "Writing 5 duels"] {
    let why = refusal(GenerationRules.admit(running: title)) ?? ""
    ok(why.hasPrefix("Still writing " + title.dropFirst("Writing ".count)), "\(title): \(why)")
}

let odd = refusal(GenerationRules.admit(running: "Checking 40 questions")) ?? ""
ok(odd.contains("checking 40 questions"), "a title that is not writing is still named: \(odd)")
let blank = refusal(GenerationRules.admit(running: "  ")) ?? ""
ok(!blank.isEmpty && blank.contains("Something else is being written"), "an empty title still refuses, in plain words")
let bare = refusal(GenerationRules.admit(running: "Writing ")) ?? ""
ok(!bare.isEmpty && !bare.contains("Still writing \u{2014}"), "a bare \"Writing\" title does not leave a gap: \(bare)")

// the same running job refuses every time: nothing about asking changes it
ok(GenerationRules.admit(running: "Writing 40 questions") == questions, "asking twice gives the same answer")

// MARK: closing a screen stops only what it started

let mine = UUID(), other = UUID()
ok(GenerationRules.closingStops(running: mine, closing: mine), "closing New set stops the generation it started")
ok(!GenerationRules.closingStops(running: other, closing: mine),
   "but not one another window's New set started (its cloud job would be deleted)")
ok(!GenerationRules.closingStops(running: nil, closing: mine),
   "nor one started outside New set, or nothing at all")

print(failures == 0 ? "\nALL GENERATION RULES TESTS PASS" : "\n\(failures) GENERATION RULES TEST FAILURE(S)")
exit(failures == 0 ? 0 : 1)
