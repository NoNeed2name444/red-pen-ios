import SwiftUI

/// Everything behind the gear: the pages that belong to no one category.
///
/// The studying itself is in the library's dock - Questions, Cards, Cases,
/// OSCE, Audio - each with its sets and its ways to practise. What is left is
/// visited now and then rather than worked in: the idea dump, how it is going,
/// the lectures, the tour of examples, and the account, settings and help.
/// They push onto the library's stack. One definition, one way in.
enum SupportPage: String, CaseIterable, Identifiable, Hashable {
    case notes, analytics, progress, sources, examples, account, settings, help, faq

    /// What the menu lists: the tour of examples only in the personal build.
    static var shown: [SupportPage] { allCases.filter { $0 != .examples || PersonalBuild.isOn } }

    /// The pages the menu shows under one heading, in the order it lists them.
    static func shown(in section: SupportSection) -> [SupportPage] {
        shown.filter { $0.section == section }
    }

    var id: String { rawValue }

    /// Which heading the page sits under in the menu.
    ///
    /// Nine pages in one flat list is a wall to read through every time;
    /// three short groups, each named for what you came to do, can be skimmed.
    var section: SupportSection {
        switch self {
        case .notes, .sources, .examples: return .study
        case .analytics, .progress: return .progress
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
        case .faq: return "Questions"
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
        case .analytics: AnalyticsView().scrollContentBackground(.hidden).background(LibraryBackdrop())
        case .progress: StatsView()
        case .sources: SourcesLibraryView()
        case .examples: ExamplesHubView()
        case .account: AccountView(embedded: true)
        case .settings: SettingsPage()
        case .help: HelpPage()
        case .faq: FAQPage()
        }
    }
}

/// The three headings the gear's pages are grouped under.
enum SupportSection: String, CaseIterable, Identifiable {
    case study, progress, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .study: return "Your work"
        case .progress: return "Your progress"
        case .account: return "Account & help"
        }
    }
}

/// The gear menu's contents: the pages that belong to no one category, under
/// their headings.
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
