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
                Section {
                    Text("This is the core build. The 3D map, Study Lens, analytics, audio lectures, spoken OSCE practice and the reasoning tools are in the full app.")
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
        }
    }

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
        .swipeActions {
            Button(role: .destructive) {
                store.deleteSet(set.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// A set opened in its own mode; the modes this build leaves out say so.
struct CoreSetScreen: View {
    let set: StudySet

    var body: some View {
        switch set.kind {
        case .mcq: MCQQuizView(set: set)
        case .anki: AnkiReviewView(set: set)
        case .book: BookReaderView(set: set)
        case .qa: QACardsView(set: set)
        case .osce: OsceReviewView(set: set)
        case .narrate: NotInThisBuild(feature: "Audio lectures")
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
                HelpContactSection()
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
