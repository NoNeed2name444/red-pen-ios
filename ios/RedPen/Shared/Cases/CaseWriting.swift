import Foundation

// Writing cases from the student's own material: the instructions every
// writer is given (Apple's on-device model, Gemma, the medical writer and the
// cloud), and reading a writer's JSON back into case files.
//
// The instructions are written for this mode alone. They ask for what the
// case file holds and the checks demand (CaseChecks): the history written
// out as a clerking note (the patient is never questioned), examination and
// test steps with their minutes, a few key findings (key-features, Page &
// Bordage 1995), the red flags and the one or two that must not be missed,
// differentials each with the steps for and against them (illness scripts,
// Schmidt & Rikers 2007), the turning step, a next step as a single best
// answer, and three teaching points tied to the lecture.
//
// Foundation only; the reading is tested in the "cases" suite.

enum CaseWriting {

    /// What to steer one case towards, beyond the lecture.
    struct Brief: Equatable, Sendable {
        /// The diagnosis the case must have ("Another patient like this").
        var diagnosis: String? = nil
        /// An earlier presentation to stay away from.
        var unlike: String? = nil
        /// Where to set it, turned over case by case so a set is not all one ward.
        var setting: CaseFile.Setting? = nil
        /// Diagnoses already written in this run, not to be repeated.
        var avoid: [String] = []
    }

    /// The accuracy check's instruction for a case, as the server's checker
    /// is told what the output was meant to be.
    static let checkInstruction = "Write a clinical case for medical students from the source: a patient's presentation, the findings of history, examination and tests, the diagnosis, the next step and teaching points."

    /// Characters of lecture in one on-device prompt: the instructions and a
    /// whole case written back share a 4,096-token window.
    static let onDeviceSourceChars = 2_400

    /// Cases per call: one. A case is long, and a writer asked for several at
    /// once thins every one of them.
    static let perCall = 1

    static let maxCases = 50

    /// The setting for the n-th case of a set: emergency first, then the rest
    /// in turn.
    static func setting(for index: Int) -> CaseFile.Setting {
        let order: [CaseFile.Setting] = [.emergency, .ward, .clinic, .community]
        return order[index % order.count]
    }

    /// The instructions. `json` adds the exact shape to answer in, for the
    /// writers with no schema of their own (all but Apple's).
    static func instructions(source: String, subject: String, brief: Brief, options: Int = 5,
                             json: Bool) -> String {
        var rules: [String] = [
            "You write one practice patient for a medical student, built from the student's own lecture (below). The student reads the admission notes, then works the patient up against a clock: they choose what to examine and which tests to order, each costing minutes, keep a ranked list of up to three working diagnoses, then commit to the diagnosis and the single best next step. Afterwards they see what mattered.",
            "",
            "How to build the patient:",
            "1. Stay inside the lecture. The diagnosis, the findings that point to it and the teaching must be supported by it. Use realistic adult values and current practice. Never invent a dose, a value or a recommendation.",
            "2. Give the patient a made-up full name, an age, a sex (F or M) and a few words about their life. Choose where they are seen: emergency, ward, clinic or community.",
            "3. Write the complaint as the patient would say it, in everyday words, in the first person - no medical terms.",
            "4. Write the history already taken, as a doctor's clerking note: presenting complaint, history of the presenting complaint, past medical history, drugs and allergies, social history. Clinical shorthand is fine. The student reads it; there are no questions to the patient anywhere in the case.",
            "5. Give arrival observations that fit the story: heart rate, systolic and diastolic blood pressure, breathing rate, oxygen saturation and temperature in degrees Celsius.",
            "6. Write 10 to 14 steps (never under 8 or over 20) in two groups only: examine and test - never a question to the patient. Use both groups. Each step has a short label naming the action (\"Feel the abdomen\", \"Listen to the heart\", \"Serum sodium\"), the finding it reveals as a doctor would note it, and its cost in minutes: 2-4 for an examination, 5-10 for a bedside test, 15-60 for a laboratory test or imaging. Keep the deciding findings for the steps: the clerking note should leave the diagnosis open.",
            "7. Mark each step's value: key for the 2 to 5 findings the diagnosis turns on, useful for findings that help, low for actions that add little in this patient. In the note say why the step matters here - or, for a low one, why it adds little here.",
            "8. Mark redFlag on findings that signal danger, and mustNotMiss on the one or two whose omission could kill the patient.",
            "9. Put test values in results as numbers with their units, and give the reference range (low and high) for tests outside routine chemistry.",
            "10. List 3 to 5 differentials, most likely first, the diagnosis among them. For each, the ids of the steps that support it and of those that argue against it; every differential needs at least one supporting step. Add 2 or 3 distractors: plausible diagnoses that are wrong here.",
            "11. turningStep is the id of the key step after which the diagnosis should clearly lead.",
            "12. budget is the minutes allowed: enough for the key steps plus about a third.",
            "13. The next step is a single-best-answer question with exactly \(options) options of similar length and style, the correct one at answer (counting from 0), and why it is correct.",
            "14. Give three teaching points, one sentence each, and the lecture pages they come from if the lecture shows page numbers.",
        ]
        let topic: String = subject.trimmingCharacters(in: .whitespaces)
        if !topic.isEmpty && topic != "General" { rules.append("The subject is \(topic).") }
        if let setting = brief.setting { rules.append("See this patient in: \(setting.rawValue).") }
        if let diagnosis = brief.diagnosis, !diagnosis.isEmpty {
            rules.append("The diagnosis must be \(diagnosis).")
        }
        if let unlike = brief.unlike, !unlike.isEmpty {
            rules.append("Present it differently from this earlier patient, with a different age, setting and leading complaint: \(unlike)")
        }
        if !brief.avoid.isEmpty {
            rules.append("Already written, do not repeat these diagnoses: " + brief.avoid.joined(separator: "; ") + ".")
        }
        if json {
            rules.append("")
            rules.append("Answer with JSON only, in exactly this shape:")
            rules.append(shape)
        }
        rules.append("")
        rules.append("LECTURE:")
        rules.append(source)
        return rules.joined(separator: "\n")
    }

