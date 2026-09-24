import SwiftUI

/// The controls for a lecture that has a recording attached.
///
/// Kept apart from the reading-pace controls rather than shared, because the
/// two are not the same instrument. Reading pace has Play and a speed; a
/// recording has a position you can scrub to and a length you can see, and
/// pretending one is the other produces a bar where half the controls lie.
struct NarrateAudioBar: View {
    @ObservedObject var player: LecturePlayer
    @Binding var speed: Double
    /// Scrubbing must not fight the player: while the thumb is held, the slider
    /// shows the held value and the clock is only moved on release.
    @State private var scrubbing = false
    @State private var held: Double = 0

    private var position: Double { scrubbing ? held : player.time }

    var body: some View {
        StudyActionBar {
            VStack(spacing: 4) {
                Slider(value: Binding(get: { position },
                                      set: { held = $0 }),
                       in: 0...max(player.duration, 0.1),
                       onEditingChanged: { editing in
                           if editing {
                               held = player.time
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

            HStack(spacing: 12) {
                Button {
                    player.seek(to: player.time - 10)
                } label: { Image(systemName: "gobackward.10") }
                    .buttonStyle(.bigCompanion)
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
                    player.seek(to: player.time + 10)
                } label: { Image(systemName: "goforward.10") }
                    .buttonStyle(.bigCompanion)
                    .accessibilityLabel("Forward 10 seconds")

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(rate == 1 ? "Normal" : "\(rate, specifier: "%g")\u{00d7}") {
                            speed = rate
                            player.setRate(rate)
                        }
                    }
                } label: {
                    Text(speed == 1 ? "1\u{00d7}" : "\(speed, specifier: "%g")\u{00d7}")
                        .monospacedDigit()
                }
                .buttonStyle(.bigCompanion)
                .accessibilityLabel("Playback speed")
            }
        }
    }
}

/// What the screen shows while a recording is being turned into a transcript.
///
/// It reports progress as a state rather than a percentage, because the
/// recogniser does not report one and a fake bar that crawls to 90% and sits
/// there is worse than an honest spinner.
struct TranscribingBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.headline)
                Text("On this phone. The recording is not uploaded anywhere.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentCard()
        .padding(.horizontal, 16)
    }
}
