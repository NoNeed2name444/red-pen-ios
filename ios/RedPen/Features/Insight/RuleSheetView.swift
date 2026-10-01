import SwiftUI
import UIKit

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
        let hasActions: Bool = store.missedWithoutRules.count > 0 || canWrite || isWriting
        sheet(shown)
            // the same slab `.studyBar` puts there, but only while there is
            // something to do - the list keeps its place when it goes
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasActions {
                    StudyActionBar { actions }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .searchable(text: $query, prompt: "Search rules")
            .navigationTitle("Rule sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: store.ruleSheetText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.ruleSheet.isEmpty)
                    // swipe-to-delete, visibly: pointer users and first-timers
                    if !store.ruleSheet.isEmpty {
                        EditButton()
                    }
                }
            }
    }

    private func sheet(_ shown: [RuleGroup]) -> some View {
        List {
            if store.ruleSheet.isEmpty {
                Section {
                    Text("Every question you get wrong can leave one line here to remember. Add them from a quiz\u{2019}s results, or from your recent mistakes below.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let note {
                Section {
                    Label(note, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
    }

    // MARK: - The bottom slab

    /// Add from mistakes (the main button) and Write with AI beside it; while
    /// the model writes, how far it has got instead.
    @ViewBuilder
    private var actions: some View {
        if isWriting {
            RuleWritingProgress(done: writtenSoFar, total: writingTotal)
        } else {
            RuleSheetButtons(missed: store.missedWithoutRules.count,
                             plain: canWrite ? plainRules.count : 0,
                             onAdd: addFromMistakes,
                             onWrite: writeWithAI)
        }
    }

    private func addFromMistakes() {
        let added = store.addRulesForMissed()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let plural: String = added == 1 ? "" : "s"
        withAnimation(.snappy) { note = "Added \(added) rule\(plural)." }
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
            let done: Int = writtenSoFar
            let plural: String = todo.count == 1 ? "" : "s"
            let failed: String = "The model did not answer in a usable way; your rules are unchanged. Try again later."
            let rewrote: String = "Rewrote \(done) of \(todo.count) rule\(plural)."
            isWriting = false
            note = done == 0 ? failed : rewrote
        }
    }
}

/// The rule sheet's slab: "Add N from your recent mistakes" as the main
/// button at the trailing end, "Write N rules with AI" beside it. Stacked on
/// a phone, where both would otherwise wrap.
private struct RuleSheetButtons: View {
    let missed: Int
    /// Plain rules the model could rewrite; 0 when there is no model or
    /// nothing to rewrite.
    let plain: Int
    let onAdd: () -> Void
    let onWrite: () -> Void
    @Environment(\.windowSpan) private var span

    var body: some View {
        let wide: Bool = span != .slim
        let side = AnyLayout(HStackLayout(spacing: 12))
        let stack = AnyLayout(VStackLayout(spacing: 12))
        let layout: AnyLayout = wide ? side : stack
        let writePlural: String = plain == 1 ? "" : "s"
        let writeTitle: String = "Write \(plain) rule\(writePlural) with AI"
        let addTitle: String = "Add \(missed) from your recent mistakes"
        layout {
            if plain > 0 {
                Button(action: onWrite) {
                    Label(writeTitle, systemImage: "sparkles")
                }
                .buttonStyle(.bigSecondary)
                .accessibilityHint("Rewrites each plain rule as one exam-style line, ten at a time")
            }
            if span == .broad && plain > 0 && missed > 0 { Spacer(minLength: 16) }
            if missed > 0 {
                Button(action: onAdd) {
                    Label(addTitle, systemImage: "text.badge.plus")
                }
                .buttonStyle(.bigPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// While the model rewrites the rules: how many so far, and that the app
/// can still be used.
private struct RuleWritingProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        let fraction: Double = Double(done) / Double(max(1, total))
        let status: String = "Writing rules with AI \u{00B7} \(done) of \(total)"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ThinProgress(fraction: fraction)
            Text("Ten at a time. You can keep using the app while it works.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
