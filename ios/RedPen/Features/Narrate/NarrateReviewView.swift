import SwiftUI
import UniformTypeIdentifiers

/// The Narrate player, in its two states.
///
/// With a recording attached it follows the audio: the recogniser's own word
/// timestamps decide which word is lit, and the clock is the audio's position,
/// so scrubbing and speed changes cannot put the highlight out of step. With no
/// recording it falls back to a reading pace, holding each line for
/// `NarrateScheduler.segmentMs()` - that half is in NarrateReading.
///
/// The transcript is editable either way: long-press a word, say what it should
/// have been, and the fix spreads to everything that sounds the same and is
/// remembered for next time.
///
/// `body` is split into `stage` and `screen` on purpose. SwiftUI type-checks a
/// view's whole modifier chain as one expression, and this screen has enough of
/// them that the compiler gave up on it outright.
struct NarrateReviewView: View {
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

    @State var index = 0
    @State var playing = false
    @State var finished = false
    @State var speed: Double = 1
    @State var timer: Timer?
    @State var remainingMs: Double = 0
    @State var segStartedAt = Date()

    @State var segments: [NarrateSegment] = []
    @State var texts: [String] = []
    @State private var fixing: FixTarget?
    @State private var report: String?
    @State private var lastOutcome: CorrectionOutcome?
    @State private var snapshot: [String] = []
    @State private var importing = false
    @State private var choosingEngine = false
    @State private var engine: LectureImporter.Engine = .cloud

    /// Word timings exist only when a recording was transcribed.
    var words: [TranscriptWord] {
        guard let measured = NarrateScheduler.measured(segments) else { return [] }
        return WordTiming.layout(texts: texts,
                                 ends: segments.map { $0.end ?? 0 },
                                 measured: measured)
    }

    var spokenNow: TranscriptWord? {
        player.hasAudio ? WordTiming.word(at: player.time, in: words) : nil
    }

    private var title: String {
        studySet.subject.isEmpty ? "Narrate" : studySet.subject
    }

    private var troubleShowing: Binding<Bool> {
        Binding(get: { importer.trouble != nil },
                set: { if !$0 { importer.trouble = nil } })
    }

    // MARK: the screen, in three shallow layers

    @ViewBuilder
    private var controls: some View {
        if player.hasAudio {
            NarrateAudioBar(player: player, speed: $speed)
        } else {
            NarrateReadingControls(speed: $speed, playing: playing, finished: finished,
                                   canPlay: !segments.isEmpty,
                                   onPlayPause: { playing ? pause() : play() },
                                   onRestart: restart)
        }
    }

    private var stage: some View {
        VStack(spacing: 0) {
            header
            if let message = importer.working { TranscribingBanner(message: message) }
            transcript
            controls
        }
        .modeScreen(.narrate)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screen: some View {
        stage
            .onAppear(perform: seed)
            .onDisappear { timer?.invalidate(); player.stop() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { choosingEngine = true } label: {
                        Label(player.hasAudio ? "Replace recording" : "Add recording",
                              systemImage: "waveform")
                    }
                    .buttonStyle(.glass)
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
                Text("Gemini is part of Pro and runs on Google's servers: the audio goes through CramDown to Google to transcribe, and while CramDown uses Google's free service Google may use it to improve its models. Only send lectures you're allowed to record. On this phone, nothing leaves the device, but mixed Arabic and English comes out far less accurate.")
            }
    }

    var body: some View {
        screen
            .onChange(of: importer.produced) { _, made in
                if let made { adopt(made) }
            }
            .onChange(of: spokenNow?.segment) { _, line in
                // the audio is the clock, so the current line follows it rather
                // than being advanced by a timer of our own
                if let line, line != index { index = line }
            }
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
            .safeAreaInset(edge: .bottom) {
                if let report { FixReport(summary: report, onUndo: undo) }
            }
    }

    // MARK: setting up

    private func seed() {
        guard segments.isEmpty else { return }
        segments = studySet.narrateSegments
        texts = segments.map(\.text)
        _ = learned.applyLearned(to: &texts)
        if let recording = LectureAudio.existing(for: studySet.id) { player.load(recording) }
    }

    /// A freshly transcribed lecture replaces the typed transcript, and is
    /// saved, because losing a forty-minute transcription to a back-swipe would
    /// be unforgivable.
    private func adopt(_ made: [NarrateSegment]) {
        segments = made
        texts = made.map(\.text)
        index = 0
        var updated = studySet
        updated.narrateSegments = made
        store.update(updated)
        if let recording = LectureAudio.existing(for: studySet.id) { player.load(recording) }
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
        withAnimation(.snappy) { report = outcome.summary() }
    }

    private func undo() {
        guard let outcome = lastOutcome else { return }
        learned.undo(snapshot, into: &texts, touching: outcome)
        lastOutcome = nil
        persistText()
        withAnimation(.snappy) { report = nil }
    }

    /// A correction is an edit to the transcript, so it outlives the screen.
    func persistText() {
        guard texts.count == segments.count else { return }
        for i in segments.indices { segments[i].text = texts[i] }
        var updated = studySet
        updated.narrateSegments = segments
        store.update(updated)
    }

    // MARK: the two pieces of chrome

    private var header: some View {
        let total = segments.count
        let fraction = player.hasAudio
            ? (player.duration > 0 ? player.time / player.duration : 0)
            : (total > 0 ? Double(index + (finished ? 1 : 0)) / Double(total) : 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Line \(min(index + 1, max(total, 1))) of \(total)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(player.hasAudio ? "Following the recording" : "Hold a word to fix it")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ThinProgress(fraction: min(1, max(0, fraction)))
        }
        .padding()
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if texts.isEmpty {
                    Text("This transcript is empty.").foregroundStyle(.secondary).padding()
                } else {
                    NarrateWordFlow(texts: texts, langs: segments.map(\.lang),
                                    currentIndex: index,
                                    spokenWord: spokenNow?.index,
                                    onJump: { jump(to: $0) },
                                    onFix: { fixing = $0 })
                        .contentCard()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                        .readableColumn()
                }
            }
            .onChange(of: index) { _, line in
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }
}
