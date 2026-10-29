#if os(iOS)
import SwiftUI

/// Record a lecture in the app (T0146 item 5), from New set's lecture
/// choices and the Narrate screen.
///
/// The elapsed time, a level meter, and Pause/Resume and Stop in the study
/// bar. The microphone is asked for only from the Record tap here: first the
/// plain sheet, then the system's prompt; refused, a row with Open Settings.
/// On Stop the student chooses where it goes: an existing lecture set or a
/// new one named for when the recording began ("Lecture, 23 Oct 14:05").
/// Saving only saves it there, on this phone (RecordingSave,
/// LectureImporter.storeRecorded); Cancel keeps it, with Save the recording
/// in the bar. Transcribe on the Saved banner is the one way it is sent to
/// Gemini, and its transcript lands on the set even if this screen closes
/// first. A recording the app was killed during is offered to keep or delete.
struct RecordLectureView: View {
    /// The lecture set offered first, when opened from one.
    var preferred: StudySet?
    /// Called with the set the recording went into.
    var onSaved: (StudySet) -> Void = { _ in }
    /// Transcribe tapped for a saved recording: the screen that opened this
    /// transcribes it for its own set with its own importer (true, and this
    /// closes); false leaves it to this one.
    var handOff: ((URL, StudySet) -> Bool)? = nil

    @EnvironmentObject private var store: Store
    @EnvironmentObject private var learned: PronunciationLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var recorder = LectureRecorder.shared
    @StateObject private var importer = LectureImporter()

    @State private var flow = RecordFlow(gate: SystemMicGate())
    @State private var showingSheet = false
    @State private var micOff = false
    @State private var save = RecordingSave()
    /// The keep-or-delete question for a recovered recording, put off with Cancel for this visit.
    @State private var recoveryLater = false
    @State private var savedTo: StudySet?

    /// Narrate sets, the one this was opened from first.
    private var lectureSets: [StudySet] {
        var sets = store.library.filter { $0.kind == .narrate }
        if let preferred, let at = sets.firstIndex(where: { $0.id == preferred.id }) {
            sets.insert(sets.remove(at: at), at: 0)
        }
        return sets
    }

    private func words(_ key: String) -> String { L10n.lookup(key) }
    /// A catalog string under a key of the recorder's own, with its English.
    private func words(key: String, english: String) -> String {
        L10n.bundle.localizedString(forKey: key, value: english, table: L10nRules.table)
    }

    var body: some View {
        NavigationStack {
            content
                .modeScreen(.narrate)
                .navigationTitle(words(RecorderWords.screenTitle))
                .navigationBarTitleDisplayMode(.inline)
                .diagnosticsScreen("screen:record_lecture")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(words("Done")) { dismiss() }
                            .buttonStyle(.wardQuiet)
                            .disabled(recorder.state.isActive)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .studyBar(folds: false) { controls }
        }
        .interactiveDismissDisabled(recorder.state.isActive)
        .sheet(isPresented: $showingSheet) { permissionSheet }
        // Cancel sets choosing false and keeps the file: Save the recording opens this again
        .confirmationDialog(words(RecorderWords.saveTo), isPresented: choosingShowing, titleVisibility: .visible) {
            ForEach(lectureSets) { set in
                Button(set.name) { handOn(into: set) }
            }
            Button(String(format: words("New set: %@"), newTitle)) { handOn(into: nil) }
            Button(words(RecorderWords.sheetCancel), role: .cancel) {}
        } message: {
            Text(words(RecorderWords.saveBody))
        }
        .confirmationDialog(words(RecorderWords.recoverTitle), isPresented: recoveredShowing, titleVisibility: .visible) {
            Button(words(key: RecorderWords.keepKey, english: RecorderWords.keep)) { keepRecovered() }
            Button(words(key: RecorderWords.discardKey, english: RecorderWords.discard), role: .destructive) { discardRecovered() }
            Button(words(RecorderWords.sheetCancel), role: .cancel) {}
        } message: {
            Text(words(RecorderWords.recoverBody))
        }
        .onChange(of: recorder.finished) { _, file in
            if let file { save.offer(file) }
        }
        .alert(words("Couldn't use that recording"), isPresented: troubleShowing) {
            Button(words("Done"), role: .cancel) { recorder.clearFailure() }
        } message: {
            Text(failureText)
        }
        .onAppear {
            importer.onScreen = false
            // a recording stopped earlier and not yet saved: offered again
            if let file = recorder.finished, save.file == nil { save.offer(file) }
        }
    }

