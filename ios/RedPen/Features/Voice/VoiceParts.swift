import SwiftUI

/// Why the microphone isn't being used, and the way to change it.
struct VoicePermissionNote: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(message, systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open Settings") { VoiceAccess.openSettings() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                // a whole finger's worth of target, not just the words
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The small "Example" label on a shipped example attempt.
struct VoiceExampleTag: View {
    var body: some View {
        Text("Example")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

/// A station's countdown, as a chip: red in the last minute, "Time" at the end.
///
/// Counted to a fixed end time rather than ticked down, so it stays right
/// through the screen locking and the app being in the background. A glass
/// chip on the raised plane: inside a raised header it sits flush.
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

/// The chip itself, for a number of seconds left.
private struct StationTimerFace: View {
    let left: Int

    private var clock: String {
        if left == 0 { return "Time" }
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    private var spoken: String {
        if left == 0 { return "Station time is up" }
        let minutes: Int = left / 60
        let seconds: Int = left % 60
        return "Station clock, \(minutes) minutes \(seconds) seconds left"
    }

    var body: some View {
        let ink: Color = left <= 60 ? Color.red : Color.primary
        HStack(spacing: 5) {
            Image(systemName: "timer").font(.caption2)
            Text(clock)
                .monospacedDigit()
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .liquidGlassChip(plane: .raised)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
