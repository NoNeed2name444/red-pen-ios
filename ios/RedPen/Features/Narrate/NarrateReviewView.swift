import SwiftUI
import UniformTypeIdentifiers

/// The Narrate player, in its two states.
///
/// With a recording attached it follows the audio: the recogniser's own word
/// timestamps decide which word is lit, and the clock is the audio's position,
/// so scrubbing and speed changes cannot put the highlight out of step. With no
/// recording the lecture is read aloud (NarrateVoice: the natural cloud voice,
/// or the phone's own) and the word being said is lit - that half is in
/// NarrateReading.
///
/// Keeping it smooth: the word timeline is laid out once per transcript, not
/// per frame; the audio's 15-a-second clock is watched only by the scrub bar;
/// the players publish the spoken word only when it changes; each line is an
/// Equatable view, so a moving word rebuilds one line; and the transcript
/// scrolls only when the current line leaves a comfortable band.
///
/// The transcript is editable either way: long-press a word, say what it should
/// have been, and the fix spreads to everything that sounds the same and is
/// remembered for next time.
///
/// `body` is split into `stage` and `screen` on purpose. SwiftUI type-checks a
/// view's whole modifier chain as one expression, and this screen has enough of
/// them that the compiler gave up on it outright.
struct NarrateReviewView: View {
    /// A lecture made from the Audio page's "Add an audio file": its file
    /// picker opens as soon as the screen does.
    @MainActor static var importOnOpen: UUID?

    let studySet: StudySet
    /// Only used by the CI screenshot launch to open on the back of a card.
    var startRevealed: Bool = false

    init(set studySet: StudySet, startIndex: Int = 0, startPlaying: Bool = false,
         startFinished: Bool = false, startFixing: Int? = nil) {
        self.studySet = studySet
        _index = State(initialValue: min(startIndex, max(0, studySet.narrateSegments.count - 1)))
        _playing = State(initialValue: startPlaying)
        _finished = State(initialValue: startFinished)
        if let word = startFixing, let first = studySet.narrateSegments.first {
            let words = first.text.split(separator: " ").map(String.init)
            if words.indices.contains(word) {
                _fixing = State(initialValue: FixTarget(segment: 0, word: word, heard: words[word]))
            }
        }
    }

    @EnvironmentObject var store: Store
    @EnvironmentObject var learned: PronunciationLibrary
    @StateObject var player = LecturePlayer()
    @StateObject var importer = LectureImporter()
    @StateObject var voice = NarrateVoice()

    @State var index = 0
    @State var playing = false
    @State var finished = false
    @State var speed: Double = 1
    @State private var band = NarrateScrollBand()

    @State var segments: [NarrateSegment] = []
    @State var texts: [String] = []
    @State private var fixing: FixTarget?
    @State private var report: String?
    @State private var lastOutcome: CorrectionOutcome?
    @State private var snapshot: [String] = []
    @State private var importing = false
    @State private var choosingEngine = false
    @State private var engine: LectureImporter.Engine = .cloud

    /// The word being said in the current line, from whichever is playing:
    /// the recording, or the voice reading the lecture.
    private var spokenWord: Int? {
        let spot: NarrateSpot? = player.hasAudio ? player.spot : voice.spot
        guard let spot, spot.line == index else { return nil }
        return spot.word
    }

    private var title: String {
        studySet.subject.isEmpty ? "Narrate" : studySet.subject
    }

    private var troubleShowing: Binding<Bool> {
        Binding(get: { importer.trouble != nil },
                set: { if !$0 { importer.trouble = nil } })
    }

    // MARK: the screen, in three shallow layers

    /// What sits in the bottom bar: the recording's own player, or the
    /// read-aloud controls with the way to add a recording beside them.
    @ViewBuilder
    private var controls: some View {
        if player.hasAudio {
            NarrateAudioBar(player: player, clock: player.clock, speed: $speed)
        } else {
            NarrateReadingControls(speed: $speed, playing: playing, finished: finished,
                                   canPlay: !segments.isEmpty,
                                   isEmpty: texts.isEmpty,
                                   onPlayPause: { playing ? pause() : play() },
                                   onRestart: restart,
                                   onAddAudio: addAudioAction)
        }
    }

