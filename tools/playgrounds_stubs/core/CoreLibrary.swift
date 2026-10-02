import SwiftUI

// Only in the Swift Playgrounds core build (make_swiftpm.py --without core).
// The core's library: folders and sets, Due today, Sources, a New set button
// and Settings. It is named LibraryView so the design preview's launch
// screens (PreviewLaunch) find it. The full app's LibraryView, with the dock,
// the categories, examples and search, is not in this build.
struct LibraryView: View {
    @EnvironmentObject private var store: Store
    @State private var makingSet = false
    @State private var showingSettings = false
    #if targetEnvironment(simulator)
    /// CI only (swiftpm-launch.yml, `-launchTestOpenSets`): the set the launch
    /// test has open. Never compiled for a device, so never in the owner's
    /// app on the iPad.
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
                Section {
                    NavigationLink {
                        DueTodayView()
                    } label: {
                        Label("Due today", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        SourcesLibraryView()
                    } label: {
                        Label("Sources", systemImage: "doc.text")
                    }
                }
                ForEach(store.folders) { folder in
                    Section(folder.name) {
                        ForEach(sets(in: folder)) { set in
                            row(set)
                        }
                    }
                }
                Section(store.folders.isEmpty ? "Your sets" : "Other sets") {
                    if store.library.isEmpty {
                        Text("Nothing here yet. Tap + to make a set from a lecture.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(loose) { set in
                        row(set)
                    }
                }
                CoreLibraryExtras()
                CoreLibraryExports()
                Section {
                    Text(CoreBuildNote.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LibraryBackdrop())
            .navigationTitle("Stethoscore")
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
                        Image(systemName: "plus")
                    }
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
        NavigationLink {
            CoreSetScreen(set: set)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: set.kind.symbol)
                    .foregroundStyle(set.kind.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name)
                        .font(.body.weight(.medium))
                    Text("\(set.kind.label) \u{00B7} \(set.itemCount) items \u{00B7} \(set.subject)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
