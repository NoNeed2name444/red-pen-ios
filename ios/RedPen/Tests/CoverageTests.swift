// Whether a long set actually covers the lecture, or just asks the same eight
// facts ten times.
//
// This is the failure the student cannot see: sixty questions look like a
// thorough set whether or not they test sixty different things.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: how many questions the source can support

check("a longer lecture earns more questions",
      MCQCoverage.suggestedCount(forCharacters: 32_000) == 100,
      "\(MCQCoverage.suggestedCount(forCharacters: 32_000))")
check("a scrap of text still gets a set",
      MCQCoverage.suggestedCount(forCharacters: 200) == 5)
check("nothing pasted does not crash",
      MCQCoverage.suggestedCount(forCharacters: 0) == 5)
check("a textbook does not get a thousand questions",
      MCQCoverage.suggestedCount(forCharacters: 5_000_000) == 200)

// MARK: what a stem is actually about

let words = MCQCoverage.contentWords(
    "A 54-year-old man presents with crushing chest pain. Which of the following is the most likely diagnosis?")
check("the medicine is kept",
      words.contains("crushing") && words.contains("chest") && words.contains("diagnosis"),
      "\(words.sorted())")
// every exam question ever written contains these, so counting them makes two
// questions about different organs look alike
check("the exam scaffolding is not",
      !words.contains("most") && !words.contains("likely")
        && !words.contains("following") && !words.contains("man"),
      "\(words.sorted())")

// MARK: the same question, asked twice

let infarct = "A 54-year-old man presents with crushing chest pain radiating to the left arm. Which of the following is the most likely diagnosis?"
let reworded = "A 60-year-old man has crushing chest pain radiating to the left arm; what is the diagnosis?"
let porphyria = "Which enzyme is deficient in acute intermittent porphyria?"

check("a rewritten vignette is the same question",
      MCQCoverage.overlap(infarct, reworded) >= 0.6,
      "\(MCQCoverage.overlap(infarct, reworded))")
check("a different fact is a different question",
      MCQCoverage.overlap(infarct, porphyria) < 0.3,
      "\(MCQCoverage.overlap(infarct, porphyria))")
check("nothing overlaps nothing without dividing by zero",
      MCQCoverage.overlap("", "") == 0)

let asked = [MCQCoverage.Asked(stem: infarct, key: "Myocardial infarction")]
check("asking it again is caught",
      MCQCoverage.isRepeat(stem: reworded, key: "Myocardial infarction", of: asked))
check("a new fact is let through",
      !MCQCoverage.isRepeat(stem: porphyria, key: "Porphobilinogen deaminase", of: asked))
check("the first question of a set is never a repeat",
      !MCQCoverage.isRepeat(stem: infarct, key: "Myocardial infarction", of: []))

// The shape repetition usually takes: the vignette is changed and the answer
// is not. Half-similar stems are only a repeat when they land on the same key.
let rhythm = "atrial fibrillation with structural heart disease rhythm control choice"
let ventricular = "recurrent ventricular tachycardia after myocardial infarction rhythm control choice"
let drugAsked = [MCQCoverage.Asked(stem: rhythm, key: "Amiodarone")]
check("a new vignette with the same answer is a repeat",
      MCQCoverage.isRepeat(stem: ventricular, key: "Amiodarone", of: drugAsked),
      "\(MCQCoverage.overlap(rhythm, ventricular))")
check("the same vignette shape with a different answer is not",
      !MCQCoverage.isRepeat(stem: ventricular, key: "Lidocaine", of: drugAsked))
check("a blank answer does not match every other blank answer",
      !MCQCoverage.isRepeat(stem: ventricular, key: "",
                            of: [MCQCoverage.Asked(stem: rhythm, key: "")]))

// MARK: what the next batch is told

check("the first batch is told nothing", MCQCoverage.avoidanceNote([]).isEmpty)

let many = (1...60).map {
    MCQCoverage.Asked(stem: "Question number \($0) about " + String(repeating: "detail ", count: 40),
                      key: "Answer \($0)")
}
let note = MCQCoverage.avoidanceNote(many)
check("the note says how many have been asked", note.contains("60 question"), "\(note.prefix(120))")
check("only the recent ones are listed",
      note.components(separatedBy: "\n- ").count - 1 == 40,
      "\(note.components(separatedBy: "\n- ").count - 1)")
check("the most recent is among them", note.contains("Question number 60"))
// the source material has to fit in the same context, so the note cannot grow
// without limit
check("a long stem is cut short", note.contains("\u{2026}"))
check("the note stays small", note.count < 6_000, "\(note.count)")
check("the answer is carried with the stem", note.contains("[answer: Answer 60]"))

print(failures.isEmpty ? "\nALL COVERAGE TESTS PASS"
                       : "\n\(failures.count) COVERAGE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