    /// Adding a recording, from the bar - hidden while one is being made.
    private var addAudioAction: (() -> Void)? {
        guard importer.working == nil else { return nil }
        return { choosingEngine = true }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            header
            if let message = importer.working {
                TranscribingBanner(message: message, onDevice: !importer.inCloud)
            }
            transcript
        }
        .modeScreen(.narrate)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screen: some View {
        stage
            .onAppear(perform: seed)
            .onDisappear { voice.stop(); player.stop() }
            // a recording screen: the camera stays off while it is open
            .popOutFacePaused()
            // adding a recording is in the same More menu as every other
            // study screen's extras; this screen has no Turn into
            .studyMoreMenu(for: studySet, turnInto: false) {
                Button { choosingEngine = true } label: {
                    Label(player.hasAudio ? "Replace recording" : "Add recording",
                          systemImage: "waveform")
                }
            }
            // the multiple-selection form on purpose: it hands back [URL],
            // which is the shape LectureImporter.attach takes
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { picked in
                Task { await importer.attach(picked, to: studySet, learned: learned, engine: engine) }
            }
            .confirmationDialog("Transcribe the recording with", isPresented: $choosingEngine,
                                titleVisibility: .visible) {
                Button("Gemini (Pro) \u{2014} best for Arabic + English") { engine = .cloud; importing = true }
                Button("This phone only \u{2014} offline") { engine = .device; importing = true }
            } message: {
                Text("Gemini is part of Pro and runs on Google's servers: the audio goes through \(Brand.name) to Google to transcribe, and while \(Brand.name) uses Google's free service Google may use it to improve its models. Only send lectures you're allowed to record. On this phone, nothing leaves the device, but mixed Arabic and English comes out far less accurate.")
            }
    }

