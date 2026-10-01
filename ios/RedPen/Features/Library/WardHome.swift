import SwiftUI

// The library's home in the Ward Round language (docs/design/targets-2026-10-01.md
// §1). Every category's page opens with the date, the app's name and a
// greeting, in place of a large title. On Questions, the page the app opens
// on, today's ward round follows: a card of beds (BedPlan), each a tap into
// what it holds, and one button that starts the first; then two tiles, Vitals
// and the brain map. The round also stands on Cards while cards are due, where
// the Today card stood. The sets come after, each with how far into it the
// student is.
//
// Everything a bed opens already had a way in from the library: the due
// cards, a subject's drill, a set, a station, or the exam-week planner's
// session (LibraryView.launch). Nothing here is stored.

// MARK: - The exam the countdowns name

/// The exam date and name kept by Settings → Your exam, as the home and the
/// Vitals screen count down to them.
enum ExamCountdown {
    /// The chosen exam's short name; the track's when no one exam is chosen;
    /// nil for general revision, which the countdown calls finals.
    static var examName: String? {
        if let exam = ExamChoice.current { return exam.shortName }
        let track: ExamTrack = ExamTrack.current
        return track == .general ? nil : track.rawValue.uppercased()
    }

    /// Days until the exam, or nil when no date is set.
    static func daysLeft(now: Date = Date()) -> Int? {
        guard let exam = ExamCap.storedDate() else { return nil }
        return ExamWeekPlanner.daysLeft(to: exam, now: now)
    }

    /// "Finals in 23 days"; nil with no date, or once it has passed.
    static func text(now: Date = Date()) -> String? {
        WardWords.countdown(days: daysLeft(now: now), exam: examName)
    }
}

// MARK: - The home's sections

extension LibraryView {

    /// The date, the name, a greeting and the countdown, as the page's first
    /// row - its title.
    var homeHeaderSection: some View {
        let now: Date = Date()
        let hour: Int = Calendar.current.component(.hour, from: now)
        let greeting: String = WardWords.greeting(hour: hour, name: account.account?.displayName)
        let header = HomeHeader(date: now, greeting: greeting, countdown: ExamCountdown.text(now: now))
        return Section { homeRow(header) }
    }

    /// The round on Questions whenever the library holds anything, and on
    /// Cards while cards are due.
    var showsRound: Bool {
        guard !searching, !store.library.isEmpty else { return false }
        if category == .questions { return true }
        return category == .cards && !reviews.dueAcross(store.library).isEmpty
    }

    /// Today's ward round, and on Questions the two tiles under it.
    @ViewBuilder
    var homeRoundSections: some View {
        if showsRound {
            let due: [ReviewPlan.Due] = reviews.dueAcross(store.library)
            Section { homeRow(roundCard(due: due)) }
            if category == .questions {
                Section { homeRow(homeTiles(due: due.count)) }
            }
        }
    }

    /// A row the home's cards sit in: the page's gutter, nothing behind.
    private func homeRow<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func roundCard(due: [ReviewPlan.Due]) -> some View {
        let input: BedPlan.Input = bedInput(due: due)
        let beds: [BedPlan.Bed] = BedPlan.beds(input)
        let note: String? = input.phase.holdsNewMaterial ? input.phase.headline : nil
        return HomeRoundCard(beds: beds, note: note,
                             onOpen: { bed in openBed(bed) },
                             onPlan: { LearnRouter.shared.open(.examPlan) })
    }

    private func homeTiles(due: Int) -> some View {
        let readiness: ReadinessEstimate? = store.readiness(dueCards: due)
        let days: [String: Int] = StudyDays.merged(log: studyLog.days, answers: store.answerLog,
                                                   version: store.changeCount)
        let rhythm: RhythmReading.Reading = RhythmReading.read(days: days, now: Date())
        let map: (ideas: Int, links: Int) = BrainMapCount.counts(noteStore)
        return HomeTiles(readiness: readiness, streak: studyLog.streak, rhythm: rhythm,
                         ideas: map.ideas, links: map.links,
                         onVitals: { support = .analytics },
                         onIdeas: { goToIdeas() })
    }

