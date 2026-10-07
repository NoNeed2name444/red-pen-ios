import Foundation

/// The question screen as a patient's chart (docs/design/targets-2026-10-01.md
/// §1): the header's words, what the chart card shows of a stem, how options
/// are marked, the bar's words and what VoiceOver hears. Foundation only, so
/// ChartQuizTests runs it on Linux; MCQQuizView draws it.
enum ChartQuiz {
    // MARK: the header

    /// The title: the set's subject, else its name.
    static func title(subject: String, name: String) -> String {
        let s: String = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let n: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !s.isEmpty ? s : (n.isEmpty ? "Questions" : n)
    }

    /// "Patient 7 of 20": each question is a patient on the round.
    static func status(current: Int, total: Int) -> String { "Patient \(current + 1) of \(total)" }

    /// Under it: in a timed paper only how many are answered (the score is
    /// what it holds back); the resume question; a first nudge; the score.
    static func detail(examMode: Bool, resuming: Bool, correct: Int, checked: Int) -> String {
        if examMode { return "\(checked) answered" }
        if resuming { return "Pick up where you left off?" }
        return checked == 0 ? "Tap the answer you think is right" : "\(correct) of \(checked) right so far"
    }

    /// How far the amber strip under the title has filled.
    static func fraction(current: Int, total: Int) -> Double { Double(current) / Double(max(1, total)) }

    /// The chip beside PATIENT CHART.
    static func kindChip(retest: Bool) -> String { retest ? "Second try" : "Best answer" }

    /// The exam clock, "12:30" or "1:05:00"; and as VoiceOver reads it.
    static func clock(_ seconds: Int) -> String {
        let s: Int = max(0, seconds)
        let h: Int = s / 3600, m: Int = s % 3600 / 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s % 60) : String(format: "%d:%02d", m, s % 60)
    }

    static func spokenClock(_ seconds: Int) -> String { "\(seconds / 60) minutes \(seconds % 60) seconds left" }

    // MARK: the chart card

    /// What the card shows of a stem. One with no vital signs or results
    /// stays plain text - the whole stem as written, no chips, no empty grid
    /// or table; otherwise the chart's parts, the story and, in bold, the
    /// question.
    struct Layout: Equatable {
        var plain: Bool
        var chips: [String] = []
        var vitals: [PatientChart.Vital] = []
        var labs: [PatientChart.Lab] = []
        var story: String
        var question: String = ""
    }

    static func layout(_ stem: String) -> Layout {
        let c: PatientChart = PatientChart.read(stem)
        guard c.hasObservations else { return Layout(plain: true, story: stem) }
        return Layout(plain: false, chips: c.chips, vitals: c.vitals, labs: c.labs, story: c.story, question: c.question)
    }

    /// The highlighter keeps one set of marked pieces a question; on a chart
    /// the story's pieces keep their numbers and the question's start here.
    static let questionMarks: Int = 10_000

    /// One part's marks, numbered from 0.
    static func marks(_ all: Set<Int>, question: Bool) -> Set<Int> {
        if !question { return all.filter { $0 < questionMarks } }
        return Set(all.filter { $0 >= questionMarks }.map { $0 - questionMarks })
    }

    /// `all` with one part's marks replaced by `part`.
    static func merging(_ part: Set<Int>, question: Bool, into all: Set<Int>) -> Set<Int> {
        let other: Set<Int> = all.filter { question ? $0 < questionMarks : $0 >= questionMarks }
        return other.union(question ? Set(part.map { $0 + questionMarks }) : part)
    }

    /// A reading flagged high or low is drawn in Resus Red, beside its arrow
    /// or its H or L.
    enum Tone: Equatable { case ink, danger }

    static func tone(_ flag: PatientChart.Flag?) -> Tone { flag == nil ? .ink : .danger }

    private static let signs: [String: String] = ["BP": "Blood pressure", "HR": "Heart rate",
                                                  "RR": "Respiratory rate", "Temp": "Temperature",
                                                  "SpO2": "Oxygen saturation"]

    /// Readings as VoiceOver says them: "Blood pressure 128 over 82, high",
    /// "Albumin 22 g/L, low".
    static func spoken(_ vital: PatientChart.Vital) -> String {
        let name: String = signs[vital.label] ?? vital.label
        return name + " " + vital.value.replacingOccurrences(of: "/", with: " over ") + flagWord(vital.flag)
    }

    static func spoken(_ lab: PatientChart.Lab) -> String { lab.name + " " + lab.value + " " + lab.unit + flagWord(lab.flag) }

    private static func flagWord(_ flag: PatientChart.Flag?) -> String {
        guard let flag else { return "" }
        return flag == .high ? ", high" : ", low"
    }

    // MARK: the options and the bar

    /// How an option row is drawn: chosen (Theatre Blue) or idle until it is
    /// checked; then right (green, a check), wrong (the pick: red, a cross)
    /// or past. A timed paper keeps right and wrong for the results.
    enum Mark: Equatable { case idle, chosen, right, wrong, past }

    static func mark(slot: Int, selected: Int?, correct: Int, checked: Bool, examMode: Bool) -> Mark {
        if !checked || examMode { return slot == selected ? .chosen : .idle }
        if slot == correct { return .right }
        return slot == selected ? .wrong : .past
    }

    /// A crossed-out option is dimmed, except the right answer once it shows.
    static func faded(struck: Bool, mark: Mark) -> Bool { struck && mark != .right }

    /// What VoiceOver adds to a marked option, so colour is never the only sign.
    static func spoken(_ mark: Mark) -> String? {
        if mark == .right { return "Correct answer" }
        return mark == .wrong ? "Your answer, wrong" : nil
    }

    /// The main button's words: what to do next, never a grey button with no
    /// reason given.
    static func primaryTitle(checked: Bool, picked: Bool, holding: Bool, examMode: Bool, last: Bool) -> String {
        if holding && !checked { return "Keep reading" }
        // a paper is sat as on the day: a question can be skipped and come
        // back to, and nothing is marked until the paper is handed in
        if examMode && !checked { return last ? "Finish paper" : (picked ? "Next patient" : "Skip for now") }
        if !checked && !picked { return "Pick an answer" }
        if !checked { return "Check answer" }
        return last ? "See results" : "Next patient"
    }

    /// Explain sits beside Next patient once the explanation shows; a timed
    /// paper keeps explanations for the end.
    static func explains(checked: Bool, examMode: Bool) -> Bool { checked && !examMode }
}
