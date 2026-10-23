import Combine
import SwiftUI

/// Everything behind the account menu: the pages that belong to no one
/// category.
///
/// The studying itself is in the library's dock - Questions, Cards, OSCE,
/// Audio, and Ideas beside them. What is left is visited now and then
/// rather than worked in: how it is going, the lectures, the tour of
/// examples, and the account, settings and help. They push onto the
/// library's stack. One definition, one way in.
enum SupportPage: String, CaseIterable, Identifiable, Hashable {
    case notes, analytics, progress, sources, examples, account, settings, help, faq

    /// What the menu lists, in the order it lists them. Every page is kept,
    /// but three are no longer listed, because each already has a home:
    /// Ideas is a place in the dock (LibraryView routes `.notes` there), By
    /// subject is the Questions › Tools tile and a link in Vitals, and the
    /// common questions are the end of How it works.
    static var shown: [SupportPage] { allCases.filter { $0.isListed } }

    /// The pages the menu shows under one heading, in the order it lists them.
    static func shown(in section: SupportSection) -> [SupportPage] {
        shown.filter { $0.section == section }
    }

    var id: String { rawValue }

    /// Whether the account menu lists this page. The tour of examples is
    /// for everyone.
    var isListed: Bool {
        switch self {
        case .notes, .progress, .faq: return false
        case .examples: return true
        case .analytics, .sources, .account, .settings, .help: return true
        }
    }

    /// Which heading the page sits under in the menu (or would, for the
    /// pages it no longer lists).
    ///
    /// Two short groups, each named for what you came to do, can be skimmed;
    /// a flat list is a wall to read through every time.
    var section: SupportSection {
        switch self {
        case .notes, .analytics, .progress, .sources, .examples: return .study
        case .account, .settings, .help, .faq: return .account
        }
    }

    var title: String {
        switch self {
        case .notes: return "Ideas"
        case .analytics: return "Progress"
        case .progress: return "By subject"
        case .sources: return "Your lectures"
        case .examples: return "Try every feature"
        case .account: return "Account"
        case .settings: return "Settings"
        case .help: return "How it works"
        case .faq: return "Common questions"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "lightbulb"
        case .analytics: return "waveform.path.ecg"
        case .progress: return "chart.bar.xaxis"
        case .sources: return "doc.richtext"
        case .examples: return "sparkles.rectangle.stack"
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        case .help: return "questionmark.app"
        case .faq: return "questionmark.circle"
        }
    }

    @ViewBuilder
    var page: some View {
        switch self {
        case .notes: IdeasView()
        case .analytics: AnalyticsView()
        case .progress: StatsView()
        case .sources: SourcesLibraryView()
        case .examples: ExamplesHubView()
        case .account: AccountView(embedded: true)
        case .settings: SettingsPage()
        case .help: HelpPage()
        case .faq: HelpPage(startsAtQuestions: true)
        }
    }
}

/// The headings the account menu's pages are grouped under.
enum SupportSection: String, CaseIterable, Identifiable {
    case study, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Your work"
        case .account: return "Account & help"
        }
    }
}

/// The account menu's contents: the pages that belong to no one category,
/// under their headings.
///
/// Buttons rather than links: a NavigationLink cannot live inside a Menu, so
/// choosing a page sets `chosen` and the screen pushes it.
struct SupportMenuItems: View {
    @Binding var chosen: SupportPage?

    var body: some View {
        ForEach(SupportSection.allCases) { section in
            let pages: [SupportPage] = SupportPage.shown(in: section)
            if !pages.isEmpty {
                Section(L10n.lookup(section.title)) {
                    ForEach(pages) { page in
                        Button(L10n.lookup(page.title), systemImage: page.symbol) { chosen = page }
                    }
                }
            }
        }
    }
}

// MARK: - Settings

// Settings, How it works and the common questions are plain soft forms:
// rows as tiles raised just off the base, small-caps headers.

