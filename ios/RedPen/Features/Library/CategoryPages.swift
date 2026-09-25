import SwiftUI

/// The study screen for a set, whichever mode it is in.
struct StudySetScreen: View {
    let set: StudySet

    var body: some View {
        // opening a set is a session starting: the lift-off streak, once
        // (WarpEffect)
        screen
            .liftOffOnAppear()
    }

    @ViewBuilder
    private var screen: some View {
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

// MARK: - OSCE: the talking patient

/// A patient who talks back, for every OSCE station in the library, and a
/// marked example to see how it goes.
struct SpokenPatientsView: View {
    @EnvironmentObject private var store: Store

    private var stations: [OsceChecklist] {
        store.library.filter { $0.kind == .osce }.flatMap(\.osceChecklists)
    }

    var body: some View {
        List {
            Section {
                if stations.isEmpty {
                    Text("Make an OSCE set and each station shows up here, with a patient to talk to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(stations.enumerated()), id: \.offset) { _, station in
                    NavigationLink {
                        SpokenStationView(station: station)
                    } label: {
                        CategoryRowLabel(title: station.title, symbol: "person.wave.2.fill",
                                         detail: "Talk to the patient, then get marked.",
                                         tint: StudySetKind.osce.tint)
                    }
                    .frostedListRow()
                }
            } header: {
                CategoryHeading(title: "Your stations")
            }
            if PersonalBuild.isOn {
                Section {
                    NavigationLink {
                        StationReportView(attempt: VoiceExamples.breakingBadNews)
                    } label: {
                        CategoryRowLabel(title: "Example: breaking bad news", symbol: "doc.text.magnifyingglass",
                                         detail: "A marked attempt, to see how it works.",
                                         tint: StudySetKind.osce.tint)
                    }
                    .frostedListRow()
                } header: {
                    CategoryHeading(title: "Example")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .skyScroll()
        // one comfortable column on a wide iPad
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(AppBackdrop(tint: StudySetKind.osce.tint))
        .navigationTitle("Talking patient")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A row that opens a page: a coloured symbol, a name, and one line.
struct CategoryRowLabel: View {
    let title: String
    let symbol: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 48)
    }
}

extension View {
    /// A list row frosted, so the backdrop shows through while the row stays
    /// easy to read - the library's own row background.
    func frostedListRow() -> some View {
        listRowBackground(Rectangle().fill(.regularMaterial))
    }
}

// MARK: - Cards: draw from memory

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
                        .frostedListRow()
                } header: {
                    CategoryHeading(title: "Example")
                }
            }
            if withPictures.isEmpty {
                Section {
                    Text("Pictures in your sets show up here. Pick one, draw it from memory, then compare.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(withPictures) { set in
                pictures(in: set)
            }
        }
        .scrollContentBackground(.hidden)
        .skyScroll()
        // one comfortable column on a wide iPad
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(AppBackdrop(tint: StudySetKind.anki.tint))
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
                .frostedListRow()
            }
        } header: {
            CategoryHeading(title: set.name)
        }
    }

    /// Decoded only when tapped: a list of every picture in the library
    /// should not decode every picture in the library.
    private func open(_ set: StudySet, _ index: Int) {
        let caption: String = "\(set.name) \u{2014} picture \(index + 1)"
        figure = RecallFigure(set: set, index: index, caption: caption, library: store.library)
    }
}