    // MARK: what the round is made from

    /// Everything BedPlan weighs, read from the library.
    func bedInput(due: [ReviewPlan.Due]) -> BedPlan.Input {
        let track: ExamTrack = ExamTrack.current
        let situation: ExamWeekPlanner.Situation = store.cachedSituation(dueCards: due.count)
        var input = BedPlan.Input()
        input.mission = ExamWeekPlanner.mission(situation)
        input.phase = situation.phase
        input.dueCards = due.count
        input.dueFrom = dueSubjects(due)
        input.topics = store.subjectStats().map { stats in
            BedPlan.Topic(name: stats.subject, questions: stats.questions,
                          answered: stats.answered, correct: stats.correct)
        }
        input.fresh = freshSets()
        input.stations = roundStations()
        input.untried = situation.untried
        input.secondsPerQuestion = track.secondsPerQuestion
        input.stationMinutes = track.stationMinutes
        input.mockMinutes = ExamWeekPlanner.paper(for: track).minutes
        return input
    }

    /// The subjects the due cards come from, most cards first: a deck's
    /// subject, or its name when it has none.
    private func dueSubjects(_ due: [ReviewPlan.Due]) -> [String] {
        var label: [UUID: String] = [:]
        for set in store.library where set.kind == .anki {
            let subject: String = Store.subjectName(set)
            label[set.id] = subject == "General" ? set.name : subject
        }
        var counts: [String: Int] = [:]
        for item in due {
            let name: String = label[item.setID] ?? item.setName
            counts[name, default: 0] += 1
        }
        let order: [(key: String, value: Int)] = counts.sorted { a, b in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }
        return order.map { $0.key }
    }

    /// Sets nothing has been done in yet, in the modes a bed can hold.
    private func freshSets() -> [BedPlan.FreshSet] {
        var out: [BedPlan.FreshSet] = []
        for set in store.library {
            guard let mode = LibraryView.bedMode(set.kind), !started(set) else { continue }
            out.append(BedPlan.FreshSet(id: set.id, name: set.name, subject: set.subject, mode: mode,
                                        items: set.itemCount, createdAt: set.createdAt))
        }
        return out
    }

    /// The modes a set can take a bed in.
    static func bedMode(_ kind: StudySetKind) -> BedPlan.Mode? {
        switch kind {
        case .mcq: return .questions
        case .anki: return .cards
        case .book: return .textbook
        default: return nil
        }
    }

    /// Each OSCE set's station, the one opening the set lands on: where it
    /// was left (OsceReviewView resumes there), or the first.
    private func roundStations() -> [BedPlan.Station] {
        var out: [BedPlan.Station] = []
        for set in store.library where set.kind == .osce {
            guard let first = set.osceChecklists.first else { continue }
            var title: String = first.title
            var resumes: Bool = false
            if let saved = store.osceProgress[set.id], saved.fits(set.osceChecklists) {
                title = set.osceChecklists[saved.checklistIndex].title
                resumes = true
            }
            out.append(BedPlan.Station(setID: set.id, title: title, resumes: resumes, createdAt: set.createdAt))
        }
        return out
    }

    /// Whether anything has been done in a set yet.
    func started(_ set: StudySet) -> Bool {
        if store.quizProgress[set.id] != nil || store.readingProgress[set.id] != nil { return true }
        let done: Double = progress(of: set) ?? 0
        return done > 0
    }

    /// How far into a set the student is, 0...1: questions answered at least
    /// once, cards reviewed, the page reached, the step reached in a station.
    /// Nil for a lecture, which keeps no place.
    func progress(of set: StudySet) -> Double? {
        let total: Int = set.itemCount
        guard total > 0 else { return nil }
        let done: Int
        switch set.kind {
        case .mcq:
            done = set.questions.filter { !(store.answerHistory[$0.id] ?? []).isEmpty }.count
        case .anki:
            done = set.cards.filter { (reviews.records[$0.id]?.reviews ?? 0) > 0 }.count
        case .osce:
            done = osceStepsDone(set)
        case .narrate:
            return nil
        default:
            // a textbook's page, or a card read in order
            done = store.readingProgress[set.id]?.position ?? 0
        }
        return min(1, Double(done) / Double(total))
    }

