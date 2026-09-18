import SwiftUI
import UniformTypeIdentifiers

/// The Narrate player, in its two states.
///
/// With a recording attached it follows the audio: the recogniser's own word
/// timestamps decide which word is lit, and the clock is the audio's position,
/// so scrubbing and speed changes cannot put the highlight out of step. With no
/// recording it falls back to the web app's reading pace, holding each line for
/// `NarrateScheduler.segmentMs()`.
///
/// The transcript is editable either way: long-press a word, say what it should
/// have been, and the fix spreads to everything that sounds the same and is
/// remembered for next time - see FixWordSheet.
struct NarrateReviewView: View {
    let studySet: StudySet
    @EnvironmentObject var store: Store
    @EnvironmentObject var learned: PronunciationLibrary
    @StateObject private var player = LecturePlayer()
    @StateObject private var importer = LectureImporter()

    @State private var index = 0
    @State private var playing = false
    @State private var finished = false
    @State private var speed: Double = 1
    @State private var timer: Timer?
    @State private var remainingMs: Double = 0
    @State private var segStartedAt = Date()

    @State private var segments: [NarrateSegment] = []
    @State private var texts: [String] = []
    @State private var fixing: FixTarget?
    @State private var report: String?
    @State private var lastOutcome: CorrectionOutcome?
    @State private var snapshot: [String] = []
    @State private var importing = false

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

    /// Word timings exist only when a recording was transcribed.
    private var words: [TranscriptWord] {
        guard let measured = NarrateScheduler.measured(segments) else { return [] }
        return WordTiming.layout(texts: texts,
                                 ends: segments.map { $0.end ?? 0 },
                                 measured: measured)
    }

    private var spokenNow: TranscriptWord? {
        player.hasAudio ? WordTiming.word(at: player.time, in: words) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = importer.working { TranscribingBanner(message: message) }
            transcript
            if player.hasAudio {
                NarrateAudioBar(player: player, speed: $speed)
            } else {
                NarrateReadingControls(speed: $speed, playing: playing, finished: finished,
                                       canPlay: !segments.isEmpty,
                                       onPlayPause: { playing ? pause() : play() },
                                       onRestart: restart)
            }
        }
        .modeScreen(.narrate)
        .navigationTitle(studySet.subject.isEmpty ? "Narrate" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seed)
        .onDisappear { timer?.invalidate(); player.stop() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: {
                    Label(player.hasAudio ? "Replace recording" : "Add recording",
                          systemImage: "waveform")
                }
                .buttonStyle(.glass)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { picked in
            Task { await importer.attach(picked, to: studySet, learned: learned) }
        }
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
        .alert("Couldn't use that recording", isPresented: Binding(
            get: { importer.trouble != nil }, set: { if !$0 { importer.trouble = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(importer.trouble ?? "") }
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
    private func persistText() {
        guard texts.count == segments.count else { return }
        for i in segments.indices { segments[i].text = texts[i] }
        var updated = studySet
        updated.narrateSegments = segments
        store.update(updated)
    }

    // MARK: the screen

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
                }
            }
            .onChange(of: index) { _, line in
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }

    // MARK: the reading pace, for a set with no recording

    private func play() {
        guard !finished, !segments.isEmpty else { return }
        playing = true
        if remainingMs == 0 { remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed) }
        scheduleAdvance()
    }

    private func pause() {
        guard playing else { return }
        remainingMs = max(200, remainingMs - Date().timeIntervalSince(segStartedAt) * 1000)
        timer?.invalidate()
        playing = false
    }

    private func scheduleAdvance() {
        timer?.invalidate()
        segStartedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: remainingMs / 1000, repeats: false) { _ in
            Task { @MainActor in advance() }
        }
    }

    private func advance() {
        guard index < segments.count - 1 else { finish(); return }
        index += 1
        remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed)
        if playing { scheduleAdvance() }
    }

    private func finish() {
        playing = false
        finished = true
        timer?.invalidate()
    }

    /// Tapping a line means "take me there" in both states - to that moment in
    /// the recording, or to that point in the reading.
    private func jump(to i: Int) {
        guard !segments.isEmpty else { return }
        index = max(0, min(segments.count - 1, i))
        if player.hasAudio {
            if let start = segments[index].start { player.seek(to: start) }
            return
        }
        timer?.invalidate()
        finished = false
        remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed)
        if playing { scheduleAdvance() }
    }

    private func restart() {
        timer?.invalidate()
        index = 0
        finished = false
        playing = false
        remainingMs = segments.isEmpty ? 0 : NarrateScheduler.segmentMs(segments[0], speed: speed)
    }
}
