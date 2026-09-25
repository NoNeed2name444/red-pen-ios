import SwiftUI

extension View {
    /// Once, on the signed-in library: shows whatever LearnRouter is asked
    /// to open, in a sheet of its own - from a notification, the Today card
    /// or a settings row.
    func learnRoutes() -> some View {
        modifier(LearnRoutes())
    }
}

private struct LearnRoutes: ViewModifier {
    @ObservedObject private var router = LearnRouter.shared

    func body(content: Content) -> some View {
        content.sheet(item: $router.route) { route in
            LearnSheet(route: route)
        }
    }
}

/// One learning screen in its own navigation stack, with a Done button.
private struct LearnSheet: View {
    let route: LearnRoute
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            screen
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("learnDone")
                    }
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .examPlan: ExamPlanView()
        case .examKit: ExamDayKitView()
        case .bedtime: BedtimeReviewView()
        case .morningCheck: MorningCheckView()
        case .symptomBlocks: SymptomBlocksView()
        case .mockPaper: MockPaperView()
        case .question(let id): questionScreen(id)
        case .quiz(let set, let timed): MCQQuizView(set: set, keepsProgress: false, startsTimed: timed)
        case .pretest(let id): pretestScreen(id)
        }
    }

    @ViewBuilder
    private func questionScreen(_ id: UUID) -> some View {
        if let set = store.singleQuestionQuiz(id) {
            MCQQuizView(set: set, keepsProgress: false)
        } else {
            ContentUnavailableView("That question has gone", systemImage: "questionmark.folder",
                                   description: Text("It may have been deleted, or edited on another device."))
        }
    }

    @ViewBuilder
    private func pretestScreen(_ id: UUID) -> some View {
        if let set = store.library.first(where: { $0.id == id }) {
            GuessFirstView(set: set)
        } else {
            ContentUnavailableView("That set has gone", systemImage: "questionmark.folder")
        }
    }
}
