// Tidying generated OSCE stations, and the round trip through the text format.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

// MARK: numbering comes off

ok(OsceStations.stripLeadingMarker("1. Wash your hands") == "Wash your hands",
   "a leading number is not part of the step")
ok(OsceStations.stripLeadingMarker("2) Introduce yourself") == "Introduce yourself",
   "however it is punctuated")
ok(OsceStations.stripLeadingMarker("- Gain consent") == "Gain consent", "a dash is a bullet, not a word")
ok(OsceStations.stripLeadingMarker("Step 3: Expose the chest") == "Expose the chest",
   "and neither is 'Step 3:'")
ok(OsceStations.stripLeadingMarker("10 mL of saline") == "10 mL of saline",
   "but a step that simply starts with a number keeps it")

// MARK: cleaning

let messy = [
    "  1. Wash your hands  ",
    "Wash your hands",          // the same step again
    "WASH YOUR HANDS",          // and again, shouting
    "",                         // nothing
    "ok",                       // too short to be a step
    String(repeating: "x", count: 300),   // a paragraph, not a step
    "Introduce\nyourself to the patient",
]
let cleaned = OsceStations.clean(messy)
ok(cleaned == ["Wash your hands", "Introduce yourself to the patient"],
   "cleaning strips numbering, drops repeats, blanks, stubs and paragraphs")

ok(OsceStations.clean(Array(repeating: "", count: 5)).isEmpty,
   "a station of nothing cleans to nothing")

let many = (1...50).map { "Step number \($0) of the examination" }
ok(OsceStations.clean(many).count == OsceStations.maxSteps,
   "an unreasonably long station is capped")

// MARK: what counts as a station

func station(_ title: String, _ steps: [String]) -> OsceChecklist {
    OsceChecklist(title: title, steps: steps)
}

let three = ["Introduce yourself", "Gain consent", "Wash your hands"]
ok(OsceStations.isUsable(station("Cardiovascular examination", three)),
   "a titled station with enough steps is usable")
ok(!OsceStations.isUsable(station("", three)), "one with no title is not")
ok(!OsceStations.isUsable(station("Something", ["Only this", "And this"])),
   "and neither is one with two steps, which is not a station")

let tidied = OsceStations.tidy([
    station("  1. Respiratory examination ", ["1. Introduce yourself", "Gain consent", "Wash hands", "Wash hands"]),
    station("Respiratory Examination", three),       // the same station, differently cased
    station("Too short", ["a", "b"]),                // not a station
    station("Abdominal examination", three),
])
ok(tidied.count == 2, "tidying drops repeats and the unusable")
ok(tidied[0].title == "Respiratory examination", "and cleans the title too")
ok(tidied[0].steps == ["Introduce yourself", "Gain consent", "Wash hands"],
   "and the steps inside it")
ok(tidied[1].title == "Abdominal examination", "keeping the order they arrived in")

// MARK: the text format round trips
//
// Generated stations are handed to the student as text to edit before saving,
// so what comes out has to be exactly what the new-set screen reads back in.

let formatted = OsceStations.format(tidied)
let reparsed = PlainTextImport.parseOsce(formatted)
ok(reparsed.count == tidied.count, "every station survives the round trip")
ok(reparsed.map(\.title) == tidied.map(\.title), "with its title")
ok(reparsed.map(\.steps) == tidied.map(\.steps), "and every step, in order")
ok(formatted.hasPrefix("## "), "and it is written in the format the screen documents")

// MARK: the prompt carries what it has to

let asked = OsceStations.prompt(sourceText: "A lecture about the abdomen.",
                                 count: 2, subject: "Surgery",
                                 alreadyWritten: ["Respiratory examination"])
ok(asked.contains("Surgery"), "the prompt names the subject")
ok(asked.contains("A lecture about the abdomen."), "and carries the source")
ok(asked.contains("Respiratory examination"),
   "and says what has already been written, so the next call does not repeat it")
ok(asked.contains("Do not number the steps"),
   "and asks for unnumbered steps, since the order is the number")

let plab = OsceStations.prompt(sourceText: "Chest pain.", count: 1, subject: "", alreadyWritten: [], exam: .plab)
ok(plab.contains("PLAB 2") && plab.contains("8 minutes"), "a PLAB student gets PLAB 2 stations")
ok(!OsceStations.prompt(sourceText: "x", count: 1, subject: "", alreadyWritten: [], exam: .general).contains("PACES"),
   "and general revision gets no exam format")

print(failures == 0 ? "\nALL OSCE TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