    /// The JSON the writers without a schema answer in.
    static let shape: String = #"{"cases":[{"title":"short title","specialty":"...","setting":"emergency","patient":{"name":"...","age":58,"sex":"F","about":"..."},"complaint":"...","clerking":{"presenting":"...","history":"...","past":"...","drugs":"...","social":"..."},"vitals":{"hr":96,"sbp":128,"dbp":82,"rr":18,"spo2":97,"temp":37.2},"budget":25,"steps":[{"id":"s1","group":"examine","label":"...","finding":"...","minutes":2,"value":"key","redFlag":false,"mustNotMiss":false,"note":"...","results":[{"name":"Sodium","value":131,"unit":"mmol/L"}]}],"diagnosis":{"name":"...","accepted":["..."]},"differentials":[{"name":"...","accepted":["..."],"for":["s1"],"against":["s4"]}],"distractors":["..."],"turningStep":"s3","nextStep":{"options":["...","...","...","...","..."],"answer":0,"why":"..."},"teaching":["...","...","..."],"pages":"12-14"}]}"#

    /// The user turn that requests it.
    static let request = "Write the patient now."
    static let requestJSON = "Write the patient now, as JSON only."

    // MARK: reading a writer's answer

    /// Every case in a reply: a "cases" list, or one case on its own. A
    /// malformed case costs only itself.
    static func parse(_ raw: String, lecture: String = "") -> [CaseFile] {
        guard let object = jsonObject(in: raw) else { return [] }
        let items: [[String: Any]]
        if let list = object["cases"] as? [[String: Any]] {
            items = list
        } else if object["steps"] != nil {
            items = [object]
        } else {
            items = []
        }
        return items.compactMap { read($0, lecture: lecture) }
    }

    /// The cases across a cloud job's replies, at most `count`.
    static func collect(_ replies: [String], count: Int, lecture: String = "") -> [CaseFile] {
        Array(replies.flatMap { parse($0, lecture: lecture) }.prefix(count))
    }

    /// The outermost JSON object in a reply, with any reasoning block, code
    /// fence or sentence around it left out.
    static func jsonObject(in raw: String) -> [String: Any]? {
        var text: String = raw
        while let open = text.range(of: "<think>"), let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
            text.removeSubrange(open.lowerBound..<close.upperBound)
        }
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last else { return nil }
        let body: Substring = text[first...last]
        guard let data = String(body).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// One case from its JSON; nil when it has no complaint or no steps.
    static func read(_ o: [String: Any], lecture: String) -> CaseFile? {
        var file = CaseFile()
        file.title = string(o["title"])
        file.specialty = string(o["specialty"])
        file.setting = CaseFile.Setting.read(string(o["setting"]))
        if let p = o["patient"] as? [String: Any] {
            file.patient = CaseFile.Patient(name: string(p["name"]), age: Int(number(p["age"]) ?? 0),
                                            sex: string(p["sex"]), about: string(p["about"]))
        }
        file.complaint = unquoted(string(o["complaint"]))
        if let k = o["clerking"] as? [String: Any] {
            file.clerking = CaseFile.Clerking(presenting: string(k["presenting"] ?? k["pc"]),
                                              history: string(k["history"] ?? k["hpc"]),
                                              past: string(k["past"] ?? k["pmh"]),
                                              drugs: string(k["drugs"] ?? k["medications"]),
                                              social: string(k["social"] ?? k["sh"]))
        }
        if let v = o["vitals"] as? [String: Any] { file.arrival = vitals(v) }
        file.budgetMinutes = Int(number(o["budget"] ?? o["budgetMinutes"]) ?? 20)
        let rawSteps: [[String: Any]] = o["steps"] as? [[String: Any]] ?? []
        file.steps = rawSteps.enumerated().compactMap { step($0.element, index: $0.offset) }
        if let d = o["diagnosis"] as? [String: Any] {
            file.diagnosis = CaseFile.Diagnosis(name: string(d["name"]), accepted: strings(d["accepted"]))
        } else {
            file.diagnosis = CaseFile.Diagnosis(name: string(o["diagnosis"]))
        }
        let rawDifferentials: [[String: Any]] = o["differentials"] as? [[String: Any]] ?? []
        file.differentials = rawDifferentials.compactMap { d in
            let name: String = string(d["name"])
            guard !name.isEmpty else { return nil }
            return Differential(name: name, accepted: strings(d["accepted"]),
                                supportedBy: strings(d["for"] ?? d["supportedBy"]),
                                againstBy: strings(d["against"] ?? d["againstBy"]))
        }
        file.distractors = strings(o["distractors"])
        file.turningStep = string(o["turningStep"])
        if let n = o["nextStep"] as? [String: Any] {
            let options: [String] = strings(n["options"])
            file.nextStep = CaseFile.NextStep(options: options,
                                              key: keyIndex(n["answer"] ?? n["key"], options: options),
                                              why: string(n["why"]))
        }
        file.teaching = strings(o["teaching"])
        file.source = CaseFile.Source(lecture: lecture, pages: string(o["pages"]))
        if file.title.isEmpty { file.title = file.diagnosis.name }
        guard !file.complaint.isEmpty, !file.steps.isEmpty else { return nil }
        return file
    }