    private func osceStepsDone(_ set: StudySet) -> Int {
        guard let saved = store.osceProgress[set.id], saved.fits(set.osceChecklists) else { return 0 }
        let before: Int = set.osceChecklists.prefix(saved.checklistIndex).reduce(0) { $0 + $1.steps.count }
        return before + saved.stepIndex
    }

    // MARK: what a bed opens

    func openBed(_ bed: BedPlan.Bed) {
        switch bed.kind {
        case .priority(let mission):
            launch(mission)
        case .dueCards:
            showingDue = true
        case .weakest(let topic):
            let drill: StudySet = store.drill(subject: topic.name)
            if !drill.questions.isEmpty { quickQuiz = drill }
        case .freshSet(let fresh):
            openSet(fresh.id)
        case .station(let station):
            openSet(station.setID)
        }
    }

    private func openSet(_ id: UUID) {
        guard let set = store.library.first(where: { $0.id == id }) else { return }
        opened.append(set)
    }
}

// MARK: - The header

/// The top of a category's page, in place of a large title: the date in
/// small caps, the app's name with a squiggle of ECG beside it, a greeting,
/// and the countdown to the exam when there is a date.
struct HomeHeader: View {
    let date: Date
    let greeting: String
    let countdown: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .wardSmallCaps()
            nameLine
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
            if let countdown {
                WardPill(text: countdown, symbol: "calendar")
                    .padding(.top, WardSpace.xs)
            }
        }
        .padding(.top, WardSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameLine: some View {
        HStack(alignment: .center, spacing: WardSpace.s) {
            Text(Brand.name)
                .font(WardType.display)
                .foregroundStyle(Color.wardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            EcgSquiggle()
                .stroke(Color.wardEcg, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 34, height: 18)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Today's ward round

/// The round's card: its heading with how many patients and how long, the
/// way into the exam plan, a row per bed, and the button that starts bed 1.
struct HomeRoundCard: View {
    let beds: [BedPlan.Bed]
    /// The exam-week line, while new material is held back.
    let note: String?
    let onOpen: (BedPlan.Bed) -> Void
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.m) {
            heading
            if beds.isEmpty {
                quiet
            } else {
                bedRows
                if let note { noteLine(note) }
                startButton
            }
        }
        .wardCard()
    }

    private var heading: some View {
        HStack(alignment: .firstTextBaseline, spacing: WardSpace.s) {
            Text("Today\u{2019}s ward round \u{00B7} " + BedPlan.summary(beds))
                .wardSmallCaps()
                .accessibilityLabel(BedPlan.spokenSummary(beds))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: WardSpace.s)
            planButton
        }
    }

    private var planButton: some View {
        Button(action: onPlan) {
            Label("Plan", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.wardPrimaryInk)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint("Opens the exam plan and forecast")
        .accessibilityIdentifier("missionPlan")
    }

    private var quiet: some View {
        Label("All done for now \u{2014} nothing is waiting.", systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(Color.wardInkSecondary)
    }

    private var bedRows: some View {
        VStack(spacing: 0) {
            ForEach(beds) { bed in
                bedButton(bed)
                if bed.id != beds.last?.id {
                    Rectangle()
                        .fill(Color.wardHairline)
                        .frame(height: 1)
                        .padding(.leading, 52)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func bedButton(_ bed: BedPlan.Bed) -> some View {
        Button { onOpen(bed) } label: {
            WardRow(symbol: HomeRoundCard.symbol(bed), tone: HomeRoundCard.tone(bed),
                    overline: bed.overline, title: bed.title, detail: bed.detail,
                    chip: HomeRoundCard.chip(bed))
        }
        .buttonStyle(.pressableRow)
        .accessibilityLabel(bed.spoken)
        .accessibilityHint("Opens this bed")
        .accessibilityIdentifier("wardBed-\(bed.number)")
    }

    private func noteLine(_ text: String) -> some View {
        Label(text, systemImage: "moon.stars")
            .font(.footnote)
            .foregroundStyle(Color.wardInkSecondary)
    }

    private var startButton: some View {
        let first: BedPlan.Bed? = beds.first
        let hint: String = first.map { "Starts with bed 1: " + $0.title } ?? ""
        return Button {
            if let first { onOpen(first) }
        } label: {
            Label("Start ward round", systemImage: "bolt.fill")
        }
        .buttonStyle(.wardPrimary)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHint(hint)
        .accessibilityIdentifier("missionLiftOff")
    }

    // MARK: each bed's icon and chip

    static func symbol(_ bed: BedPlan.Bed) -> String {
        switch bed.kind {
        case .priority(let mission): return mission.symbol
        case .dueCards: return StudySetKind.anki.symbol
        case .weakest: return "target"
        case .freshSet(let set): return modeKind(set.mode).symbol
        case .station: return StudySetKind.osce.symbol
        }
    }

    static func tone(_ bed: BedPlan.Bed) -> WardTone {
        switch bed.kind {
        case .priority(let mission):
            switch mission {
            case .examKit, .mock: return .warning
            default: return .blue
            }
        case .dueCards: return .red
        case .weakest: return .danger
        case .freshSet(let set):
            switch set.mode {
            case .questions: return .blue
            case .cards: return .red
            case .textbook: return .green
            }
        case .station: return .warning
        }
    }

    /// The chip's words and tone: every tone here keeps its text at AA on
    /// the chip's wash (Caution Amber, Theatre Blue, Resus Red).
    static func chip(_ bed: BedPlan.Bed) -> (text: String, tone: WardTone)? {
        guard let status = bed.status else { return nil }
        let tone: WardTone
        switch status {
        case .due, .timed, .today: tone = .warning
        case .new: tone = .blue
        case .weak: tone = .danger
        }
        return (text: status.rawValue, tone: tone)
    }

    private static func modeKind(_ mode: BedPlan.Mode) -> StudySetKind {
        switch mode {
        case .questions: return .mcq
        case .cards: return .anki
        case .textbook: return .book
        }
    }
}

// MARK: - Vitals and the brain map

/// The two tiles under the round, side by side (one above the other at the
/// largest text sizes): Vitals opens the Vitals screen, the brain map Ideas.
struct HomeTiles: View {
    let readiness: ReadinessEstimate?
    let streak: Int
    let rhythm: RhythmReading.Reading
    let ideas: Int
    let links: Int
    let onVitals: () -> Void
    let onIdeas: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: WardSpace.m) {
                vitals
                brainMap
            }
        } else {
            HStack(alignment: .top, spacing: WardSpace.m) {
                vitals
                brainMap
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vitals: some View {
        Button(action: onVitals) {
            VitalsTileFace(readiness: readiness, streak: streak, rhythm: rhythm)
        }
        .buttonStyle(.pressableRow)
        .accessibilityLabel(vitalsSpoken)
        .accessibilityHint("Opens Vitals")
        .accessibilityIdentifier("homeVitals")
    }

    private var brainMap: some View {
        Button(action: onIdeas) {
            BrainMapTileFace(line: brainLine)
        }
        .buttonStyle(.pressableRow)
        .accessibilityLabel("Brain map. " + brainLine)
        .accessibilityHint("Opens Ideas: the idea dump, its board and the 3D map")
        .accessibilityIdentifier("homeBrainMap")
    }

    private var vitalsSpoken: String {
        var parts: [String] = ["Vitals"]
        if let readiness {
            parts.append("Readiness \(Int((readiness.center * 100).rounded())) percent")
        } else {
            parts.append("Readiness not estimated yet")
        }
        parts.append(VitalsTileFace.streakText(streak))
        parts.append(rhythm.spoken)
        return parts.joined(separator: ". ")
    }

    /// "128 ideas · 6 links", or what the map is while it is empty.
    private var brainLine: String {
        guard ideas > 0 else { return "Your ideas, joined up on a map" }
        var line: String = BedPlan.counted(ideas, "idea")
        if links > 0 { line += " \u{00B7} " + BedPlan.counted(links, "link") }
        return line
    }
}

/// The Vitals tile: the readiness ring, the streak with a heart, and the last
/// two weeks as a rhythm strip.
private struct VitalsTileFace: View {
    let readiness: ReadinessEstimate?
    let streak: Int
    let rhythm: RhythmReading.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            Text("Vitals").wardSmallCaps()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WardSpace.m) {
                    ring
                    figures
                }
                VStack(alignment: .leading, spacing: WardSpace.s) {
                    ring
                    figures
                }
            }
            RhythmTrace(beats: rhythm.beats)
                .stroke(Color.wardEcg, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(height: 18)
                .accessibilityHidden(true)
        }
        .homeTile()
    }

    private var ring: some View {
        let centre: String? = readiness == nil ? "\u{2013}" : nil
        return WardRing(value: readiness?.center ?? 0, tone: .amber, lineWidth: 6, centre: centre)
            .frame(width: 56, height: 56)
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Readiness")
                .font(.caption)
                .foregroundStyle(Color.wardInkSecondary)
            Label {
                Text(VitalsTileFace.streakText(streak))
            } icon: {
                Image(systemName: "heart.fill").foregroundStyle(Color.wardEcg)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.wardInk)
        }
    }

    static func streakText(_ streak: Int) -> String {
        streak > 0 ? "\(streak)-day streak" : "No streak yet"
    }
}

/// The brain map tile: a small node graph and the count of ideas.
private struct BrainMapTileFace: View {
    let line: String

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            Text("Brain map").wardSmallCaps()
            NodeGlyph()
                .frame(width: 72, height: 48)
                .accessibilityHidden(true)
            Text(line)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.wardInk)
                .multilineTextAlignment(.leading)
        }
        .homeTile()
    }
}

