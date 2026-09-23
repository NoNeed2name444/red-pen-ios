import Foundation

/// The hidden side of a simulated patient: who they are, what is wrong, and
/// what a good consultation would have covered. Written once from a Cases card
/// and never shown until the debrief.
struct CaseFile: Codable, Hashable {
    var name: String = ""
    var age: String = ""
    var sex: String = ""
    var presentingComplaint: String = ""
    var history: String = ""
    var pastHistory: String = ""
    var medications: String = ""
    var allergies: String = ""
    var social: String = ""
    var family: String = ""
    /// How they come across: worried, flat, in pain, irritable.
    var affect: String = ""
    /// What an examiner hands over when the student says what they examine.
    var examFindings: String = ""
    var diagnosis: String = ""
    var checklist: [ChecklistItem] = []

    /// The case as one block of text: what the patient is played from, and
    /// what MedVAL checks each reply against.
    var brief: String {
        [("Patient", "\(name), \(age), \(sex)"),
         ("Presenting complaint", presentingComplaint),
         ("History of presenting complaint", history),
         ("Past medical history", pastHistory),
         ("Medications", medications),
         ("Allergies", allergies),
         ("Social history", social),
         ("Family history", family),
         ("Affect", affect),
         ("Examination findings", examFindings),
         ("Diagnosis (hidden from the student)", diagnosis)]
            .filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
    }
}

/// One thing a good consultation covers, in the OSCE's four parts.
struct ChecklistItem: Codable, Hashable, Identifiable {
    enum Section: String, Codable, CaseIterable {
        case history, differential, exam, plan
        var title: String {
            switch self {
            case .history: return "History"
            case .differential: return "Differential"
            case .exam: return "Examination"
            case .plan: return "Plan"
            }
        }
    }
    var id: UUID = UUID()
    var section: Section
    var text: String
    var covered: Bool = false
}

struct CaseMessage: Identifiable, Hashable {
    enum Speaker { case doctor, patient, examiner }
    let id = UUID()
    var speaker: Speaker
    var text: String
    /// MedVAL's grade of this reply, when a checker is on.
    var verdict: AccuracyVerdict?
    /// How many replies were thrown away before this one passed.
    var regenerations: Int = 0
}

