import SwiftUI

/// Narrate without a recording.
///
/// A typed transcript has no audio to follow, so the lines are held for a
/// reading pace worked out from their length - the web app's behaviour, and
/// still the right one for a lecture the student typed out themselves.
///
/// Kept apart from the view for two reasons: none of it is about how anything
/// looks, and NarrateReviewView's body was long enough that the compiler
/// stopped being able to type-check it.
extension NarrateReviewView {

    func play() {
        guard !finished, !segments.isEmpty else { return }
        playing = true
        if remainingMs == 0 {
            remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed)
        }
        scheduleAdvance()
    }

    /// Pausing keeps the part of the line that has not been read yet, so
    /// resuming does not start the line over.
    func pause() {
        guard playing else { return }
        remainingMs = max(200, remainingMs - Date().timeIntervalSince(segStartedAt) * 1000)
        timer?.invalidate()
        playing = false
    }

    func scheduleAdvance() {
        timer?.invalidate()
        segStartedAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: remainingMs / 1000, repeats: false) { _ in
            Task { @MainActor in advance() }
        }
    }

    func advance() {
        guard index < segments.count - 1 else { finish(); return }
        index += 1
        remainingMs = NarrateScheduler.segmentMs(segments[index], speed: speed)
        if playing { scheduleAdvance() }
    }

    func finish() {
        playing = false
        finished = true
        timer?.invalidate()
    }

    /// Tapping a line means "take me there" in both states - to that moment in
    /// the recording, or to that point in the reading.
    func jump(to i: Int) {
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

    func restart() {
        timer?.invalidate()
        index = 0
        finished = false
        playing = false
        remainingMs = segments.isEmpty ? 0
                                       : NarrateScheduler.segmentMs(segments[0], speed: speed)
    }
}
