import Foundation
#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
import FoundationModels
#endif

/// One case from Apple's on-device model, through a `@Generable` case file,
/// so the answer comes back in the case's shape rather than as JSON to parse.
/// Availability is MCQGenerator's, so the app gives one answer to whether
/// on-device writing works here.
enum CaseAppleWriter {

    static var availability: MCQGenerator.Availability { MCQGenerator.availability }

    /// Characters of lecture per prompt: the schema, the rules and a whole
    /// case share the model's 4,096-token window.
    static let sourceChars = 2_000

    static func one(source: String, subject: String, brief: CaseWriting.Brief, lecture: String) async throws -> CaseFile? {
        #if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
        guard #available(iOS 26.0, *) else {
            throw MCQGenerator.GenerationError.unavailable("Writing cases needs iOS 26 or later.")
        }
        if case .unavailable(let reason) = availability { throw MCQGenerator.GenerationError.unavailable(reason) }
        let rules: String = CaseWriting.instructions(source: String(source.prefix(sourceChars)), subject: subject,
                                                     brief: brief, json: false)
        let session = LanguageModelSession(instructions: Instructions { rules })
        let response = try await session.respond(to: CaseWriting.request, generating: GeneratedCaseFile.self)
        return response.content.caseFile(lecture: lecture)
        #else
        throw MCQGenerator.GenerationError.unavailable("Writing cases isn't available in this build.")
        #endif
    }
}

