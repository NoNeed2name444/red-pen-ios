import SwiftUI

/// The decision: the leading diagnosis confirmed (the top of the ladder, or
/// another picked here), the next step as a single best answer, and an
/// optional one-line reason. Discharging closes the case and opens the
/// debrief.
struct CaseDecisionView: View {
    let file: CaseFile
    let leading: String
    let decide: (CaseRun.Decision) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var diagnosis: String
    @State private var choosing = false
    @State private var typed = ""
    @State private var option: Int? = nil
    @State private var reason = ""

    init(file: CaseFile, leading: String, decide: @escaping (CaseRun.Decision) -> Void) {
        self.file = file
        self.leading = leading
        self.decide = decide
        _diagnosis = State(initialValue: leading)
        _choosing = State(initialValue: leading.isEmpty)
    }

    private var ready: Bool {
        !diagnosis.trimmingCharacters(in: .whitespaces).isEmpty && option != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    diagnosisCard
                    nextStepCard
                    reasonCard
                }
                .padding(16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .wardScreen()
            .navigationTitle("Decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { discharge() } label: {
                    Label("Discharge and debrief", systemImage: "doc.text")
                }
                .buttonStyle(.wardPrimary)
                .disabled(!ready)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.wardSurface.ignoresSafeArea(edges: .bottom))
                .accessibilityHint(ready ? "Closes the case and shows what mattered" : "Confirm a diagnosis and choose a next step first")
            }
        }
    }

    private var diagnosisCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Leading diagnosis")
            if !diagnosis.isEmpty {
                HStack {
                    Text(diagnosis)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(choosing ? "Keep" : "Change") { choosing.toggle() }
                        .frame(minHeight: 44)
                }
            }
            if choosing {
                HStack(spacing: 8) {
                    TextField("Type a diagnosis", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(useTyped)
                    Button("Use", action: useTyped)
                        .buttonStyle(.wardCompact)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(file.candidates, id: \.self) { name in
                    Button {
                        diagnosis = name
                        choosing = false
                    } label: {
                        HStack {
                            Text(name).frame(maxWidth: .infinity, alignment: .leading)
                            if CaseNames.same(name, diagnosis) {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(CaseNames.same(name, diagnosis) ? [.isSelected] : [])
                }
            }
        }
        .caseCard()
    }

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Next step")
            Text("What is the single best next step?")
                .font(.headline)
            ForEach(Array(file.nextStep.options.enumerated()), id: \.offset) { index, text in
                Button { option = index } label: {
                    WardOptionRow(letter: AccuracyItem.letter(index), text: text,
                                  mark: option == index ? .chosen : .idle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Option \(AccuracyItem.letter(index)): \(text)")
                .accessibilityAddTraits(option == index ? [.isSelected] : [])
            }
        }
        .caseCard()
    }

    private var reasonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CaseLabel("Your reason (optional)")
            TextField("One line: why this patient, why now", text: $reason)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
        }
        .caseCard()
    }

    private func useTyped() {
        let name: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        diagnosis = file.resolve(name) ?? name
        typed = ""
        choosing = false
    }

    private func discharge() {
        guard ready, let option else { return }
        decide(CaseRun.Decision(diagnosis: diagnosis, nextStep: option,
                                reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}
