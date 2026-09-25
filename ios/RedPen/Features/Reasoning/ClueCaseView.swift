import SwiftUI

/// A set's clue-by-clue cases: each with how it went last time, and the
/// slab for writing more at the bottom, under the thumb.
struct ClueCasesView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var confirmClear = false

    private var isExample: Bool { self.set.id == ReasoningExamples.setId }

    var body: some View {
        let cases = reasoning.pack(for: set.id).cases
        List {
            Section {
                Text("Clues come from the vaguest to the most specific. Commit whenever you are sure: a right answer with clues still hidden scores up to 2; a wrong one scores 0.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if cases.isEmpty {
                Section {
                    Text("No cases yet. Write some from this set below.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Cases") {
                    ForEach(Array(cases.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            ClueCaseView(clueCase: item, setId: set.id)
                        } label: {
                            row(item, number: index + 1)
                        }
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Clue-by-clue cases")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cases.isEmpty && !isExample {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete cases", systemImage: "trash", role: .destructive) { confirmClear = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete these cases and their scores?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete cases", role: .destructive) { reasoning.clear(.cases, for: set.id) }
        }
        .reasoningWriteSlab(tool: .cases, set: set)
    }

    private func row(_ item: ClueCase, number: Int) -> some View {
        let last = reasoning.lastPlay(of: item.id)
        let opening: String = item.clues.first ?? "Case \(number)"
        let notPlayed: String = "\(item.clues.count) clues \u{00B7} not played"
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                // the first clue only: the diagnosis stays hidden until played
                Text(opening).lineLimit(2)
                if let last {
                    Text(Self.lastLine(last))
                        .font(.caption)
                        .foregroundStyle(last.correct ? Color.green : Color.orange)
                } else {
                    Text(notPlayed).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func lastLine(_ last: CasePlay) -> String {
        if last.correct {
            let score: String = String(format: "%.2f", last.score)
            return "Right at clue \(last.cluesSeen) of \(last.totalClues) \u{00B7} \(score)"
        }
        return last.prematureClosure ? "Premature closure last time" : "Missed last time"
    }
}

/// One case, played: clues revealed one at a time, and at any point a commit
/// to one of four diagnoses. Where it stands is at the top; Next clue and
/// the four diagnoses are in the slab at the bottom, under the thumb.
struct ClueCaseView: View {
    let clueCase: ClueCase
    let setId: UUID
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var shown = 1
    @State private var options: [String]
    @State private var result: CasePlay?
    /// The attending's hint for this play: nil until asked, empty while it
    /// is being written.
    @State private var hint: String?

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
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    clueList
                    if let hint, result == nil {
                        AttendingHintCard(text: hint.isEmpty ? nil : hint)
                    }
                    if let result {
                        outcome(result)
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .studyBar { bar }
        }
        .background(LibraryBackdrop())
        .navigationTitle("Case")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: shown)
        .animation(.snappy, value: result?.id)
    }

    // MARK: where it stands

    /// What a right answer is worth now: 2 on the first clue, falling to 1
    /// on the last.
    private var worth: Double {
        let remaining: Double = Double(total - shown)
        let whole: Double = Double(max(1, total))
        return 1 + remaining / whole
    }

    private var header: some View {
        let status: String = result == nil ? "Clue \(shown) of \(total)" : "All \(total) clues"
        let worthText: String = String(format: "%.2f", worth)
        let detail: String? = result == nil ? "Worth \(worthText) if right" : nil
        let seen: Int = result == nil ? shown : total
        let fraction: Double = Double(seen) / Double(max(1, total))
        return StudyProgressHeader(status, detail: detail, fraction: fraction) {
            // the header's one small control: a nudge, never the diagnosis
            if result == nil {
                HintChip(used: hint != nil, action: askHint)
            }
        }
    }

    /// The next step in the reasoning from the clues shown so far, without
    /// naming the diagnosis. Kept per case once written.
    private func askHint() {
        guard hint == nil else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy) { hint = "" }
        let seen: [String] = Array(clueCase.clues.prefix(shown))
        let stem: String = seen.joined(separator: " ")
        let item: ClueCase = clueCase
        let choices: [String] = options
        Task {
            let text: String = await HintWriter.hint(id: item.id, stem: stem, options: choices,
                                                     answer: item.diagnosis, differential: item.differential)
            withAnimation(.snappy) { hint = text }
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
        let number: Int = index + 1
        let decisive: Bool = result != nil && number == clueCase.decisiveClue
        let seenCount: Int = result?.cluesSeen ?? total
        let unseen: Bool = result != nil && index >= seenCount
        let committedHere: Bool = result != nil && number == result?.cluesSeen
        let dot: Color = decisive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 22, height: 22)
                .background(Circle().fill(dot))
            VStack(alignment: .leading, spacing: 4) {
                Text(clue)
                    .foregroundStyle(unseen ? Color.secondary : Color.primary)
                if decisive {
                    Label("The diagnosis became clear here", systemImage: "lightbulb.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                if committedHere {
                    Label("You committed here", systemImage: "hand.point.up.left.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: shape)
    }

    // MARK: the bottom slab

    @ViewBuilder
    private var bar: some View {
        if result == nil {
            ClueCaseControls(options: options, canReveal: shown < total,
                             onNext: { shown = min(total, shown + 1) },
                             onCommit: commit)
        } else {
            Button {
                shown = 1
                options = Self.shuffled(clueCase)
                result = nil
                hint = nil
            } label: {
                Label("Play again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: the result

    private func outcome(_ play: CasePlay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ClueCaseVerdict(play: play, diagnosis: clueCase.diagnosis, total: total)
            if !play.correct {
                Text("You chose \(play.chosen).").font(.subheadline)
            }
            if play.prematureClosure {
                prematureNote(play)
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
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.opacity(0.1)))
            }
            if let tiers = clueCase.differential, !tiers.isEmpty {
                // the shipped example was written for the app, not from a lecture
                let lecture: String? = setId == ReasoningExamples.setId ? ReasoningExamples.sourceLabel : nil
                HowToReachCard(differential: tiers, lecture: lecture)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Also considered").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(clueCase.differentials.joined(separator: " \u{00B7} "))
                    .font(.subheadline)
            }
        }
    }

    private func prematureNote(_ play: CasePlay) -> some View {
        let when: String = play.cluesSeen == 1 ? "one clue" : "two clues"
        let advice: String = "You settled on an answer after \(when), before anything ruled out the alternatives. Take the next clue when the ones you have fit more than one diagnosis."
        return Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Premature closure").font(.subheadline.weight(.semibold))
                Text(advice)
                    .font(.footnote)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    private func commit(_ option: String) {
        let play = CasePlay(caseId: clueCase.id, setId: setId, cluesSeen: shown, totalClues: total,
                            chosen: option, correct: clueCase.isDiagnosis(option))
        reasoning.record(play)
        result = play
    }
}

/// Right or wrong, and the score against the best there was.
private struct ClueCaseVerdict: View {
    let play: CasePlay
    let diagnosis: String
    let total: Int

    private var headline: String {
        play.correct ? "Right \u{2014} \(diagnosis)" : "It was \(diagnosis)"
    }

    /// The score, against what committing on the first clue would have made.
    private var scoreLine: String {
        let whole: Double = Double(max(1, total))
        let best: Double = 1 + Double(total - 1) / whole
        let score: String = String(format: "%.2f", play.score)
        let possible: String = String(format: "%.2f", best)
        let when: String = "committed on clue \(play.cluesSeen) of \(play.totalClues)"
        return "Score \(score) of a possible \(possible) \u{00B7} \(when)"
    }

    var body: some View {
        let symbol: String = play.correct ? "checkmark.circle.fill" : "xmark.circle.fill"
        let colour: Color = play.correct ? Color.green : Color.red
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(colour)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                Text(scoreLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The slab while a case is being played: Next clue, then a line saying that
/// a diagnosis commits, then the four diagnoses two by two. Return takes the
/// next clue; 1 to 4 commit.
private struct ClueCaseControls: View {
    let options: [String]
    let canReveal: Bool
    let onNext: () -> Void
    let onCommit: (String) -> Void
    @Environment(\.windowSpan) private var span

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// What the four buttons do, said before they are pressed - with the
    /// number keys on a wide iPad, where a keyboard is likely.
    private var commitCaption: String {
        let keys: Int = min(options.count, 9)
        guard span == .broad, keys > 1 else { return "Commit to a diagnosis" }
        return "Commit to a diagnosis \u{00B7} keys 1\u{2013}\(keys)"
    }

    var body: some View {
        let nextTitle: String = canReveal ? "Next clue" : "No more clues"
        VStack(spacing: 12) {
            Button(action: onNext) {
                Label(nextTitle, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bigSecondary)
            .keyboardShortcut(.defaultAction)
            .disabled(!canReveal)
            // tapping one ends the case, so say so before the buttons
            Text(commitCaption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    optionButton(option, number: index + 1)
                }
            }
        }
        .frame(maxWidth: 640)
    }

    /// 1 to 9 for the options; nothing past nine.
    private static func shortcut(_ number: Int) -> KeyboardShortcut? {
        guard number >= 1 && number <= 9, let digit = String(number).first else { return nil }
        return KeyboardShortcut(KeyEquivalent(digit), modifiers: [])
    }

    private func optionButton(_ option: String, number: Int) -> some View {
        let key: KeyboardShortcut? = Self.shortcut(number)
        return Button {
            onCommit(option)
        } label: {
            Text(option)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bigSecondary)
        .keyboardShortcut(key)
        .accessibilityHint("Commits to this diagnosis")
    }
}
