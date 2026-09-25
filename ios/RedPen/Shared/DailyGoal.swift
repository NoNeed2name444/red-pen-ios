import Foundation

/// How many cards and questions a day the student means to do: asked in the
/// first-run flow (FirstRunView), read wherever the day's progress is shown.
/// One key, so every screen that shows the goal agrees on it.
enum DailyGoal {
    static let key = "stethoscore.dailyGoal"

    /// What a goal can be; anything stored outside it is brought back in.
    static let range: ClosedRange<Int> = 10...300

    /// The goal, 50 until one is set.
    static var current: Int {
        get {
            let stored: Int = UserDefaults.standard.integer(forKey: key)
            if stored == 0 { return 50 }
            return min(max(stored, range.lowerBound), range.upperBound)
        }
        set {
            let kept: Int = min(max(newValue, range.lowerBound), range.upperBound)
            UserDefaults.standard.set(kept, forKey: key)
        }
    }
}
