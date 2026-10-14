// What VoiceOver says on the study screens (Shared/AccessibilityText.swift):
// rating intervals in words, answers announced as soon as they are checked,
// options' state, clocks, percentages, cloze blanks and the study calendar's
// five steps.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func same(_ label: String, _ got: String, _ want: String) {
    check(label, got == want, "got \"\(got)\", want \"\(want)\"")
}

// MARK: intervals

same("bare drops the leading in", SpokenText.bareInterval("in 4 d"), "4 d")
same("bare leaves a plain label", SpokenText.bareInterval("10 min"), "10 min")
same("bare trims", SpokenText.bareInterval("  in  2 hr "), "2 hr")
same("shown under a rating", SpokenText.backIn("in 4 d"), "back in 4 d")
same("never back in in", SpokenText.backIn("in 1 min"), "back in 1 min")
same("nothing to show", SpokenText.backIn(""), "")
same("days in words", SpokenText.interval("in 4 d"), "4 days")
same("one day", SpokenText.interval("in 1 d"), "1 day")
same("minutes in words", SpokenText.interval("10 min"), "10 minutes")
same("one minute", SpokenText.interval("in 1 min"), "1 minute")
same("hours in words", SpokenText.interval("in 2 hr"), "2 hours")
same("unknown unit left alone", SpokenText.interval("in 3 wk"), "3 wk")
same("not a number left alone", SpokenText.interval("soon"), "soon")
same("rating with its interval", SpokenText.rating("Good", interval: "in 4 d"), "Good, back in 4 days")
same("rating without one", SpokenText.rating("Again", interval: ""), "Again")

// the scheduler's own labels all read as words
let schedulerLabels: [String] = ["in 1 min", "in 10 min", "in 1 hr", "in 5 hr", "in 1 d", "in 36 d"]
for label in schedulerLabels {
    let words: String = SpokenText.interval(label)
    check("\(label) has no abbreviation", !words.hasSuffix(" d") && !words.contains("min ") && !words.hasSuffix("hr"), words)
}

// MARK: counts, percent, clocks

same("one card", SpokenText.count(1, "card"), "1 card")
same("no cards", SpokenText.count(0, "card"), "0 cards")
same("own plural", SpokenText.count(2, "start over", plural: "start overs"), "2 start overs")
same("percent rounds", SpokenText.percent(0.724), "72 percent")
same("percent clamps high", SpokenText.percent(1.7), "100 percent")
same("percent clamps low", SpokenText.percent(-0.2), "0 percent")
same("percent of nan", SpokenText.percent(Double.nan), "0 percent")
same("clock minutes and seconds", SpokenText.duration(seconds: 125), "2 minutes 5 seconds")
same("clock whole minute", SpokenText.duration(seconds: 60), "1 minute")
same("clock seconds only", SpokenText.duration(seconds: 1), "1 second")
same("clock zero", SpokenText.duration(seconds: 0), "0 seconds")
same("clock never negative", SpokenText.duration(seconds: -5), "0 seconds")

// MARK: answers

same("before checking, chosen", SpokenText.optionState(checked: false, isCorrect: true, isChosen: true), "Chosen")
same("before checking, nothing gives the answer away",
     SpokenText.optionState(checked: false, isCorrect: true, isChosen: false), "")
same("right and picked", SpokenText.optionState(checked: true, isCorrect: true, isChosen: true), "Correct, your answer")
same("right, not picked", SpokenText.optionState(checked: true, isCorrect: true, isChosen: false), "Correct answer")
same("picked, wrong", SpokenText.optionState(checked: true, isCorrect: false, isChosen: true), "Your answer, incorrect")
same("neither", SpokenText.optionState(checked: true, isCorrect: false, isChosen: false), "")
same("announce right", SpokenText.answerResult(correct: true, letter: "B", answer: "x"), "Correct.")
same("announce wrong with the answer",
     SpokenText.answerResult(correct: false, letter: "C", answer: " Aortic stenosis \n"),
     "Incorrect. The answer is C: Aortic stenosis.")
same("announce wrong, empty option", SpokenText.answerResult(correct: false, letter: "A", answer: ""),
     "Incorrect. The answer is A.")
same("announce wrong, no key", SpokenText.answerResult(correct: false, letter: "", answer: "x"), "Incorrect.")
same("cloze blanks said as blank",
     SpokenText.clozeFront("The \u{25A2}\u{25A2}\u{25A2} nerve supplies \u{25A2}\u{25A2}\u{25A2}"),
     "The blank nerve supplies blank")
same("cloze without blanks unchanged", SpokenText.clozeFront("Plain front"), "Plain front")

// MARK: the study calendar

check("nothing done", HeatLevel.of(count: 0, busiest: 10) == .none)
check("nothing anywhere", HeatLevel.of(count: 3, busiest: 0) == .none)
check("a little", HeatLevel.of(count: 2, busiest: 10) == .light)
check("quarter is light", HeatLevel.of(count: 25, busiest: 100) == .light)
check("some", HeatLevel.of(count: 5, busiest: 10) == .some)
check("a lot", HeatLevel.of(count: 9, busiest: 10) == .lots)
check("the busiest day", HeatLevel.of(count: 10, busiest: 10) == .most)
check("over the busiest clamps", HeatLevel.of(count: 12, busiest: 10) == .most)
check("one of one is the most", HeatLevel.of(count: 1, busiest: 1) == .most)
let strengths: [Double] = HeatLevel.allCases.map(\.strength)
check("strengths rise", strengths == strengths.sorted() && strengths.first == 0 && strengths.last == 1, "\(strengths)")
let words: Set<String> = Set(HeatLevel.allCases.map(\.word))
check("every step has its own word", words.count == HeatLevel.allCases.count)

// MARK: result

if failures.isEmpty {
    print("all accessibility text checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
