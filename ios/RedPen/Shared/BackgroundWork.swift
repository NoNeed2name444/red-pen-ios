import BackgroundTasks
import UIKit
import UserNotifications

/// Generation keeps going when the student leaves the app.
///
/// iOS 26's continued processing task: work a person started - writing forty
/// questions, a textbook - carries on in the background with the system's own
/// progress indicator, whether it runs on this device's model or asks the
/// cloud. The system may stop it under pressure (and the expiration handler
/// then cancels the job cleanly); swiping the app away ends it, as it ends
/// every app's work.
@MainActor
enum BackgroundWork {
    private static var running: [UUID: BGContinuedProcessingTask] = [:]
    private static var titles: [UUID: String] = [:]

    private static var prefix: String { (Bundle.main.bundleIdentifier ?? "vignette") + ".generate." }

    /// Only when the build declares the identifiers: registering one that the
    /// Info.plist does not permit stops the app (a Swift Playgrounds build
    /// cannot declare them, and simply works in the foreground).
    private static var permitted: Bool {
        let allowed = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        return allowed.contains(prefix + "*")
    }

    static func begin(_ id: UUID, title: String) {
        guard permitted else { return }
        titles[id] = title
        let identifier = prefix + id.uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                // finished before the system got round to starting it
                guard GenerationCenter.shared.job?.id == id else {
                    task.setTaskCompleted(success: true)
                    return
                }
                running[id] = task
                task.progress.totalUnitCount = 100
                task.expirationHandler = {
                    Task { @MainActor in
                        if GenerationCenter.shared.job?.id == id { GenerationCenter.shared.cancel() }
                    }
                }
            }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title,
                                                       subtitle: "Starting\u{2026}")
        request.strategy = .fail
        try? BGTaskScheduler.shared.submit(request)
    }

    static func progress(_ id: UUID, done: Int, total: Int, phase: String?) {
        guard let task = running[id], total > 0 else { return }
        task.progress.completedUnitCount = Int64(min(100, done * 100 / total))
        task.updateTitle(titles[id] ?? "Writing", subtitle: phase ?? "\(done) of \(total)")
    }

    static func end(_ id: UUID, success: Bool) {
        titles.removeValue(forKey: id)
        running.removeValue(forKey: id)?.setTaskCompleted(success: success)
    }
}

/// Local notifications: generation finished while the app was away, and
/// cards due for review. Nothing leaves the phone - no server, no push.
@MainActor
enum AppNotifications {
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// "Your 40 questions are ready" - only when the student is not looking
    /// at the app already.
    static func generationFinished(_ title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "generation-\(UUID().uuidString)", content: content, trigger: nil))
    }

    /// One reminder, rescheduled every time the app goes to the background:
    /// when the next card falls due - or, with cards already waiting, this
    /// evening at six (tomorrow's, if six has passed).
    static func scheduleReviews(sets: [StudySet], reviews: ReviewStore, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["review-due"])
        let decks = sets.filter { $0.kind == .anki && !$0.cards.isEmpty }
        let dueNow = decks.reduce(0) { $0 + reviews.dueCount(for: $1.cards, now: now) }
        let when: Date
        let body: String
        if dueNow > 0 {
            let calendar = Calendar.current
            var evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600)
            if evening <= now.addingTimeInterval(300) { evening = calendar.date(byAdding: .day, value: 1, to: evening) ?? evening }
            when = evening
            body = "\(dueNow) card\(dueNow == 1 ? " is" : "s are") due for review."
        } else if let next = decks.compactMap({ reviews.nextDue(for: $0.cards) }).filter({ $0 > now }).min() {
            when = next
            body = "Cards are due for review."
        } else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Time to review"
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        center.add(UNNotificationRequest(identifier: "review-due", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