/// Runs one simulated consultation: the student asks as the doctor, the
/// writer model answers as the patient from the case file, and every reply is
/// checked against that file before it is shown.
@MainActor
final class CaseSimulator: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case interviewing
        case presenting
        case grading
        case debrief
        case failed(String)
    }

    @Published private(set) var phase: Phase = .preparing
    @Published private(set) var messages: [CaseMessage] = []
    @Published private(set) var caseFile = CaseFile()
    @Published private(set) var busy = false
    @Published private(set) var status: String?

    let card: QACard
    let subject: String
    private let writer: LLMBackend
    private let checker: LLMBackend?

    /// Replies MedVAL grades at this level or above are regenerated.
    static let regenerateAtRisk = 3
    static let maxRegenerations = 2

    init(card: QACard, subject: String, writer: LLMBackend, checker: LLMBackend?) {
        self.card = card
        self.subject = subject
        self.writer = writer
        self.checker = checker
    }

    var checkerLabel: String? { checker?.label }

    private var cardText: String {
        ([card.topic, card.stem] + card.answer).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: building the case

    func prepare() async {
        phase = .preparing
        status = "Writing the patient\u{2026}"
        do {
            var file = try await writeCaseFile(correction: nil)
            // the case file is itself generated: it is checked against the card
            // it was written from before anyone talks to it
            if let checker, let verdict = try? await AccuracyChecker.check(
                instruction: "Write a simulated patient's case file, consistent with the clinical case card.",
                input: cardText, output: file.brief, using: checker),
               verdict.riskLevel >= Self.regenerateAtRisk {
                status = "Correcting the case against the card\u{2026}"
                file = try await writeCaseFile(correction: verdict.findings.map(\.text).joined(separator: "\n"))
            }
            if file.checklist.isEmpty { file.checklist = Self.fallbackChecklist(from: card) }
            caseFile = file
            messages = [CaseMessage(speaker: .examiner,
                                    text: "\(file.name.isEmpty ? "The patient" : file.name) is waiting. Introduce yourself and take a history. Ask to examine when you're ready, then end the consultation to present your differential and plan.")]
            phase = .interviewing
            status = nil
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            status = nil
        }
    }

    private func writeCaseFile(correction: String?) async throws -> CaseFile {
        var prompt = """
        You are building a simulated patient for a medical student's OSCE practice\(subject.isEmpty ? "" : " in \(subject)").
        Base everything on this clinical case card. Do not change the diagnosis or any fact on the card; fill gaps with details typical for that diagnosis.

        CASE CARD:
        \(cardText)

        Answer with JSON only, in exactly this shape:
        {"name":"","age":"","sex":"","presentingComplaint":"","history":"","pastHistory":"","medications":"","allergies":"","social":"","family":"","affect":"","examFindings":"","diagnosis":"",
         "checklist":{"history":["..."],"differential":["..."],"exam":["..."],"plan":["..."]}}

        The checklist is what an OSCE examiner would tick: 6-12 history points, 3-5 differentials (the diagnosis first), 3-8 examination steps, 3-6 management steps. Each under 15 words.
        """
        if let correction {
            prompt += "\n\nYour previous case file contradicted the card:\n\(correction)\nWrite it again, consistent with the card."
        }
        let reply = try await writer.complete([.user(prompt)], maxTokens: 1400, temperature: 0.5)
        guard let data = LLMText.jsonObject(in: reply),
              let raw = try? JSONDecoder().decode(RawCaseFile.self, from: data) else {
            throw LLMError.emptyReply
        }
        return raw.caseFile
    }

    private struct RawCaseFile: Decodable {
        var name, age, sex, presentingComplaint, history, pastHistory, medications,
            allergies, social, family, affect, examFindings, diagnosis: String?
        var checklist: [String: [String]]?

        var caseFile: CaseFile {
            var file = CaseFile(
                name: name ?? "", age: age ?? "", sex: sex ?? "",
                presentingComplaint: presentingComplaint ?? "", history: history ?? "",
                pastHistory: pastHistory ?? "", medications: medications ?? "",
                allergies: allergies ?? "", social: social ?? "", family: family ?? "",
                affect: affect ?? "", examFindings: examFindings ?? "", diagnosis: diagnosis ?? "")
            for section in ChecklistItem.Section.allCases {
                for text in checklist?[section.rawValue] ?? [] where !text.isEmpty {
                    file.checklist.append(ChecklistItem(section: section, text: text))
                }
            }
            return file
        }
    }

    /// When the model gives no checklist, the card's own answer bullets are
    /// the marking scheme.
    static func fallbackChecklist(from card: QACard) -> [ChecklistItem] {
        card.answer.map { ChecklistItem(section: .plan, text: Highlight.plain($0)) }
    }

    // MARK: the consultation

    func send(_ question: String) async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .interviewing, !busy, !text.isEmpty else { return }
        messages.append(CaseMessage(speaker: .doctor, text: text))
        markCovered(by: text)
        busy = true
        defer { busy = false; status = nil }

        let asksToExamine = Self.isExamRequest(text)
        var correction: String?
        var attempts = 0
        while true {
            status = attempts == 0 ? (asksToExamine ? "Examining\u{2026}" : "The patient is answering\u{2026}")
                                   : "Checking the answer against the case\u{2026}"
            let reply: String
            do {
                reply = try await patientReply(to: text, examining: asksToExamine, correction: correction)
            } catch {
                messages.append(CaseMessage(speaker: .examiner,
                                            text: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription))
                return
            }
            guard let checker else {
                messages.append(CaseMessage(speaker: asksToExamine ? .examiner : .patient, text: reply))
                return
            }
            status = "Checking the answer against the case\u{2026}"
            let verdict = try? await AccuracyChecker.check(
                instruction: asksToExamine
                    ? "As the OSCE examiner, give the examination findings the student asked for, from the case file."
                    : "Reply as the simulated patient described in the case file, to the doctor's last question, in plain words.",
                input: caseFile.brief + "\n\nDoctor: " + text,
                output: reply, using: checker)
            if let verdict, verdict.riskLevel >= Self.regenerateAtRisk, attempts < Self.maxRegenerations {
                attempts += 1
                correction = verdict.findings.map(\.text).joined(separator: "\n")
                continue
            }
            messages.append(CaseMessage(speaker: asksToExamine ? .examiner : .patient,
                                        text: reply, verdict: verdict, regenerations: attempts))
            return
        }
    }

    private func patientReply(to question: String, examining: Bool, correction: String?) async throws -> String {
        var system: String
        if examining {
            system = """
            You are the OSCE examiner. The student has asked to examine the patient. Give only the findings for what they asked to examine, from the case file, in one short paragraph of clinical language. Findings not in the case file are normal. Never state the diagnosis.

            CASE FILE:
            \(caseFile.brief)
            """
        } else {
            system = """
            You are a patient in an OSCE station, talking to a medical student. Stay in character.
            - Answer only what you are asked, in everyday words, one to three sentences. Do not use medical terms a patient wouldn't know.
            - Never say your diagnosis or suggest one. Don't volunteer information you weren't asked about.
            - If asked something the case file doesn't cover, give an answer typical for this patient that doesn't contradict it.
            - Show your affect: \(caseFile.affect.isEmpty ? "as the case suggests" : caseFile.affect).

            CASE FILE:
            \(caseFile.brief)
            """
        }
        if let correction {
            system += "\n\nYour last answer contradicted the case file:\n\(correction)\nAnswer again, consistent with the case file."
        }
        var turns: [ChatTurn] = [.system(system)]
        // the conversation so far, the student as "user"; examiner notes stay
        // out of the patient's memory
        for message in messages.suffix(16) {
            switch message.speaker {
            case .doctor: turns.append(.user(message.text))
            case .patient: turns.append(.assistant(message.text))
            case .examiner: continue
            }
        }
        if turns.last?.role != .user || turns.last?.text != question { turns.append(.user(question)) }
        // Doctor-R1 reasons before answering; a patient doesn't need to
        if writer.isOnDevice, let last = turns.indices.last {
            turns[last].text += "\n/no_think"
        }
        return try await writer.complete(turns, maxTokens: examining ? 260 : 160, temperature: 0.7)
    }

    static func isExamRequest(_ text: String) -> Bool {
        let l = text.lowercased()
        return ["examine", "examination", "auscultate", "palpate", "percuss", "inspect",
                "vital signs", "vitals", "blood pressure", "look at your", "listen to your"]
            .contains { l.contains($0) }
    }

    // MARK: coverage

    /// A cheap running tick while the student talks: an item is covered once
    /// most of its meaningful words have come up. The final grade is the
    /// model's; this only keeps the live count honest in the meantime.
    private func markCovered(by text: String) {
        let said = Self.words(text)
        for i in caseFile.checklist.indices where !caseFile.checklist[i].covered {
            let item = Self.words(caseFile.checklist[i].text)
            guard !item.isEmpty else { continue }
            if Double(item.intersection(said).count) / Double(item.count) >= 0.5 {
                caseFile.checklist[i].covered = true
            }
        }
    }

    private static func words(_ text: String) -> Set<String> {
        let stop: Set<String> = ["about", "have", "with", "your", "what", "does", "that", "this", "there", "their", "when", "which", "from", "been", "patient", "ask", "asks"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stop.contains($0) })
    }

    var coveredCount: Int { caseFile.checklist.filter(\.covered).count }

    func endInterview() { if phase == .interviewing { phase = .presenting } }

    /// Grades the whole consultation plus the student's differential and plan
    /// against the checklist, then shows what was missed.
    func finish(assessment: String) async {
        phase = .grading
        status = "Marking your consultation\u{2026}"
        let doctorLines = messages.filter { $0.speaker == .doctor }.map { "- " + $0.text }.joined(separator: "\n")
        markCovered(by: assessment)
        let numbered = caseFile.checklist.enumerated()
            .map { "\($0.offset + 1). [\($0.element.section.title)] \($0.element.text)" }
            .joined(separator: "\n")
        let prompt = """
        You are an OSCE examiner marking a medical student's consultation.

        CHECKLIST:
        \(numbered)

        WHAT THE STUDENT ASKED AND SAID:
        \(doctorLines)

        THE STUDENT'S DIFFERENTIAL AND PLAN:
        \(assessment)

        For each checklist item, decide whether the student covered it (the meaning, not the exact words).
        Answer with JSON only: {"covered":[1,4,...]} listing the numbers of the covered items.
        """
        if let reply = try? await writer.complete([.user(prompt)], maxTokens: 400, temperature: 0.1),
           let data = LLMText.jsonObject(in: reply),
           let graded = try? JSONDecoder().decode(Graded.self, from: data) {
            for number in graded.covered where caseFile.checklist.indices.contains(number - 1) {
                caseFile.checklist[number - 1].covered = true
            }
        }
        status = nil
        phase = .debrief
    }

    private struct Graded: Decodable { var covered: [Int] }

    var missed: [ChecklistItem] { caseFile.checklist.filter { !$0.covered } }

    /// Replies the checker graded moderate or high risk even after the retries
    /// ran out, so the debrief can say which answers not to learn from.
    var unreliableReplies: [CaseMessage] {
        messages.filter { ($0.verdict?.riskLevel ?? 1) >= Self.regenerateAtRisk }
    }
}
