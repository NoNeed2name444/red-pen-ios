import Foundation

// A patient to work up against the clock: who arrives and their history,
// already written as the clerking note, what can be examined and tested (each
// at a cost in minutes), what it all turns out to be, and what to do next.
// The patient is never questioned: the history is read, not asked for. One CaseFile is one patient; a Cases set holds a
// list of them (StudySet.caseFiles).
//
// The shape follows the key-features approach (Page & Bordage 1995): a few
// findings carry the case, so they are marked `key`, and the ones that would
// kill if missed are marked `mustNotMiss`. The differentials, each with the
// steps for and against it, are the case's illness scripts (Schmidt &
// Rikers 2007).
//
// Foundation only, so the checks, the score and the ladder history are tested
// on Linux (suite "cases"). Read tolerantly: a field a later version adds, or
// one a writer left out, takes its default rather than losing the case.

/// One patient case.
struct CaseFile: Identifiable, Codable, Hashable, Sendable {

    /// Where the patient is seen.
    enum Setting: String, Codable, CaseIterable, Sendable {
        case emergency, ward, clinic, community

        var label: String {
            switch self {
            case .emergency: return "Emergency"
            case .ward: return "Ward"
            case .clinic: return "Clinic"
            case .community: return "Community"
            }
        }

        /// A setting written loosely by a model: "ED", "A&E", "GP surgery".
        static func read(_ text: String) -> Setting {
            let t: String = text.lowercased()
            if let exact = Setting(rawValue: t) { return exact }
            if t.contains("emerg") || t.contains("a&e") || t == "ed" || t.contains("casualty") { return .emergency }
            if t.contains("clinic") || t.contains("outpatient") { return .clinic }
            if t.contains("gp") || t.contains("community") || t.contains("home") || t.contains("practice") { return .community }
            return .ward
        }
    }

    /// Who the patient is, in a line.
    struct Patient: Codable, Hashable, Sendable {
        /// A made-up name, for the initials on the patient's card. May be empty.
        var name: String = ""
        var age: Int = 0
        /// "F" or "M".
        var sex: String = ""
        /// A few words about them: "retired teacher, lives alone".
        var about: String = ""

        var isFemale: Bool { sex.uppercased().hasPrefix("F") || sex.lowercased().hasPrefix("w") }

        /// "F" or "M", whatever the writer wrote.
        var sexLetter: String { isFemale ? "F" : (sex.isEmpty ? "" : "M") }

        /// Two letters for the avatar: the name's, or the sex and age.
        var initials: String {
            let words: [Substring] = name.split(separator: " ").filter { !$0.isEmpty }
            let letters: String = words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
            if !letters.isEmpty { return letters }
            return sexLetter + (age > 0 ? String(age) : "")
        }

        /// "58 F"
        var ageSex: String {
            let age: String = self.age > 0 ? String(self.age) : ""
            return [age, sexLetter].filter { !$0.isEmpty }.joined(separator: " ")
        }

        /// What VoiceOver says: "58-year-old woman".
        var spoken: String {
            let who: String = isFemale ? "woman" : (sex.isEmpty ? "patient" : "man")
            return age > 0 ? "\(age)-year-old \(who)" : who
        }
    }

    /// The history as a doctor wrote it on admission: read on arrival,
    /// never asked for.
    struct Clerking: Codable, Hashable, Sendable {
        /// Presenting complaint.
        var presenting: String = ""
        /// History of the presenting complaint.
        var history: String = ""
        /// Past medical history.
        var past: String = ""
        /// Drugs and allergies.
        var drugs: String = ""
        /// Social history.
        var social: String = ""

        /// The note's parts in the order a clerking is written, the empty
        /// ones left out.
        var parts: [(label: String, text: String)] {
            [("Presenting complaint", presenting), ("History of presenting complaint", history),
             ("Past medical history", past), ("Drugs", drugs), ("Social", social)]
                .map { (label: $0.0, text: $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .filter { !$0.text.isEmpty }
        }

        var isEmpty: Bool { parts.isEmpty }

        init(presenting: String = "", history: String = "", past: String = "", drugs: String = "", social: String = "") {
            self.presenting = presenting
            self.history = history
            self.past = past
            self.drugs = drugs
            self.social = social
        }

        private enum Keys: String, CodingKey { case presenting, history, past, drugs, social }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            presenting = (try? c.decodeIfPresent(String.self, forKey: .presenting)) ?? ""
            history = (try? c.decodeIfPresent(String.self, forKey: .history)) ?? ""
            past = (try? c.decodeIfPresent(String.self, forKey: .past)) ?? ""
            drugs = (try? c.decodeIfPresent(String.self, forKey: .drugs)) ?? ""
            social = (try? c.decodeIfPresent(String.self, forKey: .social)) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(presenting, forKey: .presenting)
            try c.encode(history, forKey: .history)
            try c.encode(past, forKey: .past)
            try c.encode(drugs, forKey: .drugs)
            try c.encode(social, forKey: .social)
        }
    }

