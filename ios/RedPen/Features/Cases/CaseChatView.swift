import SwiftUI

/// A Cases card played as a patient: the student asks as the doctor, the model
/// answers as the patient, and the consultation is marked against an OSCE
/// checklist at the end.
///
/// Opened as a sheet from Cases mode, so the card view itself - reveal, next,
/// previous - is untouched.
struct CaseChatView: View {
    let card: QACard
    let subject: String
    /// The case's note in Ideas, which the debrief can add to; nil where
    /// the case has no set to go back to.
    var idea: IdeaClip? = nil

    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State private var simulator: CaseSimulator?
    @State private var draft = ""
    @State private var assessment = ""
    @State private var showModels = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(card.topic.isEmpty ? "Simulated patient" : card.topic)
                .diagnosticsScreen("screen:case_chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
        // a sheet of its own, so it says which screen's colour it is in
        // rather than trusting it to be passed down
        .tint(StudySetKind.qa.tint)
        .environment(\.modeTint, StudySetKind.qa.tint)
        // the microphone may be listening: the camera stays off
        .popOutFacePaused()
        .sheet(isPresented: $showModels) { ModelSettingsView() }
        .task(id: llm.writerChoice) { await start() }
    }

    /// The consultation on the Cases backdrop, lists and forms included.
    private var content: some View {
        Group {
            if let simulator {
                CaseSession(simulator: simulator, draft: $draft, assessment: $assessment,
                            idea: idea, onClose: { dismiss() })
            } else {
                notReady
            }
        }
        .scrollContentBackground(.hidden)
        .background(ModeBackdrop(kind: .qa))
    }

    /// No model yet: the way to choose one is the main button, in the bar
    /// under the thumb like every other study screen's.
    private var notReady: some View {
        ContentUnavailableView {
            Label("Choose a model to play the patient", systemImage: "stethoscope")
        } description: {
            Text("With Pro, use Doctor-R1 on this device or \(Brand.name) Cloud; Apple's own model works for free where Apple Intelligence is on. Add MedVAL and every patient answer is checked against the case before you see it.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .studyBar {
            Button("AI models") { showModels = true }
                .buttonStyle(.bigPrimary)
        }
    }

    private func start() async {
        guard simulator == nil, let writer = llm.backend(for: .writer) else { return }
        let sim = CaseSimulator(card: card, subject: subject, writer: writer,
                                checker: llm.backend(for: .checker))
        simulator = sim
        await sim.prepare()
    }
}

private struct CaseSession: View {
    @ObservedObject var simulator: CaseSimulator
    @Binding var draft: String
    @Binding var assessment: String
    /// The case's note in Ideas, for the debrief's Save to Ideas.
    let idea: IdeaClip?
    /// Closes the consultation, from the debrief's Done.
    let onClose: () -> Void
    @FocusState private var typing: Bool

    var body: some View {
        switch simulator.phase {
        case .preparing:
            ProgressView(simulator.status ?? "Preparing\u{2026}").frame(maxHeight: .infinity)
        case .failed(let message):
            failed(message)
        case .interviewing:
            VStack(spacing: 0) {
                coverageBar
                transcript
            }
        case .presenting, .grading:
            presentForm
        case .debrief:
            debrief
        }
    }

