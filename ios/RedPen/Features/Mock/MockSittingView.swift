import SwiftUI

/// A mock paper being sat: a strict clock per section, nothing said about
/// right or wrong, flags and a grid to jump between questions, and the exam
/// tools in More. When the last section closes, the results.
struct MockSittingView: View {
    let sitting: MockSitting
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.windowSpan) private var span
    @Environment(\.scenePhase) private var phase

    @State private var section: Int = 0
    @State private var current: Int = 0
    /// The option chosen for each question, as its own index (not the slot).
    @State private var selected: [UUID: Int] = [:]
    @State private var orders: [UUID: [Int]] = [:]
    @State private var flagged: Set<UUID> = []
    @State private var struck: [UUID: Set<Int>] = [:]
    @State private var highlights: [UUID: Set<Int>] = [:]
    @State private var highlighting = false
    @State private var toolSheet: ExamToolSheet?
    @State private var sectionEndsAt: Date?
    /// Seconds each question has been on screen.
    @State private var spent: [UUID: Double] = [:]
    @State private var shownAt = Date()
    @State private var startedAt = Date()
    /// Between two sections: the next one's clock waits for the student.
    @State private var onBreak = false
    @State private var showGrid = false
    @State private var confirmEnd = false
    @State private var confirmQuit = false
    @State private var result: MockResult?

    /// A new sitting, or one put back as it was left (`resumed`, from
    /// MockSittingStore): the same questions, option orders, answers, marks
    /// and the time that was left on the clock.
    init(sitting: MockSitting, resumed: MockSittingSave? = nil) {
        self.sitting = sitting
        var made: [UUID: [Int]] = resumed?.orders ?? [:]
        for pick in sitting.picks.flatMap({ $0 }) where made[pick.question.id] == nil {
            made[pick.question.id] = OptionOrder.make(count: pick.question.options.count, shuffle: true)
        }
        _orders = State(initialValue: made)
        if let resumed {
            _section = State(initialValue: min(max(0, resumed.section), max(0, sitting.specs.count - 1)))
            _current = State(initialValue: max(0, resumed.current))
            _selected = State(initialValue: resumed.selected)
            _flagged = State(initialValue: resumed.flagged)
            _struck = State(initialValue: resumed.struck)
            _highlights = State(initialValue: resumed.highlights)
            _spent = State(initialValue: resumed.spent)
            _startedAt = State(initialValue: resumed.startedAt)
            _onBreak = State(initialValue: resumed.onBreak)
            _sectionEndsAt = State(initialValue: resumed.secondsLeft.map { Date().addingTimeInterval(max(1, $0)) })
        }
    }

    /// What changes as the paper is sat: kept on disk whenever it does.
    private struct SittingState: Equatable {
        var section: Int
        var current: Int
        var selected: [UUID: Int]
        var flagged: Set<UUID>
        var struck: [UUID: Set<Int>]
        var highlights: [UUID: Set<Int>]
        var onBreak: Bool
        var sectionEndsAt: Date?
    }

    private var saved: SittingState {
        SittingState(section: section, current: current, selected: selected, flagged: flagged, struck: struck,
                 highlights: highlights, onBreak: onBreak, sectionEndsAt: sectionEndsAt)
    }

    /// The sitting as it stands, for MockSittingStore.
    private var snapshot: MockSittingSave {
        MockSittingSave(title: sitting.title, specs: sitting.specs,
                        questionIds: sitting.picks.map { $0.map(\.question.id) },
                        wanted: sitting.wanted, track: sitting.track.rawValue, passMark: sitting.passMark,
                        section: section, current: current, selected: selected, orders: orders,
                        flagged: flagged, struck: struck, highlights: highlights,
                        secondsLeft: sectionEndsAt.map { max(0, $0.timeIntervalSinceNow) },
                        onBreak: onBreak, spent: spent, startedAt: startedAt)
    }

    /// Kept after every change while the paper is open; never once it is marked.
    private func persist() {
        guard result == nil else { return }
        MockSittingStore.save(snapshot)
    }

    private var picks: [QuestionPick] {
        sitting.picks.indices.contains(section) ? sitting.picks[section] : []
    }
    private var spec: MockSectionSpec { sitting.specs[min(section, sitting.specs.count - 1)] }
    private var pick: QuestionPick { picks[min(current, max(0, picks.count - 1))] }
    private var q: MCQQuestion { pick.question }
    private var isLastSection: Bool { section >= sitting.specs.count - 1 }

    private func order(_ question: MCQQuestion) -> [Int] {
        OptionOrder.valid(orders[question.id], count: question.options.count)
    }

    var body: some View {
        NavigationStack {
            content
                .modeScreen(.mcq)
                .navigationTitle(sitting.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .examToolSheets($toolSheet)
        }
        .interactiveDismissDisabled()
        .onAppear {
            // a resumed sitting already has its clock, or is between sections
            guard sectionEndsAt == nil, result == nil, !onBreak else { return }
            startSection()
        }
        // on disk after every answer, flag, move and section, and as the app
        // leaves the screen: iOS may end it in the background at any time
        .onChange(of: saved) { _, _ in persist() }
        .onChange(of: phase) { _, new in
            if new != .active {
                if sectionEndsAt != nil { noteTime() }
                persist()
            }
        }
        // the section closes when its time is up, answered or not
        .task(id: sectionEndsAt) {
            guard let ends = sectionEndsAt else { return }
            let wait: Double = ends.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, sectionEndsAt == ends else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            closeSection()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            MockResultsView(result: result, sitting: sitting, selected: selected,
                            minutesUsed: minutesUsed, onDone: { dismiss() })
        } else if onBreak {
            breakScreen
        } else if picks.isEmpty {
            WardEmptyState(symbol: "questionmark.square.dashed", title: "No questions", tone: .grey)
                .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                header
                questionScroll
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if result == nil {
                Button("End") { confirmQuit = true }
                    .confirmationDialog("End the paper now?", isPresented: $confirmQuit, titleVisibility: .visible) {
                        Button("End and see results", role: .destructive) { finish() }
                        Button("Leave without results", role: .destructive) {
                            MockSittingStore.clear()
                            dismiss()
                        }
                    } message: {
                        Text("Unanswered questions count as wrong.")
                    }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if result == nil && !onBreak {
                Menu {
                    ExamToolMenuItems(sheet: $toolSheet, highlighting: $highlighting)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityHint("Lab values, calculator and highlighter")
            }
        }
    }

    // MARK: the header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            StudyProgressHeader(statusLine, detail: detailLine(at: context.date), fraction: progress) {
                if let ends = sectionEndsAt { clock(ends) }
            }
        }
    }

    private var statusLine: String { "Question \(current + 1) of \(picks.count)" }

    private var progress: Double { Double(current) / Double(max(1, picks.count)) }

    private func detailLine(at now: Date) -> String {
        let answered: Int = picks.filter { selected[$0.question.id] != nil }.count
        var parts: [String] = []
        if sitting.specs.count > 1 { parts.append("\(spec.title) of \(sitting.specs.count)") }
        parts.append("\(answered) answered")
        if let ends = sectionEndsAt {
            let whole: Double = Double(spec.minutes) * 60
            let elapsed: Double = whole - ends.timeIntervalSince(now)
            let target: Int = MockPacing.target(elapsed: elapsed, questions: picks.count, minutes: spec.minutes)
            if target > 0 { parts.append("aim: Q\(target) by now") }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The section's clock: Resus Red for the last five minutes.
    private func clock(_ ends: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left: Int = max(0, Int(ends.timeIntervalSince(context.date).rounded(.up)))
            WardTimerPill(seconds: left, warnBelow: 301)
                .accessibilityLabel("\(left / 60) minutes left in this section")
        }
    }

    static func clockText(_ seconds: Int) -> String {
        let h: Int = seconds / 3600
        let m: Int = (seconds % 3600) / 60
        let s: Int = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: the question

    private var questionScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                questionCard
                VStack(spacing: 12) {
                    ForEach(q.options.indices, id: \.self) { slot in
                        optionRow(slot)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .readableColumn()
            .id(q.id)
        }
        .studyBar { bar }
        .sheet(isPresented: $showGrid) { grid }
        .confirmationDialog(endTitle, isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(isLastSection ? "Finish paper" : "Close \(spec.title)", role: .destructive) { closeSection() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(endMessage)
        }
    }

    private var questionCard: some View {
        let on: Bool = flagged.contains(q.id)
        let marked = Binding<Set<Int>>(get: { highlights[q.id] ?? [] }, set: { highlights[q.id] = $0 })
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Pick the one best answer")
                    .wardSmallCaps()
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    if on { flagged.remove(q.id) } else { flagged.insert(q.id) }
                } label: {
                    Label(on ? "Flagged" : "Flag", systemImage: on ? "flag.fill" : "flag")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(WardChipButtonStyle(on: on, tone: .warning))
                .accessibilityLabel(on ? "Remove flag" : "Flag for review")
            }
            HighlightableStem(stem: q.stem, plain: AttributedString(q.stem), marked: marked,
                              highlighting: highlighting)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.wardInk)
                .lineSpacing(3)
            if let image = questionImage {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .contentCard()
    }

    private var questionImage: UIImage? {
        guard let idx = q.imageIndex, pick.set.images.indices.contains(idx) else { return nil }
        let raw: String = pick.set.images[idx]
        let body: String
        if raw.hasPrefix("data:"), let comma = raw.firstIndex(of: ",") {
            body = String(raw[raw.index(after: comma)...])
        } else {
            body = raw
        }
        guard let data = Data(base64Encoded: body) else { return nil }
        return UIImage(data: data)
    }

    private func original(_ slot: Int) -> Int? {
        OptionOrder.original(ofSlot: slot, in: order(q))
    }

    private func optionText(_ slot: Int) -> String {
        guard let i = original(slot), q.options.indices.contains(i) else { return "" }
        return q.options[i]
    }

    /// One option as a Ward row (WardOptionRow): Theatre Blue once chosen,
    /// and nothing about right or wrong until the end.
    private func optionRow(_ slot: Int) -> some View {
        let id: UUID = q.id
        let orig: Int? = original(slot)
        let chosen: Bool = orig != nil && selected[id] == orig
        let crossed: Set<Int> = struck[id] ?? []
        let out: Bool = orig.map { (o: Int) -> Bool in crossed.contains(o) } ?? false
        let shape = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)
        let letter: String = String(Character(Unicode.Scalar(UInt8(65 + min(slot, 25)))))
        let mark: ChartQuiz.Mark = chosen ? .chosen : .idle
        return Button {
            guard !out, let orig else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { selected[id] = orig }
        } label: {
            WardOptionRow(letter: letter, text: optionText(slot), mark: mark, struck: out)
        }
        .buttonStyle(.pressableRow)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.highlight)
        .numberKey(slot + 1)
        .strikeOutGestures(struck: out, enabled: true) { toggleStrike(slot) }
        .accessibilityLabel("Answer \(letter): \(optionText(slot))" + (out ? ", crossed out" : ""))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func toggleStrike(_ slot: Int) {
        guard let orig = original(slot) else { return }
        let id: UUID = q.id
        var set: Set<Int> = struck[id] ?? []
        let on: Bool = set.contains(orig)
        if on { set.remove(orig) } else { set.insert(orig) }
        withAnimation(.snappy(duration: 0.2)) {
            struck[id] = set
            if !on && selected[id] == orig { selected[id] = nil }
        }
    }

    // MARK: the bar

    private var bar: some View {
        let last: Bool = current >= picks.count - 1
        let nextTitle: String = last ? (isLastSection ? "Finish paper" : "End \(spec.title)") : "Next"
        let nextSymbol: String = last ? "flag.checkered" : "arrow.right"
        return HStack(spacing: 12) {
            Button { go(to: current - 1) } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bigCompanion)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(current == 0)
            .accessibilityLabel("Previous question")

            Button { showGrid = true } label: {
                Label("Review", systemImage: "square.grid.3x3")
            }
            .buttonStyle(.bigCompanion)
            .accessibilityHint("All the questions in this section, with the flagged and unanswered ones marked")

            if span == .broad { Spacer(minLength: 16) }

            Button {
                if last { confirmEnd = true } else { go(to: current + 1) }
            } label: {
                Label(nextTitle, systemImage: nextSymbol)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var endTitle: String {
        isLastSection ? "Finish the paper?" : "Close \(spec.title)?"
    }

    private var endMessage: String {
        let open: Int = picks.filter { selected[$0.question.id] == nil }.count
        let marked: Int = picks.filter { flagged.contains($0.question.id) }.count
        let closing: String = isLastSection ? "" : " A closed section can\u{2019}t be reopened."
        return "\(open) unanswered, \(marked) flagged." + closing
    }

    private func go(to index: Int) {
        guard picks.indices.contains(index) else { return }
        noteTime()
        current = index
    }

    /// Adds the time on the question just left to its total.
    private func noteTime() {
        guard picks.indices.contains(current) else { return }
        let now = Date()
        spent[q.id, default: 0] += now.timeIntervalSince(shownAt)
        shownAt = now
    }

    // MARK: the grid

    private var grid: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 52), spacing: 10)]
        return NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(picks.indices, id: \.self) { i in
                        gridCell(i)
                    }
                }
                .padding(16)
            }
            .wardScreen()
            .navigationTitle(spec.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showGrid = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func gridCell(_ i: Int) -> some View {
        let id: UUID = picks[i].question.id
        let answered: Bool = selected[id] != nil
        let marked: Bool = flagged.contains(id)
        let here: Bool = i == current
        let shape = RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous)
        let state: String = (answered ? "answered" : "unanswered") + (marked ? ", flagged" : "")
        return Button {
            go(to: i)
            showGrid = false
        } label: {
            ZStack(alignment: .topTrailing) {
                Text("\(i + 1)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(answered ? Color.wardPrimaryInk : Color.wardInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    // raised to be tapped; answered, pressed in, its number blue
                    .wardRelief(in: shape, lift: .low, pressed: answered)
                    .overlay(shape.strokeBorder(here ? Color.wardInk : Color.clear, lineWidth: 2))
                if marked {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.wardWarning)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Question \(i + 1), \(state)")
    }

    // MARK: sections and the end

    private var breakScreen: some View {
        let next: MockSectionSpec = spec
        let line: String = "\(next.questions) questions in \(MockPaperView.hours(next.minutes)). Its clock starts when you do."
        return ScrollView {
            FinishHero(symbol: "cup.and.saucer", title: "Section closed", message: line)
                .contentCard()
                .padding(16)
                .readableColumn()
        }
        .studyBar {
            Button {
                onBreak = false
                startSection()
            } label: {
                Label("Start \(next.title)", systemImage: "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func startSection() {
        let minutes: Double = Double(spec.minutes)
        current = 0
        shownAt = Date()
        sectionEndsAt = Date().addingTimeInterval(minutes * 60)
    }

    private func closeSection() {
        noteTime()
        sectionEndsAt = nil
        showGrid = false
        if isLastSection {
            finish()
        } else {
            section += 1
            current = 0
            onBreak = true
        }
    }

    private var minutesUsed: Int {
        Int((Date().timeIntervalSince(startedAt) / 60).rounded())
    }

    /// Marks every question, records the answers given in the library's
    /// history, and keeps the sitting.
    private func finish() {
        if sectionEndsAt != nil { noteTime() }
        sectionEndsAt = nil
        var marks: [MockMark] = []
        for pick in sitting.picks.flatMap({ $0 }) {
            let question: MCQQuestion = pick.question
            let chosen: Int? = selected[question.id]
            let right: Bool = chosen == question.correctIndex
            let subject: String = Store.subjectName(pick.set)
            marks.append(MockMark(questionId: question.id, subject: subject, picked: chosen, correct: right,
                                  flagged: flagged.contains(question.id), seconds: spent[question.id] ?? 0))
            // an answer left blank says nothing about what the student knows
            if chosen != nil {
                store.recordAnswer(question.id, correct: right, picked: chosen, saving: false)
            }
        }
        store.save()
        let passMark: Double = sitting.passMark ?? PassMark.typical(for: sitting.track)
        let made = MockResult(marks: marks, passMark: passMark, penalty: sitting.penalty)
        let total: Int = made.total
        ExamStore.shared.record(MockRecord(title: sitting.title, track: sitting.track.rawValue,
                                           correct: made.correct, total: total, wanted: sitting.wanted,
                                           passMark: passMark, minutesUsed: minutesUsed,
                                           score: made.penalty > 0 ? made.fraction : nil))
        // marked and kept in the history: nothing left to resume
        MockSittingStore.clear()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) {
            onBreak = false
            result = made
        }
    }
}
