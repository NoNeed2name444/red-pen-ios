import Combine
import SwiftUI
import UIKit
import UserNotifications
#if canImport(ActivityKit) && !SWIFT_PACKAGE
import ActivityKit
#endif

/// Runs the one ward round (WardRound, in StudySession.swift): starts it,
/// keeps it across a relaunch, and acts on what its clock says.
///
/// There is no ticking timer here. The clock is dates; this sleeps until the
/// running phase is due to end, wakes once, and moves the round on - and
/// does the same whenever the app comes back to the front, for whatever
/// ended while the phone was locked. The screens showing a round redraw
/// themselves once a second while they are on screen (WardRoundRing).
///
/// What the round does to the rest of the app:
/// - each round's focus minutes go into StudyLog, so they count for the
///   streak, and to Health when that is on (PlatformNotice.focusRoundEnded,
///   MindfulMinutes);
/// - everything studied while a round's clock runs is counted on it, from
///   StudyLog.recorded;
/// - the end of a round and of its break are left with the notification
///   centre, which only shows them while the app is not in front
///   (LearnNotificationDelegate shows nothing but "learn-" in front); in
///   front the chip says so instead (`notice`);
/// - the Xcode build shows it as a Live Activity (WardRoundActivity).
@MainActor
final class WardRoundClock: ObservableObject {
    static let shared = WardRoundClock()

    /// The running round, JSON.
    static let stateKey = "wardRound.state"
    /// The last choices on the tile.
    static let focusKey = "wardRound.focusMinutes"
    static let breakKey = "wardRound.breakMinutes"

    /// The round under way, or nil.
    @Published private(set) var round: WardRound?
    /// A short line when a phase ends in front of the student ("Round 2 of
    /// 4 done - take 5 minutes"); the chip shows it for a few seconds.
    @Published private(set) var notice: String?

    private var wake: Task<Void, Never>?
    private var noticeClear: Task<Void, Never>?
    private var bag: Set<AnyCancellable> = []
    private var restored = false
    /// Bumped on every reschedule, so a slower earlier one never adds its
    /// alarms after a later one cleared them.
    private var alarmGeneration = 0

    private init() {
        StudyLog.shared.recorded
            .sink { [weak self] count in self?.studied(count) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &bag)
    }

    /// Screenshot runs and UI tests never see a round unless they ask for
    /// one with `-wardRoundDemo`.
    private static var automated: Bool {
        let args: [String] = ProcessInfo.processInfo.arguments
        let marks: [String] = ["-uiPreviewScreen", "-stillSky", "-graphPreview", "-personalBuild"]
        return args.contains { marks.contains($0) }
    }

    private static var demo: Bool { ProcessInfo.processInfo.arguments.contains("-wardRoundDemo") }

    /// Once, when the library is on screen: picks up a round left running.
    func restore() {
        guard !restored else { return }
        restored = true
        if Self.demo {
            start(.standard)
            return
        }
        guard !Self.automated,
              let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let saved = try? JSONDecoder().decode(WardRound.self, from: data),
              saved.phase != .done else {
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
            return
        }
        round = saved
        tick()
        changed()
    }

    // MARK: the student's moves

    func start(_ plan: WardRoundPlan) {
        UserDefaults.standard.set(plan.focusMinutes, forKey: Self.focusKey)
        UserDefaults.standard.set(plan.breakMinutes, forKey: Self.breakKey)
        round = WardRound.begin(plan, at: Date())
        notice = nil
        changed()
    }

    func pause() { edit { $0.pause(at: Date()) } }

    func resume() { edit { $0.resume(at: Date()) } }

    func startNext() { edit { $0.startNext(at: Date()) } }

    /// Ends the running round early (its time still counts) or skips a break.
    func skip() {
        guard var now = round else { return }
        let events: [WardRound.Event] = now.skip(at: Date())
        round = now
        handle(events, quietly: true)
        changed()
    }

    /// Stops the whole ward round; a round under way counts for its time.
    func stop() {
        guard var now = round else { return }
        let events: [WardRound.Event] = now.stop(at: Date())
        handle(events, quietly: true)
        close()
    }

    /// Puts a finished (or stopped) ward round away.
    func close() {
        round = nil
        notice = nil
        changed()
    }

    private func edit(_ change: (inout WardRound) -> Void) {
        guard var now = round else { return }
        change(&now)
        round = now
        changed()
    }

    // MARK: the clock

    /// Moves the round on to now, for whatever has ended since it last looked.
    func tick() {
        guard var now = round else { return }
        let events: [WardRound.Event] = now.advance(to: Date())
        guard !events.isEmpty else {
            arm()
            return
        }
        round = now
        handle(events, quietly: UIApplication.shared.applicationState != .active)
        changed()
    }

    private func studied(_ count: Int) {
        guard var now = round, now.phase == .focus else { return }
        now.noteStudied(count)
        round = now
        save()
        WardRoundActivity.sync(now, soon: true)
    }

