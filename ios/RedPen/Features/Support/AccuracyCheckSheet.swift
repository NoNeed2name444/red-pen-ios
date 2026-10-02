import SwiftUI

struct AccuracyRequest: Identifiable {
    let id = UUID()
    let set: StudySet
    let instruction: String
    let text: String
}

/// MedVAL's grade of one card, question, page or station, with what it found.
///
/// Opens at half height, so the card being checked stays in view above it;
/// drag it up for the whole result.
struct AccuracyCheckSheet: View {
    let request: AccuracyRequest
    @EnvironmentObject private var llm: LocalLLMService
    @Environment(\.dismiss) private var dismiss
    @State private var verdict: AccuracyVerdict?
    @State private var trouble: String?
    @State private var hadSource = true
    @State private var showModels = false

    var body: some View {
        NavigationStack {
            List {
                Section("Checking") {
                    Text(Highlight.plain(request.text)).font(.footnote).lineLimit(8)
                }
                if let verdict {
                    resultSection(verdict)
                    if !verdict.reasoning.isEmpty {
                        Section("Why") { Text(verdict.reasoning).font(.footnote) }
                    }
                } else if let trouble {
                    troubleSection(trouble)
                } else {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Checking\u{2026}").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Accuracy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showModels) { ModelSettingsView() }
        .task { await run() }
    }

    private func resultSection(_ verdict: AccuracyVerdict) -> some View {
        let symbol: String = verdict.passed ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        let colour: Color = AccuracyCheckSheet.riskColor(verdict)
        let footer: String = footerText(verdict)
        return Section {
            Label(verdict.riskTitle, systemImage: symbol)
                .foregroundStyle(colour)
                .font(.headline)
            if verdict.findings.isEmpty {
                Text("No errors found.")
            }
            ForEach(verdict.findings, id: \.self) { finding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.category.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(finding.text).font(.footnote)
                }
            }
        } header: {
            Text("Result")
        } footer: {
            Text(footer)
        }
    }

    /// Nothing could check it: why, and the one place to fix that.
    private func troubleSection(_ trouble: String) -> some View {
        Section {
            Text(trouble).foregroundStyle(.red)
            // the one thing to do here, standing out of the glass
            Button {
                showModels = true
            } label: {
                Label("AI models", systemImage: "cpu")
            }
            .buttonStyle(.bigSecondary)
        }
    }

    /// Green for a pass, red for a serious risk, orange for anything between.
    static func riskColor(_ verdict: AccuracyVerdict) -> Color {
        if verdict.passed { return Color.green }
        if verdict.riskLevel >= 4 { return Color.red }
        return Color.orange
    }

    private func footerText(_ verdict: AccuracyVerdict) -> String {
        let who: String = verdict.checkedBy
        if hadSource {
            return "Checked by \(who) against the matching pages of this set's source."
        }
        return "Checked by \(who) against standard teaching \u{2014} this set has no source attached, so this is a weaker check."
    }

    private func run() async {
        guard let backend = llm.backend(for: .checker) else {
            trouble = "Choose an accuracy checker in AI models \u{2014} MedVAL on this device, or a hosted model."
            return
        }
        let reference = AccuracyChecker.reference(for: request.text, in: request.set,
                                                  limit: backend.promptBudgetChars)
        hadSource = reference != nil
        do {
            verdict = try await AccuracyChecker.check(
                instruction: request.instruction,
                input: reference ?? AccuracyChecker.noSourceNote,
                output: request.text, using: backend)
        } catch {
            trouble = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
