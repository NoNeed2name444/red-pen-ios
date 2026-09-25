import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ "Your data": back up everything into one file, restore from
/// one, and every card set out to Anki - with the date of the last backup,
/// so it is obvious when one is due. Free, with no account: the file goes
/// wherever the share sheet sends it (Files, iCloud Drive, AirDrop, Mail).
///
/// A Form section, for SettingsPage's list:
///
///     LibraryDataSettingsSection()
///
/// It reads Store, ReviewStore and NoteStore from the environment, which the
/// app root provides.
struct LibraryDataSettingsSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @EnvironmentObject private var notes: NoteStore
    @AppStorage(LibraryBackupRunner.includeFilesKey) private var includeFiles = true
    /// Mirrors the stored date, so the row updates the moment a backup is made.
    @AppStorage(LibraryBackup.lastBackupKey) private var lastBackupStamp: Double = 0

    @State private var working: Work?
    @State private var shareURL: URL?
    @State private var restoring = false
    @State private var pendingRestore: URL?
    @State private var message: (title: String, body: String)?

    enum Work: String {
        case backup = "Backing up\u{2026}"
        case restore = "Restoring\u{2026}"
        case anki = "Building the Anki file\u{2026}"
    }

    var body: some View {
        Section {
            lastBackupRow
            Toggle(isOn: $includeFiles) {
                Label("Include lecture files and recordings", systemImage: "waveform.and.magnifyingglass")
            }
            actionRow("Back up everything", symbol: "externaldrive.badge.icloud", work: .backup) { backUp() }
                .accessibilityIdentifier("backupEverything")
            actionRow("Restore from a backup", symbol: "arrow.counterclockwise.icloud", work: .restore) { restoring = true }
                .accessibilityIdentifier("restoreBackup")
            actionRow("Export all cards as Anki", symbol: "rectangle.stack.badge.plus", work: .anki) { exportAnki() }
                .disabled(!hasCards)
                .accessibilityIdentifier("exportAllAnki")
        } header: {
            Text("Your data")
        } footer: {
            Text("One file with every set, your review schedule, progress, notes, study log and settings. Save it to Files or iCloud Drive. Restoring adds what this phone doesn\u{2019}t have \u{2014} nothing here is replaced or deleted.")
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.zip, .data]) { result in
            if case .success(let url) = result { pendingRestore = url }
        }
        .confirmationDialog("Restore from this backup?", isPresented: restoreAsked, titleVisibility: .visible,
                            presenting: pendingRestore) { url in
            Button("Restore") { restore(url) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Sets, schedules, notes and files this phone doesn\u{2019}t have are added. A set that differs from yours is added beside it.")
        }
        .sheet(isPresented: shareShown) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .alert(message?.title ?? "", isPresented: messageShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message?.body ?? "")
        }
    }

    // MARK: rows

    private var lastBackupRow: some View {
        let date: Date? = lastBackupStamp > 0 ? Date(timeIntervalSince1970: lastBackupStamp) : nil
        let stale: Bool = date.map { Date().timeIntervalSince($0) > 14 * 86_400 } ?? true
        let value: String = date.map { $0.formatted(.relative(presentation: .named)) } ?? "Never"
        return LabeledContent {
            Text(value)
                .foregroundStyle(stale ? Color.orange : Color.secondary)
        } label: {
            Label("Last backup", systemImage: stale ? "exclamationmark.triangle" : "checkmark.shield")
        }
        .accessibilityElement(children: .combine)
    }

    private func actionRow(_ title: String, symbol: String, work: Work, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack {
                Label(working == work ? work.rawValue : title, systemImage: symbol)
                Spacer(minLength: 8)
                if working == work { ProgressView() }
            }
        }
        .disabled(working != nil)
    }

    private var hasCards: Bool {
        store.library.contains { $0.kind == .anki && !$0.cards.isEmpty }
    }

    // MARK: bindings

    private var restoreAsked: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var shareShown: Binding<Bool> {
        Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    // MARK: work

    private func backUp() {
        working = .backup
        Task {
            do {
                let url = try await LibraryBackupRunner.makeBackup(store: store, reviews: reviews, notes: notes,
                                                                   includeFiles: includeFiles)
                lastBackupStamp = UserDefaults.standard.double(forKey: LibraryBackup.lastBackupKey)
                shareURL = url
            } catch {
                ReviewPromptRules.noteTrouble()
                message = ("Couldn\u{2019}t back up", error.localizedDescription)
            }
            working = nil
        }
    }

    private func restore(_ url: URL) {
        working = .restore
        Task {
            do {
                let report = try await LibraryBackupRunner.restore(from: url, store: store, reviews: reviews, notes: notes)
                message = ("Backup restored", report.summary)
            } catch {
                ReviewPromptRules.noteTrouble()
                message = ("Couldn\u{2019}t restore", error.localizedDescription)
            }
            working = nil
        }
    }

    private func exportAnki() {
        working = .anki
        Task {
            do {
                shareURL = try await LibraryBackupRunner.exportAllAsAnki(store: store)
            } catch {
                ReviewPromptRules.noteTrouble()
                message = ("Couldn\u{2019}t export", "Something went wrong building the Anki file.")
            }
            working = nil
        }
    }
}