    /// One step; nil when it is unreadable or asks the patient something
    /// (a history group): a case never questions its patient.
    static func step(_ s: [String: Any], index: Int) -> CaseStep? {
        let label: String = string(s["label"])
        let finding: String = string(s["finding"])
        guard !label.isEmpty, !finding.isEmpty, let group = CaseStep.Group.read(string(s["group"])) else { return nil }
        let rawResults: [[String: Any]] = s["results"] as? [[String: Any]] ?? []
        let results: [CaseStep.LabResult] = rawResults.compactMap { r in
            let name: String = string(r["name"])
            guard !name.isEmpty, let value = number(r["value"]) else { return nil }
            let low: Double? = number(r["low"]), high: Double? = number(r["high"])
            let ranged: Bool = (low ?? 0) < (high ?? 0)
            return CaseStep.LabResult(name: name, value: value, unit: string(r["unit"]),
                                      low: ranged ? low : nil, high: ranged ? high : nil)
        }
        let id: String = string(s["id"])
        return CaseStep(id: id.isEmpty ? "s\(index + 1)" : id,
                        group: group,
                        label: label, finding: finding,
                        minutes: Int(number(s["minutes"]) ?? 2),
                        value: CaseStep.Yield.read(string(s["value"])),
                        redFlag: flag(s["redFlag"]), mustNotMiss: flag(s["mustNotMiss"]),
                        results: results, note: string(s["note"]))
    }

    /// The arrival observations, in the chart's order.
    static func vitals(_ v: [String: Any]) -> [CaseFile.Obs] {
        var out: [CaseFile.Obs] = []
        if let hr = number(v["hr"]) { out.append(.init(sign: .hr, value: hr)) }
        if let sbp = number(v["sbp"]) { out.append(.init(sign: .bp, value: sbp, second: number(v["dbp"]))) }
        if let rr = number(v["rr"]) { out.append(.init(sign: .rr, value: rr)) }
        if let spo2 = number(v["spo2"]) { out.append(.init(sign: .spo2, value: spo2)) }
        if let temp = number(v["temp"]) { out.append(.init(sign: .temp, value: temp)) }
        if let gcs = number(v["gcs"]) { out.append(.init(sign: .gcs, value: gcs)) }
        return out
    }

    // MARK: small readers, tolerant of how a model writes

    static func string(_ any: Any?) -> String {
        if let s = any as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = number(any) { return CaseFile.Obs.number(n) }
        return ""
    }

    static func strings(_ any: Any?) -> [String] {
        if let list = any as? [Any] { return list.map { string($0) }.filter { !$0.isEmpty } }
        let one: String = string(any)
        return one.isEmpty ? [] : [one]
    }

    static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String {
            let cleaned: String = s.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted).joined()
            return Double(cleaned)
        }
        return nil
    }

    static func flag(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = number(any) { return n != 0 }
        return ["true", "yes", "1"].contains(string(any).lowercased())
    }

    /// The answer as an index, written 2, "2", "C" or as the option's words.
    static func keyIndex(_ any: Any?, options: [String]) -> Int {
        if !(any is String), let n = number(any), options.indices.contains(Int(n)) { return Int(n) }
        let s: String = string(any)
        if let i = Int(s), options.indices.contains(i) { return i }
        if s.count == 1, let scalar = s.uppercased().unicodeScalars.first {
            let i: Int = Int(scalar.value) - 65
            if options.indices.contains(i) { return i }
        }
        return options.firstIndex { CaseNames.same($0, s) } ?? 0
    }

    /// The complaint without the quotation marks a writer may have added; the
    /// screen adds its own.
    static func unquoted(_ text: String) -> String {
        let marks: CharacterSet = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        return text.trimmingCharacters(in: marks.union(.whitespacesAndNewlines))
    }
}
