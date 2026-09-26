import SwiftUI

extension AccuracyGrade {
    var color: Color {
        switch self {
        case .verified: return .green
        case .check: return .orange
        case .flagged: return .red
        case .unchecked: return .secondary
        }
    }
}

/// The accuracy badge on a question, card, case, station or page: Verified,
/// Check this, Flagged - or not checked yet - and a tap for why.
///
/// Shown only where the answer already is (after a question is answered, a
/// card turned over), because the "why" can name the right answer.
struct AccuracyBadge: View {
    let set: StudySet
    let itemID: String
    @ObservedObject private var accuracy = AccuracyStore.shared
    @State private var showing = false

    var body: some View {
        if let item = accuracy.item(itemID, in: set) {
            let assessment: AccuracyAssessment = accuracy.assessment(of: item)
            let checking: Bool = accuracy.isChecking(item)
            Button { showing = true } label: {
                // the capsule is small; the target is 44 points tall
                AccuracyBadgeFace(grade: assessment.grade, checking: checking)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accuracy: " + (checking ? "checking" : assessment.grade.title))
            .accessibilityHint("Shows why, the sources, and Report an error")
            .sheet(isPresented: $showing) {
                AccuracyWhySheet(item: item)
            }
        }
    }
}

/// The capsule itself: a symbol and a word, in the grade's colour - never
/// the colour alone, so it reads with Differentiate Without Colour.
struct AccuracyBadgeFace: View {
    let grade: AccuracyGrade
    var checking: Bool = false

