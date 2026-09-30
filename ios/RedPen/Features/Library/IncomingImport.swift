import SwiftUI

// MARK: - Decks, tables and backups opened from other apps
//
// The data lane's end of ImportRouter: an Anki deck, a Quizlet / CSV / TSV
// table or a whole-library backup opened from Files, Mail or AirDrop (or
// dropped on the window) gets the same glass preview as Cards ▸ Paste or
// import, and a backup the same "Restore from this backup?" question as
// Settings ▸ Your data. Nothing changes until the student taps (plan rule 8).
// Anything else - a single shared set, a lecture, a picture - is declined
// and the router's own inbox sheet shows it.

extension View {
    /// Registers with ImportRouter while this view is on screen. `busy`: the
    /// screen has a sheet of its own up, so a preview could not be shown -
    /// a file that comes in then waits until it has closed.
    func incomingImportPreview(busy: Bool = false) -> some View {
        modifier(IncomingImport(busy: busy))
    }
}

private struct IncomingImport: ViewModifier {
    let busy: Bool

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var reviews: ReviewStore
    @EnvironmentObject private var notes: NoteStore

    @State private var token: UUID?
    /// `busy`, kept where the router's handler (registered once, a copy of
    /// this modifier from then) still reads the current value.
    @State private var screenBusy = false
    @State private var reading: String?
    @State private var preview: ImportPreview?
    /// The preview the sheet actually showed - a sheet asked for while
    /// another presentation is up never appears, and must not leave
    /// `preview` set for ever.
    @State private var appeared: UUID?
    /// How many times this preview has been asked for and not appeared.
    @State private var misses = 0
    @State private var backup: IncomingFile?
    @State private var message: IncomingMessage?
    /// Files taken but not yet shown: one at a time, and none while `busy`.
    @State private var held: [IncomingFile] = []
    /// A preview read and waiting for the screen to be free.
    @State private var parked: ParkedPreview?

    func body(content: Content) -> some View {
        content
            .onAppear { register() }
            .onDisappear {
                if let token { ImportRouter.shared.unregister(token) }
                token = nil
            }
            .onChange(of: busy, initial: true) { _, now in
                screenBusy = now
                if !now { next() }
            }
            .sheet(item: $preview, onDismiss: { next() }) { shown in
                ImportPreviewSheet(preview: shown) { commit(shown) }
                    .onAppear { appeared = shown.id }
            }
            .confirmationDialog("Restore from this backup?", isPresented: backupAsked,
                                titleVisibility: .visible, presenting: backup) { file in
                Button("Restore") { restore(file) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Sets, schedules, notes and files this phone doesn\u{2019}t have are added. Nothing here is replaced or deleted.")
            }
            .alert(message?.title ?? "", isPresented: messageShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message?.body ?? "")
            }
            .overlay(alignment: .top) {
                if let reading {
                    Label("Reading \(reading)\u{2026}", systemImage: "arrow.down.doc")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .liquidGlassChip()
                        .padding(.top, 8)
                        .transition(.opacity)
                        .accessibilityIdentifier("incomingImportReading")
                }
            }
    }

    // MARK: routing

    private func register() {
        if let token { ImportRouter.shared.unregister(token) }
        token = ImportRouter.shared.register { file in take(file) }
    }

    /// True when this preview will show the file (now, or once the screen
    /// is free); false leaves it to the inbox.
    private func take(_ file: IncomingFile) -> Bool {
        switch file.kind {
        case .ankiDeck, .ankiCollection, .csv, .tsv, .backup:
            held.append(file)
            next()
            return true
        default:
            return false
        }
    }

    /// Whether nothing of this preview's is up or on its way.
    private var idle: Bool {
        reading == nil && preview == nil && backup == nil
    }

    /// The next thing waiting, once the screen is free.
    private func next() {
        guard !screenBusy, idle else { return }
        if let waiting = parked {
            parked = nil
            present(waiting.preview, from: waiting.file)
            return
        }
        guard !held.isEmpty else { return }
        let file: IncomingFile = held.removeFirst()
        if file.kind == .backup {
            backup = file
        } else {
            read(file)
        }
    }

    private func read(_ file: IncomingFile) {
        let url: URL = file.url
        reading = (file.name as NSString).deletingPathExtension
        Task {
            do {
                // a question sheet comes in as questions, anything else as cards
                let made: ImportPreview = try await LibraryImport.preview(detecting: url, subject: "")
                reading = nil
                misses = 0
                if screenBusy {
                    parked = ParkedPreview(file: file, preview: made)
                } else {
                    present(made, from: file)
                }
            } catch {
                reading = nil
                Diagnostics.record(.error, area: .importing, message: "import.incoming_unreadable", error: error)
                ReviewPromptRules.noteTrouble()
                message = IncomingMessage(title: "Couldn\u{2019}t read \(file.name)", body: error.localizedDescription)
            }
        }
    }

    /// Shows the preview, and checks that it really appeared: a sheet this
    /// screen does not know about (one pushed deeper in) can still be up.
    /// If it did not, it is parked and tried again a little later; after a
    /// few tries the file goes to the inbox instead.
    private func present(_ made: ImportPreview, from file: IncomingFile) {
        appeared = nil
        preview = made
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard preview?.id == made.id, appeared != made.id else { return }
            preview = nil
            misses += 1
            if misses >= 4 {
                misses = 0
                ImportRouter.shared.showInbox(file)
                next()
                return
            }
            parked = ParkedPreview(file: file, preview: made)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            next()
        }
    }

    private func commit(_ shown: ImportPreview) {
        LibraryImport.commit(shown, store: store, reviews: reviews)
        SpaceWarp.liftOff()
        preview = nil
    }

    private func restore(_ file: IncomingFile) {
        backup = nil
        reading = "backup"
        Task {
            do {
                let report = try await LibraryBackupRunner.restore(from: file.url, store: store,
                                                                   reviews: reviews, notes: notes)
                reading = nil
                message = IncomingMessage(title: "Backup restored", body: report.summary)
            } catch {
                reading = nil
                ReviewPromptRules.noteTrouble()
                message = IncomingMessage(title: "Couldn\u{2019}t restore", body: error.localizedDescription)
            }
            next()
        }
    }

    // MARK: bindings

    private var backupAsked: Binding<Bool> {
        Binding(get: { backup != nil }, set: { shown in
            if !shown {
                backup = nil
                // Cancel: the next file, if any; Restore goes on in restore()
                Task { @MainActor in next() }
            }
        })
    }

    private var messageShown: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }
}

private struct IncomingMessage {
    var title: String
    var body: String
}

private struct ParkedPreview {
    var file: IncomingFile
    var preview: ImportPreview
}
