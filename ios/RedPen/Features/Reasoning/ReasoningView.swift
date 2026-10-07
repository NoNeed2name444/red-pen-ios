import SwiftUI
import UIKit

/// Reasoning: practice at thinking like a clinician rather than recalling
/// facts. Every set in the library, each with its two tools - duels between
/// lookalikes, and one-screen disease scripts.
struct ReasoningView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var query = ""

    private var sets: [StudySet] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return store.library
            .filter { set in
                let haystack: String = (set.name + " " + set.subject).lowercased()
                return words.isEmpty || words.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        let found: [StudySet] = sets
        let emptyLine: String = store.library.isEmpty
            ? "Make a set from a lecture first, then come back here."
            : "No set matches."
        List {
            Section {
                Text("Exams test how you reach a diagnosis, not just what you know. Pick a set and practise telling lookalikes apart and holding a whole disease on one screen.")
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            .wardRowBackground()
            Section("Your sets") {
                if found.isEmpty {
                    Text(emptyLine)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                ForEach(found) { set in
                    NavigationLink {
                        ReasoningSetView(set: set)
                    } label: {
                        setRow(set)
                    }
                    .hoverEffect(.highlight)
                }
            }
            .wardRowBackground()
            // below the student's own sets: their work comes first
            if PersonalBuild.isOn {
                Section("Examples") {
                    NavigationLink {
                        ReasoningSetView(set: ReasoningExamples.set)
                    } label: {
                        setRow(ReasoningExamples.set)
                    }
                    .hoverEffect(.highlight)
                }
                .wardRowBackground()
            }
        }
        .wardForm()
        .navigationTitle("Reasoning")
        .searchable(text: $query, prompt: "Find a set")
        .generationHUD()
    }

    private func setRow(_ set: StudySet) -> some View {
        let pack = reasoning.pack(for: set.id)
        let anyMade: Bool = ReasoningTool.allCases.contains { tool in pack.count(of: tool) > 0 }
        let counts: String = "\(pack.count(of: .duels)) duels \u{00B7} \(pack.count(of: .scripts)) scripts"
        return VStack(alignment: .leading, spacing: 3) {
            Text(set.name).font(.body.weight(.medium)).foregroundStyle(Color.wardInk).lineLimit(2)
            HStack(spacing: 10) {
                Text(set.subject).lineLimit(1)
                if anyMade {
                    Text(counts)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(Color.wardInkSecondary)
        }
        .padding(.vertical, 2)
    }
}

/// The two tools for one set: two white tiles, stacked under the thumb on a phone and side by side on a wide iPad.
///
/// It measures its own width rather than trusting the window's: it is also
/// opened in a sheet (the library row's menu), which on an iPad is far
/// narrower than the window it inherits `.broad` from.
struct ReasoningSetView: View {
    let set: StudySet

    var body: some View {
        ReasoningSetBody(set: set)
            .measuringWindow()
    }
}

/// ReasoningSetView's content, laid out for the width it was measured at.
private struct ReasoningSetBody: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @Environment(\.windowSpan) private var span

    private var isExample: Bool { self.set.id == ReasoningExamples.setId }

    private var footnote: String {
        if isExample { return "Ready-made examples, to try each tool without writing anything." }
        let origin: String = set.sources.isEmpty ? "the set\u{2019}s own content" : "the lecture this set was made from"
        return "Written from \(origin), by the model chosen in AI models."
    }

    var body: some View {
        let pack = reasoning.pack(for: set.id)
        let broad: Bool = span == .broad
        let across = AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        let stacked = AnyLayout(VStackLayout(spacing: 12))
        let tiles: AnyLayout = broad ? across : stacked
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                tiles {
                    ForEach(ReasoningTool.allCases) { tool in
                        NavigationLink {
                            destination(tool)
                        } label: {
                            ReasoningToolTile(tool: tool, count: pack.count(of: tool), tall: broad)
                        }
                        .buttonStyle(PopTileStyle(cornerRadius: WardRadius.card))
                    }
                }
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Color.wardInkSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .wardScreen()
        .navigationTitle(set.name)
        .navigationBarTitleDisplayMode(.inline)
        .generationHUD()
    }

    @ViewBuilder
    private func destination(_ tool: ReasoningTool) -> some View {
        switch tool {
        case .duels: DuelsView(set: set)
        case .scripts: ScriptsView(set: set)
        }
    }
}

/// One tool as a tile: its symbol, its name, and one line - what it is
/// before anything is written, how many there are after. Its face is the
/// link's PopTileStyle: raised off the base, pressed in under the finger.
private struct ReasoningToolTile: View {
    let tool: ReasoningTool
    let count: Int
    /// Side by side on a wide iPad: the tiles share one height.
    let tall: Bool

    private var line: String {
        if count == 0 { return tool.blurb }
        let plural: String = count == 1 ? "" : "s"
        return "\(count) \(tool.noun)\(plural) written"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        let minHeight: CGFloat = tall ? 132 : 76
        HStack(alignment: .center, spacing: 14) {
            WardIconSquare(symbol: tool.symbol, tone: .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title)
                    .font(.headline)
                    .foregroundStyle(Color.wardInk)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.wardInkSecondary)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(shape)
    }
}

/// How many to write, the Write button, and what went wrong last time - the
/// bottom slab of each tool's list. Give it to `.studyBar { }` (or use
/// `reasoningWriteSlab(tool:set:)`), so the list scrolls under the slab.
///
/// While anything is being written it shows that instead: how far it has
/// got, and Stop - the slab stands in for the generation card on these
/// screens, so there is one progress display, not two.
struct ReasoningWriteBar: View {
    let tool: ReasoningTool
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @ObservedObject private var center = GenerationCenter.shared
    @State private var count: Int
    @Environment(\.windowSpan) private var span

    init(tool: ReasoningTool, set: StudySet) {
        self.tool = tool
        self.set = set
        let start: Int = min(10, max(1, tool.defaultCount))
        _count = State(initialValue: start)
    }

    var body: some View {
        if set.id != ReasoningExamples.setId {
            VStack(alignment: .leading, spacing: 8) {
                if let job = center.job {
                    writingRow(job)
                } else {
                    idleRow
                }
                if let why = reasoning.trouble[ReasoningStore.troubleKey(tool, set.id)] {
                    WardBanner(tone: .danger, symbol: "exclamationmark.triangle.fill", text: why)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func counted(_ n: Int) -> String {
        let plural: String = n == 1 ? "" : "s"
        return "\(n) \(tool.noun)\(plural)"
    }

    private var writeTitle: String {
        reasoning.pack(for: set.id).count(of: tool) == 0 ? "Write" : "Write more"
    }

    private var idleRow: some View {
        HStack(spacing: 12) {
            ReasoningCountMenu(count: $count, label: counted(count), options: countOptions,
                               writer: LocalLLMService.shared.summary(for: .writer))
            if span == .broad { Spacer(minLength: 16) }
            Button {
                reasoning.write(tool, for: set, count: count)
            } label: {
                Label(writeTitle, systemImage: "sparkles")
            }
            .buttonStyle(.wardPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(reasoning.writing != nil)
            .accessibilityHint("Writes \(counted(count)) from this set")
        }
    }

    private var countOptions: [ReasoningCountOption] {
        (1...10).map { n in ReasoningCountOption(id: n, title: counted(n)) }
    }

    private func writingRow(_ job: GenerationCenter.Job) -> some View {
        let done: String = job.total > 0 ? "\(job.done) of \(job.total)" : "Starting\u{2026}"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                    .lineLimit(1)
                EcgStrip(progress: job.fraction)
                Text(done)
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.wardInkSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Stop", role: .destructive) { center.cancel() }
                .buttonStyle(WardButtonStyle(kind: .secondary, fills: false))
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Stops what is being written")
        }
    }
}

/// One choice in the count menu: "4 duels".
private struct ReasoningCountOption: Identifiable {
    let id: Int
    let title: String
}

/// The "4 duels" chooser at the leading end of the write slab: a menu of
/// 1 to 10, with the writer model named inside it.
private struct ReasoningCountMenu: View {
    @Binding var count: Int
    let label: String
    let options: [ReasoningCountOption]
    let writer: String?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        Menu {
            Picker("How many", selection: $count) {
                ForEach(options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            if let writer {
                Text("Writer: \(writer)")
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .monospacedDigit()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .foregroundStyle(Color.wardPrimaryInk)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 56, minHeight: 56)
            .wardRaised(in: shape)
            .contentShape(shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.lift)
        }
        .accessibilityLabel("How many to write")
        .accessibilityValue(label)
    }
}

extension View {
    /// A tool list's bottom slab: the write bar for a set of the student's
    /// own; the ready-made examples have nothing to write, so they keep only
    /// the generation card.
    @ViewBuilder
    func reasoningWriteSlab(tool: ReasoningTool, set: StudySet) -> some View {
        if set.id == ReasoningExamples.setId {
            generationHUD()
        } else {
            studyBar { ReasoningWriteBar(tool: tool, set: set) }
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
        .tint(Color.wardPrimaryInk)
        .measuringWindow()
    }
}
