import SwiftUI

/// Everything that is ABOUT the app rather than part of studying: the account,
/// the few settings worth having, how the modes work, and the questions that
/// get asked.
///
/// The studying itself lives in the four tabs (Library, Practice, Ideas,
/// Progress - see AppTabsView), which are also the iPad sidebar. What is left
/// here sits behind the gear on the Library and Progress bars and pushes onto
/// that tab's stack. One definition, one way in.
enum SupportPage: String, CaseIterable, Identifiable, Hashable {
    /// How the studying is going - not strictly about the app, but like the
    /// others it is somewhere visited now and then rather than worked in.
    case examples, analytics, sources, progress, coverage, notes, reasoning, account, settings, help, faq

    /// What the menus list: the tour of examples only in the personal build.
    static var shown: [SupportPage] { allCases.filter { $0 != .examples || PersonalBuild.isOn } }

    /// The pages the menus show under one heading, in the order they list them.
    ///
    /// A page that has a home in one of the four tabs (Practice, Ideas,
    /// Progress) is not listed again behind the gear: one way in, not two.
    static func shown(in section: SupportSection) -> [SupportPage] {
        shown.filter { $0.section == section && !$0.hasTab }
    }

    /// Whether the page lives in a tab of its own (see AppTabsView).
    var hasTab: Bool {
        switch self {
        case .analytics, .progress, .coverage, .notes, .reasoning: return true
        case .examples, .sources, .account, .settings, .help, .faq: return false
        }
    }

    var id: String { rawValue }

    /// Which heading the page sits under in the phone menu and the iPad sidebar.
    ///
    /// Eleven pages in one flat list was a wall to read through every time;
    /// four short groups, each named for what you came to do, can be skimmed.
    var section: SupportSection {
        switch self {
        case .examples, .sources: return .study
        case .analytics, .progress, .coverage: return .progress
        case .notes, .reasoning: return .tools
        case .account, .settings, .help, .faq: return .account
        }
    }

    var title: String {
        switch self {
        case .examples: return "Try every feature"
        case .analytics: return "Your mistakes"
        case .sources: return "Your lectures"
        case .progress: return "Progress"
        case .coverage: return "Syllabus check"
        case .notes: return "Ideas"
        case .reasoning: return "Reasoning practice"
        case .account: return "Account"
        case .settings: return "Settings"
        case .help: return "How it works"
        case .faq: return "Questions"
        }
    }

    var symbol: String {
        switch self {
        case .examples: return "sparkles.rectangle.stack"
        case .analytics: return "chart.xyaxis.line"
        case .sources: return "doc.richtext"
        case .progress: return "chart.bar.xaxis"
        case .coverage: return "checklist"
        case .notes: return "point.3.connected.trianglepath.dotted"
        case .reasoning: return "brain.head.profile"
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        case .help: return "lightbulb"
        case .faq: return "questionmark.circle"
        }
    }

    var blurb: String {
        switch self {
        case .examples: return "See every feature with an example"
        case .analytics: return "What you got wrong, and what to study next"
        case .sources: return "Read your lecture files again"
        case .progress: return "How well you are doing, by subject"
        case .coverage: return "What your exam covers that you haven't studied"
        case .notes: return "Jot down ideas and link them up"
        case .reasoning: return "Work through cases one clue at a time"
        case .account: return "Sign in, sync and subscription"
        case .settings: return "Change how the app behaves"
        case .help: return "What each kind of set is for"
        case .faq: return "Short answers to common questions"
        }
    }

    @ViewBuilder
    var page: some View {
        switch self {
        case .examples: ExamplesHubView()
        case .analytics: AnalyticsView()
        case .sources: SourcesLibraryView()
        case .progress: StatsView()
        case .coverage: CoverageView()
        case .notes: IdeasView()
        case .reasoning: ReasoningView()
        case .account: AccountView(embedded: true)
        case .settings: SettingsPage()
        case .help: HelpPage()
        case .faq: FAQPage()
        }
    }
}

/// The four headings the support pages are grouped under.
enum SupportSection: String, CaseIterable, Identifiable {
    case study, progress, tools, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Your library"
        case .progress: return "Your progress"
        case .tools: return "Tools"
        case .account: return "Account & help"
        }
    }
}

/// The gear menu's contents, shared by the Library and Progress tabs: the
/// pages that are about the app rather than part of studying, under their
/// headings. The four tabs themselves are the iPad sidebar now (AppTabsView),
/// so this is the one list of these pages on every shape of window.
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

// MARK: - The pages

struct SettingsPage: View {
    @EnvironmentObject private var reviews: ReviewStore
    @AppStorage("cramdown.confirmDelete") private var confirmDelete = true
    @AppStorage("cramdown.openLastSet") private var openLastSet = false
    @State private var showModels = false

    var body: some View {
        Form {
            Section {
                Toggle("Ask before deleting a set", isOn: $confirmDelete)
                Toggle("Open the last set on launch", isOn: $openLastSet)
            } footer: {
                Text("Nothing here changes what is in your sets \u{2014} only how the app behaves around them.")
            }

            Section("Review") {
                LabeledContent("Cards scheduled", value: "\(reviews.records.count)")
            }

            Section {
                Button { showModels = true } label: {
                    Label("AI models", systemImage: "cpu")
                }
            } footer: {
                Text("Doctor-R1 and MedVAL on this device, or \(Brand.name) Cloud (Gemini).")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
            } footer: {
                Text(Brand.line)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LibraryBackdrop())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showModels) { ModelSettingsView() }
    }
}

/// What each mode is for, in the student's terms rather than the app's.
struct HelpPage: View {
    var body: some View {
        List {
            Section {
                Text("Put your material in once, then study it in whichever shape suits the exam you are sitting.")
                    .font(.callout)
            }
            Section("The modes") {
                ForEach(StudySetKind.allCases, id: \.self) { kind in
                    HStack(alignment: .top, spacing: 12) {
                        ModeTile(kind: kind, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.label).font(.headline)
                            Text(Self.what(kind))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Getting material in") {
                bullet("Paste or type it into a new set.")
                bullet("Import a lecture PDF or slide deck and let the app cut it into pages.")
                bullet("Record a lecture and have it written out, then study the writing.")
            }
            Section("Getting it out") {
                bullet("Swipe a set to export it: every mode prints as a flashcard deck.")
                bullet("A Cards set exports as an .apkg deck instead, because paper keeps neither its schedule nor its masks.")
            }
        }
        .navigationTitle("How it works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(.secondary)
            Text(text).font(.footnote)
        }
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
}

struct FAQPage: View {
    private static let entries: [(String, String)] = [
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

    var body: some View {
        List {
            ForEach(Array(Self.entries.enumerated()), id: \.offset) { _, entry in
                DisclosureGroup {
                    Text(entry.1)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } label: {
                    Text(entry.0).font(.subheadline.weight(.semibold))
                }
            }
        }
        .navigationTitle("Questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var shortVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
