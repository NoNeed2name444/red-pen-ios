import AppIntents
import SwiftUI

// Only in the Playgrounds core3 build (make_swiftpm.py --without core3):
// the full shell, sessions, stats, editors, sync and the Ward Round home's
// learning pieces are the app's own. What this file stands in for is
// everything that shell still opens which a later zip brings back: Ideas,
// the sky and pop-out, diagnostics, the platform, reasoning, insight,
// coverage, mock papers' neighbours, onboarding and the examples hub.
// The full app never compiles this file.

// MARK: - Ideas (Features/Notes): the map stays out

struct IdeasView: View {
    init(query: Binding<String>? = nil, dockClearance: CGFloat = 0) {}

    var body: some View { NotInThisBuild(feature: "Ideas") }
}

struct NoteEditorView: View {
    init(noteID: UUID) {}

    var body: some View { NotInThisBuild(feature: "Ideas") }
}

/// Which of Ideas' views is open (NotesShared.swift): the library reads it
/// to keep the sky only under the 3D map, which never opens here.
enum IdeasMode: String {
    case list, board, space
}

enum NoteExamples {
    static func seedIfNeeded(into store: NoteStore) {}
}

extension View {
    func noteSourceChip(noteID: UUID) -> some View { self }
}

extension LibraryView {
    /// Save to Ideas is left out (LibrarySavedIdeas.swift).
    func attachIdeaSaver() {}
}

extension View {
    func appLinksInPlace() -> some View { self }

    /// Files opened from other apps (IncomingImport.swift) wait for a later zip.
    func incomingImportPreview(busy: Bool = false) -> some View { self }
}

// MARK: - The sky and the pop-out, flat

enum PopOutSettings {
    static let enabledKey = "vignette.popOut"
    static let faceKey = "vignette.popOut.face"
}

enum SpaceSettings {
    static let alwaysNightKey = "vignette.space.alwaysNight"
    static let soundsKey = "vignette.space.sounds"
    static let graphicsKey = "vignette.space.graphics"
    static let linkLengthKey = GraphLinkLength.key
    static let straightLinesKey = GraphLineStyle.key
}

@MainActor
final class PopOutMotion {
    static let shared = PopOutMotion()
    static var faceTrackingAvailable: Bool { false }

    func refresh() {}
    func requestFaceTracking() async -> Bool { false }
}

@MainActor
final class SpaceSounds {
    static let shared = SpaceSounds()

    func prepare() {}
}

@MainActor
final class SpaceQualityCenter {
    static let shared = SpaceQualityCenter()

    func recompute() {}
}

private struct GraphicsBudgetKey: EnvironmentKey {
    static let defaultValue: GraphicsBudget = .high
}

extension EnvironmentValues {
    var graphics: GraphicsBudget {
        get { self[GraphicsBudgetKey.self] }
        set { self[GraphicsBudgetKey.self] = newValue }
    }
}

extension View {
    func skyScroll() -> some View { self }
    func skyZoomSource(_ id: String) -> some View { self }
    func skyZoomDestination(_ id: String) -> some View { self }
    func liftOffOnAppear() -> some View { self }
    func ideasThemeTip(when: Bool = true) -> some View { self }
}

struct SkyRoot<Content: View>: View {
    let content: Content

    var body: some View { content }
}

// MARK: - Diagnostics: recorded by the real app, not here

enum DiagnosticsRuntime {
    static func start() {}
    static func phaseChanged(_ phase: ScenePhase, token: @escaping @MainActor () -> String?) {}
}

struct DiagnosticsSettingsView: View {
    var body: some View { NotInThisBuild(feature: "Crash and failure reports") }
}

// MARK: - First run: skipped; the pages come back in a later zip

@MainActor
final class FirstRunStore: ObservableObject {
    func isDue(_ accountId: String, terms: RecordingTermsStore) -> Bool { false }
    func finish(_ accountId: String) {}
}

struct FirstRunView: View {
    let accountId: String
    let onDone: () -> Void

