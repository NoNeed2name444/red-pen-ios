import SwiftUI

// The pages a category's tiles push when there is a choice of set to make
// first: one mode's own sets, the reasoning tools, and Turn into.

// MARK: - One mode's sets

/// Every set of one kind - the page a mode's tile opens, as the mode's own tab
/// did before the dock had categories: the newest one to carry on with at the
/// top, then all of them, then New.
///
/// Links carry their destination rather than a value: this page is pushed by
/// item, and a value link from inside it would go through the library's typed
/// path underneath it.
struct KindShelfView: View {
    let feature: CategoryFeature
    @EnvironmentObject private var store: Store
    @State private var making: StudySetKind?

    private var kind: StudySetKind { feature.shelfKind ?? .mcq }

    var body: some View {
        let sets: [StudySet] = feature.shelfSets(store)
        List {
            if let newest = sets.first {
                Section {
                    link(newest, id: "shelfContinue")
                } header: {
                    CategoryHeading(title: "Carry on")
                }
            }
            Section {
                ForEach(sets) { set in
                    link(set, id: "shelfSet-\(set.kind.rawValue)")
                }
                newButton
            } header: {
                CategoryHeading(title: sets.count == 1 ? "Your set" : "All \(sets.count)")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackdrop(tint: kind.tint))
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $making) { kind in NewSetView(kind: kind) }
    }

    private func link(_ set: StudySet, id: String) -> some View {
        NavigationLink {
            StudySetScreen(set: set)
        } label: {
            ShelfSetRow(set: set)
        }
        .accessibilityIdentifier(id)
        .frostedListRow()
    }

    private var newButton: some View {
        Button { making = kind } label: {
            Label("New \(feature.newNoun)", systemImage: "plus")
                .font(.body.weight(.semibold))
                .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("shelfNew")
        .frostedListRow()
    }
}

extension CategoryFeature {
    /// What "New ..." makes, on a mode's page.
    var newNoun: String {
        switch self {
        case .multipleChoice: return "question set"
        case .flashcards: return "flashcard deck"
        case .textbooks: return "textbook"
        case .pictures: return "picture card deck"
        case .qaCases: return "set of cases"
        case .stations: return "OSCE station"
        case .lectures: return "narrated lecture"
        default: return "set"
        }
    }
}

/// A set as one row: its mode's tile, its name and how much is in it.
struct ShelfSetRow: View {
    let set: StudySet

    var body: some View {
        let count: Int = set.itemCount
        let plural: String = count == 1 ? "" : "s"
        HStack(spacing: 14) {
            ModeTile(kind: set.kind, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.body.weight(.semibold)).lineLimit(2)
                Text("\(count) \(set.itemNoun)\(plural)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 48)
    }
}

// MARK: - Cases: one reasoning tool

/// One reasoning tool - clue-by-clue cases, lookalike duels or disease
/// scripts - and the sets to use it on, so each is its own tile rather than
/// three levels down.
struct ReasoningToolPicker: View {
    let feature: CategoryFeature
    @EnvironmentObject private var store: Store

    private var tool: ReasoningTool {
        switch feature {
        case .duels: return .duels
        case .scripts: return .scripts
        default: return .cases
        }
    }

    var body: some View {
        let sets: [StudySet] = store.library.sorted { $0.updatedAt > $1.updatedAt }
        List {
            Section {
                Text(tool.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if PersonalBuild.isOn {
                Section {
                    link(ReasoningExamples.set)
                } header: {
                    CategoryHeading(title: "Example")
                }
            }
            Section {
                if sets.isEmpty {
                    Text("Make a set from a lecture first, then come back here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(sets) { set in
                    link(set)
                }
            } header: {
                CategoryHeading(title: "Pick a set")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackdrop(tint: StudySetKind.qa.tint))
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ set: StudySet) -> some View {
        NavigationLink {
            destination(set)
        } label: {
            CategoryRowLabel(title: set.name, symbol: tool.symbol,
                             detail: set.subject, tint: StudySetKind.qa.tint)
        }
        .frostedListRow()
    }

    @ViewBuilder
    private func destination(_ set: StudySet) -> some View {
        switch tool {
        case .cases: ClueCasesView(set: set)
        case .duels: DuelsView(set: set)
        case .scripts: ScriptsView(set: set)
        }
    }
}

// MARK: - Turn into

/// The category's sets, to pick one and turn it into another mode - the same
/// picker as holding a set, for anyone who never thought to hold one.
struct TurnIntoListView: View {
    let kinds: [StudySetKind]
    @EnvironmentObject private var store: Store
    @State private var turning: StudySet?

    var body: some View {
        let sets: [StudySet] = store.library
            .filter { kinds.contains($0.kind) && Self.canTurn($0) }
            .sorted { $0.updatedAt > $1.updatedAt }
        List {
            Section {
                if sets.isEmpty {
                    Text("Make a set here first. Then any of them can become questions, flashcards, cases, an OSCE station or a textbook.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(sets) { set in
                    Button { turning = set } label: {
                        ShelfSetRow(set: set)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("turnPick-\(set.kind.rawValue)")
                    .frostedListRow()
                }
            } header: {
                CategoryHeading(title: "Pick a set to turn")
            } footer: {
                Text("The set you pick stays as it is; the new one opens straight away.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackdrop(tint: Color.accentColor))
        .navigationTitle("Turn into\u{2026}")
        .navigationBarTitleDisplayMode(.inline)
        .turnIntoPicker(for: $turning)
    }

    private static func canTurn(_ set: StudySet) -> Bool {
        ModeConversion.targets.contains { ModeConversion.canTurn(set, into: $0) }
    }
}
