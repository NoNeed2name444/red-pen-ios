import SwiftUI

// Only in the Swift Playgrounds core build (make_swiftpm.py --without core).
// The core's library, as a small Ward Round home: the date, the app's name
// and the exam countdown; today's ward round with Due today as bed 1; the
// sets on cards, folders as their headings; Sources; a New set button and
// Settings. It is named LibraryView so the design preview's launch screens
// (PreviewLaunch) find it. The full app's home (WardHome.swift), with the
// dock, the categories, the planner's beds and search, is not in this build.
struct LibraryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @EnvironmentObject private var account: AccountStore
    @State private var makingSet = false
    @State private var showingSettings = false
    #if targetEnvironment(simulator)
    /// CI only (`-launchTestOpenSets`): the set the launch test has open.
    /// Never compiled for a device, so never in the owner's app on the iPad.
    @State private var launchTestSet: StudySet?
    #endif

    private var loose: [StudySet] {
        store.library.filter { $0.folderId == nil }
    }

    private func sets(in folder: StudyFolder) -> [StudySet] {
        store.library.filter { $0.folderId == folder.id }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { homeRow(header) }
                roundSection
                ForEach(store.folders) { folder in
                    Section {
                        ForEach(sets(in: folder)) { set in
                            row(set)
                        }
                    } header: {
                        WardSectionLabel(folder.name)
                    }
                }
                Section {
                    if store.library.isEmpty {
                        WardEmptyState(symbol: "bed.double", title: "No patients yet",
                                       message: "Make a set from a lecture and it is admitted here.") {
                            Button("New set") { makingSet = true }
                                .buttonStyle(.wardCompact)
                        }
                        .listRowBackground(Color.clear)
                    }
                    ForEach(loose) { set in
                        row(set)
                    }
                } header: {
                    WardSectionLabel(store.folders.isEmpty ? "Your sets" : "Other sets")
                }
                CoreLibraryExtras()
                CoreLibraryExports()
                Section {
                    Text(CoreBuildNote.text)
                        .font(.footnote)
                        .foregroundStyle(Color.wardInkSecondary)
                        .listRowBackground(Color.clear)
                }
            }
            .wardForm()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        makingSet = true
                    } label: {
                        Label("New set", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.wardCompact)
                    .accessibilityLabel("New set")
                }
            }
            .sheet(isPresented: $makingSet) { NewSetView() }
            .sheet(isPresented: $showingSettings) { CoreSettingsView() }
            #if targetEnvironment(simulator)
            .navigationDestination(item: $launchTestSet) { CoreSetScreen(set: $0) }
            .task { await openEverySetForLaunchTest() }
            #endif
        }
    }

    /// The date in small caps, the name with its squiggle of ECG, a
    /// greeting, and the countdown when the exam has a date.
    private var header: some View {
        let now: Date = Date()
        let hour: Int = Calendar.current.component(.hour, from: now)
        let greeting: String = WardWords.greeting(hour: hour, name: account.account?.displayName)
        return VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .wardSmallCaps()
            HStack(spacing: WardSpace.s) {
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
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
            if let countdown = CoreCountdown.text(now: now) {
                WardPill(text: countdown, symbol: "calendar")
                    .padding(.top, WardSpace.xs)
            }
        }
        .padding(.top, WardSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Today's ward round: the due cards as bed 1, then Sources.
    private var roundSection: some View {
        let due: Int = reviews.dueAcross(store.library).count
        let chip: (text: String, tone: WardTone)? = due > 0 ? ("\(due) due", .warning) : nil
        let detail: String = due > 0 ? "Cards waiting for review" : "Nothing due"
        return Section {
            NavigationLink {
                DueTodayView()
            } label: {
                WardRow(symbol: "rectangle.on.rectangle.angled", tone: .amber, overline: "Bed 1",
                        title: "Due today", detail: detail, chip: chip, chevron: false)
            }
            .wardRowBackground()
            NavigationLink {
                SourcesLibraryView()
            } label: {
                WardRow(symbol: "doc.text", tone: .grey, title: "Sources",
                        detail: "The lectures and papers behind your sets", chevron: false)
            }
            .wardRowBackground()
        } header: {
            WardSectionLabel("Today's ward round")
        }
    }

    /// The header's row: the page's gutter, nothing behind.
    private func homeRow<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    #if targetEnvironment(simulator)
    /// Opens every set in turn, a few seconds each, so a screen that reads
    /// something the core app does not supply (an environment object, say)
    /// stops the launch test - as the example lecture once stopped the app on
    /// the owner's iPad - instead of passing because nothing was opened.
    private func openEverySetForLaunchTest() async {
        guard ProcessInfo.processInfo.arguments.contains("-launchTestOpenSets") else { return }
        // the examples, and the lectures that become examples, arrive first
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        for set in store.library {
            print("LaunchTest: opening", set.kind.rawValue, "-", set.name)
            launchTestSet = set
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            launchTestSet = nil
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        print("LaunchTest: opened all", store.library.count, "sets")
    }
    #endif

    private func row(_ set: StudySet) -> some View {
        let plural: String = set.itemCount == 1 ? "" : "s"
        let subject: String = set.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let showsSubject: Bool = !subject.isEmpty && subject != "General"
        let amount: String = "\(set.itemCount) \(set.itemNoun)\(plural)"
        return NavigationLink {
            CoreSetScreen(set: set)
        } label: {
            WardRow(symbol: set.kind.symbol, overline: set.kind.label, title: set.name,
                    detail: showsSubject ? "\(amount) \u{00B7} \(subject)" : amount, chevron: false)
        }
        .wardRowBackground()
        .coreRowActions(set)
        .swipeActions {
            Button(role: .destructive) {
                store.deleteSet(set.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// The exam the countdown names, from Settings → Your exam: the full app's
/// ExamCountdown (WardHome.swift), which this build leaves out.
enum CoreCountdown {
    static func text(now: Date = Date()) -> String? {
        guard let exam = ExamCap.storedDate() else { return nil }
        let calendar = Calendar.current
        let days: Int? = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                 to: calendar.startOfDay(for: exam)).day
        let track: ExamTrack = ExamTrack.current
        let name: String? = ExamChoice.current?.shortName ?? (track == .general ? nil : track.rawValue.uppercased())
        return WardWords.countdown(days: days, exam: name)
    }
}

/// A set opened in its own mode; a narrate set opens what the variant has
/// (core-audio-out or core-audio-in).
struct CoreSetScreen: View {
    let set: StudySet

    var body: some View {
        switch set.kind {
        case .mcq: MCQQuizView(set: set)
        case .anki: AnkiReviewView(set: set)
        case .book: BookReaderView(set: set)
        case .osce: OsceReviewView(set: set)
        case .narrate: CoreNarrateScreen(set: set)
        case .cases: NotInThisBuild(feature: "Cases")
        }
    }
}

/// Settings: the account, the exam, reviews and help. The full app's
/// Settings hub (models, graphics, diagnostics, backups) is not in this build.
struct CoreSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Account") { AccountView() }
                    NavigationLink("Exam") { ExamPickerView() }
                }
                ReviewSettingsSection()
                CoreDataSection()
                HelpContactSection()
                Section("About") {
                    NavigationLink("Sources and licences") { ContentLicencesView() }
                }
            }
            .wardForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// What this build leaves out, under the library: what every core build
/// leaves out, and the parts its variant has not brought back.
enum CoreBuildNote {
    static var text: String {
        let missing: [String] = ["the 3D map", "Study Lens", "analytics", "the reasoning tools"]
            + CoreAudioPart.missing + CoreExportsPart.missing
        let listed: String = missing.count > 1
            ? missing.dropLast().joined(separator: ", ") + " and " + (missing.last ?? "")
            : missing.joined()
        return "This build leaves out \(listed), so Swift Playgrounds can build it on the iPad. The full app has them."
    }
}
