#if canImport(AppIntents) && !SWIFT_PACKAGE && !WIDGET_EXTENSION
import AppIntents
import Foundation

/// A Focus filter: Settings > Focus > (a Focus, say "Study") > Add Filter >
/// Stethoscore. While that Focus is on, only study reminders come through -
/// the ward round's, due cards, the question of the day, the bedtime and
/// morning checks - and the rest (a cloud set finished, a generation done)
/// wait quietly in the notification centre.
///
/// The study notifications carry StudyFocus.criteria as their
/// filterCriteria; the predicate lets only those through.
///
/// Xcode build only: a Focus filter is found through the App Intents
/// metadata step, which the Playgrounds package does not have.
struct StudyFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Study reminders only"
    static var description = IntentDescription("While this Focus is on, only study reminders from Stethoscore come through: the ward round, due cards and the daily questions.")

    @Parameter(title: "Only study reminders", default: true)
    var studyOnly: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: studyOnly ? "Only study reminders" : "Every reminder")
    }

    var appContext: FocusFilterAppContext {
        let wanted: [String] = [StudyFocus.criteria]
        let predicate: NSPredicate? = studyOnly ? NSPredicate(format: "SELF IN %@", wanted) : nil
        return FocusFilterAppContext(notificationFilterPredicate: predicate)
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}
#endif
