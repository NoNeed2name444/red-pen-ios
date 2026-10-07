import SwiftUI

// The pages a category's tiles push when there is a choice of set to make
// first: one mode's own sets, the reasoning tools, and Turn into.

// MARK: - One mode's sets

/// Every set of one kind - the page a mode's tile opens, as the mode's own tab
/// did before the dock had categories: all of them, newest first, and at the
/// bottom, under the thumb, "Continue" on the newest with "New" beside it.
///
/// Links carry their destination rather than a value: this page is pushed by
/// item, and a value link from inside it would go through the library's typed
/// path underneath it.
struct KindShelfView: View {
    let feature: CategoryFeature
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @State private var making: StudySetKind?
    /// For "Open the last set on launch": these links carry their own
    /// destination, so they do not pass through the library's, which is
    /// where it is otherwise remembered.
    @AppStorage("cramdown.lastSetId") private var lastSetId = ""

    private var kind: StudySetKind { feature.shelfKind ?? .mcq }

    var body: some View {
        let sets: [StudySet] = feature.shelfSets(store)
        let heading: String = sets.count == 1 ? "Your set" : "All \(sets.count)"
        List {
            if feature == .pictures {
                Section {
                    PhotoCardsTile(tint: kind.tint)
                }
            }
            Section {
                if sets.isEmpty {
                    WardEmptyState(symbol: kind.symbol, title: "None yet",
                                   message: "Tap New to make one.")
                        .listRowBackground(Color.clear)
                }
                ForEach(sets) { set in
                    link(set, id: "shelfSet-\(set.kind.rawValue)")
                }
            } header: {
                CategoryHeading(title: heading)
            }
        }
        .scrollContentBackground(.hidden)
        // one comfortable column on a wide iPad
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .wardForm()
        .navigationTitle(feature.title)
        .navigationBarTitleDisplayMode(.inline)
        .studyBar { shelfBar(newest: sets.first) }
        // the bar's buttons in this mode's colour
        .environment(\.modeTint, kind.tint)
        .sheet(item: $making) { kind in NewSetView(kind: kind) }
    }

    /// New at the leading end; the hero - carry on with the newest set - at
    /// the trailing end, under the right thumb.
    private func shelfBar(newest: StudySet?) -> some View {
        HStack(spacing: 12) {
            newButton
            if let newest { continueLink(newest) }
        }
    }

    private func continueLink(_ set: StudySet) -> some View {
        let title: String = "Continue: \(set.name)"
        return NavigationLink {
            opened(set)
        } label: {
            Label(title, systemImage: "play.fill")
                .lineLimit(1)
        }
        .buttonStyle(.bigPrimary)
        .accessibilityIdentifier("shelfContinue")
    }

    private func link(_ set: StudySet, id: String) -> some View {
        NavigationLink {
            opened(set)
        } label: {
            SetRow(set: set, due: due(in: set), progress: nil)
        }
        .accessibilityIdentifier(id)
        .frostedListRow()
    }

    /// Cards due now, for a deck; nothing for any other mode.
    private func due(in set: StudySet) -> Int {
        set.kind == .anki ? reviews.dueCount(for: set.cards) : 0
    }

    /// A set's screen, remembered as the last set opened.
    private func opened(_ set: StudySet) -> some View {
        let id: String = set.id.uuidString
        return StudySetScreen(set: set)
            .onAppear { lastSetId = id }
    }

    private var newButton: some View {
        let spoken: String = "New \(feature.newNoun)"
        return Button { making = kind } label: {
            Label("New", systemImage: "plus")
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("shelfNew")
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
        case .stations: return "OSCE station"
        case .lectures: return "narrated lecture"
        case .patients: return "Cases set"
        default: return "set"
        }
    }
}

/// Picture cards: "From a photo or scan", a soft tile raised above the decks
/// and pressed in under the finger. Its page is pushed with its destination,
/// as every link on this page is.
struct PhotoCardsTile: View {
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        NavigationLink {
            PictureFromPhotoView()
        } label: {
            HStack(spacing: WardSpace.m) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .wardRaised(in: RoundedRectangle(cornerRadius: WardRadius.icon, style: .continuous), lift: .low)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("From a photo or scan").font(.headline).foregroundStyle(Color.wardInk)
                    Text("Labels read and covered for you, then adjust")
                        .font(.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.wardInkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(shape)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(PopTileStyle(cornerRadius: WardRadius.card))
        .accessibilityIdentifier("pictureFromPhoto")
        .wardButtonRow()
    }
}

// MARK: - Cards: one reasoning tool

/// One reasoning tool - lookalike duels or disease scripts - and the sets to
/// use it on, so each is its own tile rather than three levels down.
struct ReasoningToolPicker: View {
    let feature: CategoryFeature
    @EnvironmentObject private var store: Store

    private var tool: ReasoningTool {
        feature == .scripts ? .scripts : .duels
    }

    var body: some View {
        let sets: [StudySet] = store.library.sorted { $0.updatedAt > $1.updatedAt }
        List {
            Section {
                Text(tool.blurb)
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInkSecondary)
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
                    WardEmptyState(symbol: tool.symbol, title: "No sets yet",
                                   message: "Make a set from a lecture first, then come back here.")
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
        // one comfortable column on a wide iPad
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .wardForm()
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ set: StudySet) -> some View {
        NavigationLink {
            destination(set)
        } label: {
            CategoryRowLabel(title: set.name, symbol: tool.symbol,
                             detail: set.subject, tint: StudySetKind.anki.tint)
        }
        .frostedListRow()
    }

    @ViewBuilder
    private func destination(_ set: StudySet) -> some View {
        switch tool {
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
                    WardEmptyState(symbol: "arrow.triangle.2.circlepath", title: "Nothing to turn yet",
                                   message: "Make a set here first. Then any of them can become questions, flashcards, an OSCE station or a textbook.")
                        .listRowBackground(Color.clear)
                }
                ForEach(sets) { set in
                    Button { turning = set } label: {
                        SetRow(set: set, due: 0, progress: nil)
                    }
                    .buttonStyle(.plain)
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
        // one comfortable column on a wide iPad
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .wardForm()
        .navigationTitle("Turn into\u{2026}")
        .navigationBarTitleDisplayMode(.inline)
        .turnIntoPicker(for: $turning)
    }

    private static func canTurn(_ set: StudySet) -> Bool {
        ModeConversion.targets.contains { ModeConversion.canTurn(set, into: $0) }
    }
}
