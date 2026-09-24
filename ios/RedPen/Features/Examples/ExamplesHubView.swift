import SwiftUI

/// The personal build's tour: every feature, each opening straight onto its
/// worked example, so all of it can be tried without making anything first.
struct ExamplesHubView: View {
    @EnvironmentObject private var store: Store

    private var exampleSets: Int { store.library.filter { $0.name.hasPrefix("Example") }.count }

    var body: some View {
        List {
            Section {
                row("Ideas: dump, board and 3D map", "point.3.connected.trianglepath.dotted",
                    "13 linked groin hernia notes \u{2014} switch List / Board / Space", id: "ideas") { IdeasView() }
                row("Clue-by-clue cases, lookalike duels, disease scripts", "brain.head.profile",
                    "Open \u{201C}Examples\u{201D} at the top", id: "reasoning") { ReasoningView() }
            } header: { Text("Thinking") }

            Section {
                row("Progress: readiness, confidence, why you lose marks", "chart.bar.xaxis",
                    "Ten days of example answers", id: "progress") { StatsView() }
                row("Analytics: what to focus on next, trends, mistakes", "chart.xyaxis.line",
                    "Ranked next steps, weekly accuracy, recent wrong answers", id: "analytics") { AnalyticsView() }
                row("Rule sheet", "list.bullet.rectangle",
                    "One line per mistake, by subject", id: "rules") { RuleSheetView() }
                row("Syllabus coverage with the AI check", "checklist",
                    "An example check beside the live keyword result", id: "coverage") { CoverageView() }
            } header: { Text("Where you stand") }

            Section {
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
            } header: { Text("Voice") }

            Section {
                // presented full screen, not pushed: see DrawRecallExampleRow
                DrawRecallExampleRow()
            } header: { Text("Drawing") }

            Section {
                Label("\(exampleSets) example sets are in your library\u{2019}s Examples folder \u{2014} one in every mode.",
                      systemImage: "square.stack.3d.up")
                Label("Hold any set and choose \u{201C}Turn into\u{2026}\u{201D} to make it another mode.",
                      systemImage: "arrow.triangle.2.circlepath")
                Label("Hold any set and choose \u{201C}Reasoning practice\u{2026}\u{201D} for its cases, duels and scripts.",
                      systemImage: "brain")
            } header: { Text("In the library") }
            .font(.subheadline)
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Try every feature")
        .accessibilityIdentifier("examplesHub")
    }

    private func row<Destination: View>(_ title: String, _ symbol: String, _ detail: String, id: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("example-\(id)")
    }
}