#if canImport(FoundationModels) && !NO_FOUNDATION_MODELS
@available(iOS 26.0, *)
@Generable
struct GeneratedCaseFile {
    @Guide(description: "A short title for the case, without the diagnosis.")
    var title: String
    @Guide(description: "The specialty, for example Cardiology.")
    var specialty: String
    @Guide(description: "Where the patient is seen.", .anyOf(["emergency", "ward", "clinic", "community"]))
    var setting: String
    @Guide(description: "A made-up full name for the patient.")
    var patientName: String
    @Guide(description: "Age in years.")
    var age: Int
    @Guide(description: "Sex.", .anyOf(["F", "M"]))
    var sex: String
    @Guide(description: "A few words about the patient's life.")
    var about: String
    @Guide(description: "The complaint in the patient's own everyday words, first person, no medical terms.")
    var complaint: String
    @Guide(description: "Clerking: the presenting complaint, as a doctor writes it.")
    var presentingComplaint: String
    @Guide(description: "Clerking: the history of the presenting complaint, already taken.")
    var historyOfComplaint: String
    @Guide(description: "Clerking: past medical history.")
    var pastHistory: String
    @Guide(description: "Clerking: drugs and allergies.")
    var drugs: String
    @Guide(description: "Clerking: social history.")
    var socialHistory: String
    @Guide(description: "Heart rate on arrival, per minute.")
    var heartRate: Int
    @Guide(description: "Systolic blood pressure on arrival, mmHg.")
    var systolic: Int
    @Guide(description: "Diastolic blood pressure on arrival, mmHg.")
    var diastolic: Int
    @Guide(description: "Breathing rate on arrival, per minute.")
    var respiratoryRate: Int
    @Guide(description: "Oxygen saturation on arrival, percent.")
    var oxygenSaturation: Int
    @Guide(description: "Temperature on arrival, degrees Celsius.")
    var temperature: Double
    @Guide(description: "Minutes allowed: the key steps plus about a third.")
    var budgetMinutes: Int
    @Guide(description: "10 to 14 examination and test steps; never a question to the patient.")
    var steps: [GeneratedCaseStep]
    @Guide(description: "The diagnosis.")
    var diagnosis: String
    @Guide(description: "Other names for the same diagnosis.")
    var acceptedNames: [String]
    @Guide(description: "3 to 5 differentials, most likely first, the diagnosis among them.")
    var differentials: [GeneratedCaseDifferential]
    @Guide(description: "2 or 3 plausible diagnoses that are wrong here.")
    var distractors: [String]
    @Guide(description: "The id of the key step after which the diagnosis should lead.")
    var turningStep: String
    @Guide(description: "The next-step options, similar in length and style.")
    var nextStepOptions: [String]
    @Guide(description: "The index of the correct next step, counting from 0.")
    var nextStepAnswer: Int
    @Guide(description: "Why the correct next step is correct.")
    var nextStepWhy: String
    @Guide(description: "Three teaching points, one sentence each.")
    var teaching: [String]
    @Guide(description: "The lecture pages the teaching comes from, or empty.")
    var pages: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedCaseStep {
    @Guide(description: "A short id: s1, s2, s3 and so on.")
    var id: String
    @Guide(description: "The group.", .anyOf(["examine", "test"]))
    var group: String
    @Guide(description: "The action, for example: Feel the abdomen.")
    var label: String
    @Guide(description: "What the action finds, as a doctor would note it.")
    var finding: String
    @Guide(description: "Minutes it costs.")
    var minutes: Int
    @Guide(description: "How much it matters here.", .anyOf(["key", "useful", "low"]))
    var value: String
    @Guide(description: "True if the finding signals danger.")
    var redFlag: Bool
    @Guide(description: "True for the one or two findings whose omission could kill.")
    var mustNotMiss: Bool
    @Guide(description: "Why it matters here, or why it adds little.")
    var note: String
    @Guide(description: "Test values, empty for questions and examinations.")
    var results: [GeneratedCaseResult]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedCaseResult {
    var name: String
    var value: Double
    var unit: String
    @Guide(description: "Lower reference limit, or 0 if not needed.")
    var low: Double
    @Guide(description: "Upper reference limit, or 0 if not needed.")
    var high: Double
}

@available(iOS 26.0, *)
@Generable
struct GeneratedCaseDifferential {
    var name: String
    var acceptedNames: [String]
    @Guide(description: "Ids of the steps that support it.")
    var supportingSteps: [String]
    @Guide(description: "Ids of the steps that argue against it.")
    var opposingSteps: [String]
}

@available(iOS 26.0, *)
extension GeneratedCaseFile {
    func caseFile(lecture: String) -> CaseFile? {
        var file = CaseFile()
        file.title = title
        file.specialty = specialty
        file.setting = CaseFile.Setting.read(setting)
        file.patient = CaseFile.Patient(name: patientName, age: age, sex: sex, about: about)
        file.complaint = CaseWriting.unquoted(complaint)
        file.clerking = CaseFile.Clerking(presenting: presentingComplaint, history: historyOfComplaint,
                                          past: pastHistory, drugs: drugs, social: socialHistory)
        file.arrival = [
            .init(sign: .hr, value: Double(heartRate)),
            .init(sign: .bp, value: Double(systolic), second: Double(diastolic)),
            .init(sign: .rr, value: Double(respiratoryRate)),
            .init(sign: .spo2, value: Double(oxygenSaturation)),
            .init(sign: .temp, value: temperature),
        ]
        file.budgetMinutes = budgetMinutes
        file.steps = steps.enumerated().compactMap { index, s -> CaseStep? in
            guard let group = CaseStep.Group.read(s.group) else { return nil }
            return CaseStep(id: s.id.isEmpty ? "s\(index + 1)" : s.id, group: group,
                     label: s.label, finding: s.finding, minutes: s.minutes, value: CaseStep.Yield.read(s.value),
                     redFlag: s.redFlag, mustNotMiss: s.mustNotMiss,
                     results: s.results.filter { !$0.name.isEmpty }.map { r in
                         let ranged: Bool = r.low < r.high
                         return CaseStep.LabResult(name: r.name, value: r.value, unit: r.unit,
                                                   low: ranged ? r.low : nil, high: ranged ? r.high : nil)
                     },
                     note: s.note)
        }
        file.diagnosis = CaseFile.Diagnosis(name: diagnosis, accepted: acceptedNames)
        file.differentials = differentials.map {
            Differential(name: $0.name, accepted: $0.acceptedNames,
                         supportedBy: $0.supportingSteps, againstBy: $0.opposingSteps)
        }
        file.distractors = distractors
        file.turningStep = turningStep
        file.nextStep = CaseFile.NextStep(options: nextStepOptions,
                                          key: nextStepOptions.indices.contains(nextStepAnswer) ? nextStepAnswer : 0,
                                          why: nextStepWhy)
        file.teaching = teaching
        file.source = CaseFile.Source(lecture: lecture, pages: pages)
        if file.title.isEmpty { file.title = diagnosis }
        guard !file.complaint.isEmpty, !file.steps.isEmpty else { return nil }
        return file
    }
}
#endif
