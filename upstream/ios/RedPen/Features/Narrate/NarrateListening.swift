import SwiftUI

/// Listening to a lecture: its speed, its sections and the sleep timer, for
/// the recording and for the lecture read aloud alike.
///
/// Kept apart from NarrateReviewView for the same reason NarrateReading is:
/// none of it is about how anything looks, and the view's body is already as
/// long as the compiler will type-check in one go.
extension NarrateReviewView {

    /// Whichever is playing the lecture: the recording, or the voice.
    private var sleepTarget: SleepTarget {
        if player.hasAudio { return player }
        return voice
    }

    var sections: [AudioChapter] {
        player.hasAudio ? player.chapters : voice.chapters
    }

    /// The section being heard. A recording says for itself (its transcript
    /// may have no word times to move the line by); the voice is on the line
    /// the screen shows.
    var currentSection: Int? {
        if player.hasAudio { return player.section }
        return AudioChapters.index(containingLine: index, in: voice.chapters)
    }

    var listenRow: some View {
        NarrateListenRow(sections: sections, current: currentSection, sleep: sleep,
                         onPrevious: previousSection, onNext: nextSection,
                         onPick: pickSection)
    }

    /// The speed changes, and speed changes coming back from the lock
    /// screen, kept in step with the screen's own.
    func listenSync<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: player.rate) { _, now in
                if now != speed { speed = now }
            }
            .onChange(of: voice.speed) { _, now in
                if now != speed { speed = now }
            }
            .onChange(of: player.hasAudio) { _, _ in attachSleep() }
    }

    // MARK: speed

    /// The speed this lecture was last heard at, or the last one chosen.
    func restoreSpeed() {
        let kept: Double = AudioRate.remembered(for: studySet.id, in: .standard)
        speed = kept
        voice.setSpeed(kept)
        player.setRate(kept)
    }

    /// Kept for this lecture, and as the speed the next new one opens at -
    /// but only when it is a choice, not the lecture opening at its own.
    func speedChosen(_ now: Double) {
        voice.setSpeed(now)
        player.setRate(now)
        guard AudioRate.remembered(for: studySet.id, in: .standard) != now else { return }
        AudioRate.remember(now, for: studySet.id, in: .standard)
    }

    // MARK: sections

    /// Worked out once per transcript, with the rest of the layout.
    func layoutSections() {
        let starts: [Double?] = segments.map(\.start)
        let ends: [Double?] = segments.map(\.end)
        let made: [AudioChapter] = AudioChapters.derive(lines: texts, starts: starts, ends: ends)
        voice.setChapters(made)
        player.setChapters(made)
    }

    func previousSection() {
        if player.hasAudio { player.previousSection() } else { voice.previousSection() }
    }

    func nextSection() {
        if player.hasAudio { player.nextSection() } else { voice.nextSection() }
    }

    func pickSection(_ i: Int) {
        if player.hasAudio { player.jump(toSection: i) } else { voice.jump(toSection: i) }
    }

    // MARK: the sleep timer

    /// The timer stops whichever is playing; adding a recording moves it.
    func attachSleep() {
        sleep.attach(sleepTarget)
    }
}