/// The brain map tile's numbers: the notes, and the links between them,
/// counted again only when the notes change rather than on every redraw.
@MainActor
enum BrainMapCount {
    private static var memo: (key: String, ideas: Int, links: Int)?

    static func counts(_ notes: NoteStore) -> (ideas: Int, links: Int) {
        let all: [Note] = notes.notes
        let latest: Double = all.map { $0.updatedAt.timeIntervalSince1970 }.max() ?? 0
        let key: String = "\(all.count)-\(latest)"
        if let saved = memo, saved.key == key { return (ideas: saved.ideas, links: saved.links) }
        let links: Int = notes.allEdges().count
        memo = (key: key, ideas: all.count, links: links)
        return (ideas: all.count, links: links)
    }
}

/// The days studied as the Vitals screen counts them (RhythmReading.merged:
/// the study log with the dated answers), worked out again only when either
/// changes rather than on every redraw of the home.
@MainActor
enum StudyDays {
    private static var memo: (key: String, days: [String: Int])?

    static func merged(log: [String: Int], answers: [AnswerEvent], version: Int) -> [String: Int] {
        let total: Int = log.values.reduce(0, +)
        let key: String = "\(version)-\(log.count)-\(total)"
        if let saved = memo, saved.key == key { return saved.days }
        let dates: [Date] = answers.map { $0.date }
        let days: [String: Int] = RhythmReading.merged(log: log, answers: dates)
        memo = (key: key, days: days)
        return days
    }
}

