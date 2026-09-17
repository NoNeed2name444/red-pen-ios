import SwiftUI

/// OSCE recall drill — matches `renderOsceStep()` / `renderOsceComplete()` /
/// `osceGrade()`: work through each checklist's steps in order, one hidden
/// at a time ("what comes next?"), reveal it, grade yourself Knew it / Missed
/// it. Missed steps queue up for a second pass once the checklist's first
/// pass finishes; that second pass is not itself repeated. When a checklist
/// completes, move on to the next one in the set.
struct OsceReviewView: View {
    let studySet: StudySet
    @Environment(\.dismiss) private var dismiss

    @State private var checklistIndex: Int
    @State private var stepIndex = 0
    @State private var revealed = false
    @State private var missed: [Int] = []
    @State private var repeatQueue: [Int] = []
    @State private var repeatPos = 0
    @State private var complete = false

    init(set studySet: StudySet, startChecklistIndex: Int = 0, startRevealed: Bool = false, startComplete: Bool = false, startMissed: [Int] = []) {
        self.studySet = studySet
        _checklistIndex = State(initialValue: min(startChecklistIndex, max(0, studySet.osceChecklists.count - 1)))
        _revealed = State(initialValue: startRevealed)
        _complete = State(initialValue: startComplete)
        _missed = State(initialValue: startMissed)
    }

    private var checklists: [OsceChecklist] { studySet.osceChecklists }
    private var checklist: OsceChecklist? { checklists.indices.contains(checklistIndex) ? checklists[checklistIndex] : nil }
    private var inRepeat: Bool { !repeatQueue.isEmpty }
    private var currentStepIdx: Int { inRepeat ? repeatQueue[repeatPos] : stepIndex }
    private var currentStepText: String? {
        guard let checklist, checklist.steps.indices.contains(currentStepIdx) else { return nil }
        return checklist.steps[currentStepIdx]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let checklist {
                progressHeader(checklist)
                Divider()
                if complete {
                    completeBody(checklist)
                } else {
                    stepBody(checklist)
                }
            } else {
                ContentUnavailableView("No checklists in this set.", systemImage: "checklist")
            }
        }
        .navigationTitle(studySet.subject.isEmpty ? "OSCE" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: header

    @ViewBuilder
    private func progressHeader(_ checklist: OsceChecklist) -> some View {
        let totalSteps = checklists.reduce(0) { $0 + $1.steps.count }
        let stepsBeforeThis = checklists.prefix(checklistIndex).reduce(0) { $0 + $1.steps.count }
            + (complete ? checklist.steps.count : (inRepeat ? checklist.steps.count : stepIndex))
        let fraction = totalSteps > 0 ? min(1.0, Double(stepsBeforeThis) / Double(totalSteps)) : 0

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !complete {
                    Text(inRepeat ? "Missed step \(repeatPos + 1) of \(repeatQueue.count)" : "Step \(stepIndex + 1) of \(checklist.steps.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(inRepeat ? .orange : .secondary)
                    if inRepeat {
                        Text("again")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .foregroundStyle(.orange)
                            .liquidGlassChip(tint: .orange)
                    }
                }
                Spacer()
            }
            Text(checklist.title).font(.title3.weight(.semibold))
            ProgressView(value: fraction).tint(.accentColor)
        }
        .padding()
    }

    // MARK: step

    @ViewBuilder
    private func stepBody(_ checklist: OsceChecklist) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                if revealed, let text = currentStepText {
                    Text(text)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(inRepeat ? "Once more — what was step \(currentStepIdx + 1)? Say it, then reveal." : "What comes next? Say it out loud, then reveal.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                if !revealed && !inRepeat && stepIndex == 0 {
                    Text("Work through the station out loud, revealing each step to check yourself.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(minHeight: 220)
            .padding(.bottom, 12)
        }
        footer
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            if revealed {
                HStack(spacing: 12) {
                    Button("Missed it") { grade(knewIt: false) }
                        .buttonStyle(.glass).tint(.red)
                    Button("Knew it") { grade(knewIt: true) }
                        .buttonStyle(.glassProminent)
                }
            } else {
                Button("Reveal") { revealed = true }
                    .buttonStyle(.glassProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: complete

    @ViewBuilder
    private func completeBody(_ checklist: OsceChecklist) -> some View {
        let hasNext = checklistIndex < checklists.count - 1
        let total = checklist.steps.count
        let missedCount = missed.count
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text(hasNext ? "Checklist complete — \(checklist.title)" : "All checklists complete!")
                .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(missedCount == 0
                 ? "Recalled all \(total) steps first time."
                 : "Recalled \(total - missedCount) of \(total) steps first time — the \(missedCount) you missed came round again.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            if hasNext {
                Button("Next checklist: \(checklists[checklistIndex + 1].title) ›") { nextChecklist() }
                    .buttonStyle(.glassProminent)
            } else {
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    // MARK: logic — mirrors osceGrade()

    private func grade(knewIt: Bool) {
        guard let checklist else { return }
        if inRepeat {
            repeatPos += 1
            if repeatPos >= repeatQueue.count {
                repeatQueue = []
                complete = true
                return
            }
        } else {
            if !knewIt { missed.append(stepIndex) }
            if stepIndex >= checklist.steps.count - 1 {
                if !missed.isEmpty {
                    repeatQueue = missed
                    repeatPos = 0
                } else {
                    complete = true
                    return
                }
            } else {
                stepIndex += 1
            }
        }
        revealed = false
    }

    private func nextChecklist() {
        checklistIndex += 1
        stepIndex = 0
        revealed = false
        missed = []
        repeatQueue = []
        repeatPos = 0
        complete = false
    }
}
