import SwiftUI

/// Why the microphone isn't being used, and the way to change it.
struct VoicePermissionNote: View {
    let message: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Label(message, systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(Color.wardInkSecondary)
            Button("Open Settings") { VoiceAccess.openSettings() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.wardPrimaryInk)
                .buttonStyle(.borderless)
                // a whole finger's worth of target, not just the words
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        // a note, so pressed into the base like a banner
        .wardInset(in: shape)
    }
}

/// The small "Example" label on a shipped example attempt.
struct VoiceExampleTag: View {
    var body: some View {
        WardChip(text: "Example", tone: .grey)
    }
}

/// A station's countdown, as a timer pill: red in the last minute, "Time"
/// at the end.
///
/// Counted to a fixed end time rather than ticked down, so it stays right
/// through the screen locking and the app being in the background.
struct StationTimerChip: View {
    /// When time runs out; nil shows a full station, not started.
    let endsAt: Date?
    let totalSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            StationTimerFace(left: secondsLeft(at: context.date))
        }
    }

    private func secondsLeft(at date: Date) -> Int {
        guard let endsAt else { return totalSeconds }
        let rest: Double = endsAt.timeIntervalSince(date).rounded(.up)
        return max(0, Int(rest))
    }

    /// One station's length in the exam the student is sitting.
    nonisolated static var stationSeconds: Int { ExamTrack.current.stationMinutes * 60 }
}

/// The pill itself, for a number of seconds left.
private struct StationTimerFace: View {
    let left: Int

    private var spoken: String {
        if left == 0 { return "Station time is up" }
        let minutes: Int = left / 60
        let seconds: Int = left % 60
        return "Station clock, \(minutes) minutes \(seconds) seconds left"
    }

    var body: some View {
        WardTimerPill(seconds: left, warnBelow: 61)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }
}
