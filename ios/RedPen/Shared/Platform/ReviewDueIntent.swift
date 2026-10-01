import AppIntents
import Foundation

/// "Review due cards": the Control Centre button, the widgets' button, a
/// Siri phrase and a Spotlight action, all the same intent.
///
/// Compiled into the app and into the widget extension (project.yml), which
/// is what lets a Control name it. It opens the app, and the app's copy is
/// the one that runs; the extension's copy never does anything
/// (WIDGET_EXTENSION is defined only there).
struct ReviewDueIntent: AppIntent {
    static var title: LocalizedStringResource = "Review due cards"
    static var description = IntentDescription("Opens Stethoscore on every card due today, across all your decks.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppRouter.shared.open(.reviewDue)
        #endif
        return .result()
    }
}

/// The exam countdown widget's tap: the exam plan.
struct OpenExamPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "Open exam plan"
    static var description = IntentDescription("Opens the plan that works back from your exam date.")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppRouter.shared.open(.examPlan)
        #endif
        return .result()
    }
}
