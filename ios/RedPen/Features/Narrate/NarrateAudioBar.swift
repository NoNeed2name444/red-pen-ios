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
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 8) {
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

                HStack {
                    Text(LectureAudio.clock(position))
                    Spacer()
                    Text(LectureAudio.clock(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        player.seek(to: player.time - 10)
                    } label: { Image(systemName: "gobackward.10") }
                        .buttonStyle(.glass)

                    Button {
                        player.toggle(rate: speed)
                    } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        player.seek(to: player.time + 10)
                    } label: { Image(systemName: "goforward.10") }
                        .buttonStyle(.glass)

                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(rate == 1 ? "Normal" : "\(rate, specifier: "%g")\u{00d7}") {
                                speed = rate
                                player.setRate(rate)
                            }
                        }
                    } label: {
                        Text(speed == 1 ? "1\u{00d7}" : "\(speed, specifier: "%g")\u{00d7}")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
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
                Text(message).font(.subheadline.weight(.medium))
                Text("On this phone. The recording is not uploaded anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentCard()
        .padding(.horizontal)
    }
}
