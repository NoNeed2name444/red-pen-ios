import SwiftUI
import UIKit

/// Reasoning: practice at thinking like a clinician rather than recalling
/// facts. Every set in the library, each with its three tools - cases told a
/// clue at a time, duels between lookalikes, and one-screen disease scripts.
struct ReasoningView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var query = ""

    private var sets: [StudySet] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return store.library
            .filter { set in
                words.isEmpty || words.allSatisfy { (set.name + " " + set.subject).lowercased().contains($0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        List {
            Section {
                Text("Exams test how you reach a diagnosis, not just what you know. Pick a set and practise committing early, telling lookalikes apart, and holding a whole disease on one screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if PersonalBuild.isOn {
                Section("Examples") {
                    NavigationLink {
                        ReasoningSetView(set: ReasoningExamples.set)
                    } label: {
                        setRow(ReasoningExamples.set)
                    }
                }
            }
            Section("Your sets") {
                if sets.isEmpty {
                    Text(store.library.isEmpty ? "Make a set from a lecture first, then come back here."
                                               : "No set matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sets) { set in
                    NavigationLink {
                        ReasoningSetView(set: set)
                    } label: {
                        setRow(set)
                    }
                }
            }
        }
        .navigationTitle("Reasoning")
        .searchable(text: $query, prompt: "Find a set")
        .generationHUD()
    }

    private func setRow(_ set: StudySet) -> some View {
        let pack = reasoning.pack(for: set.id)
        let made = ReasoningTool.allCases.map { tool in pack.count(of: tool) }
        return VStack(alignment: .leading, spacing: 3) {
            Text(set.name).font(.body.weight(.medium)).lineLimit(2)
            HStack(spacing: 10) {
                Text(set.subject).lineLimit(1)
                if made.contains(where: { $0 > 0 }) {
                    Text("\(made[0]) cases \u{00B7} \(made[1]) duels \u{00B7} \(made[2]) scripts")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The three tools for one set.
struct ReasoningSetView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared

    var body: some View {
        let pack = reasoning.pack(for: set.id)
        List {
            Section {
                ForEach(ReasoningTool.allCases) { tool in
                    NavigationLink {
                        destination(tool)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tool.symbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(.body.weight(.semibold))
                                Text(tool.blurb).font(.caption).foregroundStyle(.secondary)
                                let n = pack.count(of: tool)
                                Text(n == 0 ? "None written yet" : "\(n) \(tool.noun)\(n == 1 ? "" : "s")")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(n == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                if set.id == ReasoningExamples.setId {
                    Text("Ready-made examples, to try each tool without writing anything.")
                } else {
                    Text("Written from \(set.sources.isEmpty ? "the set's own content" : "the lecture this set was made from"), by the model chosen in AI models.")
                }
            }
            if let stats = caseStats(pack) {
                Section("Clue-by-clue so far") {
                    LabeledContent("Cases played", value: "\(stats.played)")
                    LabeledContent("Right", value: "\(stats.right)")
                    LabeledContent("Average score", value: String(format: "%.2f of 2", stats.average))
                    if stats.premature > 0 {
                        LabeledContent("Premature closures", value: "\(stats.premature)")
                    }
                }
            }
        }
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .generationHUD()
    }

    @ViewBuilder
    private func destination(_ tool: ReasoningTool) -> some View {
        switch tool {
        case .cases: ClueCasesView(set: set)
        case .duels: DuelsView(set: set)
        case .scripts: ScriptsView(set: set)
        }
    }

    private func caseStats(_ pack: ReasoningPack) -> (played: Int, right: Int, average: Double, premature: Int)? {
        let ids = Set(pack.cases.map(\.id))
        let plays = reasoning.casePlays.filter { ids.contains($0.caseId) }
        guard !plays.isEmpty else { return nil }
        let total = plays.reduce(0.0) { $0 + $1.score }
        return (plays.count, plays.filter(\.correct).count, total / Double(plays.count),
                plays.filter(\.prematureClosure).count)
    }
}

/// How many to write, the Write button, and what went wrong last time -
/// the same strip at the top of each tool.
struct ReasoningWriteBar: View {
    let tool: ReasoningTool
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var count: Int

    init(tool: ReasoningTool, set: StudySet) {
        self.tool = tool
        self.set = set
        _count = State(initialValue: tool.defaultCount)
    }

    var body: some View {
        if set.id != ReasoningExamples.setId {
            VStack(alignment: .leading, spacing: 8) {
                if reasoning.isWriting(tool, for: set.id) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing \(tool.noun)s\u{2026}").foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop", role: .destructive) { reasoning.cancelWriting() }
                            .buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: 12) {
                        Stepper("\(count) \(tool.noun)\(count == 1 ? "" : "s")", value: $count, in: 1...12)
                            .monospacedDigit()
                        Button {
                            reasoning.write(tool, for: set, count: count)
                        } label: {
                            Label(reasoning.pack(for: set.id).count(of: tool) == 0 ? "Write" : "Write more",
                                  systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reasoning.writing != nil)
                    }
                }
                if let why = reasoning.trouble[ReasoningStore.troubleKey(tool, set.id)] {
                    Text(why).font(.footnote).foregroundStyle(.red)
                }
                if let who = LocalLLMService.shared.summary(for: .writer) {
                    Text("Writer: \(who)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// "Reasoning practice…" in a library row's menu. A view of its own rather
/// than a plain button, so it can pick up the Ideas store from the library's
/// environment and hand it to the sheet, which is presented outside it.
struct ReasoningMenuItem: View {
    let set: StudySet
    @EnvironmentObject private var notes: NoteStore

    var body: some View {
        Button("Reasoning practice\u{2026}", systemImage: "brain.head.profile") {
            ReasoningPresenter.present(set, notes: notes)
        }
    }
}

/// Opens Reasoning for one set on top of whatever is showing - how the
/// library's row menu gets there without a sheet of its own.
@MainActor
enum ReasoningPresenter {
    static func present(_ set: StudySet, notes: NoteStore) {
        // the row's menu is still closing when its button runs; presenting
        // over it at once can be refused
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard var top = scene?.keyWindow?.rootViewController else { return }
            while let next = top.presentedViewController { top = next }
            let holder = ReasoningSheetHolder()
            let host = UIHostingController(rootView: AnyView(
                ReasoningSheet(set: set, holder: holder).environmentObject(notes)))
            holder.controller = host
            top.present(host, animated: true)
        }
    }
}

/// The presented sheet's own controller, so Done can close it.
final class ReasoningSheetHolder {
    weak var controller: UIViewController?
}

private struct ReasoningSheet: View {
    let set: StudySet
    let holder: ReasoningSheetHolder

    var body: some View {
        NavigationStack {
            ReasoningSetView(set: set)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { holder.controller?.dismiss(animated: true) }
                    }
                }
        }
        .tint(Color.accentColor)
    }
}