    var body: some View { NotInThisBuild(feature: "The first-run pages") }
}

enum InsightExamples {
    static func seed(into store: Store, now: Date = Date()) {}
}

// MARK: - Platform: Spotlight's toggle stores its key; the rest is the App Store build

enum PlatformNotice {
    static let search = Notification.Name("stethoscore.command.search")
    static let openItem = Notification.Name("stethoscore.openItem")

    static func publisher(_ name: Notification.Name) -> NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: name)
    }
}

enum SetWindow {
    static let sceneID = "study-set"
}

struct SetWindowRoot: View {
    let setID: UUID?

    var body: some View { EmptyView() }
}

struct StethoscoreCommands: Commands {
    var body: some Commands {
        CommandMenu("Study") {
            Button("Review Due Cards") {}
        }
    }
}

@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()
    static let key = "platform.spotlight"

    func update(_ library: [StudySet]) {}
    func clear() {}
}

enum GlancePublisher {
    static let liveActivityKey = "platform.examDayLiveActivity"
}

enum AppLock {
    static let key = "platform.appLock"
    static var supported: Bool { false }
    static var biometryName: String { "Face ID" }
}

@MainActor
enum MindfulMinutes {
    static let key = "platform.mindfulMinutes"
    static var available: Bool { false }

    static func requestAccess() async -> Bool { false }
}

struct ReviewDueIntent: AppIntent {
    static var title: LocalizedStringResource = "Review due cards"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

extension View {
    func appLockShield() -> some View { self }
    func platformRoutes(libraryShowing: Bool) -> some View { self }
}

// MARK: - Screens a later zip puts back

struct CoverageView: View {
    var body: some View { NotInThisBuild(feature: "Exam coverage") }
}

struct ExamDashboardCard: View {
    var body: some View { NotInThisBuild(feature: "The exam card") }
}

struct ExamplesHubView: View {
    var body: some View { NotInThisBuild(feature: "Try every feature") }
}

struct OcclusionExampleView: View {
    var body: some View { NotInThisBuild(feature: "The picture-card example") }
}

struct ReasoningView: View {
    var body: some View { NotInThisBuild(feature: "Reasoning") }
}

struct ReasoningSetView: View {
    let set: StudySet

    var body: some View { NotInThisBuild(feature: "Reasoning") }
}

struct DuelsView: View {
    let set: StudySet

    var body: some View { NotInThisBuild(feature: "Lookalike duels") }
}

struct ScriptsView: View {
    let set: StudySet

    var body: some View { NotInThisBuild(feature: "Disease scripts") }
}

enum ReasoningTool {
    case duels, scripts

    var title: String {
        switch self {
        case .duels: return "Lookalike duels"
        case .scripts: return "Disease scripts"
        }
    }

    var symbol: String {
        switch self {
        case .duels: return "arrow.left.arrow.right"
        case .scripts: return "rectangle.stack"
        }
    }

    var blurb: String {
        switch self {
        case .duels: return "Two conditions people confuse. Whose feature is it?"
        case .scripts: return "Who gets it, how it runs, what clinches it, what to do."
        }
    }
}

enum ReasoningExamples {
    static let set = StudySet(
        id: UUID(uuidString: "5EA50000-0000-4000-8000-000000000000") ?? UUID(),
        name: "Examples: hernia, DKA",
        subject: "Medicine & surgery",
        kind: .book)
}

struct InsightQuiz: Identifiable, Hashable {
    var set: StudySet
    var minReadSeconds = 0
    var timed = false
    var id: UUID { self.set.id }
}

struct InsightQuestionList: View {
    let title: String
    let tip: String?
    let picks: [QuestionPick]

    var body: some View { NotInThisBuild(feature: "Mistake insight") }
}

struct ReadinessCard: View {
    let estimate: ReadinessEstimate?
    let answered: Int
    let includesExamples: Bool
    var onDrill: (String) -> Void = { _ in }

    var body: some View { EmptyView() }
}
