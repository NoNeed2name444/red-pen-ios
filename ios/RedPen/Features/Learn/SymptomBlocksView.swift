import SwiftUI

/// Symptom-first blocks: "Chest pain block", "Breathless block", "Groin lump
/// block" - questions from every set that share a presenting complaint,
/// mixed so neighbouring questions have different answers.
///
/// After a block, the mix-ups: what was picked against what it was, read
/// from the answers given during it.
struct SymptomBlocksView: View {
    @EnvironmentObject private var store: Store
    @State private var quiz: StudySet?
    /// The block last started, and when, for its mix-ups.
    @State private var last: (block: SymptomBlocks.Block, started: Date)?

    var body: some View {
        let items: [SymptomBlocks.Item] = store.symptomItems()
        let all: [SymptomBlocks.Block] = SymptomBlocks.blocks(items, includeThin: true)
        let ready: [SymptomBlocks.Block] = all.filter(isReady)
        let thin: [SymptomBlocks.Block] = all.filter { !isReady($0) }
        List {
            Section {
                Text("Questions from every set that start from the same complaint, mixed, so you learn to tell the lookalikes apart the way the exam asks.")
                    .font(.subheadline).foregroundStyle(Color.wardInkSecondary)
            }
            if let last { mixUps(last.block, since: last.started) }
            if ready.isEmpty {
                Section {
                    Text("No complaint has enough questions yet: a block needs \(SymptomBlocks.minimumQuestions) questions with at least \(SymptomBlocks.minimumCauses) different answers.")
                        .font(.subheadline).foregroundStyle(Color.wardInkSecondary)
                }
            } else {
                Section("Blocks") {
                    ForEach(ready) { block in blockRow(block) }
                }
            }
            if !thin.isEmpty {
                Section("Not enough questions yet") {
                    ForEach(thin) { block in thinRow(block) }
                }
            }
        }
        .wardForm()
        .navigationTitle("Symptom blocks")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $quiz) { MCQQuizView(set: $0, keepsProgress: false) }
    }

    private func isReady(_ block: SymptomBlocks.Block) -> Bool {
        block.ids.count >= SymptomBlocks.minimumQuestions && block.causes >= SymptomBlocks.minimumCauses
    }

    private func blockRow(_ block: SymptomBlocks.Block) -> some View {
        let p: SymptomBlocks.Presentation = block.presentation
        let shown: Int = min(20, block.ids.count)
        let lookalikes: String = p.lookalikes.prefix(4).joined(separator: ", ")
        return Button {
            last = (block, Date())
            quiz = store.symptomQuiz(block)
        } label: {
            HStack(spacing: 14) {
                WardIconSquare(symbol: p.symbol, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.blockTitle).font(.body.weight(.semibold)).foregroundStyle(Color.wardInk)
                    Text("\(shown) questions \u{00B7} \(block.causes) different answers")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Color.wardInkSecondary)
                    Text(lookalikes + "\u{2026}")
                        .font(.caption).foregroundStyle(Color.wardInkSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill").font(.caption).foregroundStyle(Color.wardPrimaryInk).accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Starts a mixed block of \(p.name.lowercased()) questions")
    }

    private func thinRow(_ block: SymptomBlocks.Block) -> some View {
        let p: SymptomBlocks.Presentation = block.presentation
        let plural: String = block.ids.count == 1 ? "" : "s"
        return HStack(spacing: 14) {
            WardIconSquare(symbol: p.symbol, tone: .grey, size: 32)
            Text(p.name).foregroundStyle(Color.wardInk)
            Spacer(minLength: 0)
            Text("\(block.ids.count) question\(plural)").font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.wardInkSecondary)
        }
        .frame(minHeight: 44)
    }

    /// What was confused for what in the block just sat.
    @ViewBuilder
    private func mixUps(_ block: SymptomBlocks.Block, since: Date) -> some View {
        let wanted: Set<UUID> = Set(block.ids)
        let events: [AnswerEvent] = store.answerLog.filter { $0.date >= since && wanted.contains($0.questionId) }
        if !events.isEmpty {
            let questions = optionsByID(store.picks(ids: block.ids))
            let rows: [SymptomBlocks.Confusion] = SymptomBlocks.confusions(questions: questions, events: events)
            let right: Int = events.filter(\.correct).count
            Section {
                Text("\(right) of \(events.count) right")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                if rows.isEmpty {
                    Text("No mix-ups this time.").font(.subheadline).foregroundStyle(Color.wardInkSecondary)
                }
                ForEach(rows.prefix(6)) { row in confusionRow(row) }
            } header: {
                Text("Mix-ups \u{00B7} \(block.presentation.blockTitle)")
            } footer: {
                Text("What you picked, and what it was. The pairs that come up most are the ones to put side by side.")
            }
        }
    }

    private func optionsByID(_ picks: [QuestionPick]) -> [UUID: (options: [String], correct: Int)] {
        var out: [UUID: (options: [String], correct: Int)] = [:]
        for pick in picks { out[pick.question.id] = (pick.question.options, pick.question.correctIndex) }
        return out
    }

    private func spoken(_ row: SymptomBlocks.Confusion) -> String {
        let times: String = row.count > 1 ? ", \(row.count) times" : ""
        return "Picked \(row.picked), it was \(row.actual)" + times
    }

    private func confusionRow(_ row: SymptomBlocks.Confusion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.picked).foregroundStyle(Color.wardInkSecondary).strikethrough()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(Color.wardInkSecondary).accessibilityHidden(true)
            Text(row.actual).fontWeight(.semibold).foregroundStyle(Color.wardInk)
            Spacer(minLength: 0)
            if row.count > 1 {
                Text("\u{00D7}\(row.count)").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.wardInkSecondary)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }
}
