import Foundation

/// How much the student means to do each day - cards, questions and steps -
/// for the goal ring beside the streak. Set in Settings > Study.
enum DailyGoal {
    static let key = "stethoscore.dailyGoal"

    /// The goal, 50 until one is chosen, always within `range`.
    static var current: Int {
        get {
            let stored: Int = UserDefaults.standard.integer(forKey: key)
            guard stored > 0 else { return 50 }
            return min(max(stored, range.lowerBound), range.upperBound)
        }
        set {
            let clamped: Int = min(max(newValue, range.lowerBound), range.upperBound)
            UserDefaults.standard.set(clamped, forKey: key)
        }
    }

    static let range: ClosedRange<Int> = 10...300
}