    /// Setting up went wrong: Try again is the main button, in the bar.
    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't set up the case", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .studyBar {
            Button("Try again") { Task { await simulator.prepare() } }
                .buttonStyle(.bigPrimary)
        }
    }

    /// How much of the checklist is covered so far, and the way out of the
    /// interview - the same header every study screen has.
    private var coverageBar: some View {
        let total = simulator.caseFile.checklist.count
        let covered = simulator.coveredCount
        let fraction: Double = Double(covered) / Double(max(1, total))
        let detail: String? = simulator.checkerLabel.map { "Answers checked by \($0)" }
        let status: String = "\(covered) of \(total) checklist points"
        return StudyProgressHeader(status, detail: detail, fraction: fraction) {
            HStack(spacing: 8) {
                CaseStationClock()
                finishButton
            }
        }
    }

    private var finishButton: some View {
        Button { simulator.endInterview() } label: {
            Label("Finish", systemImage: "flag.checkered")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 36)
        }
        .buttonStyle(.glass)
        .disabled(simulator.busy)
        .accessibilityHint("Ends the interview so you can present your diagnosis and plan")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(simulator.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if simulator.busy, let status = simulator.status {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(status).font(.footnote).foregroundStyle(.secondary)
                        }
                        .id("status")
                    }
                }
                .padding()
                .readableColumn()
            }
            .studyBar { composer }
            .onChange(of: simulator.messages.count) { _, _ in
                if let last = simulator.messages.last?.id {
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ message: CaseMessage) -> some View {
        switch message.speaker {
        case .examiner:
            Text(message.text)
                .font(.body.italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .doctor:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(StudySetKind.qa.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .patient:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if let verdict = message.verdict { verdictLine(verdict, regenerations: message.regenerations) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        }
    }

    private func verdictLine(_ verdict: AccuracyVerdict, regenerations: Int) -> some View {
        let note = regenerations > 0 ? " \u{00B7} rewritten \(regenerations)\u{00D7}" : ""
        return Label(verdict.riskTitle + note,
                     systemImage: verdict.passed ? "checkmark.shield" : "exclamationmark.shield")
            .font(.footnote)
            .foregroundStyle(verdict.passed ? Color.secondary : Color.orange)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Under the thumb: the question box, the speaker, and the microphone -
    /// or Send, once something is typed.
    private var composer: some View {
        CaseVoiceButtons(simulator: simulator, hasDraft: !trimmedDraft.isEmpty, onSend: send) {
            questionField
        }
    }

    private var questionField: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return TextField("Ask the patient, or say what you examine", text: $draft, axis: .vertical)
            .font(.body)
            .lineLimit(1...4)
            .focused($typing)
            .padding(12)
            .frame(minHeight: 48)
            .background(Color.primary.opacity(0.06), in: shape)
            // a field stands out of the glass but never leans under the finger
            .popOut(.raised, in: shape, cues: .translateOnly)
    }

    private func send() {
        let text: String = draft
        guard !trimmedDraft.isEmpty, !simulator.busy else { return }
        draft = ""
        Task { await simulator.send(text) }
    }

    /// The student's differential and plan, with the one button that marks
    /// the consultation at the bottom.
    private var presentForm: some View {
        Form {
            Section {
                TextEditor(text: $assessment).frame(minHeight: 180)
                    .popEditorRow()
            } header: {
                Text("Your differential and plan")
            } footer: {
                Text("Present as you would to the examiner: most likely diagnosis, differentials, investigations and management.")
            }
        }
        .studyBar { markButton }
    }

    private var markButton: some View {
        let grading: Bool = simulator.phase == .grading
        let title: String = grading ? (simulator.status ?? "Marking\u{2026}") : "Finish and mark"
        return Button {
            Task { await simulator.finish(assessment: assessment) }
        } label: {
            HStack(spacing: 8) {
                if grading { ProgressView().controlSize(.small) }
                Text(title)
            }
        }
        .buttonStyle(.bigPrimary)
        .disabled(grading)
    }

    /// The diagnosis and the points missed, added to the case's note.
    private var debriefIdea: IdeaClip? {
        guard let idea else { return nil }
        let list: [ChecklistItem] = simulator.caseFile.checklist
        let missed: [String] = list.filter { !$0.covered }.map(\.text)
        return SaveToIdeas.caseDebrief(diagnosis: simulator.caseFile.diagnosis, missed: missed,
                                       covered: simulator.coveredCount, total: list.count, of: idea)
    }

    private var debrief: some View {
        List {
            Section {
                LabeledContent("Diagnosis", value: simulator.caseFile.diagnosis)
                LabeledContent("Checklist", value: "\(simulator.coveredCount) of \(simulator.caseFile.checklist.count) covered")
                if let debriefIdea {
                    SaveToIdeasButton(clip: debriefIdea)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(ChecklistItem.Section.allCases, id: \.self) { section in
                let items = simulator.caseFile.checklist.filter { $0.section == section }
                if !items.isEmpty {
                    Section(section.title) {
                        ForEach(items) { item in
                            Label(item.text, systemImage: item.covered ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(item.covered ? Color.green : Color.red)
                        }
                    }
                }
            }
            if !simulator.unreliableReplies.isEmpty {
                Section {
                    ForEach(simulator.unreliableReplies) { message in
                        Text(message.text).font(.footnote)
                    }
                } header: {
                    Text("Answers to treat with caution")
                } footer: {
                    Text("The accuracy checker still found these inconsistent with the case after rewriting. Don't learn from them.")
                }
            }
            Section {
                Text("A study aid, not medical advice. Generated patients can be wrong.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .studyBar {
            Button("Done", action: onClose)
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.return, modifiers: [])
        }
        .saveToIdeasHost()
    }
}
