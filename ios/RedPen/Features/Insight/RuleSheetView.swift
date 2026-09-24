import SwiftUI

/// The rule sheet: one line to remember for every question got wrong, grouped
/// by subject, searchable, and shareable as plain text.
///
/// Rules start as the question's own words ("What is the next step? \u{2192}
/// CT pulmonary angiography"), which works with no model at all. With a
/// writer model chosen they can be rewritten as proper exam rules; that runs
/// in the background, batch by batch, and the sheet stays usable throughout.
struct RuleSheetView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var llm = LocalLLMService.shared
    @State private var query = ""
    @State private var isWriting = false
    @State private var writtenSoFar = 0
    @State private var writingTotal = 0
    @State private var note: String?

    /// The groups as shown: everything, or only the rules that match the search.
    private var groups: [RuleGroup] {
        let all = store.rulesBySubject
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return all }
        return all.compactMap { group in
            let subjectHit = group.subject.localizedCaseInsensitiveContains(term)
            let hits = group.rules.filter { rule in
                subjectHit || rule.text.localizedCaseInsensitiveContains(term)
                    || rule.detail.localizedCaseInsensitiveContains(term)
                    || rule.stem.localizedCaseInsensitiveContains(term)
            }
            return hits.isEmpty ? nil : RuleGroup(subject: group.subject, rules: hits)
        }
    }

    /// Rules still in their plain wording, newest first - what the model would rewrite.
    private var plainRules: [StudyRule] {
        store.ruleSheet.values.filter { !$0.byAI }.sorted { $0.date > $1.date }
    }

    var body: some View {
        let shown = groups
        let missed = store.missedWithoutRules.count
        List {
            if store.ruleSheet.isEmpty {
                Section {
                    Text("Every question you get wrong can leave one line here to remember. Add them from a quiz\u{2019}s results, or from your recent mistakes below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if missed > 0 || canWrite || isWriting || note != nil {
                Section {
                    if missed > 0 {
                        Button {
                            let added = store.addRulesForMissed()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.snappy) { note = "Added \(added) rule\(added == 1 ? "" : "s")." }
                        } label: {
                            Label("Add \(missed) from your recent mistakes", systemImage: "text.badge.plus")
                        }
                    }
                    if isWriting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Writing rules with AI \u{00B7} \(writtenSoFar) of \(writingTotal)")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else if canWrite {
                        Button(action: writeWithAI) {
                            Label("Write \(plainRules.count) rule\(plainRules.count == 1 ? "" : "s") with AI",
                                  systemImage: "sparkles")
                        }
                    }
                    if let note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                } footer: {
                    if canWrite || isWriting {
                        Text("The model rewrites each plain rule as one exam-style line, ten at a time. You can keep using the app while it works.")
                    }
                }
            }

            ForEach(shown) { group in
                Section(group.subject) {
                    ForEach(group.rules) { rule in
                        row(rule)
                    }
                    .onDelete { offsets in
                        for index in offsets where group.rules.indices.contains(index) {
                            store.deleteRule(group.rules[index].id)
                        }
                    }
                }
            }

            if !store.ruleSheet.isEmpty && shown.isEmpty {
                Section {
                    Text("No rules match \u{201C}\(query)\u{201D}.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Search rules")
        .navigationTitle("Rule sheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: store.ruleSheetText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(store.ruleSheet.isEmpty)
            }
        }
    }

    /// Whether there is a writer model and something for it to rewrite.
    private var canWrite: Bool {
        !isWriting && !plainRules.isEmpty && llm.backend(for: .writer) != nil
    }

    private func row(_ rule: StudyRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !rule.detail.isEmpty {
                Text(rule.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rule.byAI || rule.isExample == true {
                HStack(spacing: 8) {
                    if rule.byAI { Label("Written with AI", systemImage: "sparkles") }
                    if rule.isExample == true { Text("Example data") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = rule.text }
            Button("Delete", systemImage: "trash", role: .destructive) { store.deleteRule(rule.id) }
        }
    }

    /// Starts the model on every plain rule and returns at once; the sheet
    /// fills in as each batch comes back.
    private func writeWithAI() {
        guard !isWriting, let backend = llm.backend(for: .writer) else { return }
        let todo = plainRules
        guard !todo.isEmpty else { return }
        isWriting = true
        writtenSoFar = 0
        writingTotal = todo.count
        note = nil
        let store = self.store
        Task {
            await RuleWriter.write(todo, with: backend) { lines in
                store.applyWrittenRules(lines)
                writtenSoFar += lines.count
            }
            let done = writtenSoFar
            isWriting = false
            note = done == 0
                ? "The model did not answer in a usable way; your rules are unchanged. Try again later."
                : "Rewrote \(done) of \(todo.count) rule\(todo.count == 1 ? "" : "s")."
        }
    }
}