/// How the app looks and behaves, the exam it writes for, and where the AI
/// models are chosen.
struct SettingsPage: View {
    @EnvironmentObject private var reviews: ReviewStore
    /// Handed on to the study reminders, which read the library to pick
    /// the question of the day and tonight's misses.
    @EnvironmentObject private var store: Store
    /// The cloud's status and the Verify switch.
    @EnvironmentObject private var llm: LocalLLMService
    @AppStorage("cramdown.confirmDelete") private var confirmDelete = true
    @AppStorage("cramdown.openLastSet") private var openLastSet = false
    @AppStorage(DailyGoal.key) private var dailyGoal: Int = 50
    @AppStorage(PopOutSettings.enabledKey) private var popOut = true
    @AppStorage(PopOutSettings.faceKey) private var face = false
    @AppStorage(SpaceSettings.alwaysNightKey) private var alwaysNight = false
    @AppStorage(SpaceSettings.soundsKey) private var sounds = false
    /// The heartbeat the opening plays (LaunchSplash); its ECG draws either way.
    @AppStorage(LaunchSplash.soundKey) private var launchHeartbeat = true
    /// "Graphics": Automatic, High quality or Smooth (GraphicsQuality.swift).
    @AppStorage(SpaceSettings.graphicsKey) private var graphicsRaw: String = GraphicsChoice.automatic.rawValue
    /// "Link length": how far apart linked bodies stand in the Ideas map
    /// (GraphLinkLength), Shorter 0.6 to Longer 1.8.
    @AppStorage(SpaceSettings.linkLengthKey) private var linkLength: Double = GraphLinkLength.standard
    /// "Lines": Curved (false) or Straight (true) links in the Ideas map and
    /// on the board (GraphLineStyle).
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false
    @AppStorage(ExamTrack.storageKey) private var exam = ExamTrack.general.rawValue
    /// Seconds since 1970; 0 for no date. The library counts down to it.
    @AppStorage(ExamTrack.dateKey) private var examDate: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.spaceQuality) private var quality
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The camera was refused when face tracking was turned on.
    @State private var denied = false
    /// The exam picker and the crash reports, pushed from their rows: buttons
    /// rather than links, since a link inside a group's card would take the
    /// whole card's tap.
    @State private var pickingExam = false
    @State private var showingDiagnostics = false

    var body: some View {
        // Android's groups first, in its order (the owner, 23 Oct): Look and
        // feel, Your exam, Stethoscore Cloud, Review, each one card under its
        // small-caps heading. The groups only iOS has follow.
        Form {
            lookSection
            examSection
            cloudSection
            ReviewSettingsSection()
                .environmentObject(reviews)
            StudyReminderSettings()
                .environmentObject(store)
            studySection
            LibraryDataSettingsSection()
            PlatformSettingsSection()
                .environmentObject(store)
            AccuracyEngineSection()
            versionSection
        }
        .wardForm()
        .navigationDestination(isPresented: $pickingExam) {
            ExamPickerView(onDone: { exam = ExamTrack.current.rawValue })
        }
        .navigationDestination(isPresented: $showingDiagnostics) { DiagnosticsSettingsView() }
        .navigationTitle(L10n.string("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: popOut) { _, _ in PopOutMotion.shared.refresh() }
        .onChange(of: face) { _, on in faceChanged(on) }
        .onChange(of: graphicsRaw) { _, _ in SpaceQualityCenter.shared.recompute() }
        .onChange(of: sounds) { _, on in
            // made ready now, so the first cue after turning them on plays
            if on { SpaceSounds.shared.prepare() }
        }
        .onReceive(NotificationCenter.default
            .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    // MARK: Look and feel

    private var faceAvailable: Bool { PopOutMotion.faceTrackingAvailable }

    private var faceLocked: Bool { !popOut || !faceAvailable }

    private var lookSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WardSpace.m) {
                Text(l10n: "Look and feel")
                    .wardSmallCaps()
                    .accessibilityAddTraits(.isHeader)
                // the dark look, named as Android names it, its note under it
                VStack(alignment: .leading, spacing: WardSpace.xs) {
                    Toggle("Night shift", isOn: $alwaysNight)
                        .accessibilityIdentifier("alwaysNightToggle")
                    Text("\(Brand.name)'s dark palette")
                        .font(WardType.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                Toggle("Pop-out effect", isOn: $popOut)
                    .accessibilityIdentifier("popOutToggle")
                // its privacy note stays under it, always (independent review, T0160)
                VStack(alignment: .leading, spacing: WardSpace.xs) {
                    Toggle("Pop-out with face tracking", isOn: $face)
                        .disabled(faceLocked)
                        .accessibilityIdentifier("popOutFaceToggle")
                    Text("Face tracking only follows where your head is, on this device. Nothing is recorded or sent.")
                        .font(WardType.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                }
                Toggle("Sounds", isOn: $sounds)
                    .accessibilityIdentifier("soundsToggle")
                Toggle("Heartbeat when the app opens", isOn: $launchHeartbeat)
                    .accessibilityIdentifier("launchHeartbeatToggle")
                Picker("Graphics", selection: $graphicsRaw) {
                    ForEach(GraphicsChoice.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
                .accessibilityIdentifier("graphicsPicker")
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Link length")
                        Spacer()
                        Text(GraphLinkLength.word(linkLength))
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                    Slider(value: linkLengthBinding, in: GraphLinkLength.shortest...GraphLinkLength.longest,
                           step: GraphLinkLength.step) {
                        Text("Link length")
                    } minimumValueLabel: {
                        Text("Shorter").font(.caption)
                    } maximumValueLabel: {
                        Text("Longer").font(.caption)
                    }
                    .accessibilityValue(GraphLinkLength.spoken(linkLength))
                    .accessibilityIdentifier("linkLengthSlider")
                }
                HStack {
                    Text("Lines")
                    Spacer()
                    WardSegmented(selection: $straightLines, options: [false, true]) { straight in
                        Text(GraphLineStyle.stored(straight).title)
                    }
                    .fixedSize()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Lines")
                    .accessibilityIdentifier("lineStylePicker")
                }
                if let note = lookNote {
                    Text(note)
                        .font(WardType.caption)
                        .foregroundStyle(Color.wardInkSecondary)
                }
            }
            .wardCard(lift: .low)
            .wardCardRow()
        }
    }

    /// Only what this device is doing differently right now, and why a
    /// switch above does nothing: the long note under the group is cut to
    /// what Android says (the owner, 23 Oct).
    private var lookNote: String? {
        var parts: [String] = []
        if !faceAvailable {
            parts.append("Face tracking needs an iPhone or iPad with Face ID.")
        } else if denied {
            parts.append("Camera access is off, so the pop-out follows the tilt instead.")
        }
        if reduceMotion || lowPower {
            parts.append("Reduce Motion (or Low Power Mode) is on, so everything stands out without moving.")
        } else if quality != .full {
            parts.append("Reduce Transparency, Increase Contrast or a warm device has turned the tilt off; the sky still drifts slowly.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The stored link length, read clamped and written snapped.
    private var linkLengthBinding: Binding<Double> {
        Binding<Double>(
            get: { GraphLinkLength.stored(linkLength) },
            set: { linkLength = GraphLinkLength.clamped($0) }
        )
    }

    /// Turning face tracking on asks for the camera; a refusal turns the
    /// toggle back off and says why in the footer.
    private func faceChanged(_ on: Bool) {
        PopOutMotion.shared.refresh()
        guard on else { return }
        denied = false
        Task {
            let granted: Bool = await PopOutMotion.shared.requestFaceTracking()
            if !granted {
                face = false
                denied = true
            }
        }
    }

    // MARK: Your exam

    private var examSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WardSpace.m) {
                Text(l10n: "Your exam")
                    .wardSmallCaps()
                    .accessibilityAddTraits(.isHeader)
                // one exam row, the way to the picker (the owner, 23 Oct)
                Button { pickingExam = true } label: {
                    HStack {
                        Text("Exam").font(WardType.headline)
                        Spacer()
                        Text(ExamChoice.current?.shortName ?? "Choose")
                            .foregroundStyle(Color.wardInkSecondary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.wardPrimaryInk)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chooseExam")
                Picker("Exam style", selection: $exam) {
                    ForEach(ExamTrack.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("I have an exam date", isOn: hasExamDate)
                if examDate > 0 {
                    DatePicker("Exam date", selection: examDay, in: Date()..., displayedComponents: .date)
                }
                Text("Questions and stations are written in your exam's style: USMLE uses US units and guidelines; PLAB, MRCP and MRCS use SI units, NICE and the BNF, and their own station formats.")
                    .font(WardType.caption)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            .wardCard(lift: .low)
            .wardCardRow()
        }
    }

    private var hasExamDate: Binding<Bool> {
        Binding(get: { examDate > 0 }, set: { on in examDate = SettingsPage.defaultExamDate(on) })
    }

    private var examDay: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: examDate) },
                set: { day in examDate = day.timeIntervalSince1970 })
    }

    /// Two months from today when a date is first asked for; 0 for none.
    private static func defaultExamDate(_ on: Bool) -> Double {
        guard on else { return 0 }
        let twoMonths: TimeInterval = 60 * 86_400
        let day: Date = Date().addingTimeInterval(twoMonths)
        return day.timeIntervalSince1970
    }

    // MARK: The rest

    private var studySection: some View {
        Section {
            Toggle("Ask before deleting a set", isOn: $confirmDelete)
            Toggle("Open the last set on launch", isOn: $openLastSet)
            Stepper("Daily goal: \(dailyGoal) a day", value: $dailyGoal, in: DailyGoal.range, step: 10)
                .monospacedDigit()
                .accessibilityIdentifier("dailyGoalStepper")
        } header: {
            Text(l10n: "Study")
        } footer: {
            Text("Nothing here changes what is in your sets \u{2014} only how the app behaves around them.")
        }
        .wardRowBackground()
    }

    /// The app's writing, as Android's Stethoscore Cloud group (the owner,
    /// 22 and 23 Oct): there is no writer to choose, so no AI models page. Its
    /// status, then the two rows only iOS has: Verify and the crash reports.
    private var cloudSection: some View {
        Section {
            VStack(alignment: .leading, spacing: WardSpace.m) {
                Text("\(Brand.name) Cloud")
                    .wardSmallCaps()
                    .accessibilityAddTraits(.isHeader)
                LabeledContent("Status", value: llm.cloudBlocker ?? "Ready")
                    .accessibilityIdentifier("cloudStatus")
                Toggle("Verify what is generated", isOn: $llm.checkGenerated)
                    .accessibilityIdentifier("verifyToggle")
                Button { showingDiagnostics = true } label: {
                    HStack {
                        Label("Crash and failure reports", systemImage: "stethoscope")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.wardPrimaryInk)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("crashReports")
                Text("Crash and failure reports are technical only: never your notes, questions or recordings.")
                    .font(WardType.caption)
                    .foregroundStyle(Color.wardInkSecondary)
                Text("Questions, stations, cards and textbook pages are written by \(Brand.name) Cloud, and everything it writes is checked by the verification layer. Your text is sent to the cloud to answer; \(Brand.name) does not keep it.")
                    .font(WardType.caption)
                    .foregroundStyle(Color.wardInkSecondary)
                Text("A study aid, not medical advice; generated text can be wrong even when checked.")
                    .font(WardType.caption)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            .wardCard(lift: .low)
            .wardCardRow()
        }
    }

    private var versionSection: some View {
        Section {
            NavigationLink {
                ContentLicencesView()
            } label: {
                Label("Sources and licences", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("contentLicences")
            LabeledContent("Version", value: Bundle.main.shortVersion)
        } header: {
            Text("About")
        } footer: {
            Text(Brand.line)
        }
        .wardRowBackground()
    }
}

/// The app's accuracy engine: every question, card, case, station and page
/// checked against its lecture and the literature by free models voting,
/// scored by the trained accuracy model. Only the background pass over the
/// whole library can be turned off; new content is always checked.
struct AccuracyEngineSection: View {
    @ObservedObject private var accuracy = AccuracyStore.shared

    var body: some View {
        let checked: Int = accuracy.ledger.records.values.filter { !$0.votes.isEmpty }.count
        Section {
            Toggle("Check my whole library in the background", isOn: $accuracy.background)
            LabeledContent {
                Text("\(checked)").font(WardType.obs).monospacedDigit()
                    .foregroundStyle(Color.wardInkSecondary)
            } label: {
                Text("Items checked")
            }
            LabeledContent("Accuracy model", value: accuracy.weights.version)
            if let reason = accuracy.pausedReason {
                Text(reason).font(.footnote).foregroundStyle(Color.wardInkSecondary)
            }
        } header: {
            Text("Accuracy engine")
        } footer: {
            Text("New and edited content is checked straight away; the rest of your library slowly, newest and most-studied first, within the free daily limits. Each item is checked against its lecture and current literature (PubMed reviews, MedlinePlus, FDA labels) by two or three free models voting, never only by the model that wrote it, plus rule checks for doses, lab values and contradictions. An item is checked again only when it changes. Needs \(Brand.name) Cloud; rule checks work everywhere.")
        }
        .wardRowBackground()
    }
}

// MARK: - How it works

/// What each mode is for, in the student's terms rather than the app's, and
/// the common questions at the end.
struct HelpPage: View {
    /// Opens already scrolled to the common questions.
    let startsAtQuestions: Bool

    init(startsAtQuestions: Bool = false) {
        self.startsAtQuestions = startsAtQuestions
    }

    /// Where `startsAtQuestions` scrolls to: the first question.
    static let questionsAnchor = "help.questions"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                introSection
                modesSection
                materialSection
                exportSection
                questionsSection
                HelpContactSection()
            }
            .wardForm()
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .task { await jumpToQuestions(proxy) }
        }
    }

    private func jumpToQuestions(_ proxy: ScrollViewProxy) async {
        guard startsAtQuestions else { return }
        // one beat, so the list has laid its rows out first
        try? await Task.sleep(nanoseconds: 150_000_000)
        proxy.scrollTo(HelpPage.questionsAnchor, anchor: .top)
    }

    private var introSection: some View {
        Section {
            Text("Put your material in once, then study it in whichever shape suits the exam you are sitting.")
                .font(.callout)
        }
        .wardRowBackground()
    }

    private var modesSection: some View {
        Section("The modes") {
            ForEach(StudySetKind.allCases, id: \.self) { kind in
                HelpModeRow(kind: kind, detail: HelpPage.what(kind))
            }
        }
        .wardRowBackground()
    }

    private var materialSection: some View {
        Section("Getting material in") {
            HelpBullet(text: "Paste or type it into a new set.")
            HelpBullet(text: "Import a lecture PDF or slide deck and let the app cut it into pages.")
            HelpBullet(text: "Record a lecture and have it written out, then study the writing.")
        }
        .wardRowBackground()
    }

    private var exportSection: some View {
        Section("Getting it out") {
            HelpBullet(text: "Tap the \u{2026} on a set (or swipe it) to export it: every mode prints as a flashcard deck.")
            HelpBullet(text: "A Cards set exports as an .apkg deck instead, because paper keeps neither its schedule nor its masks.")
        }
        .wardRowBackground()
    }

    private var questionsSection: some View {
        Section("Common questions") {
            ForEach(Array(HelpPage.questions.enumerated()), id: \.offset) { index, entry in
                HelpQuestionRow(question: entry.0, answer: entry.1)
                    .id(HelpPage.questionID(index))
            }
        }
        .wardRowBackground()
    }

    private static func questionID(_ index: Int) -> String {
        if index == 0 { return questionsAnchor }
        return "help.question.\(index)"
    }

    static func what(_ kind: StudySetKind) -> String {
        switch kind {
        case .mcq: return "Single best answer questions, with the reasoning for and against each option."
        case .anki: return "Spaced repetition. Rate a card and it comes back when you are about to forget it."
        case .book: return "Your material as a textbook you read straight through, a page at a time."
        case .osce: return "A clinical skill broken into steps, marked the way an examiner would."
        case .narrate: return "A recorded lecture written out, so you can study what was actually said."
        case .cases: return "Patients to work up against the clock: read the clerking, choose what to examine and test, rank your diagnoses, decide, then see what mattered."
        }
    }

    /// What used to be its own Questions page.
    static let questions: [(String, String)] = [
        ("Where is my material kept?",
         "On this device. If you sign in, your sets, folders and review schedule sync between your devices; recordings and learned pronunciations stay on the device that made them."),
        ("Does studying need a connection?",
         "No. Reviewing, reading and answering all work offline. Generating new questions and syncing need one."),
        ("Can I take my cards to another flashcard app?",
         "Yes: export the set as an .apkg deck, the format common flashcard apps open. Its schedule and any image masks come with it."),
        ("Why did a deck appear twice?",
         "It was edited on two devices before they could sync. Both versions are kept rather than one quietly overwriting the other \u{2014} check them and delete the one you don't want."),
        ("What happens if I cancel?",
         "Everything already in your library stays and keeps working. Generating new material stops."),
        ("How do I delete everything?",
         "Account, then Delete account. That removes the account and its synced copy from the server; the copy on this device stays until you delete the app."),
    ]
}

/// One mode on the help page: its glyph in its section's accent, its name
/// and what it is for, as a WardRow. Nothing here is tapped, so no chevron.
private struct HelpModeRow: View {
    let kind: StudySetKind
    let detail: String

    var body: some View {
        WardRow(symbol: kind.symbol, tone: .accent(WardSection(kindRaw: kind.rawValue)), title: kind.label,
                detail: detail, chevron: false)
    }
}

private struct HelpBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(Color.wardInkSecondary)
            Text(text).font(.footnote)
        }
    }
}

private struct HelpQuestionRow: View {
    let question: String
    let answer: String

    var body: some View {
        DisclosureGroup {
            Text(answer)
                .font(.footnote)
                .foregroundStyle(Color.wardInkSecondary)
                .padding(.top, WardSpace.xs)
        } label: {
            Text(question).font(.subheadline.weight(.semibold))
        }
    }
}

/// The common questions, now the end of How it works. Kept so anything that
/// still names it opens the same place.
struct FAQPage: View {
    var body: some View {
        HelpPage(startsAtQuestions: true)
    }
}

extension Bundle {
    var shortVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
