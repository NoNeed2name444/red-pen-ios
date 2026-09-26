import Combine
import SwiftUI

/// Everything behind the account menu: the pages that belong to no one
/// category.
///
/// The studying itself is in the library's dock - Questions, Cards, Cases,
/// OSCE, Audio, and Ideas beside them. What is left is visited now and then
/// rather than worked in: how it is going, the lectures, the tour of
/// examples, and the account, settings and help. They push onto the
/// library's stack. One definition, one way in.
enum SupportPage: String, CaseIterable, Identifiable, Hashable {
    case notes, analytics, progress, sources, examples, account, settings, help, faq

    /// What the menu lists, in the order it lists them. Every page is kept,
    /// but three are no longer listed, because each already has a home:
    /// Ideas is a place in the dock (LibraryView routes `.notes` there), By
    /// subject is the Questions › Tools tile and a link in Progress, and the
    /// common questions are the end of How it works.
    static var shown: [SupportPage] { allCases.filter { $0.isListed } }

    /// The pages the menu shows under one heading, in the order it lists them.
    static func shown(in section: SupportSection) -> [SupportPage] {
        shown.filter { $0.section == section }
    }

    var id: String { rawValue }

    /// Whether the account menu lists this page. The tour of examples only
    /// in the personal build.
    var isListed: Bool {
        switch self {
        case .notes, .progress, .faq: return false
        case .examples: return PersonalBuild.isOn
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
        case .analytics: return "chart.xyaxis.line"
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
                Section(section.title) {
                    ForEach(pages) { page in
                        Button(page.title, systemImage: page.symbol) { chosen = page }
                    }
                }
            }
        }
    }
}

// MARK: - Settings

// Settings, How it works and the common questions have no raised control on
// purpose. Their rows are toggles, pickers and reading, and rows sit on the
// SCREEN plane by design (see PopOut.swift): only something you press to
// act - a bar, a tile, a big button - stands out of the glass. The mesh
// backdrop behind each list is the deep plane, so the layering still reads.