    /// What ended: minutes to the log and to Health, and a line in front.
    private func handle(_ events: [WardRound.Event], quietly: Bool) {
        for event in events {
            switch event {
            case .focusEnded(_, let seconds, let end):
                StudyLog.shared.recordMinutes(Int(seconds / 60), on: end)
                if seconds >= 60 {
                    let start: Date = end.addingTimeInterval(-seconds)
                    PlatformNotice.post(PlatformNotice.focusRoundEnded, ["start": start, "end": end])
                }
            case .restEnded, .finished:
                break
            }
        }
        guard !quietly, let now = round, !events.isEmpty else { return }
        say(Self.line(for: now))
    }

    /// "Round 2 of 4 done - take 5 minutes".
    private static func line(for round: WardRound) -> String {
        switch round.phase {
        case .rest: return round.roundWords + " done \u{2014} take \(round.plan.breakMinutes) minutes"
        case .ready: return "Break over \u{2014} round \(round.round + 1) when you\u{2019}re ready"
        case .done: return "Ward round done \u{2014} \(round.focusMinutes) minutes"
        case .focus: return round.roundWords
        }
    }

    private func say(_ line: String) {
        notice = line
        noticeClear?.cancel()
        noticeClear = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// After every change: saved, the chip shown or hidden, the next wake,
    /// the notifications and the Live Activity.
    private func changed() {
        save()
        arm()
        scheduleAlarms()
        WardRoundOverlay.shared.sync(showing: round != nil)
        if let round {
            WardRoundActivity.sync(round, soon: false)
        } else {
            WardRoundActivity.end()
        }
    }

    private func save() {
        guard let round, let data = try? JSONEncoder().encode(round) else {
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
            return
        }
        UserDefaults.standard.set(data, forKey: Self.stateKey)
    }

    /// One sleep, until the running phase is due to end.
    private func arm() {
        wake?.cancel()
        guard let round, round.ticks else { return }
        let wait: TimeInterval = max(0.05, round.phaseEnds.timeIntervalSinceNow)
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    /// The ends still to come, left with the notification centre - only if
    /// notifications were already allowed (Settings > Reminders asks); never
    /// asked for here. Shown only while the app is not in front.
    private func scheduleAlarms() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: WardRound.alarmIDs)
        alarmGeneration += 1
        let generation: Int = alarmGeneration
        guard let round else { return }
        let alarms: [WardRound.Alarm] = round.alarms(at: Date())
        guard !alarms.isEmpty else { return }
        Task { @MainActor [weak self] in
            let status: UNAuthorizationStatus = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            guard let self, self.alarmGeneration == generation else { return }
            for alarm in alarms {
                let content = UNMutableNotificationContent()
                content.title = alarm.title
                content.body = alarm.body
                content.sound = .default
                content.filterCriteria = StudyFocus.criteria
                let wait: TimeInterval = max(1, alarm.date.timeIntervalSinceNow)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: alarm.id, content: content, trigger: trigger))
            }
        }
    }
}

/// The word study notifications carry (UNNotificationContent.filterCriteria)
/// so the Focus filter (StudyFocusFilter, Xcode build) can let them through
/// and quiet the rest.
enum StudyFocus {
    static let criteria = "study"
}

// MARK: - The Live Activity

/// Starts, updates and ends the ward round's Live Activity: "Round 2 of 4 ·
/// 12:40 · 38 cards" on the Lock Screen and in the Dynamic Island. A no-op
/// where Live Activities do not exist (the Playgrounds build).
@MainActor
enum WardRoundActivity {
    private static var pending: Task<Void, Never>?

    /// `soon`: only a count changed, so it waits a little and goes with the
    /// next one - a card a second must not be an update a second.
    static func sync(_ round: WardRound, soon: Bool) {
        #if canImport(ActivityKit) && !SWIFT_PACKAGE
        pending?.cancel()
        guard soon else {
            send(round)
            return
        }
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let now = WardRoundClock.shared.round else { return }
            send(now)
        }
        #endif
    }

    static func end() {
        #if canImport(ActivityKit) && !SWIFT_PACKAGE
        pending?.cancel()
        for activity in Activity<WardRoundAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    #if canImport(ActivityKit) && !SWIFT_PACKAGE
    private static func send(_ round: WardRound) {
        let now = Date()
        let ends: Date? = round.ticks ? round.phaseEnds : nil
        let held: Double? = round.isPaused ? round.remaining(at: now) : nil
        let state = WardRoundAttributes.ContentState(round: round.round, rounds: round.plan.rounds,
                                                     phase: round.phase.rawValue, endsAt: ends,
                                                     heldSeconds: held, items: round.items)
        let content = ActivityContent(state: state, staleDate: ends)
        if round.phase == .done {
            for activity in Activity<WardRoundAttributes>.activities {
                Task { await activity.end(content, dismissalPolicy: .default) }
            }
            return
        }
        if let current = Activity<WardRoundAttributes>.activities.first {
            guard current.content.state != state else { return }
            Task { await current.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WardRoundAttributes(focusMinutes: round.plan.focusMinutes,
                                             breakMinutes: round.plan.breakMinutes)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }
    #endif
}
