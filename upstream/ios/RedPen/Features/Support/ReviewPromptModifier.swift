import SwiftUI
import StoreKit

/// Asks for an App Store rating once, at a good moment: finishing a review
/// on a week-long streak, or finishing a first mock paper that went
/// reasonably. Never twice, never within half an hour of an error shown on
/// screen (ReviewPromptRules), never in a screenshot or UI-test launch. The
/// system decides whether the prompt actually appears.
extension View {
    /// On a finish screen: asks if today's work made a 7-day streak.
    func reviewPromptAfterStreak(_ finishedSomething: Bool) -> some View {
        modifier(ReviewPromptModifier(kind: finishedSomething ? .streak : nil))
    }

    /// On a mock's results: asks after the first one that went reasonably.
    func reviewPromptAfterMock(_ wentWell: Bool) -> some View {
        modifier(ReviewPromptModifier(kind: wentWell ? .mock : nil))
    }
}

private struct ReviewPromptModifier: ViewModifier {
    enum Kind { case streak, mock }
    let kind: Kind?
    @Environment(\.requestReview) private var requestReview

    func body(content: Content) -> some View {
        content.task(id: kind == nil) { await ask() }
    }

    private static var automated: Bool {
        let args: [String] = ProcessInfo.processInfo.arguments
        let marks: [String] = ["-uiPreviewScreen", "-stillSky", "-graphPreview", "-personalBuild"]
        return args.contains { marks.contains($0) }
    }

    @MainActor
    private func ask() async {
        guard let kind, !Self.automated else { return }
        let milestone: ReviewPromptRules.Milestone
        switch kind {
        case .streak: milestone = .streak(StudyLog.shared.streak)
        case .mock: milestone = .mockFinished
        }
        guard ReviewPromptRules.shouldAsk(milestone, state: ReviewPromptRules.stored(), now: Date()) else { return }
        // let the finish screen settle first
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        UserDefaults.standard.set(true, forKey: ReviewPromptRules.askedKey)
        requestReview()
    }
}