/// How the app looks and behaves, the exam it writes for, and where the AI
/// models are chosen.
struct SettingsPage: View {
    @EnvironmentObject private var reviews: ReviewStore
    /// Handed on to the study reminders, which read the library to pick
    /// the question of the day and tonight's misses.
    @EnvironmentObject private var store: Store
    @AppStorage("cramdown.confirmDelete") private var confirmDelete = true
    @AppStorage("cramdown.openLastSet") private var openLastSet = false
    @AppStorage(PopOutSettings.enabledKey) private var popOut = true
    @AppStorage(PopOutSettings.faceKey) private var face = false
    @AppStorage(SpaceSettings.alwaysNightKey) private var alwaysNight = false
    @AppStorage(SpaceSettings.soundsKey) private var sounds = false
    /// "Graphics": Automatic, High quality or Smooth (GraphicsQuality.swift).
    @AppStorage(SpaceSettings.graphicsKey) private var graphicsRaw: String = GraphicsChoice.automatic.rawValue
    /// "Link length": how far apart linked bodies stand in the Ideas map
    /// (GraphLinkLength), Shorter 0.6 to Longer 1.8.
    @AppStorage(SpaceSettings.linkLengthKey) private var linkLength: Double = GraphLinkLength.standard
    /// "Lines": Curved (false) or Straight (true) links in the Ideas map and
    /// on the board (GraphLineStyle).
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false
    @Environment(\.graphics) private var graphics
    @AppStorage(ExamTrack.storageKey) private var exam = ExamTrack.general.rawValue
    /// Seconds since 1970; 0 for no date. The library counts down to it.
    @AppStorage(ExamTrack.dateKey) private var examDate: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.spaceQuality) private var quality
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// The camera was refused when face tracking was turned on.
    @State private var denied = false

    var body: some View {
        Form {
            lookSection
            examSection
            StudyReminderSettings()
                .environmentObject(store)
            studySection
            ReviewSettingsSection()
                .environmentObject(reviews)
            LibraryDataSettingsSection()
            PlatformSettingsSection()
                .environmentObject(store)
            modelsSection
            versionSection
        }
        .scrollContentBackground(.hidden)
        .skyScroll()
        .background(LibraryBackdrop())
        .navigationTitle("Settings")
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
            Toggle("Pop-out effect", isOn: $popOut)
                .accessibilityIdentifier("popOutToggle")
            Toggle("Pop-out with face tracking", isOn: $face)
                .disabled(faceLocked)
                .accessibilityIdentifier("popOutFaceToggle")
            Toggle("Always night sky", isOn: $alwaysNight)
                .accessibilityIdentifier("alwaysNightToggle")
            Toggle("Sounds", isOn: $sounds)
                .accessibilityIdentifier("soundsToggle")
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
                        .foregroundStyle(.secondary)
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
                Picker("Lines", selection: $straightLines) {
                    ForEach(GraphLineStyle.allCases) { style in
                        Text(style.title).tag(style.isStraight)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("lineStylePicker")
            }
        } header: {
            Text("Look and feel")
        } footer: {
            Text(lookFooter)
        }
    }

    /// What the two toggles will actually do on this device, right now.
    private var lookFooter: String {
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
        parts.append("Face tracking only follows where your head is, on this device. Nothing is recorded or sent.")
        parts.append("Always night sky keeps the dark star field, and the app's dark look, even in light mode.")
        parts.append(graphicsFooter)
        parts.append(GraphLinkLength.footer(linkLength))
        parts.append(lineFooter)
        parts.append("Sounds are short, quiet tones for right and wrong answers and a finished session. They follow the Ring/Silent switch and stay quiet while anything is being read aloud.")
        let footer: String = parts.joined(separator: " ")
        return footer
    }

    /// What the Lines choice does.
    private var lineFooter: String {
        if straightLines {
            return "Lines: Straight draws every link as a direct line, in the 3D map and on the board."
        }
        return "Lines: Curved keeps each map theme's own arches, axons and traces, and bows the board's lines gently."
    }

    /// The stored link length, read clamped and written snapped.
    private var linkLengthBinding: Binding<Double> {
        Binding<Double>(
            get: { GraphLinkLength.stored(linkLength) },
            set: { linkLength = GraphLinkLength.clamped($0) }
        )
    }

    /// What the Graphics choice is doing on this device, right now.
    private var graphicsFooter: String {
        let choice: GraphicsChoice = GraphicsChoice.stored(graphicsRaw)
        let smooth: Bool = graphics.tier == .smooth
        switch choice {
        case .high:
            return "Graphics: High quality draws every star, link and glow in full, at up to 120 frames a second."
        case .smooth:
            return "Graphics: Smooth uses lighter stars, links and glows and 60 frames a second in every look, for older phones that stutter."
        case .automatic:
            let now: String = smooth ? "Smooth" : "High quality"
            return "Graphics: Automatic picks Smooth on older phones, when the phone is warm or in Low Power Mode, and High quality otherwise - \(now) right now."
        }
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
            NavigationLink {
                ExamPickerView(onDone: { exam = ExamTrack.current.rawValue })
            } label: {
                LabeledContent("Exam", value: ExamChoice.current?.shortName ?? "Choose")
            }
            .accessibilityIdentifier("chooseExam")
            Picker("Exam style", selection: $exam) {
                ForEach(ExamTrack.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("I have an exam date", isOn: hasExamDate)
            if examDate > 0 {
                DatePicker("Exam date", selection: examDay, in: Date()..., displayedComponents: .date)
            }
        } header: {
            Text("Your exam")
        } footer: {
            Text("Questions and stations are written in your exam's style: USMLE uses US units and guidelines; PLAB, MRCP and MRCS use SI units, NICE and the BNF, and their own station formats.")
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
        } header: {
            Text("Study")
        } footer: {
            Text("Nothing here changes what is in your sets \u{2014} only how the app behaves around them.")
        }
    }

    private var modelsSection: some View {
        Section {
            NavigationLink {
                ModelSettingsView(embedded: true)
            } label: {
                Label("AI models", systemImage: "cpu")
            }
        } footer: {
            Text("Doctor-R1 and MedVAL on this device, or \(Brand.name) Cloud (Gemini).")
        }
    }

    private var versionSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.shortVersion)
        } footer: {
            Text(Brand.line)
        }
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
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
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
    }

    private var modesSection: some View {
        Section("The modes") {
            ForEach(StudySetKind.allCases, id: \.self) { kind in
                HelpModeRow(kind: kind, detail: HelpPage.what(kind))
            }
        }
    }

    private var materialSection: some View {
        Section("Getting material in") {
            HelpBullet(text: "Paste or type it into a new set.")
            HelpBullet(text: "Import a lecture PDF or slide deck and let the app cut it into pages.")
            HelpBullet(text: "Record a lecture and have it written out, then study the writing.")
        }
    }

    private var exportSection: some View {
        Section("Getting it out") {
            HelpBullet(text: "Tap the \u{2026} on a set (or swipe it) to export it: every mode prints as a flashcard deck.")
            HelpBullet(text: "A Cards set exports as an .apkg deck instead, because paper keeps neither its schedule nor its masks.")
        }
    }

    private var questionsSection: some View {
        Section("Common questions") {
            ForEach(Array(HelpPage.questions.enumerated()), id: \.offset) { index, entry in
                HelpQuestionRow(question: entry.0, answer: entry.1)
                    .id(HelpPage.questionID(index))
            }
        }
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
        case .qa: return "Open questions with a model answer \u{2014} say it aloud, then check."
        case .osce: return "A clinical skill broken into steps, marked the way an examiner would."
        case .narrate: return "A recorded lecture written out, so you can study what was actually said."
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

/// One mode on the help page: its tile, its name and what it is for.
private struct HelpModeRow: View {
    let kind: StudySetKind
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModeTile(kind: kind, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label).font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HelpBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
                .padding(.top, 2)
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
