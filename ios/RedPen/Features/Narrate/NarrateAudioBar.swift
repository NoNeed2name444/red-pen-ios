import SwiftUI

/// The controls for a lecture that has a recording attached.
///
/// Kept apart from the reading-pace controls rather than shared, because the
/// two are not the same instrument. Reading pace has Play and a speed; a
/// recording has a position you can scrub to and a length you can see, and
/// pretending one is the other produces a bar where half the controls lie.
///
/// This is the bar's content: the screen hands it to `.studyBar { }`, so the
/// transcript scrolls under the glass. The arrow keys skip ten seconds either
/// way; Space plays and pauses.
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

    /// Back ten, Play, forward ten - the order every player uses - and the
    /// speed, a compact menu, beside them.
    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                player.seek(to: clock.time - 10)
            } label: { Image(systemName: "gobackward.10") }
                .buttonStyle(.bigCompanion)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .accessibilityLabel("Back 10 seconds")

            Button {
                player.toggle(rate: speed)
            } label: {
                Label(player.playing ? "Pause" : "Play",
                      systemImage: player.playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bigPrimary)
            .keyboardShortcut(.space, modifiers: [])

            Button {
                player.seek(to: clock.time + 10)
            } label: { Image(systemName: "goforward.10") }
                .buttonStyle(.bigCompanion)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .accessibilityLabel("Forward 10 seconds")

            speedMenu
        }
    }

    private var speedMenu: some View {
        let shown: String = Self.rateLabel(speed)
        return Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button(Self.rateName(rate)) {
                    speed = rate
                    player.setRate(rate)
                }
            }
        } label: {
            Text(shown)
                .monospacedDigit()
        }
        .buttonStyle(.bigCompanion)
        .accessibilityLabel("Playback speed, \(shown)")
    }

    /// "1.5\u{00d7}" - the speed as the chip shows it.
    private static func rateLabel(_ rate: Double) -> String {
        String(format: "%g\u{00d7}", rate)
    }

    private static func rateName(_ rate: Double) -> String {
        rate == 1 ? "Normal" : rateLabel(rate)
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
