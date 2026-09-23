import SwiftUI

/// Everything that is ABOUT the app rather than part of studying: the account,
/// the few settings worth having, how the modes work, and the questions that
/// get asked.
///
/// On an iPad these are the sidebar, because a sidebar is for the places you
/// go occasionally and come back from - not for the material you work in all
/// day. The sets themselves belong in the main column, at full width, with the
/// mode dock under them where a hand is.
///
/// On a phone there is no sidebar, so the same four live behind the toolbar
/// menu and push onto the stack. One definition, two ways in.
enum SupportPage: String, CaseIterable, Identifiable, Hashable {
    case account, settings, help, faq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return "Account"
        case .settings: return "Settings"
        case .help: return "How it works"
        case .faq: return "Questions"
        }
    }

    var symbol: String {
        switch self {
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        case .help: return "lightbulb"
        case .faq: return "questionmark.circle"
        }
    }

    var blurb: String {
        switch self {
        case .account: return "Signing in, syncing, subscription"
        case .settings: return "What the app does on its own"
        case .help: return "What each mode is for"
        case .faq: return "Short answers"
        }
    }

    @ViewBuilder
    var page: some View {
        switch self {
        case .account: AccountView(embedded: true)
        case .settings: SettingsPage()
        case .help: HelpPage()
        case .faq: FAQPage()
        }
    }
}

/// The iPad sidebar: the app's name, the way back to the sets, and the four
/// places that are about the app rather than part of studying.
///
/// Plain buttons rather than navigation links: this column decides what the
/// main column shows, and nothing is ever pushed inside the sidebar itself.
struct SupportSidebar: View {
    @Binding var chosen: SupportPage?

    var body: some View {
        List {
            Section {
                row(title: "Your sets", symbol: "square.stack",
                    blurb: "Everything you are studying", page: nil)
            } header: {
                HStack(spacing: 8) {
                    Brand.Mark(size: 22, tint: Brand.signal)
                    Text(Brand.name).font(.headline).foregroundStyle(.primary)
                }
                .textCase(nil)
                .padding(.bottom, 2)
            }
            Section {
                ForEach(SupportPage.allCases) { page in
                    row(title: page.title, symbol: page.symbol,
                        blurb: page.blurb, page: page)
                }
            }
        }
        .navigationTitle(Brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(title: String, symbol: String, blurb: String, page: SupportPage?) -> some View {
        let here = chosen == page
        return Button {
            chosen = page
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(here ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(here ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // listRowBackground takes a VIEW, not a style, so the two branches
        // have to be the same kind of thing: a filled shape either way.
        .listRowBackground(
            Rectangle().fill(here ? AnyShapeStyle(.tint.opacity(0.12))
                                  : AnyShapeStyle(Color.clear))
        )
        .accessibilityAddTraits(here ? [.isSelected] : [])
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
                Text("Doctor-R1 and MedVAL on this device, or hosted models such as Baichuan-M2-32B.")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
            } footer: {
                Text(Brand.line)
            }
        }
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
                bullet("An Anki deck exports as .apkg instead, because paper keeps neither its schedule nor its masks.")
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
        ("Can I use my own Anki decks?",
         "You can export to .apkg and open it in Anki. Its schedule and any image masks come with it."),
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
