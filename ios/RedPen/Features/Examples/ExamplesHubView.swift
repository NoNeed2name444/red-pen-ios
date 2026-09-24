import SwiftUI

/// The personal build's tour: every feature, each opening straight onto its
/// worked example, so all of it can be tried without making anything first.
///
/// A list on a phone. On a wide iPad the same links are tiles, a few across,
/// standing a little out of the glass - with the same identifiers, so the
/// tour and its test find them either way.
struct ExamplesHubView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.windowSpan) private var span

    private var exampleSets: Int { store.library.filter { $0.name.hasPrefix("Example") }.count }

    /// Tiles rather than rows: only with the room of a wide iPad window.
    private var tiles: Bool { span == .broad }

    var body: some View {
        Group {
            if tiles {
                grid
            } else {
                list
            }
        }
        .background(LibraryBackdrop())
        .navigationTitle("Try every feature")
        .accessibilityIdentifier("examplesHub")
    }

    // MARK: - A phone: one list

    private var list: some View {
        List {
            Section {
                thinkingRows
            } header: { Text("Thinking") }

            Section {
                standingRows
            } header: { Text("Where you stand") }

            Section {
                voiceRows
            } header: { Text("Voice") }

            Section {
                drawingRows
            } header: { Text("Drawing") }

            Section {
                libraryNotes
            } header: { Text("In the library") }
            .font(.subheadline)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - A wide iPad: tiles

    private var grid: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: 14)]
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                gridSection("Thinking", columns: columns) { thinkingRows }
                gridSection("Where you stand", columns: columns) { standingRows }
                gridSection("Voice", columns: columns) { voiceRows }
                gridSection("Drawing", columns: columns) { drawingRows }
                VStack(alignment: .leading, spacing: 10) {
                    ExamplesHeading(title: "In the library")
                    VStack(alignment: .leading, spacing: 10) { libraryNotes }
                        .font(.subheadline)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
    }

    private func gridSection<Content: View>(_ title: String, columns: [GridItem],
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ExamplesHeading(title: title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                content()
            }
        }
    }

    // MARK: - The links, the same in both

    @ViewBuilder
    private var thinkingRows: some View {
        row("Ideas: dump, board and 3D map", "point.3.connected.trianglepath.dotted",
            "13 linked groin hernia notes \u{2014} switch List / Board / Space with the switcher at the bottom",
            id: "ideas") { IdeasView() }
        row("Clue-by-clue cases, lookalike duels, disease scripts", "brain.head.profile",
            "Open \u{201C}Examples\u{201D} under your sets", id: "reasoning") { ReasoningView() }
        row("How to reach it \u{2014} a groin lump", "signpost.right",
            "Most likely, expanded and can\u{2019}t-miss diagnoses, tap one for why", id: "howToReach") {
            HowToReachExample()
        }
    }

    @ViewBuilder
    private var standingRows: some View {
        row("Progress: readiness, confidence, why you lose marks", "chart.bar.xaxis",
            "Ten days of example answers", id: "progress") { StatsView() }
        row("Analytics: what to focus on next, trends, mistakes", "chart.xyaxis.line",
            "Ranked next steps, weekly accuracy, recent wrong answers", id: "analytics") { AnalyticsView() }
        row("Rule sheet", "list.bullet.rectangle",
            "One line per mistake, by subject", id: "rules") { RuleSheetView() }
        row("Syllabus coverage with the AI check", "checklist",
            "An example check beside the live keyword result", id: "coverage") { CoverageView() }
    }

    @ViewBuilder
    private var voiceRows: some View {
        row("Commute mode", "headphones",
            "Questions read aloud; answer by voice", id: "commute") { CommuteModeView() }
        row("Explain it back \u{2014} a marked example", "text.bubble",
            "The inguinal canal, explained and marked", id: "explain") {
            ExplainResultView(attempt: VoiceExamples.inguinalCanal)
        }
        row("Explain it back \u{2014} try it", "mic",
            "Explain a topic aloud and get it marked", id: "explain-live") { ExplainBackView() }
        row("Spoken OSCE \u{2014} breaking bad news report", "person.wave.2",
            "Marked on the checklist and SPIKES", id: "osce-bbn") {
            StationReportView(attempt: VoiceExamples.breakingBadNews)
        }
        row("Spoken OSCE \u{2014} chest pain history report", "stethoscope",
            "A history-taking station, marked", id: "osce-history") {
            StationReportView(attempt: VoiceExamples.chestPainHistory)
        }
    }

    @ViewBuilder
    private var drawingRows: some View {
        // presented full screen, not pushed: see DrawRecallExampleRow
        if tiles {
            DrawRecallExampleTile()
        } else {
            DrawRecallExampleRow()
        }
        row("Image occlusion \u{2014} the heart", "rectangle.dashed",
            "One cover per label, read off the diagram by the app", id: "occlusion") {
            OcclusionExampleView()
        }
    }

    @ViewBuilder
    private var libraryNotes: some View {
        let sets: String = "\(exampleSets) example sets are in your library\u{2019}s Examples folder \u{2014} one in every mode."
        Label(sets, systemImage: "square.stack.3d.up")
        Label("Hold any set and choose \u{201C}Turn into\u{2026}\u{201D} to make it another mode.",
              systemImage: "arrow.triangle.2.circlepath")
        Label("Hold any set and choose \u{201C}Reasoning practice\u{2026}\u{201D} for its cases, duels and scripts.",
              systemImage: "brain")
    }

    /// One example: a row in the list, or a raised tile on a wide iPad.
    @ViewBuilder
    private func row<Destination: View>(_ title: String, _ symbol: String, _ detail: String, id: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        let identifier: String = "example-\(id)"
        if tiles {
            NavigationLink {
                destination()
            } label: {
                ExampleTile(title: title, symbol: symbol, detail: detail)
            }
            .buttonStyle(.popTile)
            .accessibilityIdentifier(identifier)
        } else {
            NavigationLink {
                destination()
            } label: {
                ExampleRowLabel(title: title, symbol: symbol, detail: detail)
            }
            .hoverEffect(.highlight)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Draw it from memory as a tile like every other one on a wide iPad: the
/// whole face answers a tap, sinks under the finger and lifts under the
/// pointer (`.popTile`). It opens the drawing screen full screen, the way
/// DrawRecallExampleRow does and for the same reason - a navigation stack
/// pushed inside another, with a tool picker on top, is what crashed - and
/// saves the example attempt when tapped, not while the grid is drawn.
private struct DrawRecallExampleTile: View {
    @State private var figure: RecallFigure?
    @State private var opening: RecallAttempt?

    var body: some View {
        Button {
            opening = RecallExamples.seedIfNeeded()
            figure = RecallExamples.figure
        } label: {
            ExampleTile(title: "Draw it from memory", symbol: "pencil.and.scribble",
                        detail: "An inguinal canal drawing ready to Compare")
        }
        .buttonStyle(.popTile)
        .accessibilityIdentifier("example-draw")
        .fullScreenCover(item: $figure) { shown in
            DrawRecallView(figure: shown, opening: opening)
        }
    }
}

/// "How to reach it" on its own, for the tour.
private struct HowToReachExample: View {
    var body: some View {
        ScrollView {
            HowToReachCard(differential: ReasoningExamples.herniaDifferential,
                           lecture: ReasoningExamples.sourceLabel)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        }
        .background(LibraryBackdrop())
        .navigationTitle("How to reach it")
    }
}

/// A section's name above a group of tiles.
private struct ExamplesHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An example as a list row.
private struct ExampleRowLabel: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// An example as a tile: the same symbol, title and line, on a frosted
/// face that stands out of the glass.
private struct ExampleTile: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.regularMaterial, in: shape)
    }
}
