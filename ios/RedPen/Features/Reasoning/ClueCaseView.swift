import SwiftUI

/// A set's clue-by-clue cases: each with how it went last time, and the
/// strip for writing more.
struct ClueCasesView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var confirmClear = false

    var body: some View {
        let cases = reasoning.pack(for: set.id).cases
        List {
            Section {
                ReasoningWriteBar(tool: .cases, set: set)
            } footer: {
                Text("Clues come from the vaguest to the most specific. Commit whenever you are sure: a right answer with clues still hidden scores up to 2; a wrong one scores 0.")
            }
            if !cases.isEmpty {
                Section("Cases") {
                    ForEach(Array(cases.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            ClueCaseView(clueCase: item, setId: set.id)
                        } label: {
                            row(item, number: index + 1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Clue-by-clue cases")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cases.isEmpty && set.id != ReasoningExamples.setId {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", systemImage: "trash") { confirmClear = true }
                }
            }
        }
        .confirmationDialog("Delete these cases and their scores?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete cases", role: .destructive) { reasoning.clear(.cases, for: set.id) }
        }
        .generationHUD()
    }

    private func row(_ item: ClueCase, number: Int) -> some View {
        let last = reasoning.lastPlay(of: item.id)
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                // the first clue only: the diagnosis stays hidden until played
                Text(item.clues.first ?? "Case \(number)").lineLimit(2)
                if let last {
                    Text(last.correct ? "Right at clue \(last.cluesSeen) of \(last.totalClues) \u{00B7} \(String(format: "%.2f", last.score))"
                                      : last.prematureClosure ? "Premature closure last time" : "Missed last time")
                        .font(.caption)
                        .foregroundStyle(last.correct ? Color.green : Color.orange)
                } else {
                    Text("\(item.clues.count) clues \u{00B7} not played").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One case, played: clues revealed one at a time, and at any point a commit
/// to one of four diagnoses.
struct ClueCaseView: View {
    let clueCase: ClueCase
    let setId: UUID
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var shown = 1
    @State private var options: [String]
    @State private var result: CasePlay?

    init(clueCase: ClueCase, setId: UUID) {
        self.clueCase = clueCase
        self.setId = setId
        _options = State(initialValue: Self.shuffled(clueCase))
    }

    private static func shuffled(_ item: ClueCase) -> [String] {
        item.choices.shuffled()
    }

    private var total: Int { clueCase.clues.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                clueList
                if let result {
                    outcome(result)
                } else {
                    controls
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Case")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: shown)
        .animation(.snappy, value: result?.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result == nil ? "Clue \(shown) of \(total)" : "All \(total) clues")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                if result == nil {
                    Text("Worth \(String(format: "%.2f", 1 + Double(total - shown) / Double(max(1, total)))) if right")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(result == nil ? shown : total), total: Double(max(1, total)))
        }
    }

    private var clueList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(clueCase.clues.enumerated()), id: \.offset) { index, clue in
                if index < shown || result != nil {
                    clueRow(index: index, clue: clue)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func clueRow(index: Int, clue: String) -> some View {
        let decisive = result != nil && index + 1 == clueCase.decisiveClue
        let unseen = result != nil && index >= (result?.cluesSeen ?? total)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(decisive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(clue)
                    .foregroundStyle(unseen ? Color.secondary : Color.primary)
                if decisive {
                    Label("The diagnosis became clear here", systemImage: "lightbulb.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if result != nil && index + 1 == result?.cluesSeen {
                    Label("You committed here", systemImage: "hand.point.up.left.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                shown = min(total, shown + 1)
            } label: {
                Label(shown < total ? "Next clue" : "No more clues", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(shown >= total)

            Text("Commit to a diagnosis").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ForEach(options, id: \.self) { option in
                Button {
                    commit(option)
                } label: {
                    Text(option)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
            }
        }
    }

    private func outcome(_ play: CasePlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: play.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(play.correct ? Color.green : Color.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(play.correct ? "Right \u{2014} \(clueCase.diagnosis)" : "It was \(clueCase.diagnosis)")
                        .font(.headline)
                    Text("Score \(String(format: "%.2f", play.score)) of a possible \(String(format: "%.2f", 1 + Double(total - 1) / Double(max(1, total)))) \u{00B7} committed on clue \(play.cluesSeen) of \(play.totalClues)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !play.correct {
                Text("You chose \(play.chosen).").font(.subheadline)
            }
            if play.prematureClosure {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premature closure").font(.subheadline.weight(.semibold))
                        Text("You settled on an answer after \(play.cluesSeen == 1 ? "one clue" : "two clues"), before anything ruled out the alternatives. Take the next clue when the ones you have fit more than one diagnosis.")
                            .font(.footnote)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
            } else if play.correct && play.cluesSeen < clueCase.decisiveClue {
                Text("You committed before the clue that settles it \u{2014} right this time, but check the reasoning holds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !clueCase.teachingPoint.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Teaching point").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(clueCase.teachingPoint)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
            }
            if let tiers = clueCase.differential, !tiers.isEmpty {
                // the shipped example was written for the app, not from a lecture
                HowToReachCard(differential: tiers,
                               lecture: setId == ReasoningExamples.setId ? ReasoningExamples.sourceLabel : nil)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Also considered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(clueCase.differentials.joined(separator: " \u{00B7} "))
                    .font(.subheadline)
            }
            Button {
                shown = 1
                options = Self.shuffled(clueCase)
                result = nil
            } label: {
                Label("Play again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func commit(_ option: String) {
        let play = CasePlay(caseId: clueCase.id, setId: setId, cluesSeen: shown, totalClues: total,
                            chosen: option, correct: clueCase.isDiagnosis(option))
        reasoning.record(play)
        result = play
    }
}
