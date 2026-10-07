// The question screen as a patient chart: what the header says, which parts
// of a stem the chart card shows (and a stem with nothing to chart left as
// it was), the highlighter's marks across story and question, how options
// are marked - never right or wrong in a timed paper - and the bar's words.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// the header
check("the title is the set's subject", ChartQuiz.title(subject: "Nephrology", name: "Renal 1") == "Nephrology")
check("no subject: the set's name", ChartQuiz.title(subject: "  ", name: "Renal 1") == "Renal 1")
check("neither: Questions", ChartQuiz.title(subject: "", name: "") == "Questions")
check("a question is a patient", ChartQuiz.status(current: 6, total: 20) == "Patient 7 of 20",
      ChartQuiz.status(current: 6, total: 20))
check("a timed paper says only how many are answered",
      ChartQuiz.detail(examMode: true, resuming: false, correct: 2, checked: 3) == "3 answered")
check("a saved place asks first",
      ChartQuiz.detail(examMode: false, resuming: true, correct: 0, checked: 0) == "Pick up where you left off?")
check("before the first answer, a nudge",
      ChartQuiz.detail(examMode: false, resuming: false, correct: 0, checked: 0) == "Tap the answer you think is right")
check("then the running score",
      ChartQuiz.detail(examMode: false, resuming: false, correct: 2, checked: 3) == "2 of 3 right so far")
check("the strip starts empty and fills with the paper",
      ChartQuiz.fraction(current: 0, total: 20) == 0 && ChartQuiz.fraction(current: 10, total: 20) == 0.5)
check("the chip says best answer, or second try on a re-test",
      ChartQuiz.kindChip(retest: false) == "Best answer" && ChartQuiz.kindChip(retest: true) == "Second try")
check("the clock in minutes", ChartQuiz.clock(750) == "12:30", ChartQuiz.clock(750))
check("and in hours for a long paper", ChartQuiz.clock(3900) == "1:05:00", ChartQuiz.clock(3900))
check("VoiceOver hears minutes and seconds", ChartQuiz.spokenClock(125) == "2 minutes 5 seconds left")

// the chart card
let nephrotic = "A 34-year-old man presents with swelling of his legs and face for 3 weeks. BP 128/82 mmHg, HR 76/min, temperature 36.8 °C, SpO2 98% on air. Investigations show albumin 22 g/L, cholesterol 8.1 mmol/L and creatinine 88 µmol/L. Urinalysis shows 4+ protein and no blood. What is the most likely diagnosis?"
let full = ChartQuiz.layout(nephrotic)
check("a stem with observations is charted", !full.plain)
check("chips for who the patient is", full.chips == ["34 y", "Male", "3 wk"], "\(full.chips)")
check("the vitals grid and the results table",
      full.vitals.map { $0.label } == ["BP", "HR", "Temp", "SpO2"] && full.labs.count == 3,
      "\(full.vitals) \(full.labs)")
check("the story, without the lines the chart shows",
      full.story == "A 34-year-old man presents with swelling of his legs and face for 3 weeks. Urinalysis shows 4+ protein and no blood.",
      full.story)
check("the question on its own", full.question == "What is the most likely diagnosis?", full.question)

let recall = "Which nerve supplies the deltoid muscle?"
let plain = ChartQuiz.layout(recall)
check("a stem with nothing to chart is plain text, whole",
      plain.plain && plain.story == recall && plain.question.isEmpty)
check("with no chips, grid or table",
      plain.chips.isEmpty && plain.vitals.isEmpty && plain.labs.isEmpty)
let told = "A 34-year-old man has central chest pain for 2 hours. What is the most likely diagnosis?"
let toldLayout = ChartQuiz.layout(told)
check("who the patient is alone is not a chart", toldLayout.plain && toldLayout.chips.isEmpty && toldLayout.story == told)

let labsOnly = "A 34-year-old Black man presents with frothy urine, periorbital oedema and 6 g/day proteinuria. Serum albumin is 22 g/L. Which finding on light microscopy is most consistent with the most common primary cause of nephrotic syndrome in this patient?"
let results = ChartQuiz.layout(labsOnly)
check("results alone: a table and no empty grid",
      !results.plain && results.vitals.isEmpty && results.labs.map { $0.name } == ["Albumin"], "\(results.labs)")
let vitalsOnly = ChartQuiz.layout("A 70-year-old woman is confused. Her pulse is 124 beats per minute and temperature 39.2 °C. What is the next step?")
check("vitals alone: a grid and no empty table",
      !vitalsOnly.plain && vitalsOnly.labs.isEmpty && vitalsOnly.vitals.count == 2, "\(vitalsOnly.vitals)")

