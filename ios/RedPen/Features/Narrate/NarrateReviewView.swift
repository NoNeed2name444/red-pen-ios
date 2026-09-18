import SwiftUI

/// The reading-pace narrate player - ports the web app's no-recording
/// fallback path: each segment holds the reading spotlight for
/// `NarrateScheduler.segmentMs()`, then the highlight glides to the next one;
/// tapping any line jumps straight to it.
///
/// The transcript is now EDITABLE, which is why the text lives in state rather
/// than being read out of the set on every redraw. Long-press a word, say what
/// it should have been, and three things happen: that word is fixed, every
/// other word in the transcript that sounds the same is fixed with it, and the
/// pronunciation is remembered so next week's lecture never shows it. All of
/// it is reported and all of it undoes in one action - see FixWordSheet.
struct NarrateReviewView: View {
    let studySet: StudySet
    @EnvironmentObject var store: Store
    @EnvironmentObject var learned: PronunciationLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var playing = false
    @State private var finished = false
    @State private var speed: Double = 1
    @State private var timer: Timer?
    @State private var remainingMs: Double = 0
    @State private var segStartedAt: Date = Date()

    /// The lines as they now read. Seeded from the set, then edited in place.
    @State private var texts: [String] = []
    @State private var fixing: FixTarget?
    @State private var report: String?
    @State private var lastOutcome: CorrectionOutcome?
    @State private var snapshot: [String] = []

    /// Preview-only entry points (see PreviewLaunch) so CI can screenshot a
    /// mid-playback, finished, or mid-correction state without a live timer.
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

    private var segments: [NarrateSegment] { studySet.narrateSegments }
    private var langs: [String] { segments.map(\.lang) }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            controls
        }
        .modeScreen(.narrate)
        .navigationTitle(studySet.subject.isEmpty ? "Narrate" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seed)
        .onDisappear { timer?.invalidate() }
        .sheet(item: $fixing) { target in
            FixWordSheet(target: target) { spelling in fix(target, to: spelling) }
        }
        .safeAreaInset(edge: .bottom) {
            if let report {
                FixReport(summary: report, onUndo: undo)
            }
        }
    }

    /// Seeds the editable text, and applies everything already learned - the
    /// "fix it once, never see it again" half of the feature.
    private func seed() {
        guard texts.isEmpty else { return }
        texts = segments.map(\.text)
        _ = learned.applyLearned(to: &texts)
    }

    private func fix(_ target: FixTarget, to spelling: String) {
        snapshot = texts
        let outcome = learned.fix(segment: target.segment, words: target.word...target.word,
                                  to: spelling, in: &texts)
        guard outcome.here != nil else { return }
        lastOutcome = outcome
        withAnimation(.snappy) { report = outcome.summary() }
    }

    private func undo() {
        guard let outcome = lastOutcome else { return }
        learned.undo(snapshot, into: &texts, touching: outcome)
        lastOutcome = nil
        withAnimation(.snappy) { report = nil }
    }

    // MARK: header - matches renderNarrateProgress()

    private var header: some View {
        let total = segments.count
        let fraction = total > 0 ? Double(index + (finished ? 1 : 0)) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Line \(min(index + 1, max(total, 1))) of \(total)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Hold a word to fix it")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ThinProgress(fraction: min(1, fraction))
        }
        .padding()
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if texts.isEmpty {
                    Text("This transcript is empty.").foregroundStyle(.secondary).padding()
                } else {
                    NarrateWordFlow(texts: texts, langs: langs, currentIndex: index,
                                    onJump: { jump(to: $0) },
                                    onFix: { fixing = $0 })
                        .contentCard()
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
            .onChange(of: index) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 10) {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                speedButton(0.75, "Slow")
                speedButton(1, "Normal")
                speedButton(1.5, "Fast")
            }
            HStack(spacing: 12) {
                if finished {
                    Button("Restart") { restart() }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(playing ? "Pause" : "Play") { playing ? pause() : play() }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(segments.isEmpty)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func speedButton(_ value: Double, _ label: String) -> some View {
        Button(label) { speed = value }
            .buttonStyle(.glass).tint(speed == value ? StudySetKind.narrate.tint : Color.secondary)
    }

    // MARK: playback logic - ported 1:1 from the web app's timers

    private func play() {
        guard !finished, !segments.isEmpty else { return }
        playing = true
        if remainingMs == 0 { remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed) }
        scheduleAdvance()
    }

    private func pause() {
        guard playing else { return }
        let elapsed = Date().timeIntervalSince(segStartedAt) * 1000
        remainingMs = max(200, remainingMs - elapsed)
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
        guard index < segments.count - 1 else {
            finish()
            return
        }
        index += 1
        remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed)
        if playing { scheduleAdvance() }
    }

    private func finish() {
        playing = false
        finished = true
        timer?.invalidate()
    }

    private func jump(to i: Int) {
        guard !segments.isEmpty else { return }
        timer?.invalidate()
        index = max(0, min(segments.count - 1, i))
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