    var body: some View {
        let colour: Color = checking ? .secondary : grade.color
        HStack(spacing: 4) {
            if checking {
                ProgressView().controlSize(.mini)
                Text("Checking\u{2026}")
            } else {
                Image(systemName: grade.symbol)
                Text(grade.title)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(colour)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(colour.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
    }
}

/// A set's accuracy at a glance in its library row: a small mark when
/// anything is flagged or to check, nothing until something is checked.
struct AccuracySetMark: View {
    let set: StudySet
    @ObservedObject private var accuracy = AccuracyStore.shared

    var body: some View {
        if let summary = accuracy.summary(for: set), summary.checked > 0 {
            let grade: AccuracyGrade = summary.grade
            Image(systemName: grade.symbol)
                .font(.caption)
                .foregroundStyle(grade.color)
                .accessibilityLabel("Accuracy: " + (summary.line ?? grade.title))
        }
    }
}

/// The same summary in words, for a set's menu.
struct AccuracySetSummary: View {
    let set: StudySet
    @ObservedObject private var accuracy = AccuracyStore.shared

    var body: some View {
        if let summary = accuracy.summary(for: set), let line = summary.line {
            Label("Accuracy: " + line, systemImage: summary.grade.symbol)
        } else {
            Label("Accuracy: not checked yet", systemImage: "clock")
        }
    }
}

/// Why an item has its badge: which rules and which models raised what, the
/// sources the models were shown (with links), the correction they offered -
/// one tap to accept it - and Report an error.
struct AccuracyWhySheet: View {
    let item: AccuracyItem
    @EnvironmentObject private var store: Store
    @ObservedObject private var accuracy = AccuracyStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var reporting = false
    @State private var message: String?
    @State private var working = false

    private var assessment: AccuracyAssessment { accuracy.assessment(of: item) }

    var body: some View {
        NavigationStack {
            List {
                resultSection
                if !assessment.rules.isEmpty { rulesSection }
                if let votes = assessment.record?.votes, !votes.isEmpty { votesSection(votes) }
                if let evidence = assessment.record?.evidence, !evidence.isEmpty { evidenceSection(evidence) }
                if let fix = suggestion { fixSection(fix) }
                reportSection
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
    }

    private var resultSection: some View {
        let a: AccuracyAssessment = assessment
        let percent: Int = Int((a.probability * 100).rounded())
        return Section {
            AccuracyBadgeFace(grade: a.grade, checking: accuracy.isChecking(item))
            Text(explanation(a, percent: percent)).font(.footnote)
            if a.grade == .unchecked && !accuracy.isChecking(item) {
                Button {
                    Task { await checkNow() }
                } label: {
                    Label("Check now", systemImage: "checkmark.shield")
                }
                .disabled(working)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Result")
        } footer: {
            Text("Checked against this \(item.kind.noun)'s lecture and current literature by free checker models voting, with rule checks for doses, lab values and contradictions. Scored by \(Brand.name)'s accuracy model (\(accuracy.weights.version)). Still use your judgement.")
        }
    }

    private func explanation(_ a: AccuracyAssessment, percent: Int) -> String {
        switch a.grade {
        case .verified: return "The checkers agree it is right, and the sources support it (\(percent)% likely accurate)."
        case .check: return "Something about it is uncertain - read the reasons below before you rely on it (\(percent)% likely accurate)."
        case .flagged:
            if a.record == nil { return "A rule check found a likely error." }
            return "The checkers found a likely error (\(percent)% likely accurate)."
        case .unchecked:
            return "Not checked by the models yet. Rule checks found nothing; the rest of the check needs \(Brand.name) Cloud."
        }
    }

    private var rulesSection: some View {
        Section("Rule checks") {
            ForEach(assessment.rules, id: \.self) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.ruleTitle(hit.rule)).font(.caption.weight(.semibold))
                        .foregroundStyle(hit.isSevere ? Color.red : Color.orange)
                    Text(hit.detail).font(.footnote)
                }
            }
        }
    }

    private func votesSection(_ votes: [AccuracyVote]) -> some View {
        Section("Checker models") {
            ForEach(votes, id: \.self) { vote in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(vote.model).font(.caption.weight(.semibold))
                        Spacer()
                        Text(Self.riskWords(vote.risk)).font(.caption)
                            .foregroundStyle(vote.risk >= 3 ? Color.red : Color.green)
                    }
                    if let answer = vote.answer, item.kind == .mcq {
                        Text("Its own answer: " + answer).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(vote.issues, id: \.self) { issue in
                        Text(issue).font(.footnote)
                    }
                    if !vote.cites.isEmpty {
                        Text("Cites " + vote.cites.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func evidenceSection(_ evidence: [AccuracyEvidence]) -> some View {
        Section("Sources the checkers were shown") {
            ForEach(evidence, id: \.self) { e in
                if let url = URL(string: e.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("[" + e.id + "] " + e.source).font(.caption.weight(.semibold))
                            Text(e.title).font(.footnote).lineLimit(3)
                        }
                    }
                }
            }
        }
    }

    /// A correction offered for this item, if it can be applied with one tap.
    private var suggestion: AccuracySuggestion? {
        guard let fix = assessment.record?.fix, assessment.grade != .verified,
              AccuracyFix.canApply(fix, to: item) else { return nil }
        return fix
    }

    private func fixSection(_ fix: AccuracySuggestion) -> some View {
        Section {
            Text(Self.fixWords(fix)).font(.footnote)
            Button {
                accept(fix)
            } label: {
                Label("Accept the correction", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bigSecondary)
        } header: {
            Text("Suggested correction")
        } footer: {
            Text("It is checked again once changed. You can still edit it by hand.")
        }
    }

    private var reportSection: some View {
        Section {
            if reporting {
                TextField("What's wrong? (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                Button("Send report") { Task { await sendReport() } }
                    .disabled(working)
            } else if assessment.record?.reported == true {
                Label("You reported this \(item.kind.noun)", systemImage: "flag.fill").foregroundStyle(.secondary)
            } else {
                Button { reporting = true } label: {
                    Label("Report an error", systemImage: "flag")
                }
            }
        } footer: {
            Text("Reports help train the accuracy model. Only this \(item.kind.noun) and your note are sent.")
        }
    }

    // MARK: actions

    private func accept(_ fix: AccuracySuggestion) {
        for set in store.library {
            if let changed = AccuracyFix.apply(fix, toItem: item.id, in: set) {
                store.update(changed)
                message = "Corrected. It will be checked again."
                AccuracyStore.shared.kick()
                return
            }
        }
        message = "This \(item.kind.noun) isn't in your library, so it can't be changed here."
    }

    private func checkNow() async {
        working = true
        message = await AccuracyStore.shared.checkNow(item)
        working = false
    }

    private func sendReport() async {
        working = true
        let trouble: String? = await AccuracyStore.shared.report(item, note: note)
        message = trouble ?? "Thank you - reported."
        reporting = false
        working = false
    }

    // MARK: words

    static func riskWords(_ risk: Int) -> String {
        switch risk {
        case 1: return "No error"
        case 2: return "Minor"
        case 3: return "Could mislead"
        default: return "Wrong"
        }
    }

    static func ruleTitle(_ rule: String) -> String {
        switch rule {
        case "dose-range": return "Dose outside the usual range"
        case "lab-implausible": return "Impossible lab value (wrong unit?)"
        case "lab-unit": return "Unusual unit"
        case "reference-range": return "Wrong normal range"
        case "key-explanation-conflict": return "Key and explanation disagree"
        case "key-called-wrong": return "Explanation calls the key wrong"
        case "duplicate-option": return "Duplicate options"
        case "no-key": return "No valid key"
        case "non-answer-position", "all-and-none", "all-above-contradiction": return "\"All/none of the above\""
        case "negation-mismatch": return "NOT/EXCEPT question"
        case "numbers-disagree": return "Numbers disagree"
        case "direction-conflict": return "Contradiction"
        default: return rule
        }
    }

    static func fixWords(_ fix: AccuracySuggestion) -> String {
        switch fix.field {
        case "key": return "Make " + fix.value + " the correct answer."
        case "explanation": return "Explanation: " + fix.value
        case "answer": return "Answer: " + fix.value
        default: return fix.value
        }
    }
}

/// "Check accuracy" for one of the student's own notes - only when they ask.
/// For the Ideas screens to place beside a note.
struct NoteAccuracyButton: View {
    let noteID: UUID
    let title: String
    let text: String
    @ObservedObject private var accuracy = AccuracyStore.shared
    @State private var showing = false
    @State private var trouble: String?

    private var item: AccuracyItem { AccuracyItem.note(id: noteID, title: title, body: text) }

    var body: some View {
        Button {
            Task {
                if !accuracy.ledger.isChecked(item.contentHash) { trouble = await accuracy.checkNow(item) }
                showing = true
            }
        } label: {
            Label("Check accuracy", systemImage: "checkmark.shield")
        }
        .disabled(accuracy.isChecking(item))
        .sheet(isPresented: $showing) {
            AccuracyWhySheet(item: item)
        }
    }
}
