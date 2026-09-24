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
    @State private var preset: NewSetPreset?
    @State private var drawingExample: RecallFigure?
    @State private var exampleAttempt: RecallAttempt?

    /// Re-run the keyword check when the exam, the library or the answers
    /// change - not on every redraw.
    private var assessmentKey: String {
        let edited = store.library.map(\.updatedAt).max()?.timeIntervalSince1970 ?? 0
        let answers = store.answerHistory.values.reduce(0) { $0 + $1.count }
        return "\(track.rawValue)-\(store.library.count)-\(edited)-\(answers)"
    }

    var body: some View {
        List {
            examSection
            if computing && areas.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading your library\u{2026}").foregroundStyle(.secondary)
                    }
                }
            } else {
                summarySection
                aiSection
                Section {
                    Picker("Show", selection: $gapsOnly) {
                        Text("Everything").tag(false)
                        Text("Gaps only").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                ForEach(areas) { area in
                    areaSection(area)
                }
            }
            if PersonalBuild.isOn {
                Section {
                    Button {
                        exampleAttempt = RecallExamples.seedIfNeeded()
                        drawingExample = RecallExamples.figure
                    } label: {
                        Label("Draw from memory: example figure", systemImage: "pencil.and.scribble")
                    }
                } header: {
                    Text("Example")
                } footer: {
                    Text("A saved attempt is already there, so Compare can be tried straight away.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Syllabus")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: assessmentKey) { await assess() }
        .onChange(of: track) { _, now in
            checker.cancel()
            checker.load(for: now, areas: [])
        }
        .sheet(item: $preset) { NewSetView(preset: $0) }
        .fullScreenCover(item: $drawingExample) { figure in
            DrawRecallView(figure: figure, opening: exampleAttempt)
        }
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

    // MARK: - Sections

    private var examSection: some View {
        Section {
            Picker("Exam", selection: $track) {
                ForEach(ExamTrack.allCases) { exam in
                    Text(exam.title).tag(exam)
                }
            }
        } footer: {
            Text("Condensed from \(Syllabus.blueprint(for: track)), so approximate: it shows where your gaps probably are, not what the exam will ask.")
        }
    }

    private var summarySection: some View {
        let all = areas.flatMap(\.subtopics)
        let covered = all.filter { shown($0) == .covered }.count
        let thin = all.filter { shown($0) == .thin }.count
        let missing = all.filter { shown($0) == .notCovered }.count
        return Section {
            HStack(spacing: 0) {
                figure(covered, CoverageStatus.covered)
                figure(thin, CoverageStatus.thin)
                figure(missing, CoverageStatus.notCovered)
            }
            .padding(.vertical, 4)
        }
    }

    private func figure(_ count: Int, _ status: CoverageStatus) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Self.color(status))
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var aiSection: some View {
        Section {
            if checker.running {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(checker.done), total: Double(max(checker.total, 1)))
                    Text("Checking \(checker.done) of \(checker.total) areas\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Stop", role: .cancel) { checker.cancel() }
            } else {
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
                } else {
                    let fresh = checker.check == nil || checker.check?.isExample == true
                    Button {
                        checker.run(track: track, areas: areas, library: store.library)
                    } label: {
                        Label(fresh ? "Check with AI" : "Check again", systemImage: "sparkles")
                    }
                    .disabled(areas.isEmpty)
                }
            }
        } header: {
            Text("AI check")
        } footer: {
            Text("Sends each area's subtopics and a short digest of your library \u{2014} set names, matching questions and cards, lecture headings \u{2014} to \(Brand.name) Cloud.")
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
                Text("Checked by \(CoverageCloudCheck.displayName(check.source)) \u{00B7} \(check.date.formatted(.relative(presentation: .named)))")
                    .font(.subheadline.weight(.semibold))
                if !check.byPreferredModel {
                    Text("Gemini 3.1 Pro wasn't available, so \(CoverageCloudCheck.displayName(check.source)) checked it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !check.failedAreas.isEmpty {
                    Text("\(check.failedAreas.count) area\(check.failedAreas.count == 1 ? "" : "s") could not be checked this time: \(check.failedAreas.joined(separator: ", ")).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func areaSection(_ area: AreaCoverage) -> some View {
        let rows = area.subtopics.filter { !gapsOnly || shown($0) != .covered }
        if !rows.isEmpty {
            Section {
                ForEach(rows) { sub in
                    row(sub, area: area.area.name)
                }
            } header: {
                HStack {
                    Text(area.area.name)
                    Spacer()
                    let covered = area.subtopics.filter { shown($0) == .covered }.count
                    Text("\(covered) of \(area.subtopics.count) covered")
                        .textCase(nil)
                }
            }
        }
    }

    private func row(_ sub: SubtopicCoverage, area: String) -> some View {
        let status = shown(sub)
        let ai = verdict(sub)
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
            Button {
                preset = NewSetPreset(syllabus: sub.subtopic.name, area: area, exam: track,
                                      suggestion: ai?.suggestion)
            } label: {
                Label("Generate questions", systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
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
