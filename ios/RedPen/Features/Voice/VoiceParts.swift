import SwiftUI

/// Why the microphone isn't being used, and the way to change it.
struct VoicePermissionNote: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "mic.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open Settings") { VoiceAccess.openSettings() }
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
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
/// through the screen locking and the app being in the background.
struct StationTimerChip: View {
    /// When time runs out; nil shows a full station, not started.
    let endsAt: Date?
    let totalSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = endsAt.map { max(0, Int($0.timeIntervalSince(context.date).rounded(.up))) } ?? totalSeconds
            HStack(spacing: 5) {
                Image(systemName: "timer").font(.caption2)
                Text(left == 0 ? "Time" : String(format: "%d:%02d", left / 60, left % 60))
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(left <= 60 ? Color.red : Color.primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .liquidGlassChip()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(left == 0 ? "Station time is up" : "Station clock, \(left / 60) minutes \(left % 60) seconds left")
        }
    }

    /// One station's length in the exam the student is sitting.
    nonisolated static var stationSeconds: Int { ExamTrack.current.stationMinutes * 60 }
}
