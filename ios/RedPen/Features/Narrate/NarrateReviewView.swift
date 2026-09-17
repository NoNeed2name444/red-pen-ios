import SwiftUI

/// The reading-pace narrate player — ports the web app's no-recording
/// fallback path: `playNarrate()` / `pauseNarrate()` / `narrateAdvance()` /
/// `jumpToNarrateSegment()` / `restartNarrate()` / the speed buttons
/// (0.75x / 1x / 1.5x). Each segment holds the reading spotlight for
/// `NarrateScheduler.segmentMs()`, then the highlight glides to the next
/// one; tapping any line jumps straight to it. A real recording synced by
/// timestamp (the web app's other path) is a larger feature — on-device
/// transcription and alignment — left for later; this always-available
/// typed-transcript path is what most Narrate sets are read with anyway.
struct NarrateReviewView: View {
    let studySet: StudySet
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var playing = false
    @State private var finished = false
    @State private var speed: Double = 1
    @State private var timer: Timer?
    @State private var remainingMs: Double = 0
    @State private var segStartedAt: Date = Date()

    /// Preview-only entry point (see PreviewLaunch) so CI can screenshot a
    /// mid-playback or finished state without a live timer running.
    init(set studySet: StudySet, startIndex: Int = 0, startPlaying: Bool = false, startFinished: Bool = false) {
        self.studySet = studySet
        _index = State(initialValue: min(startIndex, max(0, studySet.narrateSegments.count - 1)))
        _playing = State(initialValue: startPlaying)
        _finished = State(initialValue: startFinished)
    }

    private var segments: [NarrateSegment] { studySet.narrateSegments }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            controls
        }
        .modeScreen(.narrate)
        .navigationTitle(studySet.subject.isEmpty ? "Narrate" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { timer?.invalidate() }
    }

    // MARK: header — matches renderNarrateProgress()

    private var header: some View {
        let total = segments.count
        let fraction = total > 0 ? Double(index + (finished ? 1 : 0)) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Line \(min(index + 1, max(total, 1))) of \(total)")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ThinProgress(fraction: min(1, fraction))
        }
        .padding()
    }

    // MARK: transcript — matches renderNarrateSegmentsHtml() / renderNarrateHighlight()

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if segments.isEmpty {
                    Text("This transcript is empty.").foregroundStyle(.secondary).padding()
                } else {
                    FlowText(segments: segments, currentIndex: index) { i in
                        jump(to: i)
                    }
                    .contentCard()
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 24) // keeps the last lines clear of the floating glass controls
                }
            }
            .onChange(of: index) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(segments.indices.contains(newValue) ? segments[newValue].id : nil, anchor: .center)
                }
            }
        }
    }

    // MARK: controls — matches el.narratePlayBtn / restart / speed buttons

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

    // MARK: playback logic — ported 1:1 from the web app's timers

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

/// A wrapping run of tappable phrases with the current one highlighted —
/// matches `.narrate-seg` / `.narrate-current` styling. SwiftUI has no
/// built-in inline-flow tap targets, so this lays words out itself with a
/// simple wrapping HStack-in-a-VStack.
private struct FlowText: View {
    let segments: [NarrateSegment]
    let currentIndex: Int
    let onTap: (Int) -> Void

    var body: some View {
        // Each segment is its own paragraph-ish chunk (readable + simple);
        // the web app's continuous inline flow becomes one block per line.
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                Text(seg.text)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(i == currentIndex ? Color.accentColor : .primary)
                    .fontWeight(i == currentIndex ? .semibold : .regular)
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .background(i == currentIndex ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
                    .id(seg.id)
                    .onTapGesture { onTap(i) }
                    .environment(\.layoutDirection, seg.lang == "ar" ? .rightToLeft : .leftToRight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
