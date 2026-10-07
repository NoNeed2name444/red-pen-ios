import SwiftUI

/// Everything the library draws for one row or one strip.
///
/// Split out of LibraryView because that file had grown to the point where
/// changing one thing meant re-reading four hundred lines to find it, and
/// because SwiftUI type-checks a whole view expression at once.
extension LibraryView {

    // Mission Control, the card that stood here, is now today's ward round
    // (WardHome): the beds hold what its status lines counted, its lift-off
    // is "Start ward round", and its Plan button opens the exam plan, where
    // the forecast and what is locked in are shown in full.

    /// Starts a mission: the due cards and quick quizzes on the library's own
    /// screens, everything else through LearnRouter.
    func launch(_ mission: ExamWeekPlanner.Mission) {
        switch mission {
        case .examKit: LearnRouter.shared.open(.examKit)
        case .morningCheck: LearnRouter.shared.open(.morningCheck)
        case .dueCards: showingDue = true
        case .mock:
            // the real paper; marked sat only when a sitting is finished
            // (ExamStore.mocks, read by LearnMarks.mockDone)
            LearnRouter.shared.open(.mockPaper)
        case .confidentErrors: quickQuiz = store.confidentMistakesQuiz()
        case .mistakes: quickQuiz = store.mistakesQuiz()
        case .lockIn: quickQuiz = store.lockInQuiz()
        case .flagged: startFlaggedQuiz()
        case .weakest(let subject): quickQuiz = store.drill(subject: subject)
        case .newQuestions: quickQuiz = store.untriedQuiz()
        case .nothing: break
        }
    }

