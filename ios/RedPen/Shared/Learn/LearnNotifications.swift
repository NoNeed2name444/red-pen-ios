import Foundation
import UserNotifications

/// The opt-in daily rhythm as local notifications: the question of the day
/// (answered A to E straight from the notification), the evening re-read of
/// the day's misses, and the morning check. Nothing leaves the phone.
///
/// Like the review reminder (AppNotifications.scheduleReviews), each is one
/// pending request, rebuilt from the latest library every time the app goes
/// to the background, so what it says is never stale by more than a day.
@MainActor
enum LearnNotifications {
    static let questionID = "learn-qotd"
    static let bedtimeID = "learn-bedtime"
    static let morningID = "learn-morning"
    static let verdictPrefix = "learn-verdict-"

    static let questionCategory = "learn.qotd"
    static let openCategory = "learn.open"
    /// Action identifiers for the answer buttons: "learn.answer.0" is A.
    static let answerPrefix = "learn.answer."

    /// The library that answers are recorded in. Set once at launch
    /// (RedPenApp); weak so a screenshot run's throwaway store can go.
    static weak var store: Store?

    /// The one line that makes the app the notification centre's delegate,
    /// with the store answers go to. Call from the app's init, before launch
    /// finishes, so an answer tapped while the app was not running is
    /// handled when iOS wakes it.
    static func install(store: Store) {
        self.store = store
        UNUserNotificationCenter.current().delegate = LearnNotificationDelegate.shared
    }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .authorized || status == .provisional || status == .ephemeral { return true }
        guard status == .notDetermined else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: scheduling

