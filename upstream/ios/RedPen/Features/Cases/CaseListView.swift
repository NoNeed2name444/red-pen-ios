import SwiftUI

/// A Cases set: one card per patient - initials, age and sex, where they are
/// seen and what they came with - and where each stands: New, Seen (a run in
/// progress) or Discharged with the last score.
///
/// A case the verification layer has held (a red flag in its medicine) is
/// never shown; the list says how many are waiting on the checkers.
struct CaseListView: View {
    let set: StudySet
    @EnvironmentObject private var store: Store
    @ObservedObject private var runs = CaseRunStore.shared

    /// The set as the library has it now: another patient may have joined it.
    private var current: StudySet {
        store.library.first { $0.id == set.id } ?? set
    }

    private var shown: [CaseFile] {
        let flagged: Set<String> = AccuracyHolds.snapshot()
        return current.caseFiles.filter { !CaseChecks.isHeld($0, flagged: flagged) }
    }

    private var heldCount: Int { current.caseFiles.count - shown.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                CaseLabel(current.caseFiles.count == 1 ? "1 patient" : "\(current.caseFiles.count) patients")
                    .padding(.horizontal, 4)
                if shown.isEmpty {
                    empty
                }
                ForEach(shown) { file in
                    NavigationLink {
                        CaseWardView(file: file, setID: current.id)
                    } label: {
                        CasePatientCard(file: file, state: runs.state(of: file))
                    }
                    .buttonStyle(.plain)
                }
                if heldCount > 0 {
                    Label(heldNote, systemImage: "hand.raised")
                        .font(.footnote)
                        .foregroundStyle(CaseInk.biro)
                        .padding(.horizontal, 4)
                }
            }
            .padding(16)
            // one comfortable column on a wide iPad
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .wardScreen()
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
            }

    private var empty: some View {
        Text(heldCount > 0
             ? "Every patient here is waiting on the accuracy checkers."
             : "No patients in this set yet.")
            .font(.subheadline)
            .foregroundStyle(CaseInk.biro)
            .caseCard()
    }

    private var heldNote: String {
        let plural: String = heldCount == 1 ? " is" : "s are"
        return "\(heldCount) patient\(plural) held while the checkers look at a possible error."
    }
}

/// One patient on the list.
struct CasePatientCard: View {
    let file: CaseFile
    let state: CaseRun.State

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CaseAvatar(initials: file.patient.initials)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(file.patient.ageSex)
                        .font(.headline)
                    Text("\u{00B7} " + file.setting.label)
                        .font(.subheadline)
                        .foregroundStyle(CaseInk.biro)
                }
                Text(shortComplaint)
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                CaseStateChip(state: state)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.wardInkSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .caseCard(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the patient")
        .accessibilityAddTraits(.isButton)
    }

    /// The complaint in a few words: its first clause.
    private var shortComplaint: String {
        let words: String = file.complaint
        let cut: String = words.components(separatedBy: CharacterSet(charactersIn: ",.;")).first ?? words
        return "\u{201C}" + cut.trimmingCharacters(in: .whitespaces) + "\u{201D}"
    }

    private var spoken: String {
        let status: String
        switch state {
        case .new: status = "New"
        case .seen: status = "Seen, in progress"
        case .discharged(let score): status = "Discharged, score \(score) out of 100"
        }
        return "\(file.patient.spoken), \(file.setting.label). \(shortComplaint). \(status)"
    }
}
