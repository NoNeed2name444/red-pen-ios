import SwiftUI

/// What the exam covers that the library does not: the exam's blueprint, area
/// by area, each subtopic marked covered, thin or not covered - with a way to
/// make questions on the gaps in one tap.
///
/// Two opinions, side by side. The keyword check is instant, free and works
/// offline, but it can only see words. The AI check reads what the matching
/// items actually say, and where the two disagree the AI's verdict is shown
/// with a note of what the keywords thought, so neither is hidden.
struct CoverageView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var checker = CoverageChecker()

    @State private var track: ExamTrack = ExamTrack.current
    @State private var areas: [AreaCoverage] = []
    @State private var computing = true
    @State private var gapsOnly = false
    /// One status picked from the counts at the top, or nil for the
    /// Everything / Gaps only choice in the slab.
    @State private var statusFilter: CoverageStatus?
    @State private var preset: NewSetPreset?

    /// Re-run the keyword check when the exam, the library or the answers
    /// change - not on every redraw.
    private var assessmentKey: String {
        let edited = store.library.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let answers = store.answerHistory.values.reduce(0) { $0 + $1.count }
        return "\(track.rawValue)-\(store.library.count)-\(edited)-\(answers)"
    }

    /// Everything / Gaps only; choosing either lets go of a picked count.
    private var showGaps: Binding<Bool> {
        Binding(get: { gapsOnly }, set: { now in
            gapsOnly = now
            statusFilter = nil
        })
    }

    private var ready: Bool { !(computing && areas.isEmpty) }

    var body: some View {
        List {
            if !ready {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading your library\u{2026}").foregroundStyle(.secondary)
                    }
                }
            } else {
                summarySection
                aiSection
                ForEach(areas) { area in
                    areaSection(area)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        // the slab only once there is something to show and check
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ready {
                StudyActionBar { bar }
            }
        }
        .navigationTitle("Syllabus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { examMenu }
        }
        .task(id: assessmentKey) { await assess() }
        .onChange(of: track) { _, now in
            checker.cancel()
            checker.load(for: now, areas: [])
        }
        .sheet(item: $preset) { NewSetView(preset: $0) }
    }

    // MARK: - Working it out

    private func assess() async {
        computing = true
        let library = store.library
        let history = store.answerHistory
        let blueprint = Syllabus.areas(for: track)
        let result = await Task.detached(priority: .userInitiated) {
            CoverageEngine.assess(library: library, history: history, areas: blueprint)
        }.value
        guard !Task.isCancelled else { return }
        areas = result
        computing = false
        checker.load(for: track, areas: result)
    }

    /// The status shown: the AI's when it has one, the keywords' otherwise.
    private func shown(_ sub: SubtopicCoverage) -> CoverageStatus {
        verdict(sub)?.status.coverage ?? sub.status
    }

    private func verdict(_ sub: SubtopicCoverage) -> CoverageVerdict? {
        checker.check?.verdicts[sub.id]
    }

    /// Whether a row is on show under the current filter.
    private func passes(_ sub: SubtopicCoverage) -> Bool {
        let status: CoverageStatus = shown(sub)
        if let statusFilter { return status == statusFilter }
        return !gapsOnly || status != .covered
    }

    // MARK: - The top: which exam

    private static func shortName(_ exam: ExamTrack) -> String {
        exam == .general ? "General" : exam.rawValue.uppercased()
    }

    /// The exam, as a menu in the top corner: chosen once, rarely changed.
    private var examMenu: some View {
        Menu {
            Picker("Exam", selection: $track) {
                ForEach(ExamTrack.allCases) { exam in
                    Text(exam.title).tag(exam)
                }
            }
        } label: {
            Label(Self.shortName(track), systemImage: "graduationcap")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Exam")
        .accessibilityValue(track.title)
    }

    // MARK: - The bottom slab

    /// Everything or gaps only, and the AI check: Check with AI, Check again,
    /// or Stop while it runs.
    private var bar: some View {
        VStack(spacing: 12) {
            Picker("Show", selection: showGaps) {
                Text("Everything").tag(false)
                Text("Gaps only").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 32)
            .hoverEffect(.highlight)
            checkControl
        }
        .frame(maxWidth: 560)
    }

    @ViewBuilder
    private var checkControl: some View {
        if checker.running {
            CoverageCheckProgress(done: checker.done, total: checker.total) { checker.cancel() }
        } else if checker.blocker == nil {
            let fresh: Bool = checker.check == nil || checker.check?.isExample == true
            let title: String = fresh ? "Check with AI" : "Check again"
            Button {
                checker.run(track: track, areas: areas, library: store.library)
            } label: {
                Label(title, systemImage: "sparkles")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(areas.isEmpty)
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        let all = areas.flatMap(\.subtopics)
        let covered = all.filter { shown($0) == .covered }.count
        let thin = all.filter { shown($0) == .thin }.count
        let missing = all.filter { shown($0) == .notCovered }.count
        let source: String = Syllabus.blueprint(for: track)
        let footer: String = "Condensed from \(source), so approximate: it shows where your gaps probably are, not what the exam will ask. Tap a count to show only those."
        return Section {
            HStack(spacing: 10) {
                figure(covered, CoverageStatus.covered)
                figure(thin, CoverageStatus.thin)
                figure(missing, CoverageStatus.notCovered)
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
        } footer: {
            Text(footer)
        }
    }

    /// One count as a chip that filters to it; a second tap lets go.
    ///
    /// Picking one also moves Everything / Gaps only in the slab to the side
    /// it belongs to (Covered is Everything, Thin and Not covered are Gaps
    /// only), so the slab never says the opposite of what the list shows.
    /// Setting the state directly, not through `showGaps`, keeps the pick.
    private func figure(_ count: Int, _ status: CoverageStatus) -> some View {
        let chosen: Bool = statusFilter == status
        let traits: AccessibilityTraits = chosen ? .isSelected : []
        let hint: String = chosen ? "Shows every row again" : "Shows only these"
        let isGap: Bool = status != .covered
        return Button {
            withAnimation(.snappy) {
                if chosen {
                    statusFilter = nil
                } else {
                    statusFilter = status
                    gapsOnly = isGap
                }
            }
        } label: {
            CoverageCountChip(count: count, status: status, chosen: chosen)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(traits)
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private var aiSection: some View {
        let hasNews: Bool = checker.check != nil || checker.failure != nil || checker.blocker != nil
        Section {
            if let check = checker.check {
                checkSummary(check)
            }
            if let failure = checker.failure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let blocker = checker.blocker {
                Text(blocker)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !hasNews {
                Text("The keyword check below is instant. Check with AI reads what your matching items actually say.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("AI check")
        } footer: {
            Text("Sends each area\u{2019}s subtopics and a short digest of your library \u{2014} set names, matching questions and cards, lecture headings \u{2014} to \(Brand.name) Cloud.")
        }
    }

    @ViewBuilder
    private func checkSummary(_ check: CoverageCheck) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if check.isExample {
                Label("Example check", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                Text("Made up from your keyword result to show what a real check looks like, for the first \(CoverageExamples.areaCount) areas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let who: String = CoverageCloudCheck.displayName(check.source)
                let when: String = check.date.formatted(.relative(presentation: .named))
                Text("Checked by \(who) \u{00B7} \(when)")
                    .font(.subheadline.weight(.semibold))
                if !check.byPreferredModel {
                    Text("Gemini 3.1 Pro wasn't available, so \(who) checked it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !check.failedAreas.isEmpty {
                    Text(Self.failedLine(check.failedAreas))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func failedLine(_ failed: [String]) -> String {
        let plural: String = failed.count == 1 ? "" : "s"
        let names: String = failed.joined(separator: ", ")
        return "\(failed.count) area\(plural) could not be checked this time: \(names)."
    }

    @ViewBuilder
    private func areaSection(_ area: AreaCoverage) -> some View {
        let rows = area.subtopics.filter { passes($0) }
        if !rows.isEmpty {
            let covered: Int = area.subtopics.filter { shown($0) == .covered }.count
            let tally: String = "\(covered) of \(area.subtopics.count) covered"
            Section {
                ForEach(rows) { sub in
                    row(sub, area: area.area.name)
                }
            } header: {
                HStack {
                    Text(area.area.name)
                    Spacer()
                    Text(tally)
                        .textCase(nil)
                }
            }
        }
    }

    private func generate(_ sub: SubtopicCoverage, area: String) {
        let ai = verdict(sub)
        preset = NewSetPreset(syllabus: sub.subtopic.name, area: area, exam: track,
                              suggestion: ai?.suggestion)
    }

    private func row(_ sub: SubtopicCoverage, area: String) -> some View {
        let status = shown(sub)
        let ai = verdict(sub)
        // the gaps carry the button; a covered topic keeps it in its menu
        let isGap: Bool = status != .covered
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(sub.subtopic.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                StatusChip(status: status)
            }
            Text(Self.detail(sub))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let ai {
                if !ai.evidence.isEmpty {
                    Text(ai.evidence)
                        .font(.caption)
                }
                if ai.status.coverage != sub.status {
                    Text("Keywords said \(sub.status.label.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !ai.suggestion.isEmpty {
                    Label(ai.suggestion, systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if isGap {
                // a glass chip standing out of the row; the finger's worth
                // of target is taller than the chip
                Button {
                    generate(sub, area: area)
                } label: {
                    Label("Generate questions", systemImage: "wand.and.stars")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .liquidGlassChip(tint: nil, plane: .raised)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .hoverEffect(.highlight)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Generate questions", systemImage: "wand.and.stars") {
                generate(sub, area: area)
            }
        }
    }

    // MARK: - Words and colours

    /// What the keyword engine found, in one line.
    static func detail(_ sub: SubtopicCoverage) -> String {
        guard sub.evidence > 0 else { return "Nothing in your library mentions it" }
        var parts = ["\(sub.evidence) item\(sub.evidence == 1 ? "" : "s")"]
        parts.append(sub.practice == 0 ? "no questions or cards" : "\(sub.practice) to practise")
        if let accuracy = sub.accuracy {
            parts.append("\(Int((accuracy * 100).rounded()))% right of \(sub.answered)")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func color(_ status: CoverageStatus) -> Color {
        switch status {
        case .covered: return .green
        case .thin: return .orange
        case .notCovered: return .red
        }
    }
}

/// One of the three counts at the top, as a chip that filters the rows to
/// its status. It stands a little out of the glass; the chosen one is filled.
private struct CoverageCountChip: View {
    let count: Int
    let status: CoverageStatus
    let chosen: Bool

    var body: some View {
        let colour: Color = CoverageView.color(status)
        let fill: Color = chosen ? colour.opacity(0.22) : Color.clear
        let edge: Color = chosen ? colour.opacity(0.6) : Color.primary.opacity(0.08)
        let shape = Capsule()
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(colour)
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(fill)
            }
        }
        .overlay(shape.strokeBorder(edge, lineWidth: 1))
        .contentShape(shape)
        .popOut(.raised, in: shape, tint: chosen ? colour : nil)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
    }
}

/// While the AI check runs: how many areas are done, and Stop.
private struct CoverageCheckProgress: View {
    let done: Int
    let total: Int
    let onStop: () -> Void

    var body: some View {
        let whole: Int = max(total, 1)
        let fraction: Double = Double(done) / Double(whole)
        let status: String = "Checking \(done) of \(total) areas\u{2026}"
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                ThinProgress(fraction: fraction)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Stop", role: .cancel, action: onStop)
                .buttonStyle(.bigCompanion)
                .keyboardShortcut(.cancelAction)
        }
    }
}

/// A small coloured label for a coverage status.
struct StatusChip: View {
    let status: CoverageStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(CoverageView.color(status))
            .background(CoverageView.color(status).opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

extension NewSetPreset {
    /// New set, ready to write MCQs on one subtopic of the syllabus: the
    /// brief is the material, since there is no lecture behind a gap.
    init(syllabus subtopic: String, area: String, exam: ExamTrack, suggestion: String? = nil) {
        kind = .mcq
        name = subtopic
        subject = subtopic
        let examName = exam == .general ? "general medical revision" : exam.title
        var brief = "Write exam questions on \(subtopic) (\(area)) for \(examName)."
        if let suggestion, !suggestion.isEmpty { brief += " " + suggestion }
        notes = brief
    }
}