    /// Rebuilds all three from the current library and settings.
    static func reschedule(store: Store, now: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [questionID, bedtimeID, morningID])
        var categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: openCategory, actions: [], intentIdentifiers: [], options: [])
        ]
        if ReminderSettings.questionOn, let request = questionRequest(store: store, now: now) {
            categories.insert(request.category)
            center.add(request.request)
        }
        center.setNotificationCategories(categories)
        if ReminderSettings.bedtimeOn, let request = bedtimeRequest(store: store, now: now) {
            center.add(request)
        }
        if ReminderSettings.morningOn, let request = morningRequest(store: store, now: now) {
            center.add(request)
        }
    }

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// Tomorrow's (or today's) question, with its A-E buttons.
    private static func questionRequest(store: Store, now: Date)
        -> (request: UNNotificationRequest, category: UNNotificationCategory)? {
        let minutes = ReminderSettings.minutes(ReminderSettings.questionTimeKey,
                                               default: ReminderSettings.defaultQuestionTime)
        let when = ReminderSettings.next(minutes, after: now)
        guard let pick = store.questionOfTheDay(now: when) else { return nil }
        let q = pick.question
        // Buttons carry the option's first words, so it can be answered
        // from the lock screen without opening anything. Answering does not
        // need the app in front: no .foreground option.
        let actions: [UNNotificationAction] = q.options.enumerated().map { i, option in
            let title = StudyRhythm.letter(i) + "  " + StudyRhythm.abbreviated(option, limit: 30)
            return UNNotificationAction(identifier: answerPrefix + String(i), title: title, options: [])
        }
        let category = UNNotificationCategory(identifier: questionCategory, actions: actions,
                                              intentIdentifiers: [], options: [])
        let content = UNMutableNotificationContent()
        content.title = "Question of the day \u{00B7} " + Store.subjectName(pick.set)
        content.body = StudyRhythm.questionBody(stem: q.stem, options: q.options)
        content.sound = .default
        content.categoryIdentifier = questionCategory
        content.userInfo = ["kind": "qotd", "qid": q.id.uuidString]
        let request = UNNotificationRequest(identifier: questionID, content: content, trigger: trigger(at: when))
        return (request, category)
    }

    private static func bedtimeRequest(store: Store, now: Date) -> UNNotificationRequest? {
        let minutes = ReminderSettings.minutes(ReminderSettings.bedtimeTimeKey, default: ReminderSettings.defaultBedtime)
        let when = ReminderSettings.next(minutes, after: now)
        // only tonight's, and only when there is something from today
        guard Calendar.current.isDate(when, inSameDayAs: now) else { return nil }
        let misses = store.bedtimePicks(now: now).count
        guard misses > 0 else { return nil }
        let days = ExamCap.storedDate().map { ExamWeekPlanner.daysLeft(to: $0, now: now) }
        let content = UNMutableNotificationContent()
        content.title = "Bedtime lock-in"
        content.body = StudyRhythm.bedtimeBody(misses: misses, examDays: days)
        // no sound at night
        content.categoryIdentifier = openCategory
        content.userInfo = ["kind": "bedtime"]
        return UNNotificationRequest(identifier: bedtimeID, content: content, trigger: trigger(at: when))
    }

    private static func morningRequest(store: Store, now: Date) -> UNNotificationRequest? {
        let minutes = ReminderSettings.minutes(ReminderSettings.morningTimeKey, default: ReminderSettings.defaultMorning)
        let when = ReminderSettings.next(minutes, after: now)
        // the misses of the day before that morning, as known now
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: when) ?? now
        let items = StudyRhythm.missed(on: dayBefore, events: store.answerLog).count
        guard items > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Morning check"
        content.body = StudyRhythm.morningBody(items: items)
        content.sound = .default
        content.categoryIdentifier = openCategory
        content.userInfo = ["kind": "morning"]
        return UNNotificationRequest(identifier: morningID, content: content, trigger: trigger(at: when))
    }

    // MARK: answers and taps

    /// A response, already reduced to plain strings by the delegate.
    static func handle(action: String, fields: [String: String]) {
        let kind = fields["kind"] ?? ""
        if action.hasPrefix(answerPrefix), kind == "qotd" {
            answer(action: action, fields: fields)
            return
        }
        guard action == UNNotificationDefaultActionIdentifier else { return }
        switch kind {
        case "qotd", "verdict":
            if let id = fields["qid"].flatMap(UUID.init(uuidString:)) { LearnRouter.shared.open(.question(id)) }
        case "bedtime":
            LearnRouter.shared.open(.bedtime)
        case "morning":
            LearnRouter.shared.open(.morningCheck)
        default:
            break
        }
    }

    /// Records the answer tapped on the notification and replies with the
    /// verdict, as a notification of its own.
    private static func answer(action: String, fields: [String: String]) {
        guard let store,
              let slot = Int(action.dropFirst(answerPrefix.count)),
              let id = fields["qid"].flatMap(UUID.init(uuidString:)),
              let pick = store.picks(ids: [id]).first else { return }
        let q = pick.question
        guard q.options.indices.contains(slot), q.options.indices.contains(q.correctIndex) else { return }
        let correct = slot == q.correctIndex
        store.recordAnswer(id, correct: correct, picked: slot)
        StudyLog.shared.record()
        let verdict = StudyRhythm.verdict(correct: correct, rightLetter: StudyRhythm.letter(q.correctIndex),
                                          rightText: q.options[q.correctIndex])
        let content = UNMutableNotificationContent()
        content.title = verdict.title
        content.body = verdict.body
        content.categoryIdentifier = openCategory
        content.userInfo = ["kind": "verdict", "qid": id.uuidString]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: verdictPrefix + id.uuidString, content: content, trigger: nil))
    }
}

/// The notification centre's delegate: answers from the question of the
/// day, and taps that open a screen.
///
/// Only the learning notifications (identifiers starting "learn-") are shown
/// while the app is in front; the review and generation reminders keep their old behaviour of
/// not interrupting someone already in the app.
final class LearnNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LearnNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action: String = response.actionIdentifier
        var fields: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let k = key as? String, let v = value as? String { fields[k] = v }
        }
        let done = UncheckedHandler(run: completionHandler)
        Task { @MainActor in
            LearnNotifications.handle(action: action, fields: fields)
            done.run()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id: String = notification.request.identifier
        let ours: Bool = id.hasPrefix("learn-")
        completionHandler(ours ? [.banner, .list] : [])
    }
}

/// A completion handler carried across to the main actor. The system calls
/// the delegate on its own queue and the handler may be called from any.
private struct UncheckedHandler: @unchecked Sendable {
    let run: () -> Void
}
