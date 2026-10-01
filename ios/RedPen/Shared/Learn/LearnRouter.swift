import Combine
import Foundation

/// A screen from the learning pieces, opened from anywhere: a notification
/// tap, the Today card, a settings row.
///
/// One sheet on the app's root (`.learnRoutes()`, in LearnRoutes.swift)
/// shows whichever is asked for, so nothing that opens one has to own the
/// presentation - a notification arrives with no view to hand at all.
enum LearnRoute: Identifiable, Hashable {
    case examPlan
    case examKit
    case bedtime
    case morningCheck
    case symptomBlocks
    /// The real paper (Features/Mock): its length, clock and sections.
    case mockPaper
    /// One question on its own (the question of the day's "tap for why").
    case question(UUID)
    /// A ready-made quiz, optionally in timed exam mode.
    case quiz(StudySet, timed: Bool)
    /// Guess first, for this set.
    case pretest(UUID)

    var id: String {
        switch self {
        case .examPlan: return "examPlan"
        case .examKit: return "examKit"
        case .bedtime: return "bedtime"
        case .morningCheck: return "morningCheck"
        case .symptomBlocks: return "symptomBlocks"
        case .mockPaper: return "mockPaper"
        case .question(let id): return "question-" + id.uuidString
        case .quiz(let set, _): return "quiz-" + set.id.uuidString
        case .pretest(let id): return "pretest-" + id.uuidString
        }
    }
}

@MainActor
final class LearnRouter: ObservableObject {
    static let shared = LearnRouter()

    /// The screen showing, or nil.
    @Published var route: LearnRoute?

    func open(_ route: LearnRoute) {
        // a second request while one is showing replaces it on the next pass
        if self.route != nil {
            self.route = nil
            // after the showing sheet has gone
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                self.route = route
            }
        } else {
            self.route = route
        }
    }
}
