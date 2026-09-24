import SwiftUI

/// A set's lookalike duels: each pair of conditions that get confused, with
/// how the last duel went.
struct DuelsView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var confirmClear = false

    var body: some View {
        let duels = reasoning.pack(for: set.id).duels
        List {
            Section {
                ReasoningWriteBar(tool: .duels, set: set)
            } footer: {
                Text("Features appear one at a time. Say whose each one is \u{2014} the first condition, the second, or both.")
            }
            if !duels.isEmpty {
                Section("Duels") {
                    ForEach(duels) { pair in
                        NavigationLink {
                            DuelView(pair: pair, setId: set.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(pair.a) vs \(pair.b)").font(.body.weight(.medium))
                                if let last = reasoning.lastDuel(of: pair.id) {
                                    Text("Last time \(last.right) of \(last.total)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(pair.features.count) features \u{00B7} not played")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Lookalike duels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !duels.isEmpty && set.id != ReasoningExamples.setId {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", systemImage: "trash") { confirmClear = true }
                }
            }
        }
        .confirmationDialog("Delete these duels and their scores?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete duels", role: .destructive) { reasoning.clear(.duels, for: set.id) }
        }
        .generationHUD()
    }
}

/// One duel, played: features one at a time, each swiped or tapped to the
/// condition it belongs to, then the score and the reasons.
struct DuelView: View {
    let pair: LookalikePair
    let setId: UUID
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var order: [LookalikeFeature]
    @State private var answers: [UUID: LookalikeSide] = [:]
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var recorded = false

    init(pair: LookalikePair, setId: UUID) {
        self.pair = pair
        self.setId = setId
        _order = State(initialValue: pair.features.shuffled())
    }

    private var finished: Bool { index >= order.count }
    private var right: Int { order.filter { answers[$0.id] == $0.side }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if finished {
                    summary
                } else {
                    play
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("\(pair.a) vs \(pair.b)")
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

    private var play: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Feature \(index + 1) of \(order.count)").font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                Text("\(right) right").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if index > 0 { feedback(order[index - 1]) }
            card(order[index])
            // left to right as the swipes go: first condition, both, second
            HStack(spacing: 10) {
                ForEach(LookalikeSide.buttonOrder) { side in
                    choice(side)
                }
            }
            // the first condition stays on the left, as the swipe does, in
            // a right-to-left language too
            .environment(\.layoutDirection, .leftToRight)
            Text("Swipe left for \(pair.a), right for \(pair.b), up for both.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func card(_ feature: LookalikeFeature) -> some View {
        Text(feature.text)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 170)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(alignment: .top) {
                if let leaning = leaning {
                    Text(name(leaning))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .padding(8)
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width) / 20))
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
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity))
            .accessibilityHint("Swipe left, right or up, or use the buttons below.")
    }

    /// Which way the card is being pulled, once it is far enough to count.
    private var leaning: LookalikeSide? { sideFor(drag) }

    private func sideFor(_ t: CGSize) -> LookalikeSide? {
        LookalikeSide.swiped(width: Double(t.width), height: Double(t.height))
    }

    private func choice(_ side: LookalikeSide) -> some View {
        Button {
            answer(side)
        } label: {
            Text(name(side))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func feedback(_ feature: LookalikeFeature) -> some View {
        let ok = answers[feature.id] == feature.side
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(feature.text) \u{2192} \(name(feature.side))").font(.footnote.weight(.semibold))
                if !feature.why.isEmpty {
                    Text(feature.why).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((ok ? Color.green : Color.red).opacity(0.1)))
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

    // MARK: the result

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 4) {
                Text("\(right) of \(order.count)")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text(verdict).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            if !pair.bottomLine.isEmpty {
                Text(pair.bottomLine)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
            }

            NavigationLink {
                ComparisonTableView(pair: pair)
            } label: {
                Label("Comparison table", systemImage: "tablecells").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Feature by feature").font(.headline)
            ForEach(order) { feature in
                let given = answers[feature.id]
                let ok = given == feature.side
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(ok ? Color.green : Color.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.text).font(.subheadline.weight(.medium))
                        Text(ok ? name(feature.side) : "\(name(feature.side)) \u{2014} you said \(given.map { name($0) } ?? "nothing")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        if !feature.why.isEmpty {
                            Text(feature.why).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            Button {
                order = pair.features.shuffled()
                answers = [:]
                recorded = false
                index = 0
            } label: {
                Label("Duel again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var verdict: String {
        guard !order.isEmpty else { return "" }
        let share = Double(right) / Double(order.count)
        if share >= 0.9 { return "You can tell these apart." }
        if share >= 0.7 { return "Nearly there \u{2014} look again at the ones you missed." }
        return "These still blur together. The table below lines them up."
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(pair.a).font(.headline)
                        Text(pair.b).font(.headline)
                    }
                    Divider().gridCellColumns(2)
                    ForEach(0..<max(aFeatures.count, bFeatures.count), id: \.self) { row in
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
        .navigationTitle("Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