    /// One observation on arrival.
    struct Obs: Codable, Hashable, Sendable {
        enum Sign: String, Codable, CaseIterable, Sendable {
            case hr, bp, rr, spo2, temp, gcs

            var label: String {
                switch self {
                case .hr: return "HR"
                case .bp: return "BP"
                case .rr: return "RR"
                case .spo2: return "SpO\u{2082}"
                case .temp: return "Temp"
                case .gcs: return "GCS"
                }
            }

            var spoken: String {
                switch self {
                case .hr: return "Heart rate"
                case .bp: return "Blood pressure"
                case .rr: return "Respiratory rate"
                case .spo2: return "Oxygen saturation"
                case .temp: return "Temperature"
                case .gcs: return "Glasgow coma scale"
                }
            }

            var unit: String {
                switch self {
                case .hr, .rr: return "/min"
                case .bp: return "mmHg"
                case .spo2: return "%"
                case .temp: return "\u{00B0}C"
                case .gcs: return "/15"
                }
            }
        }

        var sign: Sign
        var value: Double
        /// The diastolic pressure, for BP only.
        var second: Double? = nil

        /// "128/82", "36.8", "98"
        var shown: String {
            let first: String = Self.number(value)
            guard sign == .bp, let second else { return first }
            return first + "/" + Self.number(second)
        }

        static func number(_ value: Double) -> String {
            if value == value.rounded() { return String(Int(value)) }
            return String(format: "%.1f", value)
        }
    }

    struct Diagnosis: Codable, Hashable, Sendable {
        var name: String = ""
        /// Other names that count as the same answer when typed.
        var accepted: [String] = []
    }

    /// The decision after the diagnosis: one best next step.
    struct NextStep: Codable, Hashable, Sendable {
        var options: [String] = []
        var key: Int = 0
        var why: String = ""
    }

    /// Where the case's teaching comes from in the student's material.
    struct Source: Codable, Hashable, Sendable {
        var lecture: String = ""
        var pages: String = ""