extension View {
    /// A tile on the home: a card filling its share of the row, so two side
    /// by side stand the same height.
    func homeTile() -> some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        return self
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.wardSurface, in: shape)
            .overlay(shape.strokeBorder(Color.wardHairline, lineWidth: 1))
            .wardShadow()
            .contentShape(shape)
    }
}

// MARK: - The small drawings

/// A rhythm strip: a beat for each day studied and a flat line for each day
/// off (RhythmReading.beats), oldest on the left. Decoration: whatever shows
/// it says the rhythm in words for VoiceOver.
struct RhythmTrace: Shape {
    let beats: [Bool]

    func path(in rect: CGRect) -> Path {
        // one complex, as fractions of a day's width and the strip's height
        // (EcgSquiggle's shape)
        let complex: [(CGFloat, CGFloat)] = [
            (0.30, 0), (0.36, -0.12), (0.42, 0), (0.48, 0.10), (0.54, -0.50),
            (0.60, 0.30), (0.66, 0), (0.78, -0.14), (0.88, 0),
        ]
        var path = Path()
        let count: Int = max(beats.count, 1)
        let step: CGFloat = rect.width / CGFloat(count)
        let mid: CGFloat = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: mid))
        for (index, beat) in beats.enumerated() {
            let start: CGFloat = rect.minX + CGFloat(index) * step
            if beat {
                for point in complex {
                    path.addLine(to: CGPoint(x: start + point.0 * step, y: mid + point.1 * rect.height))
                }
            }
            path.addLine(to: CGPoint(x: start + step, y: mid))
        }
        return path
    }
}

