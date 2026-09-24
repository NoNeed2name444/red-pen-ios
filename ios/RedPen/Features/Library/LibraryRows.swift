import SwiftUI

/// Everything the library draws for one row or one strip.
///
/// Split out of LibraryView because that file had grown to the point where
/// changing one thing meant re-reading four hundred lines to find it, and
/// because SwiftUI type-checks a whole view expression at once.
extension LibraryView {

    /// Days until the exam set in AI models → Your exam, or nil when no date
    /// has been set.
    var examDays: Int? {
        let stamp = UserDefaults.standard.double(forKey: ExamTrack.dateKey)
        guard stamp > 0 else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()),
                                        to: calendar.startOfDay(for: Date(timeIntervalSince1970: stamp))).day ?? 0
    }

    /// Whether there is anything for the Today card to say. A first launch
    /// with nothing scheduled is not greeted by a card full of zeros.
    var hasTodayCard: Bool {
        examDays != nil || studyLog.streak > 0
            || store.library.contains { $0.kind == .anki } || !store.flaggedQuestions.isEmpty
    }

    /// Today, in one card: the exam, the streak and what is waiting, at most
    /// three short lines, and one button for the most useful thing to do next.
    ///
    /// These used to be four separate strips - countdown, streak, due cards,
    /// flagged questions - stacked above the sets, so the first screen was a
    /// dashboard before it was a library. The count of due cards still matters
    /// most: twenty lectures means twenty decks, and without a number on the
    /// first screen nobody knows which of them is waiting.
    ///
    /// It stands a little out of the glass as one raised slab - it holds the
    /// page's most useful button - while the rows below lie flat on it.
    var todayCard: some View {
        let due = reviews.dueAcross(store.library).count
        let hasDecks = store.library.contains { $0.kind == .anki }
        let flagged = store.flaggedQuestions
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today").font(.headline)
            if let days = examDays { examLine(days) }
            if studyLog.streak > 0 { streakLine }
            if hasDecks || !flagged.isEmpty {
                dueLine(due: due, hasDecks: hasDecks, flagged: flagged.count)
            }
            todayAction(due: due, flagged: flagged.count)
        }
        .padding(16)
        .background(.regularMaterial, in: shape)
        .popOut(.raised, in: shape)
    }

    /// The Today card's one button - due cards first, because the schedule
    /// only works if they are done today; otherwise the flagged questions -
    /// and, below it, the quieter extras.
    @ViewBuilder
    private func todayAction(due: Int, flagged: Int) -> some View {
        if due > 0 {
            let plural: String = due == 1 ? "" : "s"
            let title: String = "Study \(due) due card\(plural)"
            todayButton(title, symbol: "play.fill") { showingDue = true }
        } else if flagged > 0 {
            todayButton(flaggedTitle(flagged), symbol: "flag.fill") { startFlaggedQuiz() }
        }
        // With cards due the flagged quiz is still one tap away, just
        // quieter than the main button.
        if due > 0 && flagged > 0 {
            Button { startFlaggedQuiz() } label: {
                Text(verbatim: "Or \(flaggedTitle(flagged).lowercased())")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderless)
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

    private func flaggedTitle(_ count: Int) -> String {
        let plural: String = count == 1 ? "" : "s"
        return "Practise \(count) flagged question" + plural
    }

    private func todayButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .popOut(.hero, in: Capsule(), tint: .accentColor)
        .padding(.top, 8)
    }

    /// "43 days to PLAB · about 12 questions a day".
    private func examLine(_ days: Int) -> some View {
        let questions = store.library.filter { $0.kind == .mcq }.reduce(0) { $0 + $1.questions.count }
        let exam = ExamTrack.current
        let examName = exam == .general ? "your exam" : exam.title
        var text: String
        if days > 0 {
            let plural: String = days == 1 ? "" : "s"
            text = "\(days) day\(plural) to \(examName)"
            if questions > 0 {
                let share: Double = Double(questions) / Double(days)
                let perDay: Int = Int(share.rounded(.up))
                text += " \u{00B7} about \(perDay) questions a day"
            }
        } else if days == 0 {
            text = "Exam day \u{2014} good luck"
        } else {
            text = "Your exam date has passed"
        }
        return todayLine(symbol: "calendar", tint: .accentColor, text: text)
    }

    /// "5-day streak · 32 done today", or a nudge while the streak is still
    /// yesterday's and alive until midnight.
    private var streakLine: some View {
        let streak = studyLog.streak
        let today = studyLog.today
        let text: String = today > 0 ? "\(streak)-day streak \u{00B7} \(today) done today"
                                     : "\(streak)-day streak \u{2014} answer one to keep it"
        let tint: Color = today > 0 ? .orange : .secondary
        return todayLine(symbol: "flame.fill", tint: tint, text: text)
    }

    /// "12 cards due · 4 flagged".
    private func dueLine(due: Int, hasDecks: Bool, flagged: Int) -> some View {
        var parts: [String] = []
        if hasDecks {
            let plural: String = due == 1 ? "" : "s"
            parts.append(due > 0 ? "\(due) card\(plural) due" : "No cards due")
        }
        if flagged > 0 { parts.append("\(flagged) flagged") }
        let symbol: String = due > 0 ? "tray.full.fill" : "checkmark.circle.fill"
        let tint: Color = due > 0 ? StudySetKind.anki.tint : .secondary
        return todayLine(symbol: symbol, tint: tint, text: parts.joined(separator: " \u{00B7} "))
    }

    /// One line of the Today card: a symbol and a short sentence.
    private func todayLine(symbol: String, tint: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(2)
            Spacer(minLength: 0)
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
                            .foregroundStyle(selected.contains(set.id) ? Color.accentColor : Color.secondary)
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
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        // frosted, so the backdrop shows through while the row stays easy
        // to read
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

    /// The floating action bar shown in selection mode: one glass slab like
    /// the dock, in the dock's place. Done at the leading end; Move, Quiz and
    /// Combine, then Delete last, at the trailing end, and it asks first.
    var selectionBar: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        // the buttons' glass in a container of its own, as the dock's is, so
        // it is drawn as glass on the slab rather than sampling the slab
        return GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                selectionDoneButton
                selectionCount
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    selectionActions(compact: false)
                    selectionActions(compact: true)
                }
            }
            .padding(10)
        }
        .liquidGlassPanel(cornerRadius: 28)
        .popOut(.floating, in: shape)
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
            .foregroundStyle(.secondary)
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
        .buttonStyle(.glass)
        .disabled(selected.isEmpty)
    }

    private func quizButton(compact: Bool) -> some View {
        Button { startMixedQuiz() } label: {
            ActionLabel(title: "Quiz", symbol: "shuffle", compact: compact)
        }
        .buttonStyle(.glass)
        .disabled(!canMixQuiz)
    }

    private func combineButton(compact: Bool) -> some View {
        Button { naming = .combine } label: {
            ActionLabel(title: "Combine", symbol: "square.stack.3d.down.forward", compact: compact)
        }
        .buttonStyle(.glassProminent)
        .disabled(!canCombine)
    }

    /// Last, at the trailing end, away from Combine's glow by the bar's own
    /// order; it asks first unless "Ask before deleting a set" is off.
    private func deleteSelectedButton(compact: Bool) -> some View {
        Button(role: .destructive) { delete(Array(selected)) } label: {
            ActionLabel(title: "Delete", symbol: "trash", compact: compact)
                .foregroundStyle(.red)
        }
        .buttonStyle(.glass)
        .disabled(selected.isEmpty)
    }

    func setRow(_ set: StudySet) -> some View {
        let due = set.kind == .anki ? reviews.dueCount(for: set.cards) : 0
        let plural: String = set.itemCount == 1 ? "" : "s"
        let amount: String = "\(set.itemCount) \(set.itemNoun)\(plural)"
        return HStack(spacing: 16) {
            ModeTile(kind: set.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(set.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\u{00b7}").foregroundStyle(.tertiary)
                    Text(amount)
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
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(StudySetKind.anki.tint, in: Capsule())
                    .accessibilityLabel("\(due) due")
            }
        }
        // a whole row to aim at, not only its words
        .frame(minHeight: 56)
        .contentShape(Rectangle())
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
    /// small glass disc that stands a little out of the glass like any other
    /// control, inside a 44-point target.
    var moreMenuFace: some View {
        let disc = Circle()
        return Image(systemName: "ellipsis")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .glassEffect(.regular.interactive(), in: disc)
            .popOut(.raised, in: disc)
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
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    fannedTile(kind)
                }
            }
            .accessibilityHidden(true)
            Text("Make your first set").font(.title2.weight(.bold))
            Text("Add a lecture and \(Brand.name) turns it into questions, flashcards or cases to study.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { newSetKind = category.mainKind } label: {
                Label("New set", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 280, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .popOut(.hero, in: Capsule(), tint: .accentColor)
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

    /// One of the empty library's three fanned tiles, each at its own height
    /// out of the glass, so the fan reads as three cards held up in the air.
    ///
    /// Lifted before it is turned, so the slab side and the sheen are turned
    /// with the tile and stay the tile's own shape.
    private func fannedTile(_ kind: StudySetKind) -> some View {
        let corner: CGFloat = 52 * 0.28
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let plane: PopOutPlane = LibraryView.fanPlane(kind)
        let angle: Double = LibraryView.fanAngle(kind)
        let layer: Double = Double(plane.rawValue)
        return ModeTile(kind: kind, size: 52)
            .popOut(plane, in: shape)
            .rotationEffect(.degrees(angle))
            // drawn in the order of their heights, so a higher tile is never
            // covered by a lower one where they overlap
            .zIndex(layer)
    }

    /// The fan: questions to the left, cards upright in the middle, cases to
    /// the right.
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
        case .qa: return .floating
        default: return .raised
        }
    }
}

/// A selection bar action's face: its name and symbol, or the symbol alone
/// (still named for VoiceOver), at least 44 points tall with the glass.
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