        /// "Renal lecture, pp. 12-14"
        var cited: String {
            let pages: String = self.pages.trimmingCharacters(in: .whitespaces)
            let where_: String = pages.isEmpty ? "" : (pages.contains("-") || pages.contains(",") || pages.contains("\u{2013}") ? "pp. " : "p. ") + pages
            return [lecture.trimmingCharacters(in: .whitespaces), where_].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    /// What the verification layer made of the case.
    enum Verification: String, Codable, Sendable {
        /// Not looked at yet (a case made before checks ran).
        case unchecked
        /// Through the structure checks and the on-device rules.
        case passed
        /// A red flag in the medicine: kept, never shown, until cleared.
        case held
    }

    var id: UUID = UUID()
    var title: String = ""
    var specialty: String = ""
    var setting: Setting = .ward
    var patient: Patient = Patient()
    /// The complaint in the patient's own words.
    var complaint: String = ""
    /// The written history.
    var clerking: Clerking = Clerking()
    var arrival: [Obs] = []
    var budgetMinutes: Int = 20
    var steps: [CaseStep] = []
    var diagnosis: Diagnosis = Diagnosis()
    /// The working diagnoses worth weighing, the most likely first; the
    /// diagnosis is one of them.
    var differentials: [Differential] = []
    /// Plausible names that are none of the above, mixed into the list the
    /// ladder is picked from.
    var distractors: [String] = []
    /// The step after which the right diagnosis should lead.
    var turningStep: String = ""
    var nextStep: NextStep = NextStep()
    /// Three points to take away.
    var teaching: [String] = []
    var source: Source = Source()
    var verification: Verification = .unchecked
    /// Why a held case is held, in words.
    var heldBecause: [String] = []

    init(id: UUID = UUID(), title: String = "", specialty: String = "", setting: Setting = .ward,
         patient: Patient = Patient(), complaint: String = "", clerking: Clerking = Clerking(),
         arrival: [Obs] = [], budgetMinutes: Int = 20,
         steps: [CaseStep] = [], diagnosis: Diagnosis = Diagnosis(), differentials: [Differential] = [],
         distractors: [String] = [], turningStep: String = "", nextStep: NextStep = NextStep(),
         teaching: [String] = [], source: Source = Source(), verification: Verification = .unchecked) {
        self.id = id
        self.title = title
        self.specialty = specialty
        self.setting = setting
        self.patient = patient
        self.complaint = complaint
        self.clerking = clerking
        self.arrival = arrival
        self.budgetMinutes = budgetMinutes
        self.steps = steps
        self.diagnosis = diagnosis
        self.differentials = differentials
        self.distractors = distractors
        self.turningStep = turningStep
        self.nextStep = nextStep
        self.teaching = teaching
        self.source = source
        self.verification = verification
    }

    private enum Keys: String, CodingKey {
        case id, title, specialty, setting, patient, complaint, clerking, arrival, budgetMinutes, steps, diagnosis,
             differentials, distractors, turningStep, nextStep, teaching, source, verification, heldBecause
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init()
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? id
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        specialty = (try? c.decodeIfPresent(String.self, forKey: .specialty)) ?? ""
        setting = Setting.read((try? c.decodeIfPresent(String.self, forKey: .setting)) ?? "ward")
        patient = (try? c.decodeIfPresent(Patient.self, forKey: .patient)) ?? Patient()
        complaint = (try? c.decodeIfPresent(String.self, forKey: .complaint)) ?? ""
        clerking = (try? c.decodeIfPresent(Clerking.self, forKey: .clerking)) ?? Clerking()
        arrival = (try? c.decodeIfPresent([Obs].self, forKey: .arrival)) ?? []
        budgetMinutes = (try? c.decodeIfPresent(Int.self, forKey: .budgetMinutes)) ?? 20
        steps = (try? c.decodeIfPresent([CaseStep].self, forKey: .steps)) ?? []
        diagnosis = (try? c.decodeIfPresent(Diagnosis.self, forKey: .diagnosis)) ?? Diagnosis()
        differentials = (try? c.decodeIfPresent([Differential].self, forKey: .differentials)) ?? []
        distractors = (try? c.decodeIfPresent([String].self, forKey: .distractors)) ?? []
        turningStep = (try? c.decodeIfPresent(String.self, forKey: .turningStep)) ?? ""
        nextStep = (try? c.decodeIfPresent(NextStep.self, forKey: .nextStep)) ?? NextStep()
        teaching = (try? c.decodeIfPresent([String].self, forKey: .teaching)) ?? []
        source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? Source()
        let state: String = (try? c.decodeIfPresent(String.self, forKey: .verification)) ?? ""
        verification = Verification(rawValue: state) ?? .unchecked
        heldBecause = (try? c.decodeIfPresent([String].self, forKey: .heldBecause)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(specialty, forKey: .specialty)
        try c.encode(setting.rawValue, forKey: .setting)
        try c.encode(patient, forKey: .patient)
        try c.encode(complaint, forKey: .complaint)
        try c.encode(clerking, forKey: .clerking)
        try c.encode(arrival, forKey: .arrival)
        try c.encode(budgetMinutes, forKey: .budgetMinutes)
        try c.encode(steps, forKey: .steps)
        try c.encode(diagnosis, forKey: .diagnosis)
        try c.encode(differentials, forKey: .differentials)
        try c.encode(distractors, forKey: .distractors)
        try c.encode(turningStep, forKey: .turningStep)
        try c.encode(nextStep, forKey: .nextStep)
        try c.encode(teaching, forKey: .teaching)
        try c.encode(source, forKey: .source)
        try c.encode(verification.rawValue, forKey: .verification)
        if !heldBecause.isEmpty { try c.encode(heldBecause, forKey: .heldBecause) }
    }

    // MARK: what the verification layer reads

    /// What the case asserts as true, for the accuracy engine: the complaint,
    /// every finding and result, the diagnosis, the next step and why, and
    /// the teaching points. The other options are wrong on purpose, so they
    /// are left out, as a question's distractors are.
    var assertedText: String {
        var lines: [String] = []
        lines.append("Patient: " + [patient.spoken, patient.about].filter { !$0.isEmpty }.joined(separator: ", ") + ".")
        lines.append("Complaint: \u{201C}" + complaint + "\u{201D}")
        for part in clerking.parts { lines.append(part.label + ": " + part.text) }
        if !arrival.isEmpty {
            lines.append("Arrival observations: " + arrival.map { "\($0.sign.spoken) \($0.shown) \($0.sign.unit)" }.joined(separator: "; ") + ".")
        }
        for step in steps {
            var line: String = step.group.label + " \u{2013} " + step.label + ": " + step.finding
            if !step.results.isEmpty {
                line += " (" + step.results.map(\.said).joined(separator: "; ") + ")"
            }
            lines.append(line)
        }
        lines.append("Diagnosis: " + diagnosis.name)
        if nextStep.options.indices.contains(nextStep.key) {
            lines.append("Next step: " + nextStep.options[nextStep.key] + ". " + nextStep.why)
        }
        for point in teaching { lines.append("Teaching: " + point) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One thing the student can do: examine or test. (The history is not a
/// step: it is in the clerking note.)
struct CaseStep: Identifiable, Codable, Hashable, Sendable {

    enum Group: String, Codable, CaseIterable, Sendable {
        case examine, test

        var label: String {
            switch self {
            case .examine: return "Examine"
            case .test: return "Test"
            }
        }

        /// A group written loosely by a model: "exam", "investigation". Nil
        /// for a history question, which a case never has: a writer's step
        /// that asks the patient something is dropped (CaseWriting).
        static func read(_ text: String) -> Group? {
            let t: String = text.lowercased().trimmingCharacters(in: .whitespaces)
            if let exact = Group(rawValue: t) { return exact }
            if t.hasPrefix("hist") || t.hasPrefix("ask") || t.hasPrefix("q") || t.contains("interview") { return nil }
            if t.hasPrefix("exam") || t.contains("inspect") || t.contains("palp") || t.contains("auscult") { return .examine }
            return .test
        }
    }

    /// How much the step is worth here.
    enum Yield: String, Codable, Sendable {
        /// One of the findings the case turns on.
        case key
        /// Worth doing, not decisive.
        case useful
        /// Adds little in this patient.
        case low

        static func read(_ text: String) -> Yield {
            let t: String = text.lowercased()
            if let exact = Yield(rawValue: t) { return exact }
            if t.contains("key") || t.contains("high") || t.contains("critical") { return .key }
            if t.contains("low") || t.contains("little") || t.contains("none") { return .low }
            return .useful
        }
    }

    /// A test value, shown in the results table.
    struct LabResult: Codable, Hashable, Sendable {
        var name: String
        var value: Double
        var unit: String = ""
        /// The reference range the writer gave, for tests the accuracy
        /// engine's table does not hold (troponin, CRP). Nil when not given.
        var low: Double? = nil
        var high: Double? = nil

        /// "Potassium 6.8 mmol/L"
        var said: String {
            [name, CaseFile.Obs.number(value), unit].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    var id: String
    var group: Group
    var label: String
    var finding: String
    var minutes: Int = 2
    var value: Yield = .useful
    var redFlag: Bool = false
    var mustNotMiss: Bool = false
    var results: [LabResult] = []
    /// Why it matters here, or why it adds little: said in the debrief.
    var note: String = ""

    init(id: String, group: Group, label: String, finding: String, minutes: Int = 2, value: Yield = .useful,
         redFlag: Bool = false, mustNotMiss: Bool = false, results: [LabResult] = [], note: String = "") {
        self.id = id
        self.group = group
        self.label = label
        self.finding = finding
        self.minutes = minutes
        self.value = value
        self.redFlag = redFlag
        self.mustNotMiss = mustNotMiss
        self.results = results
        self.note = note
    }

    private enum Keys: String, CodingKey {
        case id, group, label, finding, minutes, value, redFlag, mustNotMiss, results, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        group = Group.read((try? c.decodeIfPresent(String.self, forKey: .group)) ?? "") ?? .examine
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        finding = (try? c.decodeIfPresent(String.self, forKey: .finding)) ?? ""
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 2
        value = Yield.read((try? c.decodeIfPresent(String.self, forKey: .value)) ?? "")
        redFlag = (try? c.decodeIfPresent(Bool.self, forKey: .redFlag)) ?? false
        mustNotMiss = (try? c.decodeIfPresent(Bool.self, forKey: .mustNotMiss)) ?? false
        results = (try? c.decodeIfPresent([LabResult].self, forKey: .results)) ?? []
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(group.rawValue, forKey: .group)
        try c.encode(label, forKey: .label)
        try c.encode(finding, forKey: .finding)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(value.rawValue, forKey: .value)
        try c.encode(redFlag, forKey: .redFlag)
        try c.encode(mustNotMiss, forKey: .mustNotMiss)
        if !results.isEmpty { try c.encode(results, forKey: .results) }
        if !note.isEmpty { try c.encode(note, forKey: .note) }
    }
}

/// A working diagnosis worth weighing, with the steps that argue for and
/// against it.
struct Differential: Codable, Hashable, Sendable {
    var name: String
    var accepted: [String] = []
    var supportedBy: [String] = []
    var againstBy: [String] = []

    init(name: String, accepted: [String] = [], supportedBy: [String] = [], againstBy: [String] = []) {
        self.name = name
        self.accepted = accepted
        self.supportedBy = supportedBy
        self.againstBy = againstBy
    }

    private enum Keys: String, CodingKey { case name, accepted, supportedBy, againstBy }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        accepted = (try? c.decodeIfPresent([String].self, forKey: .accepted)) ?? []
        supportedBy = (try? c.decodeIfPresent([String].self, forKey: .supportedBy)) ?? []
        againstBy = (try? c.decodeIfPresent([String].self, forKey: .againstBy)) ?? []
    }
}
