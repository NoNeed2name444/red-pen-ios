import SwiftUI

/// Everything the library draws for one row or one strip.
///
/// Split out of LibraryView because that file had grown to the point where
/// changing one thing meant re-reading four hundred lines to find it, and
/// because SwiftUI type-checks a whole view expression at once.
extension LibraryView {

    /// What is due right now, across every deck at once.
    ///
    /// The count is the point. Twenty lectures means twenty decks, and without
    /// a number on the first screen nobody knows which of them is waiting - so
    /// the schedule goes unused however well it works underneath.
    @ViewBuilder
    /// "43 days to PLAB": set in AI models → Your exam, with the pace that
    /// gets through every question in the library before then.
    var examCountdown: some View {
        let stamp = UserDefaults.standard.double(forKey: ExamTrack.dateKey)
        if stamp > 0 {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                               to: calendar.startOfDay(for: Date(timeIntervalSince1970: stamp))).day ?? 0
            let questions = store.library.filter { $0.kind == .mcq }.reduce(0) { $0 + $1.questions.count }
            let exam = ExamTrack.current
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text("\(max(0, days))").font(.title2.weight(.bold).monospacedDigit())
                    Text(days == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(days > 0 ? "to \(exam == .general ? "your exam" : exam.title)" : days == 0 ? "Exam day \u{2014} good luck" : "Exam date has passed")
                        .font(.body.weight(.semibold))
                    if days > 0 && questions > 0 {
                        Text("About \(Int((Double(questions) / Double(days)).rounded(.up))) questions a day covers your library")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    var dueBanner: some View {
        let due = reviews.dueAcross(store.library).count
        if store.library.contains(where: { $0.kind == .anki }) {
            NavigationLink { DueTodayView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: due > 0 ? "tray.full.fill" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(due > 0 ? StudySetKind.anki.tint : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(due > 0 ? "\(due) card\(due == 1 ? "" : "s") due" : "Nothing due")
                            .font(.body.weight(.semibold))
                        Text(due > 0 ? "Across all your decks" : "You're up to date")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if due > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(due == 0)
        }
    }

    /// "5-day streak · 32 today" - only once there is a streak to show, so a
    /// first launch is not greeted by a zero.
    @ViewBuilder
    var streakRow: some View {
        let streak = studyLog.streak
        let today = studyLog.today
        if streak > 0 {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(today > 0 ? Color.orange : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak)-day streak \u{00B7} \(today) today")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    if today == 0 {
                        // yesterday's streak, still alive until midnight
                        Text("Answer one question or card to keep it going")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }

    /// Every flagged question in the library as one quiz.
    ///
    /// A button that builds the quiz when tapped, not a link holding one: the
    /// quiz is a copy taken at that moment, so unflagging a question part way
    /// through it leaves the quiz as it was.
    @ViewBuilder
    var flaggedRow: some View {
        let picks = store.flaggedQuestions
        if !picks.isEmpty {
            Button {
                quickQuiz = Store.temporaryQuiz(named: "Flagged questions", subject: "Flagged",
                                                from: picks.shuffled())
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flag.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("Flagged questions (\(picks.count))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Every question in the selected MCQ sets, shuffled together into one
    /// quiz of at most fifty, and opened without being saved.
    ///
    /// Revising one lecture at a time teaches the order the lectures came
    /// in; the exam mixes them, so practice should too.
    func startMixedQuiz() {
        let sets = selectedSets.filter { $0.kind == .mcq }
        var seen: Set<UUID> = []
        var picks: [QuestionPick] = []
        for set in sets {
            for question in set.questions {
                // a Mistakes set holds copies of questions from its original
                if seen.insert(question.id).inserted {
                    picks.append(QuestionPick(set: set, question: question))
                }
            }
        }
        guard !picks.isEmpty else { return }
        let subjects = Set(sets.map { Store.subjectName($0) })
        let subject = subjects.count == 1 ? (subjects.first ?? "Mixed") : "Mixed"
        let quiz = Store.temporaryQuiz(named: "Mixed quiz", subject: subject,
                                       from: Array(picks.shuffled().prefix(50)))
        withAnimation(.snappy) { selecting = false; selected = [] }
        quickQuiz = quiz
    }

    /// A row of small mode counters - how many of each kind of set the library
    /// holds.
    var summaryStrip: some View {
        let counts = Dictionary(grouping: store.library, by: \.kind).mapValues(\.count)
        let kinds = StudySetKind.allCases.filter { counts[$0] != nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(kinds) { kind in
                    HStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.caption.weight(.semibold))
                        Text("\(counts[kind] ?? 0) \(kind.label)").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(kind.tint)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .glassEffect(.regular.tint(kind.tint.opacity(0.22)), in: .capsule)
                }
            }
            .padding(.vertical, 2)
        }
    }

    func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    /// One library row - a navigation link normally, a tickable row in
    /// selection mode, with the per-set actions in a long-press menu and as
    /// swipe actions.
    @ViewBuilder
    func row(_ set: StudySet) -> some View {
        Group {
            if selecting {
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        if selected.contains(set.id) { selected.remove(set.id) }
                        else { selected.insert(set.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected.contains(set.id) ? Color.accentColor : Color.secondary)
                        setRow(set)
                    }
                }
                .buttonStyle(.pressableRow)
            } else {
                NavigationLink(value: set) { setRow(set) }
                    .accessibilityIdentifier("setRow-\(set.kind.rawValue)")
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
        // frosted, so the backdrop shows through while the row stays easy
        // to read
        .listRowBackground(Rectangle().fill(.regularMaterial))
        .contextMenu { rowMenu(set) }
        .swipeActions(edge: .leading) {
            Button { export(set) } label: { Label(set.kind == .anki ? "Export deck" : "Export PDF", systemImage: "arrow.down.doc") }
                .tint(set.kind.tint)
        }
    }

    @ViewBuilder
    func rowMenu(_ set: StudySet) -> some View {
        Button("Rename", systemImage: "pencil") { renaming = set }
        // any mode into any other: rearranged on the spot where it can be,
        // written from the lecture where it cannot
        if ModeConversion.targets.contains(where: { ModeConversion.canTurn(set, into: $0) }) {
            Button("Turn into\u{2026}", systemImage: "arrow.triangle.2.circlepath") { turning = set }
                .accessibilityIdentifier("turnInto")
        }
        // The lecture this set came from, readable on its own - not only by
        // way of a card that happens to cite it.
        if set.sources.count == 1, let only = set.sources.first {
            Button("Open \(only.name)", systemImage: only.kind.symbol) {
                reading = SourceOpening(source: only, page: 1)
            }
        } else if set.sources.count > 1 {
            Menu("Open source", systemImage: "doc.richtext") {
                ForEach(set.sources) { source in
                    Button(source.name, systemImage: source.kind.symbol) {
                        reading = SourceOpening(source: source, page: 1)
                    }
                }
            }
        }
        if set.kind == .anki || set.kind == .mcq {
            Button("Edit cards", systemImage: "square.and.pencil") { editing = set }
        }
        Menu("Move to folder", systemImage: "folder") {
            ForEach(store.folders) { folder in
                Button(folder.name) { store.move(set.id, to: folder.id) }
            }
            Button("New folder\u{2026}", systemImage: "folder.badge.plus") {
                selected = [set.id]; naming = .folder
            }
            if set.folderId != nil {
                Divider()
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    store.move(set.id, to: nil)
                }
            }
        }
        if set.kind != .anki {
            Button("Export PDF", systemImage: "arrow.down.doc") { export(set) }
        }
        if set.kind == .anki {
            Button("Export deck (.apkg)", systemImage: "square.and.arrow.up") {
                if let url = try? ApkgExporter.export(set) { exportURL = url }
                else { exportFailedSetName = set.name }
            }
        }
        Button("Share as JSON", systemImage: "doc.text") {
            if let url = JSONExporter.export(set) { exportURL = url }
            else { exportFailedSetName = set.name }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete([set.id]) }
    }

    /// The floating action bar shown in selection mode.
    var selectionBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                Text(selected.isEmpty ? "Select sets" : "\(selected.count) selected")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { naming = .folder } label: {
                    Label("Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .disabled(selected.isEmpty)
                Button { startMixedQuiz() } label: {
                    Label("Quiz", systemImage: "shuffle")
                }
                .buttonStyle(.glass)
                .disabled(!selectedSets.contains { $0.kind == .mcq && !$0.questions.isEmpty })
                Button { naming = .combine } label: {
                    Label("Combine", systemImage: "square.stack.3d.down.forward")
                }
                .buttonStyle(.glassProminent)
                .disabled(!canCombine)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    func setRow(_ set: StudySet) -> some View {
        let due = set.kind == .anki ? reviews.dueCount(for: set.cards) : 0
        return HStack(spacing: 14) {
            ModeTile(kind: set.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\u{00b7}").foregroundStyle(.tertiary)
                    Text("\(set.itemCount) \(set.itemNoun)\(set.itemCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    if !set.subject.isEmpty && set.subject != "General" {
                        Text("\u{00b7}").foregroundStyle(.tertiary)
                        Text(set.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if due > 0 {
                Text("\(due)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(StudySetKind.anki.tint, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    ModeTile(kind: kind, size: 56)
                        .rotationEffect(.degrees(kind == .anki ? 0 : (kind == .mcq ? -10 : 10)))
                }
            }
            Text("Nothing here yet").font(.title2.weight(.bold))
            Text("Make an MCQ quiz, a set of flashcards, a textbook, a case set, an OSCE checklist, or a narrated transcript \u{2014} all of it stays on this phone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showNewSet = true } label: {
                Label("New set", systemImage: "plus").padding(.horizontal, 6)
            }
            .buttonStyle(.glassProminent)
            // the rest of the app is there from the start, not only once
            // something has been made
            HStack(spacing: 10) {
                Button { support = .sources } label: {
                    Label("Sources", systemImage: "doc.richtext")
                }
                Button { support = .help } label: {
                    Label("How it works", systemImage: "lightbulb")
                }
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("emptyLibraryLinks")
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
