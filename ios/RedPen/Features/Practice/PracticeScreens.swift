import SwiftUI

/// The study screen for a set, whichever mode it is in. The Library and the
/// Practice tab both open sets through this, so a set looks the same from
/// either.
struct StudySetScreen: View {
    let set: StudySet

    var body: some View {
        switch set.kind {
        case .mcq: MCQQuizView(set: set)
        case .anki: AnkiReviewView(set: set)
        case .book: BookReaderView(set: set)
        case .qa: QACardsView(set: set)
        case .osce: OsceReviewView(set: set)
        case .narrate: NarrateReviewView(set: set)
        }
    }
}

// MARK: - Questions & cards

/// Every set, grouped by what kind it is, to pick one and study it.
///
/// A plainer list than the Library - no folders, no select, no swipes - for
/// somebody who has come to practise rather than to organise.
struct PracticeSetsView: View {
    @EnvironmentObject private var store: Store

    private var kinds: [StudySetKind] {
        StudySetKind.allCases.filter { kind in store.library.contains { $0.kind == kind } }
    }

    var body: some View {
        List {
            if store.library.isEmpty {
                ContentUnavailableView("No sets yet", systemImage: "rectangle.stack",
                                       description: Text("Make a set in the Library, then practise it here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(kinds) { kind in
                section(kind)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Questions & cards")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ kind: StudySetKind) -> some View {
        let sets: [StudySet] = store.library.filter { $0.kind == kind }
        return Section {
            ForEach(sets) { set in
                NavigationLink(value: set) { PracticeSetRow(set: set) }
                    .listRowBackground(TintedRowBackground(tint: kind.tint))
            }
        } header: {
            Text(kind.label)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }
}

/// One set in the Practice list: its mode's tile, its name and its size.
struct PracticeSetRow: View {
    let set: StudySet

    var body: some View {
        let plural: String = set.itemCount == 1 ? "" : "s"
        let size: String = "\(set.itemCount) \(set.itemNoun)\(plural)"
        HStack(spacing: 14) {
            ModeTile(kind: set.kind, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.body.weight(.semibold)).lineLimit(2)
                Text(size).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 52)
    }
}

// MARK: - Voice

/// The spoken modes in one place: commute mode, explain it back, and an OSCE
/// patient who talks back for each station in the library.
struct VoicePracticeView: View {
    @EnvironmentObject private var store: Store

    private var stations: [OsceChecklist] {
        store.library.filter { $0.kind == .osce }.flatMap(\.osceChecklists)
    }

    var body: some View {
        List {
            Section {
                VoiceRow(title: "Commute mode", symbol: "car.fill",
                         detail: "Questions read aloud. Answer out loud.") { CommuteModeView() }
                VoiceRow(title: "Explain it back", symbol: "text.bubble.fill",
                         detail: "Explain a topic aloud and get it marked.") { ExplainBackView() }
            } header: {
                Text("Listen and talk")
            }
            stationSection
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stationSection: some View {
        Section {
            if stations.isEmpty {
                Text("Make an OSCE set in the Library and each station shows up here, with a patient to talk to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(stations.enumerated()), id: \.offset) { _, station in
                VoiceRow(title: station.title, symbol: "person.wave.2.fill",
                         detail: "Talk to the patient, then get marked.") {
                    SpokenStationView(station: station)
                }
            }
            if PersonalBuild.isOn {
                VoiceRow(title: "Example: breaking bad news", symbol: "doc.text.magnifyingglass",
                         detail: "A marked attempt, to see how it works.") {
                    StationReportView(attempt: VoiceExamples.breakingBadNews)
                }
            }
        } header: {
            Text("OSCE patient")
        }
    }
}

/// A row in the Voice list that opens its screen.
struct VoiceRow<Destination: View>: View {
    let title: String
    let symbol: String
    let detail: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(StudySetKind.narrate.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 48)
        }
        .listRowBackground(Rectangle().fill(.regularMaterial))
    }
}

// MARK: - Draw from memory

/// Every picture in the library, to draw from memory and then compare.
///
/// The drawing screen is presented full screen rather than pushed, for the
/// reason DrawRecallExampleRow gives: it has its own bar and a tool picker,
/// and pushed inside another stack that is what crashed.
struct DrawPracticeView: View {
    @EnvironmentObject private var store: Store
    @State private var figure: RecallFigure?

    private var withPictures: [StudySet] {
        store.library.filter { !$0.images.isEmpty }
    }

    var body: some View {
        List {
            if PersonalBuild.isOn {
                Section {
                    DrawRecallExampleRow()
                } header: {
                    Text("Example")
                }
            }
            if withPictures.isEmpty {
                Section {
                    Text("Pictures in your sets show up here. Pick one, draw it from memory, then compare.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(withPictures) { set in
                pictures(in: set)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Draw from memory")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $figure) { DrawRecallView(figure: $0) }
    }

    private func pictures(in set: StudySet) -> some View {
        let count: Int = set.images.count
        return Section {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    open(set, index)
                } label: {
                    Label("Picture \(index + 1)", systemImage: "photo")
                        .frame(minHeight: 44, alignment: .leading)
                }
            }
        } header: {
            Text(set.name).textCase(nil)
        }
    }

    /// Decoded only when tapped: a list of every picture in the library
    /// should not decode every picture in the library.
    private func open(_ set: StudySet, _ index: Int) {
        let caption: String = "\(set.name) \u{2014} picture \(index + 1)"
        figure = RecallFigure(set: set, index: index, caption: caption, library: store.library)
    }
}
