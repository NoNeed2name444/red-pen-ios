import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit) && !SWIFT_PACKAGE
import ActivityKit
#endif

/// Keeps the widgets' digest (GlanceDigest) up to date.
///
/// Worked out off the main thread from a copy of the library and schedule,
/// a few seconds after they stop changing (PlatformRoutes debounces), and
/// written only when a number actually changed - so a widget reloads when
/// there is something new to show and never on a rating that changed nothing
/// it displays.
@MainActor
enum GlancePublisher {
    /// Where the widget toggles live (PlatformSettingsSection).
    static let liveActivityKey = "platform.examDayLiveActivity"

    private static var last: GlanceDigest? = GlanceShelf.read()
    private static var running: Task<Void, Never>?

    static func publish(store: Store, reviews: ReviewStore) {
        let library: [StudySet] = store.library
        let records: [UUID: ReviewRecord] = reviews.records
        let limits: ReviewLimits = ReviewSettings.limits()
        let today: Int = StudyLog.shared.today
        let streak: Int = StudyLog.shared.streak
        let examDate: Date? = ExamCap.storedDate()
        let track: ExamTrack = ExamTrack.current
        let examName: String = track == .general ? "Your exam" : track.title
        running?.cancel()
        running = Task {
            let digest: GlanceDigest = await Task.detached(priority: .utility) { () -> GlanceDigest in
                let now = Date()
                let due: [ReviewPlan.Due] = ReviewPlan.dueToday(library, records: records, now: now,
                                                                 limits: limits, cap: 5000)
                let pairs: [(id: UUID, name: String)] = due.map { (id: $0.setID, name: $0.setName) }
                let upcoming: Date? = records.values.lazy.map(\.due).filter { $0 > now }.min()
                return GlanceDigest.make(now: now, due: pairs, nextDue: upcoming, examName: examName,
                                         examDate: examDate, today: today, streak: streak)
            }.value
            guard !Task.isCancelled else { return }
            save(digest)
        }
    }

    private static func save(_ digest: GlanceDigest) {
        ExamDayActivity.sync(digest)
        if let last, last.sameContent(as: digest) { return }
        last = digest
        let written: Bool = GlanceShelf.write(digest)
        #if canImport(WidgetKit)
        if written { WidgetCenter.shared.reloadAllTimelines() }
        #endif
    }
}

/// Starts, updates and ends the exam-day Live Activity. A no-op where Live
/// Activities do not exist (the Playgrounds build).
@MainActor
enum ExamDayActivity {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: GlancePublisher.liveActivityKey) as? Bool ?? true
    }

    static func sync(_ digest: GlanceDigest) {
        #if canImport(ActivityKit) && !SWIFT_PACKAGE
        let now = Date()
        let running: [Activity<ExamDayAttributes>] = Activity<ExamDayAttributes>.activities
        guard enabled, let exam = digest.examDate, ExamDayWindow.contains(now, exam: exam) else {
            for activity in running {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let state = ExamDayAttributes.ContentState(dueNow: digest.dueNow, startsAt: ExamDayWindow.startsAt(exam: exam))
        let stale: Date = ExamDayWindow.end(exam: exam)
        let content = ActivityContent(state: state, staleDate: stale)
        if let current = running.first {
            guard current.content.state != state else { return }
            Task { await current.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ExamDayAttributes(examName: digest.examName ?? "Your exam", examDay: exam)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        #endif
    }
}
