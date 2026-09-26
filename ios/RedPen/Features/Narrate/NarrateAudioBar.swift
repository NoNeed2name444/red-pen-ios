import SwiftUI

/// The controls for a lecture that has a recording attached.
///
/// Kept apart from the reading-pace controls rather than shared, because the
/// two are not the same instrument. Reading pace has Play and a speed; a
/// recording has a position you can scrub to and a length you can see, and
/// pretending one is the other produces a bar where half the controls lie.
///
/// This is the bar's content: the screen hands it to `.studyBar { }`, so the
/// transcript scrolls under the glass. The arrow keys skip back fifteen
/// seconds and forward thirty, as the buttons do; Space plays and pauses.
struct NarrateAudioBar: View {
    @ObservedObject var player: LecturePlayer
    /// The position, fifteen times a second. Watched here and only here, so
    /// the moving slider does not rebuild the transcript above it.
    @ObservedObject var clock: LectureClock
    @Binding var speed: Double
    /// Scrubbing must not fight the player: while the thumb is held, the slider
    /// shows the held value and the clock is only moved on release.
    @State private var scrubbing = false
    @State private var held: Double = 0

    private var position: Double { scrubbing ? held : clock.time }

    var body: some View {
        VStack(spacing: 12) {
            scrubber
            transport
        }
    }

    private var scrubber: some View {
        let length: Double = max(player.duration, 0.1)
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { position },
                                  set: { held = $0 }),
                   in: 0...length,
                   onEditingChanged: { editing in
                       if editing {
                           held = clock.time
                           scrubbing = true
                       } else {
                           scrubbing = false
                           player.seek(to: held)
                       }
                   })
                .tint(StudySetKind.narrate.tint)
                .accessibilityLabel("Position in the recording")

            HStack {
                Text(LectureAudio.clock(position))
                Spacer()
                Text(LectureAudio.clock(player.duration))
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// Back fifteen, Play, forward thirty - the order every player uses, and
    /// the steps a podcast player uses: back for "what did she just say",
    /// forward for a tangent - and the speed, a compact menu, beside them.
    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                player.skip(by: -NowPlaying.back)
            } label: { Image(systemName: "gobackward.15") }
                .buttonStyle(.bigCompanion)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Back 15 seconds")

            Button {
                player.toggle()
            } label: {
                Label(player.playing ? "Pause" : "Play",
                      systemImage: player.playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                player.skip(by: NowPlaying.forward)
            } label: { Image(systemName: "goforward.30") }
                .buttonStyle(.bigCompanion)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Forward 30 seconds")

            speedMenu
        }
    }

    /// 0.75x to 2.5x in quarter steps. The screen hands the choice to the
    /// player and remembers it for this lecture; the voice keeps its pitch.
    private var speedMenu: some View {
        let shown: String = AudioRate.label(speed)
        return Menu {
            // a picker inside the menu ticks the chosen speed by itself
            Picker("Playback speed", selection: $speed) {
                ForEach(AudioRate.steps, id: \.self) { rate in
                    Text(AudioRate.name(rate)).tag(rate)
                }
            }
        } label: {
            Text(shown)
                .monospacedDigit()
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Playback speed, \(shown)")
    }
}

/// What the screen shows while a recording is being turned into a transcript.
///
/// It reports progress as a state rather than a percentage, because the
/// recogniser does not report one and a fake bar that crawls to 90% and sits
/// there is worse than an honest spinner.
struct TranscribingBanner: View {
    let message: String
    /// False while Gemini has it, so the line under the message says where
    /// the recording went rather than promising it stayed on the phone.
    var onDevice: Bool = true

    private var whereLine: String {
        if onDevice { return "On this phone. The recording is not uploaded anywhere." }
        return "Gemini (Pro) is transcribing it: the recording went through \(Brand.name) to Google."
    }

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.headline)
                Text(whereLine)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentCard()
        .padding(.horizontal, 16)
    }
}