// the highlighter's marks on a chart
let marked: Set<Int> = [0, 2, ChartQuiz.questionMarks + 1]
check("the story's marks", ChartQuiz.marks(marked, question: false) == [0, 2])
check("the question's marks, from 0", ChartQuiz.marks(marked, question: true) == [1])
check("marking the question leaves the story's",
      ChartQuiz.merging([1, 3], question: true, into: marked) == [0, 2, ChartQuiz.questionMarks + 1, ChartQuiz.questionMarks + 3])
check("clearing the story leaves the question's",
      ChartQuiz.merging([], question: false, into: marked) == [ChartQuiz.questionMarks + 1])
check("a plain stem's marks are the story's", ChartQuiz.marks([0, 4], question: false) == [0, 4])

// the options
func mark(_ slot: Int, selected: Int?, checked: Bool, exam: Bool = false) -> ChartQuiz.Mark {
    ChartQuiz.mark(slot: slot, selected: selected, correct: 1, checked: checked, examMode: exam)
}
check("before checking: chosen and idle",
      mark(2, selected: 2, checked: false) == .chosen && mark(1, selected: 2, checked: false) == .idle)
check("nothing chosen: nothing blue", (0..<4).allSatisfy { mark($0, selected: nil, checked: false) == .idle })
check("checked: the right one green, the wrong pick red, the rest past",
      mark(1, selected: 2, checked: true) == .right && mark(2, selected: 2, checked: true) == .wrong
      && mark(0, selected: 2, checked: true) == .past)
check("a right pick is right, not wrong", mark(1, selected: 1, checked: true) == .right)
check("a timed paper never shows right or wrong",
      mark(1, selected: 2, checked: true, exam: true) == .idle && mark(2, selected: 2, checked: true, exam: true) == .chosen)
check("a question with no key paints no option right",
      (0..<4).allSatisfy { ChartQuiz.mark(slot: $0, selected: 2, correct: -1, checked: true, examMode: false) != .right })
check("a crossed-out option is dimmed", ChartQuiz.faded(struck: true, mark: .past) && ChartQuiz.faded(struck: true, mark: .idle))
check("except the right answer once shown", !ChartQuiz.faded(struck: true, mark: .right))
check("and nothing else is", !ChartQuiz.faded(struck: false, mark: .wrong))
check("VoiceOver hears right and wrong, not only colour",
      ChartQuiz.spoken(.right) == "Correct answer" && ChartQuiz.spoken(.wrong) == "Your answer, wrong"
      && ChartQuiz.spoken(.chosen) == nil)

// the bar
func title(checked: Bool = false, picked: Bool = true, holding: Bool = false, exam: Bool = false, last: Bool = false) -> String {
    ChartQuiz.primaryTitle(checked: checked, picked: picked, holding: holding, examMode: exam, last: last)
}
check("nothing picked says so", title(picked: false) == "Pick an answer")
check("the slow reading drill holds", title(holding: true) == "Keep reading")
check("then Check answer", title() == "Check answer")
check("checked: Next patient", title(checked: true) == "Next patient")
check("and See results on the last", title(checked: true, last: true) == "See results")
check("a paper answers and moves on", title(exam: true) == "Next patient" && title(exam: true, last: true) == "Finish paper")
check("a paper's question can be skipped", title(picked: false, exam: true) == "Skip for now"
      && title(picked: false, exam: true, last: true) == "Finish paper")
check("Explain once checked", ChartQuiz.explains(checked: true, examMode: false))
check("not before, nor in a paper",
      !ChartQuiz.explains(checked: false, examMode: false) && !ChartQuiz.explains(checked: true, examMode: true))

// readings: colour and speech
check("a flagged reading is drawn as danger",
      ChartQuiz.tone(.high) == .danger && ChartQuiz.tone(.low) == .danger && ChartQuiz.tone(nil) == .ink)
let septic = ChartQuiz.layout("A 70-year-old woman is confused. Her blood pressure is 82/50 mmHg and oxygen saturation 89%. Lactate 4.8 mmol/L. Which is the next best step?")
check("a vital sign is read out in words",
      septic.vitals.first.map(ChartQuiz.spoken) == "Blood pressure 82 over 50, low",
      String(describing: septic.vitals.first.map(ChartQuiz.spoken)))
check("saturation by name", septic.vitals.last.map(ChartQuiz.spoken) == "Oxygen saturation 89%, low",
      String(describing: septic.vitals.last.map(ChartQuiz.spoken)))
check("a result with its unit and flag", full.labs.first.map(ChartQuiz.spoken) == "Albumin 22 g/L, low",
      String(describing: full.labs.first.map(ChartQuiz.spoken)))
check("a normal reading has no flag word", full.vitals.first.map(ChartQuiz.spoken) == "Blood pressure 128 over 82")

print(failures.isEmpty ? "\nALL CHART QUIZ TESTS PASS" : "\n\(failures.count) CHART QUIZ TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
