import Foundation
import Combine

/// What the sleep timer stops: the recording, or the voice reading the lecture.
@MainActor
protocol SleepTarget: AnyObject {
    var sleepPlaying: Bool { get }
    /// Where the section playing now ends, in the player's own terms - a
    /// moment in the recording, or the line the voice stops before. Nil when
    /// it cannot say.
    func sleepSectionEnd() -> Double?
    /// Listening seconds until `end`; zero or less once there.
    func sleepSecondsLeft(until end: Double) -> Double
    func sleepFade(_ level: Float)
    /// Pause, and put the volume back for when the student wakes.
    func sleepFinish()
    /// Set by the timer: called when the student moves the place by hand.
    var sleepMoved: (@MainActor () -> Void)? { get set }
}

/// The sleep timer: counts down the listening time left, fades the last ten
/// seconds out and pauses.
///
/// It checks once a second (ten times a second through the fade) on a
/// sleeping Task - never a frame loop - and those checks keep running with the
/// phone locked, because the audio playing is what keeps the app awake. A
/// check measures the time since the last one rather than assuming it was a
/// second, so a late one does not stretch the timer. The countdown itself is
/// SleepCountdown, which the Linux tests cover.
@MainActor
final class SleepTimer: ObservableObject {
    /// What the chip shows. Published only when the label or the choice
    /// changes - once a second at most, even while the fade checks ten
    /// times a second.
    @Published private(set) var countdown: SleepCountdown?
    /// The countdown as the checks see it, to the tenth of a second.
    private var live: SleepCountdown?

    private weak var target: SleepTarget?
    /// For "end of this section": where it ends, fixed when set (or when the
    /// student moves), so reaching it does not roll on to the next one.
    private var mark: Double?
    private var task: Task<Void, Never>?
    private var lastCheck = Date()

    var running: Bool { live != nil }

    /// The player the timer stops. A new one cancels the timer.
    func attach(_ newTarget: SleepTarget?) {
        guard newTarget !== target else { return }
        cancel()
        target?.sleepMoved = nil
        target = newTarget
        newTarget?.sleepMoved = { [weak self] in self?.rearm() }
    }

    func start(_ choice: SleepChoice) {
        guard let target else { return }
        cancel()
        var left: Double?
        if choice == .endOfSection {
            guard let end = target.sleepSectionEnd() else { return }
            mark = end
            left = target.sleepSecondsLeft(until: end)
        }
        guard let made = SleepCountdown(choice: choice, sectionLeft: left) else { return }
        live = made
        countdown = made
        lastCheck = Date()
        task = Task { [weak self] in
            while let wait = self?.live?.nextCheck {
                let nanos: UInt64 = UInt64(wait * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                self?.check()
            }
        }
    }

    /// Off: the volume comes straight back.
    func cancel() {
        task?.cancel()
        task = nil
        mark = nil
        if live != nil { target?.sleepFade(1) }
        live = nil
        if countdown != nil { countdown = nil }
    }

    private func check() {
        guard var now = live, let target else {
            cancel()
            return
        }
        let at = Date()
        let heard: Double = at.timeIntervalSince(lastCheck)
        lastCheck = at
        if let mark {
            now.follow(sectionLeft: target.sleepSecondsLeft(until: mark))
        } else if target.sleepPlaying {
            now.advance(listened: heard)
        }
        if now.isDone {
            finish()
            return
        }
        live = now
        show(now)
        if target.sleepPlaying { target.sleepFade(now.volume) }
    }

    private func finish() {
        task?.cancel()
        task = nil
        mark = nil
        live = nil
        countdown = nil
        target?.sleepFinish()
    }

    private func show(_ now: SleepCountdown) {
        guard now.label != countdown?.label || now.choice != countdown?.choice else { return }
        countdown = now
    }

    /// The student moved (a scrub, a tapped line, a section): "the end of
    /// this section" is now the end of the one they moved to.
    private func rearm() {
        guard let now = live, now.choice == .endOfSection, let target,
              let end = target.sleepSectionEnd() else { return }
        mark = end
        var moved: SleepCountdown = now
        moved.follow(sectionLeft: target.sleepSecondsLeft(until: end))
        live = moved
        show(moved)
        target.sleepFade(moved.volume)
    }
}