    // MARK: the page

    private var content: some View {
        VStack(spacing: WardSpace.l) {
            Spacer(minLength: 0)
            Text(L10nFormat.clock(seconds: shownSeconds, locale: L10n.locale))
                .font(.system(.largeTitle, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Color.wardInk)
                .accessibilityLabel(words(stateLine))
                .accessibilityValue(L10nFormat.clock(seconds: shownSeconds, locale: L10n.locale))
                .accessibilityIdentifier("recordElapsed")
            Text(words(stateLine))
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
            WardGroove(fraction: recorder.level, tint: AnyShapeStyle(Color.wardPrimaryInk))
                .accessibilityHidden(true)
            if micOff {
                WardBanner(tone: .danger, symbol: "mic.slash.fill", text: words(RecorderWords.micOff),
                           actionTitle: words(RecorderWords.openSettings)) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            if let note = recorder.note {
                WardBanner(text: words(note))
            }
            if let message = importer.working {
                TranscribingBanner(message: message, onDevice: !importer.inCloud)
            } else if let savedTo, save.kept != nil {
                WardBanner(tone: .green, symbol: "checkmark.circle.fill",
                           text: String(format: words("Saved to %@"), savedTo.name),
                           actionTitle: words(RecorderWords.transcribe)) { transcribe() }
            } else if let savedTo {
                WardBanner(tone: .green, symbol: "checkmark.circle.fill",
                           text: String(format: words("Saved to %@"), savedTo.name))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WardSpace.gutter)
        .frame(maxWidth: .infinity)
    }

    /// Seconds shown, ticking with the meter while recording.
    private var shownSeconds: Double {
        _ = recorder.level
        return recorder.state.elapsed(at: Date().timeIntervalSince1970)
    }

    private var stateLine: String {
        switch recorder.state {
        case .recording: return RecorderWords.recording
        case .paused(_, let reason): return reason ?? RecorderWords.paused
        case .saving: return RecorderWords.saving
        default: return RecorderWords.screenTitle
        }
    }

    // MARK: the bar

    @ViewBuilder
    private var controls: some View {
        switch recorder.state {
        case .recording, .paused:
            HStack(spacing: WardSpace.m) {
                Button { recorder.state.isRecording ? recorder.pause() : recorder.resume() } label: {
                    Label(words(recorder.state.isRecording ? RecorderWords.pause : RecorderWords.resume),
                          systemImage: recorder.state.isRecording ? "pause.fill" : "record.circle")
                }
                .buttonStyle(.bigPrimary)
                .accessibilityIdentifier("recordPauseResume")
                Button { Task { await recorder.stop() } } label: {
                    Label(words(RecorderWords.stop), systemImage: "stop.fill")
                }
                .buttonStyle(.bigCompanion)
                .accessibilityIdentifier("recordStop")
            }
        default:
            if save.waiting {
                // a cancelled choice keeps the recording: saving it again is the bar's one button
                Button { save.reopen() } label: {
                    Label(words(RecorderWords.saveAgain), systemImage: "checkmark.circle")
                }
                .buttonStyle(.bigPrimary)
                .disabled(!save.canSave)
                .accessibilityIdentifier("recordSaveAgain")
            } else if recorder.state == .saving {
                EmptyView()
            } else {
                startButton
            }
        }
    }

    private var startButton: some View {
        Button(action: tapRecord) {
            Label(words(RecorderWords.start), systemImage: "record.circle")
        }
        .buttonStyle(.bigPrimary)
        .disabled(importer.working != nil)
        .accessibilityIdentifier("recordStart")
    }

    // MARK: the permission, asked from this tap only

    private func tapRecord() {
        switch flow.tapRecord() {
        case .sheet: showingSheet = true
        case .record: micOff = false; recorder.start()
        case .settingsRow: micOff = true
        }
    }

    private var permissionSheet: some View {
        VStack(spacing: WardSpace.l) {
            Text(words(RecorderWords.sheetTitle))
                .font(.headline)
                .foregroundStyle(Color.wardInk)
                .accessibilityAddTraits(.isHeader)
            Text(words(RecorderWords.sheetBody))
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
                .multilineTextAlignment(.center)
            Button(words(RecorderWords.sheetContinue)) {
                showingSheet = false
                Task {
                    switch await flow.continueFromSheet() {
                    case .record: micOff = false; recorder.start()
                    default: micOff = true
                    }
                }
            }
            .buttonStyle(.bigPrimary)
            .accessibilityIdentifier("recordContinue")
            Button(words(RecorderWords.sheetCancel)) { showingSheet = false }
                .buttonStyle(.bigCompanion)
                .accessibilityIdentifier("recordSheetCancel")
        }
        .padding(WardSpace.xl)
        .presentationDetents([.medium])
    }

    // MARK: handing it on

    /// Named for when the recording began, read from its file name as
    /// Android does, so both platforms name it from the same moment.
    private var newTitle: String {
        let began = save.file.flatMap { RecorderNames.moment(fileName: $0.lastPathComponent) }
            ?? RecorderNames.Moment(recorder.startedDate)
        return RecorderNames.defaultTitle(began, language: L10n.language)
    }

    /// Saving only saves: the file goes under the set on this phone, and
    /// nothing is sent. A new set is added only once the copy is made, and
    /// a copy running starts no second one.
    private func handOn(into chosen: StudySet?) {
        guard save.file != nil, !save.copying else { return }
        let set = chosen ?? StudySet(name: newTitle, subject: "Lectures", kind: .narrate)
        guard save.save(into: set.id, keep: { file, id in importer.storeRecorded(file, for: id) }) != nil else { return }
        if chosen == nil { store.addSet(set) }
        recorder.handedOn()
        savedTo = set
        onSaved(set)
    }

    /// Transcribe, the student's own action on a saved recording: the one
    /// way it is sent to Gemini.
    private func transcribe() {
        guard let set = savedTo, let kept = save.kept else { return }
        if handOff?(kept, set) == true {
            dismiss()
            return
        }
        importer.keep = { [store, id = set.id] made, spoken in
            guard var current = store.library.first(where: { $0.id == id }) else { return }
            current.narrateSegments = made
            current.language = spoken
            store.update(current)
        }
        let chosen = save
        save = RecordingSave()
        Task { await chosen.transcribe { url, _ in await importer.transcribeRecorded(url, of: set, learned: learned) } }
    }

    /// The save choice waits while a failure is said, as on Android; Done
    /// on the failure brings it up.
    private var choosingShowing: Binding<Bool> {
        Binding(get: {
            if case .failed = recorder.state { return false }
            return save.choosing && importer.trouble == nil
        }, set: { save.choosing = $0 })
    }

    // MARK: a recording the app was killed during

    private var recoveredShowing: Binding<Bool> {
        Binding(get: { recorder.recovered != nil && !recoveryLater && !save.choosing }, set: { shown in
            if !shown { recoveryLater = true }
        })
    }

    private func keepRecovered() {
        guard let file = recorder.recovered else { return }
        recorder.recovered = nil
        Task { @MainActor in save.offer(file) }
    }

    private func discardRecovered() {
        guard let file = recorder.recovered else { return }
        recorder.recovered = nil
        try? FileManager.default.removeItem(at: file)
    }

    private var failureText: String {
        if let trouble = importer.trouble { return trouble }
        if case .failed(let reason) = recorder.state { return String(format: words("Couldn't keep recording. %@"), words(reason)) }
        return ""
    }

    private var troubleShowing: Binding<Bool> {
        Binding(get: {
            if importer.trouble != nil { return true }
            if case .failed = recorder.state { return true }
            return false
        }, set: { shown in
            if !shown { importer.trouble = nil; recorder.clearFailure() }
        })
    }
}
#endif