/// A small node graph: five ideas and the links between them, the middle
/// one in Pager Amber.
struct NodeGlyph: View {
    var body: some View {
        Canvas { context, size in
            // the ideas, as fractions of the glyph, and which are joined
            let nodes: [(CGFloat, CGFloat)] = [(0.46, 0.52), (0.10, 0.20), (0.14, 0.84), (0.86, 0.16), (0.90, 0.80)]
            let links: [(Int, Int)] = [(0, 1), (0, 2), (0, 3), (0, 4), (3, 4), (1, 2)]
            let points: [CGPoint] = nodes.map { node in
                CGPoint(x: node.0 * size.width, y: node.1 * size.height)
            }
            var lines = Path()
            for link in links {
                lines.move(to: points[link.0])
                lines.addLine(to: points[link.1])
            }
            context.stroke(lines, with: .color(Color.wardPrimaryInk.opacity(0.45)), lineWidth: 1.5)
            for (index, point) in points.enumerated() {
                let radius: CGFloat = index == 0 ? 6 : 4
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                let colour: Color = index == 0 ? Color.wardBeam : Color.wardPrimaryInk
                context.fill(Path(ellipseIn: rect), with: .color(colour))
            }
        }
    }
}

// MARK: - A set's row

/// A set in the library: its mode's icon, the name and its exam, "MCQ · 42
/// questions", how far into it the student is as a bar with the percentage,
/// and the cards due for a deck with some waiting.
struct SetRow: View {
    let set: StudySet
    /// Cards due now, for a deck.
    let due: Int
    /// 0...1, or nil for a mode that keeps no place.
    let progress: Double?

    var body: some View {
        HStack(alignment: .top, spacing: WardSpace.m) {
            ModeTile(kind: set.kind, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                nameLine
                kindLine
                if let progress { progressLine(progress) }
            }
            Spacer(minLength: 0)
            if due > 0 {
                WardChip(text: "\(due) due", tone: .warning)
            }
        }
        .padding(.vertical, 2)
        // a whole row to aim at, not only its words
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var nameLine: some View {
        HStack(spacing: 6) {
            Text(set.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.wardInk)
                .lineLimit(2)
            // the exam it was written for
            ExamBadge(examId: set.exam)
        }
    }

    private var kindLine: some View {
        let plural: String = set.itemCount == 1 ? "" : "s"
        let amount: String = "\(set.itemCount) \(set.itemNoun)\(plural)"
        let subject: String = set.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsSubject: Bool = !subject.isEmpty && subject != "General"
        return HStack(spacing: 6) {
            Text(set.kind.label).font(.caption.weight(.semibold))
            separator
            Text(amount).font(.caption)
            if showsSubject {
                separator
                Text(subject).font(.caption).lineLimit(1)
            }
            // flagged or to check, once anything in it is checked
            AccuracySetMark(set: set)
        }
        .foregroundStyle(Color.wardInkSecondary)
    }

    private var separator: some View {
        Text("\u{00B7}").font(.caption).accessibilityHidden(true)
    }

    private func progressLine(_ value: Double) -> some View {
        let percent: Int = Int((max(0, min(1, value)) * 100).rounded())
        return HStack(spacing: WardSpace.s) {
            EcgStrip(progress: value)
                .frame(maxWidth: 160)
            Text("\(percent)%")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Color.wardInkSecondary)
                .accessibilityLabel("\(percent) percent done")
        }
    }
}
