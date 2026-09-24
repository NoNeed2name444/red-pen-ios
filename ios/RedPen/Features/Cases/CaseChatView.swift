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

    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State private var simulator: CaseSimulator?
    @State private var draft = ""
    @State private var assessment = ""
    @State private var showModels = false

    var body: some View {
        NavigationStack {
            Group {
                if let simulator {
                    CaseSession(simulator: simulator, draft: $draft, assessment: $assessment)
                } else {
                    notReady
                }
            }
            .navigationTitle(card.topic.isEmpty ? "Simulated patient" : card.topic)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .sheet(isPresented: $showModels) { ModelSettingsView() }
        .task(id: llm.writerChoice) { await start() }
    }

    private var notReady: some View {
        ContentUnavailableView {
            Label("Choose a model to play the patient", systemImage: "stethoscope")
        } description: {
            Text("With Pro, use Doctor-R1 on this device or \(Brand.name) Cloud; Apple's own model works for free where Apple Intelligence is on. Add MedVAL and every patient answer is checked against the case before you see it.")
        } actions: {
            Button("AI models") { showModels = true }.buttonStyle(.glassProminent)
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
    @FocusState private var typing: Bool

    var body: some View {
        switch simulator.phase {
        case .preparing:
            ProgressView(simulator.status ?? "Preparing\u{2026}").frame(maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Couldn't set up the case", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .interviewing:
            VStack(spacing: 0) {
                coverageBar
                transcript
                composer
            }
        case .presenting, .grading:
            presentForm
        case .debrief:
            debrief
        }
    }

    private var coverageBar: some View {
        HStack {
            Text("Checklist \(simulator.coveredCount) of \(simulator.caseFile.checklist.count)")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            if let checker = simulator.checkerLabel {
                Label("Checked by \(checker)", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("End & present") { simulator.endInterview() }
                .buttonStyle(.glass)
                .disabled(simulator.busy)
        }
        .padding(.horizontal).padding(.vertical, 8)
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
                .font(.callout.italic())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .doctor:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(10)
                    .foregroundStyle(.white)
                    .background(StudySetKind.qa.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .patient:
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .padding(10)
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
            .font(.caption2)
            .foregroundStyle(verdict.passed ? Color.secondary : Color.orange)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask the patient, or say what you examine", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button {
                let text = draft
                draft = ""
                Task { await simulator.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(simulator.busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var presentForm: some View {
        Form {
            Section {
                TextEditor(text: $assessment).frame(minHeight: 180)
            } header: {
                Text("Your differential and plan")
            } footer: {
                Text("Present as you would to the examiner: most likely diagnosis, differentials, investigations and management.")
            }
            Section {
                Button {
                    Task { await simulator.finish(assessment: assessment) }
                } label: {
                    HStack {
                        if simulator.phase == .grading { ProgressView().controlSize(.small) }
                        Text(simulator.phase == .grading ? (simulator.status ?? "Marking\u{2026}") : "Finish and mark")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(simulator.phase == .grading)
            }
        }
    }

    private var debrief: some View {
        List {
            Section {
                LabeledContent("Diagnosis", value: simulator.caseFile.diagnosis)
                LabeledContent("Checklist", value: "\(simulator.coveredCount) of \(simulator.caseFile.checklist.count) covered")
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
    }
}
