import SwiftUI

/// "Build a session": a filtered deck, put together from a search or from
/// filters - missed this week, a subject, a tag, what is due, what the
/// accuracy engine flagged - and sat at once as a quiz, or as a review of the
/// cards themselves. Nothing is added to the library (CustomSession).
struct CustomSessionSheet: View {
    /// A quiz, or a deck to review, ready to open.
    let onStart: (StudySet, CustomSession.Mode) -> Void

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @Environment(\.dismiss) private var dismiss

    @State private var filter: CustomSession.Filter
    @State private var plan = CustomSession.Plan()
    @State private var counting = false
    @State private var starting = false
    /// Cards that could not be made into a question, said once a quiz is
    /// built with fewer questions than the plan had.
    @State private var note: String?

    init(text: String = "", onStart: @escaping (StudySet, CustomSession.Mode) -> Void) {
        var start = CustomSession.Filter()
        start.text = text
        _filter = State(initialValue: start)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            form
                .scrollContentBackground(.hidden)
                .background(LibraryBackdrop())
                .navigationTitle("Build a session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .studyBar { startBar }
        }
        .presentationDetents([.medium, .large])
        .task(id: filter) { await count() }
        .accessibilityIdentifier("customSessionSheet")
    }

    // MARK: the form

    private var form: some View {
        Form {
            Section {
                Picker("Take", selection: $filter.include) {
                    ForEach(CustomSession.Include.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            Section {
                Toggle("Missed this week", isOn: missedThisWeek)
                Toggle("Due now", isOn: $filter.dueOnly)
                Toggle("My flagged questions", isOn: $filter.myFlags)
                Toggle("Flagged for accuracy", isOn: $filter.accuracyFlagged)
            } header: {
                CategoryHeading(title: "Only")
            } footer: {
                Text("Due counts cards; flags count questions. Missed means answered wrong, or a card rated Again.")
            }
            .frostedListRow()
            Section {
                Picker("Subject", selection: $filter.subject) {
                    Text("Any").tag(String?.none)
                    ForEach(subjects, id: \.self) { Text($0).tag(Optional($0)) }
                }
                TextField("Tag or topic, e.g. cardio", text: $filter.tag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Words in the item", text: $filter.text)
                    .autocorrectionDisabled()
                Stepper("At most \(filter.limit)", value: $filter.limit, in: 10...200, step: 10)
            } header: {
                CategoryHeading(title: "Narrow it")
            }
            .frostedListRow()
            if let note {
                Section {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            // room to scroll clear of the bar
            Color.clear.frame(height: 110)
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)
        }
    }

    private var subjects: [String] { CustomSession.subjects(in: store.library) }

    private var missedThisWeek: Binding<Bool> {
        Binding(get: { filter.failedWithinDays != nil },
                set: { filter.failedWithinDays = $0 ? 7 : nil })
    }

    // MARK: the bar

    private var startBar: some View {
        VStack(spacing: 10) {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("customSessionCount")
            HStack(spacing: 10) {
                if !plan.cards.isEmpty {
                    Button { start(.review) } label: {
                        Text("Review cards").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("customSessionReview")
                }
                Button { start(.quiz) } label: {
                    Text("Start quiz").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("customSessionQuiz")
            }
            .disabled(plan.isEmpty || starting || !filter.narrows)
        }
    }

    private var summary: String {
        if !filter.narrows { return "Choose at least one filter" }
        if counting && plan.isEmpty { return "Counting\u{2026}" }
        if plan.isEmpty { return "Nothing matches yet" }
        let q: Int = plan.questions.count
        let c: Int = plan.cards.count
        let qs: String = q == 1 ? "1 question" : "\(q) questions"
        let cs: String = c == 1 ? "1 card" : "\(c) cards"
        if q == 0 { return cs }
        if c == 0 { return qs }
        return qs + " \u{00B7} " + cs
    }

    // MARK: working it out

    /// The plan for the filter as it stands, worked out off the main thread;
    /// `.task(id:)` cancels a count the next change makes stale.
    /// The accuracy engine works a set's items out the first time it is
    /// asked, so a count that found some not ready tries again, a few times.
    private func count() async {
        counting = true
        try? await Task.sleep(for: .milliseconds(150))
        for attempt in 0..<4 {
            guard !Task.isCancelled else { return }
            let sets: [StudySet] = store.library
            let chosen: CustomSession.Filter = filter
            var waiting: Bool = false
            let context: CustomSession.Context = makeContext(accuracy: chosen.accuracyFlagged, waiting: &waiting)
            let found: CustomSession.Plan = await Task.detached(priority: .userInitiated) {
                CustomSession.plan(sets: sets, filter: chosen, context: context)
            }.value
            guard !Task.isCancelled else { return }
            plan = found
            counting = false
            guard waiting, attempt < 3 else { return }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    /// What the store and the schedule know, copied out for the plan.
    private func makeContext(accuracy: Bool, waiting: inout Bool) -> CustomSession.Context {
        var context = CustomSession.Context()
        context.now = Date()
        for event in store.answerLog where !event.correct {
            let known: Date = context.lastMissed[event.questionId] ?? .distantPast
            if event.date > known { context.lastMissed[event.questionId] = event.date }
        }
        for (id, record) in reviews.records {
            let suspended: Bool = record.suspended ?? false
            context.cards[id] = CustomSession.CardState(due: record.due, lapses: record.lapses,
                                                        ratedAt: record.ratedAt, suspended: suspended)
        }
        context.flagged = store.flagged
        if accuracy { context.accuracyFlagged = accuracyFlagged(waiting: &waiting) }
        return context
    }

    /// Items the accuracy engine graded Flagged or Check this. A set whose
    /// items are still being worked out is counted when they are ready.
    private func accuracyFlagged(waiting: inout Bool) -> Set<UUID> {
        let engine: AccuracyStore = AccuracyStore.shared
        var out: Set<UUID> = []
        for set in store.library where set.kind == .mcq || set.kind == .anki {
            guard let items = engine.items(for: set) else {
                waiting = true
                continue
            }
            for item in items {
                let grade: AccuracyGrade = engine.assessment(of: item).grade
                guard grade == .flagged || grade == .check else { continue }
                if let id = UUID(uuidString: item.id) { out.insert(id) }
            }
        }
        return out
    }

    private func start(_ mode: CustomSession.Mode) {
        guard !plan.isEmpty, !starting else { return }
        starting = true
        let sets: [StudySet] = store.library
        let chosen: CustomSession.Plan = plan
        let name: String = CustomSession.title(for: filter)
        Task {
            let made: (set: StudySet, skipped: Int) = await Task.detached(priority: .userInitiated) { () -> (set: StudySet, skipped: Int) in
                if mode == .review {
                    return (CustomSession.deck(chosen, sets: sets, name: name), 0)
                }
                let seed: UInt64 = UInt64.random(in: 1...UInt64.max)
                return CustomSession.quiz(chosen, sets: sets, name: name, seed: seed)
            }.value
            starting = false
            let empty: Bool = mode == .review ? made.set.cards.isEmpty : made.set.questions.isEmpty
            if empty {
                note = "None of these cards has a single answer to ask for, so none could become a question. Review them as cards instead."
                return
            }
            // opened under the sheet, which then slides away to show it
            onStart(made.set, mode)
            dismiss()
        }
    }
}
