import SwiftUI

/// A set's lookalike duels: each pair of conditions that get confused, with
/// how the last duel went, and the slab for writing more at the bottom.
struct DuelsView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var confirmClear = false

    private var isExample: Bool { self.set.id == ReasoningExamples.setId }

    var body: some View {
        let duels = reasoning.pack(for: set.id).duels
        List {
            Section {
                Text("Features appear one at a time. Say whose each one is \u{2014} the first condition, the second, or both.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if duels.isEmpty {
                Section {
                    Text("No duels yet. Write some from this set below.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Duels") {
                    ForEach(duels) { pair in
                        NavigationLink {
                            DuelView(pair: pair, setId: set.id)
                        } label: {
                            row(pair)
                        }
                        .hoverEffect(.highlight)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Lookalike duels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !duels.isEmpty && !isExample {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete duels", systemImage: "trash", role: .destructive) { confirmClear = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete these duels and their scores?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete duels", role: .destructive) { reasoning.clear(.duels, for: set.id) }
        }
        .reasoningWriteSlab(tool: .duels, set: set)
    }

    private func row(_ pair: LookalikePair) -> some View {
        let title: String = "\(pair.a) vs \(pair.b)"
        let fresh: String = "\(pair.features.count) features \u{00B7} not played"
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.body.weight(.medium))
            if let last = reasoning.lastDuel(of: pair.id) {
                Text("Last time \(last.right) of \(last.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(fresh)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One duel, played: features one at a time, each swiped or tapped to the
/// condition it belongs to, then the score and the reasons.
///
/// The feature card is the screen's hero: it stands highest out of the
/// glass, and is what the thumb pulls. The three answers sit in the slab at
/// the bottom in the same order as the swipes: first condition, both, second.
struct DuelView: View {
    let pair: LookalikePair
    let setId: UUID
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var order: [LookalikeFeature]
    @State private var answers: [UUID: LookalikeSide] = [:]
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var recorded = false
    @Environment(\.windowSpan) private var span

    init(pair: LookalikePair, setId: UUID) {
        self.pair = pair
        self.setId = setId
        _order = State(initialValue: pair.features.shuffled())
    }

    private var finished: Bool { index >= order.count }
    private var right: Int { order.filter { answers[$0.id] == $0.side }.count }

    var body: some View {
        Group {
            if finished {
                summaryScreen
            } else {
                playScreen
            }
        }
        .background(LibraryBackdrop())
        .navigationTitle("Duel")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: index)
    }

    private func name(_ side: LookalikeSide) -> String {
        switch side {
        case .a: return pair.a
        case .b: return pair.b
        case .both: return "Both"
        }
    }

    // MARK: playing

    private var header: some View {
        let status: String = "Feature \(min(index + 1, order.count)) of \(order.count)"
        let detail: String = "\(right) right"
        let fraction: Double = Double(index) / Double(max(1, order.count))
        return StudyProgressHeader(status, detail: detail, fraction: fraction)
    }

    private var playScreen: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 18) {
                    Text("\(pair.a) vs \(pair.b)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if index > 0 { feedback(order[index - 1]) }
                    if order.indices.contains(index) {
                        card(order[index])
                    }
                    Text("Swipe left for \(pair.a), right for \(pair.b), up for both.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .studyBar { choices }
        }
    }

    private func card(_ feature: LookalikeFeature) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let turn: Double = Double(drag.width) / 20
        return Text(feature.text)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 170)
            .background(shape.fill(Color(.secondarySystemBackground)))
            .overlay(alignment: .top) {
                if let leaning = leaning {
                    Text(name(leaning))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .padding(8)
                }
            }
            // the hero plane: the card stands out of the glass. Lifted as a
            // whole, so its sheen and its side travel with it when it is
            // pulled; the pull itself is only ever the finger's.
            .popOut(.hero, in: shape)
            .offset(drag)
            .rotationEffect(.degrees(turn))
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let side = sideFor(value.translation)
                        withAnimation(.snappy) { drag = .zero }
                        if let side { answer(side) }
                    }
            )
            .id(feature.id)
            .transition(.asymmetric(insertion: .growFade(0.9),
                                    removal: .opacity))
            .accessibilityHint("Swipe left, right or up, or use the buttons below.")
    }

    /// Which way the card is being pulled, once it is far enough to count.
    private var leaning: LookalikeSide? { sideFor(drag) }

    private func sideFor(_ t: CGSize) -> LookalikeSide? {
        LookalikeSide.swiped(width: Double(t.width), height: Double(t.height))
    }

    /// A · Both · B, left to right as the swipes go, with the arrow keys
    /// doing the same.
    private var choices: some View {
        HStack(spacing: 10) {
            ForEach(LookalikeSide.buttonOrder) { side in
                choice(side)
            }
        }
        // the first condition stays on the left, as the swipe does, in a
        // right-to-left language too
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: 640)
    }

    private static func arrow(_ side: LookalikeSide) -> KeyEquivalent {
        switch side {
        case .a: return .leftArrow
        case .both: return .upArrow
        case .b: return .rightArrow
        }
    }

    private func choice(_ side: LookalikeSide) -> some View {
        Button {
            answer(side)
        } label: {
            Text(name(side))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bigSecondary)
        .keyboardShortcut(Self.arrow(side), modifiers: [])
    }

    private func feedback(_ feature: LookalikeFeature) -> some View {
        let ok: Bool = answers[feature.id] == feature.side
        let symbol: String = ok ? "checkmark.circle.fill" : "xmark.circle.fill"
        let colour: Color = ok ? Color.green : Color.red
        let line: String = "\(feature.text) \u{2192} \(name(feature.side))"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(colour)
                .accessibilityLabel(ok ? "Right" : "Wrong")
            VStack(alignment: .leading, spacing: 2) {
                Text(line).font(.footnote.weight(.semibold))
                if !feature.why.isEmpty {
                    Text(feature.why).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(colour.opacity(0.1)))
    }

    private func answer(_ side: LookalikeSide) {
        guard !finished else { return }
        answers[order[index].id] = side
        index += 1
        if finished && !recorded {
            recorded = true
            reasoning.record(DuelPlay(pairId: pair.id, setId: setId, right: right, total: order.count))
        }
    }

    private func again() {
        order = pair.features.shuffled()
        answers = [:]
        recorded = false
        index = 0
    }

    // MARK: the result

    private var summaryScreen: some View {
        ScrollView {
            summary
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .studyBar { summaryButtons }
    }

    /// The table beside, Duel again as the one main button.
    private var summaryButtons: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ComparisonTableView(pair: pair)
            } label: {
                Label("Comparison table", systemImage: "tablecells")
            }
            .buttonStyle(.bigCompanion)
            if span == .broad { Spacer(minLength: 16) }
            Button(action: again) {
                Label("Duel again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var summary: some View {
        let score: String = "\(right) of \(order.count)"
        return VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 4) {
                Text(score)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text(verdict).font(.subheadline).foregroundStyle(.secondary)
                Text("\(pair.a) vs \(pair.b)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            if !pair.bottomLine.isEmpty {
                Text(pair.bottomLine)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
            }

            Text("Feature by feature").font(.headline)
            ForEach(order) { feature in
                DuelFeatureResult(feature: feature, given: answers[feature.id], name: name)
            }
        }
    }

    private var verdict: String {
        guard !order.isEmpty else { return "" }
        let share = Double(right) / Double(order.count)
        if share >= 0.9 { return "You can tell these apart." }
        if share >= 0.7 { return "Nearly there \u{2014} look again at the ones you missed." }
        return "These still blur together. The comparison table lines them up."
    }
}

/// One feature in the result: whose it was, what was said, and why.
private struct DuelFeatureResult: View {
    let feature: LookalikeFeature
    let given: LookalikeSide?
    let name: (LookalikeSide) -> String

    private var ok: Bool { given == feature.side }

    private var answerLine: String {
        let right: String = name(feature.side)
        if ok { return right }
        let said: String = given.map { name($0) } ?? "nothing"
        return "\(right) \u{2014} you said \(said)"
    }

    var body: some View {
        let symbol: String = ok ? "checkmark.circle.fill" : "xmark.circle.fill"
        let colour: Color = ok ? Color.green : Color.red
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(colour)
                .accessibilityLabel(ok ? "Right" : "Wrong")
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.text).font(.subheadline.weight(.medium))
                Text(answerLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                if !feature.why.isEmpty {
                    Text(feature.why).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The two conditions side by side: each one's own features, then the ones
/// they share. Shareable as plain text.
struct ComparisonTableView: View {
    let pair: LookalikePair

    var body: some View {
        let aFeatures = pair.features.filter { $0.side == .a }
        let bFeatures = pair.features.filter { $0.side == .b }
        let shared = pair.features.filter { $0.side == .both }
        let rows: Int = max(aFeatures.count, bFeatures.count)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(pair.a).font(.headline)
                        Text(pair.b).font(.headline)
                    }
                    Divider().gridCellColumns(2)
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            cell(row < aFeatures.count ? aFeatures[row] : nil)
                            cell(row < bFeatures.count ? bFeatures[row] : nil)
                        }
                    }
                    if !shared.isEmpty {
                        Divider().gridCellColumns(2)
                        GridRow {
                            Text("Both \u{2014} these do not tell them apart")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .gridCellColumns(2)
                        }
                        ForEach(shared) { feature in
                            GridRow {
                                cell(feature).gridCellColumns(2)
                            }
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: shape)
                if !pair.bottomLine.isEmpty {
                    Text(pair.bottomLine)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryBackdrop())
        .navigationTitle("Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: pair.comparisonText, subject: Text("\(pair.a) vs \(pair.b)")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ feature: LookalikeFeature?) -> some View {
        if let feature {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.text).font(.subheadline)
                if !feature.why.isEmpty {
                    Text(feature.why).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
