import SwiftUI

/// Narrate without a recording: the lecture read aloud.
///
/// It used to hold each line silently for a reading pace, so the highlight
/// jumped a whole line every couple of seconds. NarrateVoice now reads it -
/// the natural cloud voice when it can, the phone's own otherwise - and the
/// word being said is lit as it is said.
///
/// Kept apart from the view for two reasons: none of it is about how anything
/// looks, and NarrateReviewView's body was long enough that the compiler
/// stopped being able to type-check it.
extension NarrateReviewView {

    func play() {
        guard !segments.isEmpty else { return }
        if finished {
            index = 0
            finished = false
        }
        playing = true
        if voice.spot.line == index {
            voice.resume()
        } else {
            voice.play(from: index)
        }
    }

    /// Pausing keeps the place, word and all, so Play carries on from it.
    func pause() {
        playing = false
        voice.pause()
    }

    /// Tapping a line means "take me there" in both states - to that moment in
    /// the recording, or to that line of the reading.
    func jump(to i: Int) {
        guard !segments.isEmpty else { return }
        index = max(0, min(segments.count - 1, i))
        if player.hasAudio {
            if let start = segments[index].start { player.seek(to: start) }
            return
        }
        finished = false
        voice.jump(to: index)
    }

    func restart() {
        index = 0
        finished = false
        playing = false
        voice.jump(to: 0)
    }
}
