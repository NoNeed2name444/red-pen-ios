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
            // where the header ends, for the grid band under it
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { y in
                bandTrack.header(y)
            }
        return Section { homeRow(header) }
    }

    /// The round on Questions whenever the library holds anything, and on
    /// Cards while cards are due.
    var showsRound: Bool {
        guard !searching, !store.library.isEmpty else { return false }
        if category == .questions { return true }
        return category == .cards && !dueNow().isEmpty
    }

    /// Today's ward round, and on Questions the two tiles under it.
    @ViewBuilder
    var homeRoundSections: some View {
        if showsRound {
            let due: [ReviewPlan.Due] = dueNow()
            // the card and the tiles stand as low as the rows below them,
            // so the cell never cuts their lights
            Section { roundCard(due: due).launchEntrance(inOpening: true).wardCardRow() }
            if category == .questions {
                Section { homeTiles(due: due.count).launchEntrance(inOpening: true).wardCardRow() }
            }
        }
    }

    /// The row the page's title sits in: the page's gutter, nothing behind,
    /// nothing under it but the band's edge and the sections' spacing.
    private func homeRow<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// The cards due across the library: one of home's loads, marked for a
    /// recorded opening (LaunchStage.measure).
    private func dueNow() -> [ReviewPlan.Due] {
        LaunchStage.shared.measure("due") { reviews.dueAcross(store.library) }
    }

    private func roundCard(due: [ReviewPlan.Due]) -> some View {
<<<<<<< HEAD
        let input: BedPlan.Input = bedInput(due: due)
        let all: [BedPlan.Bed] = BedPlan.beds(input)
        // a short window's round is its first beds, so the card and its
        // button end above the dock (HomeFit); Plan has the whole day
        let beds: [BedPlan.Bed] = Array(all.prefix(HomeFit.shownBeds(all.count, short: shortWindow, trimmed: bedsTrimmed)))
=======
        let input: BedPlan.Input = LaunchStage.shared.measure("plan") { bedInput(due: due) }
        let beds: [BedPlan.Bed] = BedPlan.beds(input)
>>>>>>> 4540bc9e
        let note: String? = input.phase.holdsNewMaterial ? input.phase.headline : nil
        return HomeRoundCard(beds: beds, note: note,
                             onOpen: { bed in openBed(bed) },
                             // at rest only: Start's global frame moves with every scroll
                             // step, and each write would re-run this whole view
                             onStartFrame: { if bandTrack.isAtRest { startFrame = $0 } },
                             onPlan: { LearnRouter.shared.open(.examPlan) })
    }

    private func homeTiles(due: Int) -> some View {
        LaunchStage.shared.measure("tiles") { homeTilesLoaded(due: due) }
    }

    private func homeTilesLoaded(due: Int) -> HomeTiles {
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
    /// The squiggle's frame, which the opening's ECG becomes (its line is
    /// LaunchOpening.squiggleLine).
    static let squiggleSize = CGSize(width: 34, height: 18)

    let date: Date
    let greeting: String
    let countdown: String?

    var body: some View {
        // at the opening's hand-off the name settles in where the stethoscope
        // goes, the squiggle is where the ECG lands, and the rest grows into
        // place around them (LaunchStage)
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .wardSmallCaps()
<<<<<<< HEAD
                // every line it wraps to, whole, at the largest sizes
                .fixedSize(horizontal: false, vertical: true)
=======
                .launchEntrance()
>>>>>>> 4540bc9e
            nameLine
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
                .launchEntrance()
            if let countdown {
                WardPill(text: countdown, symbol: "calendar")
                    .padding(.top, WardSpace.xs)
                    .launchEntrance()
            }
        }
        .padding(.top, WardSpace.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameLine: some View {
        HStack(alignment: .center, spacing: WardSpace.s) {
            Text(Brand.name)
                .font(WardType.display)
                .foregroundStyle(Color.wardInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .launchLetters()
                .launchTarget(.title)
                .accessibilityAddTraits(.isHeader)
            EcgSquiggle()
                .stroke(Color.wardEcg, style: StrokeStyle(lineWidth: CGFloat(LaunchOpening.squiggleLine),
                                                          lineCap: .round, lineJoin: .round))
                .frame(width: HomeHeader.squiggleSize.width, height: HomeHeader.squiggleSize.height)
                // drawn the moment the opening's ECG lands on it
                .launchLanding()
                .launchTarget(.squiggle)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - The grid band under the header

/// Where the home's grid band ends, in window points (WardPaperBand): the
/// header's bottom with the list at its top, less how far the list has
/// scrolled. Kept apart from LibraryView, so following a scroll redraws only
/// the band and the masthead, not the list.
@MainActor
@Observable
final class HomeBandTrack {
    /// The header's bottom with the list at its top, once seen.
    private(set) var rest: CGFloat?
    /// How far the list has scrolled from its top.
    var scroll: CGFloat = 0 {
        didSet { noteRest() }
    }
    /// The bottom of the bar area (HomeMasthead).
    var barBottom: CGFloat = 0
    @ObservationIgnored private var seen: CGFloat?
    @ObservationIgnored private var idle = true
    @ObservationIgnored private var wasAtRest = true

    /// Clear of the header's last line: the band's edge sits this far under it.
    static let belowHeader: CGFloat = 10

    var bottom: CGFloat? { rest.map { $0 - scroll + Self.belowHeader } }

    /// The list is at its top and not moving: where its rows stand is where
    /// they rest. Phase changes come before the offset's, so a row seen
    /// moving is never taken for one at rest.
    var isAtRest: Bool { idle && abs(scroll) < 1 }

    /// The header reported where its bottom is. At rest that pairs with the
    /// scroll, so it fixes where the header stands with the list at its
    /// top; while the list moves, the scroll alone moves the band.
    func header(_ y: CGFloat) {
        seen = y
        if idle || rest == nil { rest = y + scroll }
    }

    /// The list started or stopped moving. Once at rest, where the header
    /// was last seen fixes the band afresh, while the header is on screen.
    func settle(idle now: Bool) {
        idle = now
        if now, let seen, (rest ?? .infinity) - scroll > 0 { rest = seen + scroll }
        noteRest()
    }

    private func noteRest() {
        let now: Bool = isAtRest
        guard now != wasAtRest else { return }
        wasAtRest = now
        if now { WardPartBook.shared.rebook() }
    }

    /// Another page's list: at its top, its header not yet seen.
    func reset() {
        rest = nil
        seen = nil
        idle = true
        wasAtRest = true
        scroll = 0
    }
}

/// The band behind the page, from the window's top to just under the
/// header, out to the paper frame on both sides.
struct HomeBand: View {
    let track: HomeBandTrack

    var body: some View {
        if let bottom = track.bottom {
            // No ink outline: the paper's cut supplies the rounded corners
            // here (WardPaperTop), continuous with the ringless outer frame.
            WardPaperBand(bottom: bottom, edge: false)
                .padding(.horizontal, -WardPaper.sideInset)
                .ignoresSafeArea()
                .transition(.identity)
        }
    }
}

/// The bar area over the page, solid from the window's top to the list's:
/// what scrolls up passes under it and is cut there, rather than fading
/// under iOS's soft scroll edge. With the band it is the same ECG paper on
/// the same grid, and the paper's opening starts just under the band, with
/// the frame's rounded corners, rising with it as the list scrolls and
/// held at the bar's bottom once the band has gone under it
/// (WardPaperTop); without (while searching), it is the plain base, with a
/// straight edge once the list has moved.
struct HomeMasthead: View {
    let track: HomeBandTrack
    let band: Bool

    var body: some View {
        let bottom: CGFloat? = band ? track.bottom : nil
        let paperTop: CGFloat? = bottom.map { max($0, track.barBottom) }
        let edge: Bool = bottom == nil && track.scroll > 0.5
        Color.clear
            .frame(height: 0)
            .background(alignment: .bottom) {
                WardPaperBand(bottom: .greatestFiniteMagnitude, grid: bottom != nil, edge: edge)
                    .padding(.horizontal, -WardPaper.sideInset)
                    .ignoresSafeArea(edges: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { y in
                        track.barBottom = y
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: paperTop, initial: true) { _, y in WardPaperTop.shared.y = y }
            .onAppear { WardPaperTop.shared.y = paperTop }
            // a page pushed over home has the frame's own opening
            .onDisappear { WardPaperTop.shared.y = nil }
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
    /// Where Start ward round is, in global points, as it is laid out.
    var onStartFrame: (CGRect) -> Void = { _ in }
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
        // a List row: as low as the tiles round it, the button proud of it
        .wardCard(lift: .low)
        .wardPart("the round card")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            HomeFitProbe.shared.card = $0
        }
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
            // a 44-point target that takes only the words' height in the
            // heading's row, so the row is no taller than its two lines and
            // the round's button stays clear of New set
            Label("Plan", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.wardPrimaryInk)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
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
                    WardEtch().padding(.leading, 52)
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
        .wardPart("bed \(bed.number)")
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            HomeFitProbe.shared.start = $0
            onStartFrame($0)
        }
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
        case .dueCards: return .accent(.cards)
        case .weakest: return .danger
        case .freshSet(let set):
            switch set.mode {
            case .questions: return .accent(.questions)
            case .cards: return .accent(.cards)
            case .textbook: return .accent(.textbook)
            }
        case .station: return .warning
        }
    }

    /// The chip's words and tone: every tone here keeps its text at AA in
    /// the chip's well (WardPaletteTests: Caution Amber, Resus Red, and the
    /// section's accent, which is what New takes: no blue outside
    /// Questions).
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

    var body: some View { measured }

    @ViewBuilder
    private var tiles: some View {
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

    /// Where the tiles were laid out, for the preview's fit check: no
    /// sliver of them may peek over the page's cut (HomeFit).
    private var measured: some View {
        tiles.wardPart("the tiles").onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            HomeFitProbe.shared.tiles = $0
        }
    }

    private var vitals: some View {
        Button(action: onVitals) {
            VitalsTileFace(readiness: readiness, streak: streak, rhythm: rhythm)
        }
        .buttonStyle(PopTileStyle(cornerRadius: WardRadius.card, lift: .low))
        .accessibilityLabel(vitalsSpoken)
        .accessibilityHint("Opens Vitals")
        .accessibilityIdentifier("homeVitals")
    }

    private var brainMap: some View {
        Button(action: onIdeas) {
            BrainMapTileFace(line: brainLine)
        }
        .buttonStyle(PopTileStyle(cornerRadius: WardRadius.card, lift: .low))
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
            // the figures beside the ring only where they fit whole: squeezed
            // there, "No streak yet" broke inside its word ("No strea / k
            // yet"); otherwise under the ring, at the tile's full width
            ViewThatFits(in: .horizontal) {
                HStack(spacing: WardSpace.m) {
                    ring
                    figures(besideRing: true)
                }
                VStack(alignment: .leading, spacing: WardSpace.s) {
                    ring
                    figures(besideRing: false)
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

    /// Beside the ring the streak is one line at its own width, set on the
    /// text itself: a Label's icon-and-title row kept its title at the
    /// width of "Readiness" above it (18 pt of 40 for "streak") although
    /// ViewThatFits had judged the row by the title's whole width, so the
    /// row was picked and then drawn narrower than it was judged. Under
    /// the ring it takes the tile's width and may wrap between words.
    private func figures(besideRing: Bool) -> some View {
        let text: String = VitalsTileFace.streakText(streak)
        return VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text("Readiness")
                .font(.caption)
                .foregroundStyle(Color.wardInkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: WardSpace.xs) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.wardEcg)
                    .accessibilityHidden(true)
                Text(text)
                    .homeWordFit("the Vitals tile's streak", text, font: .footnote.weight(.semibold))
                    .fixedSize(horizontal: besideRing, vertical: true)
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
                .homeWordFit("the brain map's line", line, font: .footnote.weight(.semibold))
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
    /// A tile on the home, filling its share of the row, so two side by side
    /// stand the same height. Its face is its button's: a soft tile raised
    /// low off the base, pressed in under the finger (PopTileStyle).
    func homeTile() -> some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        return self
            .padding(WardSpace.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: WardSpace.xs) {
                nameLine
                kindLine
                if let progress { progressLine(progress) }
            }
            Spacer(minLength: 0)
            if due > 0 {
                WardChip(text: "\(due) due", tone: .warning)
            }
        }
        .padding(.vertical, WardSpace.xs)
        // a whole row to aim at, not only its words
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var nameLine: some View {
        HStack(spacing: WardSpace.s) {
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
        return HStack(spacing: WardSpace.s) {
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

// MARK: - The preview's fit check

/// Where home's round card, its Start button, New set, the tiles and the
/// bar at the bottom were laid out, and how wide some of home's texts are
/// beside their widest word, for the Ward preview: on the "library" screen
/// it writes HomeFit's verdict to Documents/home-fit.txt, which the workflow
/// reads after the picture and fails the run on.
@MainActor
final class HomeFitProbe {
    static let shared = HomeFitProbe()
    var card: CGRect?
    var start: CGRect?
    var newSet: CGRect?
    var bar: CGRect?
    var tiles: CGRect?
    /// Where the page was actually cut (its bottom), after the layout moved
    /// the cut up for any part (HomeFit.settledCut).
    var pageEnd: CGFloat?
    /// The text size is above the standard ones: the page may scroll.
    var large = false
    /// Each probed text's laid-out width, and its widest word's on its own.
    var widths: [String: Double] = [:]
    var widest: [String: Double] = [:]
    /// The part names (as a multiset) in the book before `-uiPreviewPushBack`
    /// pushed a set, whether the push-and-back ran, and whether it gave up
    /// with no set to open.
    var beforePush: [String] = []
    var pushLostParts = false
    var pushBackDone = false
    var pushBackNoSet = false
    var pushDropsRemoved = 0
    var pushDropsKept = 0
    var pushLastKeptCut: Double?
    var pushBookCountBefore = 0
    var pushBookCountLastLook = 0

    private static func box(_ rect: CGRect?) -> HomeFit.Box? {
        guard let rect, !rect.isEmpty else { return nil }
        return HomeFit.Box(minX: Double(rect.minX), minY: Double(rect.minY),
                           maxX: Double(rect.maxX), maxY: Double(rect.maxY))
    }

    /// Once the page has settled, the verdict, written for the workflow.
    func report() async {
        guard PreviewLaunch.screen == "library" else { return }
        do { try await Task.sleep(for: .seconds(6)) } catch { return }
        // a push and back still under way after a slow launch ends first, and
        // the page comes to rest after its pop before anything is read
        if PreviewLaunch.pushBack, !pushBackDone, !pushBackNoSet {
            for _ in 0..<350 where !pushBackDone && !pushBackNoSet {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        if PreviewLaunch.pushBack, pushBackDone {
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
        }
        let words: [HomeFit.Words] = widths.keys.sorted().compactMap { name in
            guard let width = widths[name], let word = widest[name] else { return nil }
            return HomeFit.Words(name: name, width: width, widest: word)
        }
        // every row and part that reported itself at rest (wardPart)
        let parts: [HomeFit.Part] = WardPartBook.shared.parts.values.compactMap { part in
            Self.box(part.rect).map { HomeFit.Part(name: part.name, box: $0) }
        }.sorted { ($0.box.minY, $0.name) < ($1.box.minY, $1.name) }
        var faults: [String] = HomeFit.faults(card: Self.box(card), start: Self.box(start),
                                              bar: Self.box(bar), newSet: Self.box(newSet),
                                              tiles: Self.box(tiles), large: large, words: words,
                                              pageEnd: pageEnd.map { Double($0) }, parts: parts)
        // a probe that measured nothing would call any home fitting
        if parts.isEmpty { faults.append("no row or part of the page was measured") }
        if PreviewLaunch.pushBack {
            if pushBackNoSet {
                faults.append("push and back: no set to open")
            } else if !pushBackDone {
                faults.append("push and back: not finished")
            } else {
                if !pushLostParts {
                    faults.append("push and back: no part left the book during the push")
                }
                // Consume each occurrence: one returned set row cannot
                // stand in for two rows with the same name before the push.
                var remaining: [String: Int] = [:]
                for part in parts {
                    remaining[part.name, default: 0] += 1
                }
                var lost: [String] = []
                for name in beforePush.sorted() {
                    if let count = remaining[name], count > 0 {
                        remaining[name] = count - 1
                    } else {
                        lost.append(name)
                    }
                }
                if !lost.isEmpty {
                    faults.append("parts lost after a push and back: " + lost.joined(separator: ", "))
                }
            }
        }
        func edges(_ rect: CGRect?) -> String {
            guard let rect else { return "none" }
            return "\(Int(rect.minY))-\(Int(rect.maxY))"
        }
        var lines: [String] = faults.isEmpty ? ["fits"] : faults.map { "FAULT " + $0 }
        if PreviewLaunch.pushBack && pushBackDone {
            lines.append("push and back: done")
            lines.append("push and back: parts left the book: \(pushLostParts ? "yes" : "no")")
            let cutStr = pushLastKeptCut.map { $0.rounded() == $0 ? "\(Int($0))" : "\($0)" } ?? "none"
            lines.append("push and back: drops removed \(pushDropsRemoved), kept \(pushDropsKept) (cut \(cutStr)), book \(pushBookCountBefore) parts before the push, \(pushBookCountLastLook) at its last look")
        }
        let cut: String = bar.map { "\(Int($0.minY - HomeFit.cutRoom))" } ?? "none"
        lines.append("card \(edges(card)), start \(edges(start)), new set \(edges(newSet)), "
                     + "tiles \(edges(tiles)), bar \(edges(bar)), cut \(cut), large text \(large)")
        lines.append("page ends \(pageEnd.map { String(Int($0)) } ?? "none"), \(parts.count) parts measured: "
                     + parts.prefix(40).map { "\($0.name) \($0.box.text)" }.joined(separator: ", "))
        lines.append("words: " + words.map { "\($0.name) \(Int($0.width))/\(Int($0.widest))" }
            .joined(separator: ", "))
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("home-fit.txt")
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

/// For the preview's fit check: how wide a text was laid out, and how wide
/// its widest word is on its own in the same font (HomeFit.Words). Only on
/// the preview's "library" screen; elsewhere it adds nothing.
private struct HomeWordFit: ViewModifier {
    let name: String
    let text: String
    let font: Font

    func body(content: Content) -> some View {
        if PreviewLaunch.screen == "library" {
            content
                .onGeometryChange(for: Double.self) { Double($0.size.width) } action: {
                    HomeFitProbe.shared.widths[name] = $0
                }
                .background(alignment: .topLeading) {
                    // each word on its own, unbroken and unseen: the widest
                    // is the least width the text can have without breaking
                    // one
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(text.split(separator: " ").enumerated()), id: \.offset) { _, word in
                            Text(String(word)).font(font).fixedSize()
                        }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: Double.self) { Double($0.size.width) } action: {
                        HomeFitProbe.shared.widest[name] = $0
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// The preview's word check on this text (HomeWordFit).
    fileprivate func homeWordFit(_ name: String, _ text: String, font: Font) -> some View {
        modifier(HomeWordFit(name: name, text: text, font: font))
    }
}
