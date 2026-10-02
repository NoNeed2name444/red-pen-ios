// A question's stem read as a patient's chart: only what the stem says, the
// flags from the accuracy check's own reference ranges, and a stem with no
// observations left as it was.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let nephrotic = "A 34-year-old man presents with swelling of his legs and face for 3 weeks. BP 128/82 mmHg, HR 76/min, temperature 36.8 °C, SpO2 98% on air. Investigations show albumin 22 g/L, cholesterol 8.1 mmol/L and creatinine 88 µmol/L. Urinalysis shows 4+ protein and no blood. What is the most likely diagnosis?"
let chart = PatientChart.read(nephrotic)
check("who: age, sex and how long", chart.chips == ["34 y", "Male", "3 wk"], "\(chart.chips)")
check("the vitals, in the stem's order",
      chart.vitals.map { $0.label + " " + $0.value } == ["BP 128/82", "HR 76", "Temp 36.8 °C", "SpO2 98%"],
      "\(chart.vitals)")
check("normal vitals carry no flag", chart.vitals.allSatisfy { $0.flag == nil })
check("the results, as written",
      chart.labs.map { $0.name + " " + $0.value + " " + $0.unit } == ["Albumin 22 g/L", "Cholesterol 8.1 mmol/L", "Creatinine 88 µmol/L"],
      "\(chart.labs)")
check("low albumin is L, from the check's own range", chart.labs.first?.flag == .low)
check("a result the range table does not know is not guessed", chart.labs[1].flag == nil)
check("normal creatinine carries no flag", chart.labs[2].flag == nil)
check("the question is pulled out", chart.question == "What is the most likely diagnosis?", chart.question)
check("the story keeps what the chart does not show, and drops the lists it does",
      chart.story == "A 34-year-old man presents with swelling of his legs and face for 3 weeks. Urinalysis shows 4+ protein and no blood.",
      chart.story)

let septic = "A 70-year-old woman is confused. Her blood pressure is 82/50 mmHg, pulse 124 beats per minute, respiratory rate 28/min, temperature 39.2°C and oxygen saturation 89%. Lactate 4.8 mmol/L. Which is the next best step?"
let s = PatientChart.read(septic)
check("abnormal vitals are flagged", s.vitals.map { $0.label + ($0.flag?.rawValue ?? "-") } == ["BPL", "HRH", "RRH", "TempH", "SpO2L"], "\(s.vitals)")
check("a high lactate is H", s.labs.first.map { $0.name + " " + ($0.flag?.rawValue ?? "-") } == "Lactate H", "\(s.labs)")
check("she is Female", s.chips == ["70 y", "Female"], "\(s.chips)")

let plain = "Which nerve supplies the deltoid muscle?"
let p = PatientChart.read(plain)
check("a recall question has nothing to chart", !p.hasObservations && p.chips.isEmpty)
check("and stays the question it was", p.question == plain && p.story.isEmpty)

let mixed = "On examination his BP is 150/95 mmHg and he has bilateral pitting oedema. What is the next step?"
let m = PatientChart.read(mixed)
check("a sentence with more than numbers stays in the story", m.story.contains("bilateral pitting oedema"), m.story)
check("its reading still reaches the grid", m.vitals.first.map { $0.value + ($0.flag?.rawValue ?? "") } == "150/95H")

let decimals = "She was given 0.5 mg adrenaline. Potassium 6.8 mmol/L. What next?"
let d = PatientChart.read(decimals)
check("a decimal does not split a sentence", d.story == "She was given 0.5 mg adrenaline.", d.story)
check("high potassium is H", d.labs.first.map { ($0.flag?.rawValue ?? "-") } == "H")
check("a pulseless rhythm is not read as a pulse",
      PatientChart.read("He is pulseless with a rate of 40. What now?").vitals.isEmpty)
check("a child's age in months", PatientChart.read("An 8-month-old boy has a fever of 38.9 °C.").chips == ["8 mo", "Male"],
      "\(PatientChart.read("An 8-month-old boy has a fever of 38.9 °C.").chips)")
check("a pregnant woman says so", PatientChart.read("A 28-year-old pregnant woman, 32 weeks.").chips.contains("Pregnant"))
check("a stem with no question and nothing to chart is shown whole",
      PatientChart.read("Nephrotic syndrome.").story == "Nephrotic syndrome.")

print(failures.isEmpty ? "\nALL CHART TESTS PASS" : "\n\(failures.count) CHART TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