    /// The personal build's tour of every feature, at the bottom of every
    /// category's page.
    @ViewBuilder
    var examplesSection: some View {
        if PersonalBuild.isOn {
            Section {
                Button { support = .examples } label: {
                    Label("Try every feature", systemImage: "sparkles.rectangle.stack")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("examplesBanner")
                .frostedListRow()
            }
        }
    }

    /// Every flagged question in the library as one quiz.
    ///
    /// Built when tapped, not held ready: the quiz is a copy taken at that
    /// moment, so unflagging a question part way through it leaves the quiz
    /// as it was.
    func startFlaggedQuiz() {
        let picks = store.flaggedQuestions
        guard !picks.isEmpty else { return }
        quickQuiz = Store.temporaryQuiz(named: "Flagged questions", subject: "Flagged",
                                        from: picks.shuffled())
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

    func sectionHeader(_ text: String) -> some View {
        CategoryHeading(title: text)
    }

    /// One library row - a navigation link normally, a tickable row in
    /// selection mode, with the per-set actions in a long-press menu, behind
    /// the row's own ellipsis (for a pointer, and for anyone who never
    /// thought to hold a row) and as swipe actions.
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
                    HStack(spacing: 16) {
                        Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .accessibilityHidden(true)
                            .foregroundStyle(selected.contains(set.id) ? Color.wardPrimaryInk : Color.wardInkSecondary)
                        setRow(set)
                    }
                }
                .buttonStyle(.pressableRow)
                .accessibilityAddTraits(selected.contains(set.id) ? [.isSelected] : [])
            } else {
                // The ellipsis sits beside the link rather than inside its
                // label: a control inside a link's label fights the row for
                // the tap, and VoiceOver folds it into the row.
                HStack(spacing: 8) {
                    NavigationLink(value: set) { setRow(set) }
                        .accessibilityIdentifier("setRow-\(set.kind.rawValue)")
                    rowMoreMenu(set)
                }
            }
        }
        // a soft tile, a little tighter above and below than a form's, so
        // a long library stays quick to scan
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16))
        .frostedListRow()
        .contextMenu { rowMenu(set) }
        .swipeActions(edge: .leading) {
            Button { export(set) } label: { Label(set.kind == .anki ? "Export deck" : "Export PDF", systemImage: "arrow.down.doc") }
                .tint(set.kind.tint)
        }
    }

    @ViewBuilder
    func rowMenu(_ set: StudySet) -> some View {
        // picking several sets starts from any one of them, ticked; while
        // already picking, it adds this one rather than starting over
        Button("Select", systemImage: "checkmark.circle") {
            withAnimation(.snappy) {
                if selecting {
                    selected.insert(set.id)
                } else {
                    selecting = true
                    selected = [set.id]
                }
            }
        }
        Button("Rename", systemImage: "pencil") { renaming = set }
        // the set's accuracy in words: verified, to check, flagged
        AccuracySetSummary(set: set)
        // any mode into any other: rearranged on the spot where it can be,
        // written from the lecture where it cannot
        if ModeConversion.targets.contains(where: { ModeConversion.canTurn(set, into: $0) }) {
            Button("Turn into\u{2026}", systemImage: "arrow.triangle.2.circlepath") { turning = set }
                .accessibilityIdentifier("turnInto")
        }
        Button("Reasoning practice\u{2026}", systemImage: "brain.head.profile") { reasoningFor = set }
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
        // where the set's content came from, with its licences and credits
        Button("Sources and licences", systemImage: "books.vertical") { creditsFor = set }
            .accessibilityIdentifier("setCredits")
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
                exportDeck(set)
            }
        }
        Button("Share as JSON", systemImage: "doc.text") {
            if let url = JSONExporter.export(set) { exportURL = url }
            else { exportFailedSetName = set.name }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { delete([set.id]) }
    }

    /// The floating action bar shown in selection mode: one soft panel raised
    /// off the base like the dock, in the dock's place. Done at the leading end; Move, Quiz
    /// and Combine, then Delete last, at the trailing end, and it asks first.
    var selectionBar: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.bar, style: .continuous)
        return HStack(spacing: 8) {
            selectionDoneButton
            selectionCount
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                selectionActions(compact: false)
                selectionActions(compact: true)
            }
        }
        .padding(10)
        .wardRaised(in: shape, lift: .high)
        .frame(maxWidth: 700)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var selectionDoneButton: some View {
        Button {
            withAnimation(.snappy) { selecting = false; selected = [] }
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.wardInk)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.highlight)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Done")
        .accessibilityHint("Stop choosing sets")
        .accessibilityIdentifier("selectionDone")
    }

    private var selectionCount: some View {
        let count: Int = selected.count
        let text: String = count == 0 ? "Select sets" : "\(count) selected"
        return Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.wardInkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Whether the selection holds any questions to mix into one quiz.
    var canMixQuiz: Bool {
        selectedSets.contains { $0.kind == .mcq && !$0.questions.isEmpty }
    }

    /// Every selected set into a folder.
    func moveSelected(to folderId: UUID?) {
        for id in selected { store.move(id, to: folderId) }
        withAnimation(.snappy) { selecting = false; selected = [] }
    }

    /// Move, Quiz, Combine, then Delete - with their names, or as symbols
    /// alone when the names do not fit.
    private func selectionActions(compact: Bool) -> some View {
        HStack(spacing: 6) {
            moveMenu(compact: compact)
            quizButton(compact: compact)
            combineButton(compact: compact)
            deleteSelectedButton(compact: compact)
        }
    }

    private func moveMenu(compact: Bool) -> some View {
        Menu {
            ForEach(store.folders) { folder in
                Button(folder.name, systemImage: "folder") { moveSelected(to: folder.id) }
            }
            Button("New folder\u{2026}", systemImage: "folder.badge.plus") { naming = .folder }
        } label: {
            ActionLabel(title: "Move", symbol: "folder", compact: compact)
        }
        .menuStyle(.button)
        .buttonStyle(.wardCompact)
        .disabled(selected.isEmpty)
    }

    private func quizButton(compact: Bool) -> some View {
        Button { startMixedQuiz() } label: {
            ActionLabel(title: "Quiz", symbol: "shuffle", compact: compact)
        }
        .buttonStyle(.wardCompact)
        .disabled(!canMixQuiz)
    }

    private func combineButton(compact: Bool) -> some View {
        Button { naming = .combine } label: {
            ActionLabel(title: "Combine", symbol: "square.stack.3d.down.forward", compact: compact)
        }
        .buttonStyle(.wardCompact)
        .disabled(!canCombine)
    }

    /// Last, at the trailing end, away from Combine by the bar's own order;
    /// it asks first unless "Ask before deleting a set" is off.
    private func deleteSelectedButton(compact: Bool) -> some View {
        let ink: Color = selected.isEmpty ? Color.wardInkSecondary : Color.wardDanger
        return Button(role: .destructive) { delete(Array(selected)) } label: {
            ActionLabel(title: "Delete", symbol: "trash", compact: compact)
                .foregroundStyle(ink)
        }
        .buttonStyle(.wardCompact)
        .disabled(selected.isEmpty)
    }

    /// A set's row (SetRow, in WardHome): its icon, name and size, how far
    /// into it the student is, and the cards due for a deck.
    func setRow(_ set: StudySet) -> some View {
        let due: Int = set.kind == .anki ? reviews.dueCount(for: set.cards) : 0
        return SetRow(set: set, due: due, progress: progress(of: set))
    }

    /// The ellipsis at the end of a row: rename, turn into, export, delete -
    /// the same menu holding the row opens, in plain sight. Not shown while
    /// ticking sets.
    private func rowMoreMenu(_ set: StudySet) -> some View {
        let spoken: String = "More for \(set.name)"
        return Menu {
            rowMenu(set)
        } label: {
            moreMenuFace
        }
        // its own control inside the row, not a tap on the row
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel(spoken)
    }

    /// The face of a "more" menu - a row's, a folder's: an ellipsis on a
    /// small soft disc raised off the row, inside a 44-point target.
    var moreMenuFace: some View {
        let disc = Circle()
        return Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.wardInkSecondary)
            .frame(width: 34, height: 34)
            .wardRaised(in: disc, lift: .low)
            .frame(width: 44, height: 44)
            .contentShape(disc)
    }

    /// An empty library: what the app does in one sentence, one big button
    /// to start, and two quiet links for anyone who wants to look around
    /// first. A card at the top of the page rather than the whole page, so
    /// the category's ways to practise are still there under it.
    var emptyState: some View {
        VStack(spacing: 14) {
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .osce], id: \.self) { kind in
                    fannedTile(kind)
                }
            }
            .accessibilityHidden(true)
            Text("Make your first set").font(.title2.weight(.bold))
            Text("Add a lecture and \(Brand.name) turns it into questions or flashcards to study.")
                .font(.body)
                .foregroundStyle(Color.wardInkSecondary)
                .multilineTextAlignment(.center)
            Button { newSetKind = category.mainKind } label: {
                Label("New set", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 280, minHeight: 44)
            }
            .buttonStyle(WardButtonStyle(kind: .primary, fills: false))
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityHint("Make questions or cards from a lecture")
            .accessibilityIdentifier("newSetButton")
            // the rest of the app is there from the start, not only once
            // something has been made
            HStack(spacing: 16) {
                Button { support = .sources } label: {
                    Label("Your lectures", systemImage: "doc.richtext")
                }
                Button { support = .help } label: {
                    Label("How it works", systemImage: "questionmark.app")
                }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("emptyLibraryLinks")
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    /// One of the empty library's three fanned tiles, so the fan reads as
    /// three cards held in the hand.
    private func fannedTile(_ kind: StudySetKind) -> some View {
        let plane: PopOutPlane = LibraryView.fanPlane(kind)
        let angle: Double = LibraryView.fanAngle(kind)
        let layer: Double = Double(plane.rawValue)
        // the tile is raised already; a second shadow would muddy its own
        return ModeTile(kind: kind, size: 52)
            .rotationEffect(.degrees(angle))
            // drawn in the order of their heights, so a higher tile is never
            // covered by a lower one where they overlap
            .zIndex(layer)
    }

    /// The fan: questions to the left, cards upright in the middle, stations
    /// to the right.
    static func fanAngle(_ kind: StudySetKind) -> Double {
        switch kind {
        case .anki: return 0
        case .mcq: return -10
        default: return 10
        }
    }

    /// The middle tile highest, the right one next, the left one lowest.
    static func fanPlane(_ kind: StudySetKind) -> PopOutPlane {
        switch kind {
        case .anki: return .hero
        case .osce: return .floating
        default: return .raised
        }
    }
}

/// A selection bar action's face: its name and symbol, or the symbol alone
/// (still named for VoiceOver), at least 44 points tall with the button.
private struct ActionLabel: View {
    let title: String
    let symbol: String
    let compact: Bool

    var body: some View {
        if compact {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: 22, minHeight: 30)
        } else {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .frame(minHeight: 30)
        }
    }
}
