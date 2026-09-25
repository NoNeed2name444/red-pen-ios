import SwiftUI

/// Questions → Practise → Mock paper: the real paper for the student's exam,
/// its length and its clock, drawn from their own library. Says honestly
/// when the library is too small to fill it.
struct MockPaperView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var exams = ExamStore.shared
    @State private var paperId: String = ""
    @State private var usmleBlocks: Int = 2
    @State private var sitting: MockSitting?

    private var track: ExamTrack { ExamTrack.current }

    /// The chosen exam: its own papers, clock and blueprint, when there is one.
    private var target: TargetExam? { ExamChoice.current }

    private var papers: [MockPaperSpec] {
        if let target { return MockFormat.papers(for: target, blocks: usmleBlocks) }
        return MockFormat.papers(for: track, usmleBlocks: usmleBlocks)
    }

    private var paper: MockPaperSpec {
        papers.first { $0.id == paperId } ?? papers[0]
    }

    private var pool: [MockCandidate] {
        store.mcqPicks { _ in true }.map { MockCandidate(id: $0.question.id, subject: Store.subjectName($0.set)) }
    }

    var body: some View {
        let available: Int = MockAssembler.dedupe(pool).count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                paperChoice
                libraryNote(available)
                rules
                if !exams.mocks.isEmpty { history }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
        }
        .studyBar { startButton(available) }
        .modeScreen(.mcq)
        .navigationTitle("Mock paper")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $sitting) { made in
            MockSittingView(sitting: made)
                .environmentObject(store)
        }
    }

    private var intro: some View {
        let exam: String = target?.name ?? (track == .general ? "General revision" : track.title)
        return VStack(alignment: .leading, spacing: 6) {
            Text(exam)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Sit it like the real thing: the paper\u{2019}s length and clock, and nothing about right or wrong until the end.")
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    @ViewBuilder
    private var paperChoice: some View {
        VStack(alignment: .leading, spacing: 12) {
            if papers.count > 1 {
                Picker("Paper", selection: $paperId) {
                    ForEach(papers) { p in
                        Text(p.title).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Text(paper.title).font(.headline)
            }
            if let target, target.sitsBlockwise {
                let per: Int = target.sections.first?.questions ?? 40
                Stepper(value: $usmleBlocks, in: 1...max(1, target.sections.count)) {
                    Text("\(usmleBlocks) block" + (usmleBlocks == 1 ? "" : "s") + " of \(per)")
                }
                .popField()
                .onChange(of: usmleBlocks) { _, _ in paperId = papers[0].id }
            } else if target == nil && track == .usmle {
                Stepper(value: $usmleBlocks, in: 1...MockFormat.usmleMaxBlocks) {
                    Text("\(usmleBlocks) block" + (usmleBlocks == 1 ? "" : "s") + " of 40")
                }
                .popField()
            }
            let length: String = "\(paper.questionCount) questions \u{00B7} \(Self.hours(paper.minutes))"
            Label(length, systemImage: "timer")
                .font(.subheadline.weight(.semibold))
            Text(paper.note)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .onAppear { if paperId.isEmpty { paperId = papers[0].id } }
    }

    @ViewBuilder
    private func libraryNote(_ available: Int) -> some View {
        let wanted: Int = paper.questionCount
        if available < MockAssembler.minimumQuestions {
            Label("A mock needs at least \(MockAssembler.minimumQuestions) questions in your library. Make a question set first.",
                  systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentCard()
        } else if available < wanted {
            let sections: [MockSectionSpec] = MockAssembler.fitted(paper.sections, to: available)
            Label(MockAssembler.shortfall(have: available, spec: paper, sections: sections),
                  systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentCard()
        } else {
            let spread: String = target.map { "weighted by the \($0.shortName) blueprint" } ?? "spread across your subjects"
            Label("Drawn from \(available) questions in your library, \(spread).",
                  systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentCard()
        }
    }

    private var rules: some View {
        let lines: [String] = [
            "The clock is strict: when a section\u{2019}s time is up it closes, answered or not.",
            "Flag and jump between questions within a section; a closed section can\u{2019}t be reopened.",
            "Cross out options, highlight the stem, and open lab values or the calculator from More.",
            "Your score, by subject, comes at the end with every answer explained."
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("How it runs").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past sittings").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(exams.mocks.prefix(6)) { record in
                historyRow(record)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
    }

    private func historyRow(_ record: MockRecord) -> some View {
        let percent: Int = Int((record.fraction * 100).rounded())
        let when: String = record.date.formatted(date: .abbreviated, time: .omitted)
        let passed: Bool = record.fraction >= record.passMark
        let detail: String = "\(record.correct) of \(record.total) \u{00B7} \(when)"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(percent)%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(passed ? Color.green : Color.orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func startButton(_ available: Int) -> some View {
        let enough: Bool = available >= MockAssembler.minimumQuestions
        return Button {
            start()
        } label: {
            Label("Start mock", systemImage: "timer")
        }
        .buttonStyle(.bigPrimary)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!enough)
        .accessibilityIdentifier("mockStart")
    }

    private func start() {
        let spec: MockPaperSpec = paper
        guard let made = MockAssembler.assemble(spec, from: weightedPool(for: spec)) else { return }
        let picks: [QuestionPick] = store.mcqPicks { _ in true }
        var byId: [UUID: QuestionPick] = [:]
        for p in picks { byId[p.question.id] = p }
        let sections: [[QuestionPick]] = made.questionIds.map { ids in ids.compactMap { byId[$0] } }
        sitting = MockSitting(title: spec.title, specs: made.sections, picks: sections,
                              wanted: made.wanted, track: track, passMark: target?.passMark)
    }

    /// With an exam chosen, the paper's questions are drawn in its
    /// blueprint's proportions (ExamMock), each question filed under the
    /// area its set's subject or its stem is about.
    private func weightedPool(for spec: MockPaperSpec) -> [MockCandidate] {
        guard let target else { return pool }
        let plan: [BlueprintArea] = ExamBlueprint.plan(primary: target, secondary: ExamChoice.currentSecondary)
        let within: Set<ExamDomain> = Set(plan.map(\.domain))
        let filed: [(candidate: MockCandidate, domain: ExamDomain?)] = store.mcqPicks { _ in true }.map { pick in
            let subject: String = Store.subjectName(pick.set)
            let domain: ExamDomain? = ExamBlueprint.domain(of: subject, within: within)
                ?? ExamBlueprint.domain(of: pick.question.stem, within: within)
            return (candidate: MockCandidate(id: pick.question.id, subject: subject), domain: domain)
        }
        var rng = SystemRandomNumberGenerator()
        return ExamMock.select(filed, wanted: spec.questionCount, plan: plan, using: &rng)
    }

    /// "3 h", "1 h 40 min", "45 min".
    static func hours(_ minutes: Int) -> String {
        let h: Int = minutes / 60
        let m: Int = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

/// A paper ready to sit: its sections and their questions.
struct MockSitting: Identifiable {
    let id = UUID()
    let title: String
    let specs: [MockSectionSpec]
    let picks: [[QuestionPick]]
    let wanted: Int
    let track: ExamTrack
    /// The chosen exam's pass mark, when there is one.
    var passMark: Double? = nil
}