    var body: some View {
        screen
            .onChange(of: importer.produced) { _, made in
                if let made { adopt(made) }
            }
            .onChange(of: player.spot) { _, spot in
                // the audio is the clock, so the current line follows it rather
                // than being advanced by a timer of our own
                if let line = spot?.line, line != index { index = line }
            }
            .onChange(of: voice.spot) { _, spot in
                if !player.hasAudio, spot.line != index { index = spot.line }
            }
            .onChange(of: voice.playing) { _, now in playing = now }
            .onChange(of: voice.finished) { _, now in finished = now }
            .onChange(of: speed) { _, now in voice.setSpeed(now) }
            .sheet(item: $fixing) { target in
                FixWordSheet(target: target) { fix(target, to: $0) }
            }
            .alert("Couldn't use that recording", isPresented: troubleShowing) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importer.trouble ?? "")
            }
            .alert("Transcribed", isPresented: Binding(get: { importer.notice != nil },
                                                       set: { if !$0 { importer.notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importer.notice ?? "")
            }
    }

    // MARK: setting up

    private func seed() {
        if Self.importOnOpen == studySet.id {
            Self.importOnOpen = nil
            choosingEngine = true
        }
        guard segments.isEmpty else { return }
        segments = studySet.narrateSegments
        texts = segments.map(\.text)
        _ = learned.applyLearned(to: &texts)
        relayout()
        if let recording = LectureAudio.existing(for: studySet.id) { player.load(recording, title: title) }
    }

    /// The word timeline and the text to read, worked out once whenever the
    /// transcript changes. (It used to be a computed property, so the whole
    /// lecture was laid out again on every tick of the audio clock.)
    private func relayout() {
        voice.load(texts, langs: segments.map(\.lang), title: title)
        guard let measured = NarrateScheduler.measured(segments) else {
            player.setTimeline([])
            return
        }
        let ends: [Double] = segments.map { $0.end ?? 0 }
        player.setTimeline(WordTiming.layout(texts: texts, ends: ends, measured: measured))
    }

    /// A freshly transcribed lecture replaces the typed transcript, and is
    /// saved, because losing a forty-minute transcription to a back-swipe would
    /// be unforgivable.
    private func adopt(_ made: [NarrateSegment]) {
        segments = made
        texts = made.map(\.text)
        index = 0
        // the set as it is now, not as it was when this screen opened: a
        // rename or a synced edit since then is kept
        var updated = store.library.first { $0.id == studySet.id } ?? studySet
        updated.narrateSegments = made
        store.update(updated)
        voice.stop()
        if let recording = LectureAudio.existing(for: studySet.id) { player.load(recording, title: title) }
        relayout()
        importer.produced = nil
    }

    // MARK: fixing a word

    private func fix(_ target: FixTarget, to spelling: String) {
        snapshot = texts
        let outcome = learned.fix(segment: target.segment, words: target.word...target.word,
                                  to: spelling, in: &texts)
        guard outcome.here != nil else { return }
        lastOutcome = outcome
        persistText()
        relayout()
        withAnimation(.snappy) { report = outcome.summary() }
    }

    private func undo() {
        guard let outcome = lastOutcome else { return }
        learned.undo(snapshot, into: &texts, touching: outcome)
        lastOutcome = nil
        persistText()
        relayout()
        withAnimation(.snappy) { report = nil }
    }

    /// A correction is an edit to the transcript, so it outlives the screen.
    func persistText() {
        guard texts.count == segments.count else { return }
        for i in segments.indices { segments[i].text = texts[i] }
        // the set as it is now, not as it was when this screen opened: a
        // rename or a synced edit since then is kept
        var updated = store.library.first { $0.id == studySet.id } ?? studySet
        updated.narrateSegments = segments
        store.update(updated)
    }

    // MARK: the two pieces of chrome

    private var header: some View {
        let total = segments.count
        // by line, not by the audio clock, so the header is not redrawn
        // fifteen times a second
        let done: Int = index + (finished ? 1 : 0)
        let fraction: Double = total > 0 ? Double(done) / Double(total) : 0
        let line: Int = min(index + 1, max(total, 1))
        let detail: String
        if player.hasAudio {
            detail = "Following the recording \u{00B7} hold a word to fix it"
        } else if voice.waiting {
            detail = "Getting the voice ready\u{2026}"
        } else {
            detail = "Tap a line to read from it \u{00B7} hold a word to fix it"
        }
        return StudyProgressHeader("Line \(line) of \(total)", detail: detail,
                                   fraction: min(1, max(0, fraction)))
    }

    /// The transcript, scrolling under the bar; it follows the voice only
    /// when the current line drifts out of the comfortable band.
    private var transcript: some View {
        ScrollViewReader { proxy in
            transcriptScroll
                .onChange(of: index) { _, line in
                    // follow the voice only when the line drifts out of the band,
                    // and then gently, to a spot a third of the way down
                    guard band.needsScroll(to: line) else { return }
                    let anchor = UnitPoint(x: 0.5, y: 0.3)
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(line, anchor: anchor) }
                }
        }
    }

    private var transcriptScroll: some View {
        ScrollView {
            transcriptBody
        }
        .coordinateSpace(.named(NarrateScrollBand.space))
        // the height the transcript can actually be read in: the floating
        // bar is a safe-area inset here, so the part under it is left out
        .onGeometryChange(for: CGFloat.self) { geometry in
            let hidden: CGFloat = geometry.safeAreaInsets.bottom
            return max(0, geometry.size.height - hidden)
        } action: { height in
            band.viewport = height
        }
        .onScrollPhaseChange { _, phase in
            // the student's own scrolling wins for a few seconds
            if phase == .interacting || phase == .decelerating {
                band.handsOffUntil = Date().addingTimeInterval(3)
            }
        }
        // what a correction did, just above the bar, until undone or replaced
        .overlay(alignment: .bottom) { fixToast }
        .studyBar { controls }
    }

    @ViewBuilder
    private var fixToast: some View {
        if let report {
            FixReport(summary: report, onUndo: undo)
                // as compact as the bar on a wide iPad
                .frame(maxWidth: 560)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if texts.isEmpty {
            FinishHero(symbol: "waveform", title: "Nothing to read yet", message: emptyLine)
                .padding(.top, 32)
        } else {
            NarrateWordFlow(texts: texts, langs: segments.map(\.lang),
                            currentIndex: index,
                            spokenWord: spokenWord,
                            band: band,
                            onJump: { jump(to: $0) },
                            onFix: { fixing = $0 })
                .contentCard()
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .readableColumn()
        }
    }

    /// Where to go from an empty transcript: the Add audio button below, or
    /// More, where a recording already attached can be replaced. While a
    /// recording is being made into a transcript the button is hidden, so the
    /// line says what is happening instead of pointing at it.
    private var emptyLine: String {
        if importer.working != nil {
            return "Your recording is being transcribed. The transcript appears here when it's ready."
        }
        if player.hasAudio {
            return "This transcript is empty. Replace the recording from More."
        }
        return "This transcript is empty. Tap Add audio below to add a recording of the lecture."
    }
}
