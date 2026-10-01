import Foundation

/// FSRS-5, the Free Spaced Repetition Scheduler Anki ships, with its published
/// default weights.
///
/// A card carries two numbers. Stability is how many days it takes recall to
/// fall to 90%; difficulty (1 to 10) is how hard the card is to push up. Each
/// rating moves both, and the next interval is the time for recall to fall to
/// the retention asked for - at the default 90% that is exactly the stability.
///
/// Optional: "Classic" (AnkiScheduler) stays the default. Foundation only and
/// free of the app's types, so it is tested on a runner exactly as it runs.
/// Grades are Anki's: 1 Again, 2 Hard, 3 Good, 4 Easy.
enum FSRS {

    /// The FSRS-5 default parameters (w0 ... w18).
    static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949,
        0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698,
        0.2315, 2.9898, 0.51655, 0.6621,
    ]

    /// The forgetting curve: R(t, S) = (1 + FACTOR * t / S) ^ DECAY.
    static let decay: Double = -0.5
    static let factor: Double = 19.0 / 81.0

    /// The recall aimed for when an interval is chosen.
    static let defaultRetention: Double = 0.9

    static let minStability: Double = 0.01
    static let maxStability: Double = 36_500

    /// One card's memory.
    struct State: Equatable, Codable {
        var stability: Double
        var difficulty: Double
    }

    private static func w(_ i: Int, _ weights: [Double]) -> Double {
        weights.indices.contains(i) ? weights[i] : defaultWeights[i]
    }

    private static func clampGrade(_ grade: Int) -> Int { min(4, max(1, grade)) }

    private static func clampD(_ d: Double) -> Double { min(10, max(1, d)) }

    private static func clampS(_ s: Double) -> Double {
        guard s.isFinite else { return maxStability }
        return min(maxStability, max(minStability, s))
    }

    // MARK: the curve

    /// Recall after `elapsedDays` for a card of `stability`.
    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        let t: Double = max(0, elapsedDays)
        let s: Double = clampS(stability)
        let base: Double = 1 + factor * t / s
        return pow(base, decay)
    }

    /// Days until recall falls to `retention`.
    static func intervalDays(stability: Double, retention: Double = defaultRetention) -> Double {
        let r: Double = min(0.99, max(0.7, retention))
        let s: Double = clampS(stability)
        let grow: Double = pow(r, 1 / decay) - 1
        return s / factor * grow
    }

    // MARK: first rating

    static func initialStability(_ grade: Int, weights: [Double] = defaultWeights) -> Double {
        clampS(w(clampGrade(grade) - 1, weights))
    }

    static func initialDifficulty(_ grade: Int, weights: [Double] = defaultWeights) -> Double {
        let g: Double = Double(clampGrade(grade))
        let drop: Double = exp(w(5, weights) * (g - 1))
        return clampD(w(4, weights) - drop + 1)
    }

    // MARK: later ratings

    /// FSRS-5's difficulty update: a linear step damped as it nears 10, then
    /// pulled a little back toward an Easy card's starting difficulty.
    static func nextDifficulty(_ d: Double, grade: Int, weights: [Double] = defaultWeights) -> Double {
        let g: Double = Double(clampGrade(grade))
        let delta: Double = -w(6, weights) * (g - 3)
        let damped: Double = d + delta * (10 - d) / 9
        let anchor: Double = initialDifficulty(4, weights: weights)
        let pull: Double = w(7, weights)
        let reverted: Double = pull * anchor + (1 - pull) * damped
        return clampD(reverted)
    }

    /// Stability after a successful review (Hard, Good or Easy).
    static func recallStability(_ s: Double, difficulty d: Double, retrievability r: Double,
                                grade: Int, weights: [Double] = defaultWeights) -> Double {
        let g: Int = clampGrade(grade)
        let hardPenalty: Double = g == 2 ? w(15, weights) : 1
        let easyBonus: Double = g == 4 ? w(16, weights) : 1
        let a: Double = exp(w(8, weights))
        let b: Double = 11 - d
        let c: Double = pow(clampS(s), -w(9, weights))
        let e: Double = exp(w(10, weights) * (1 - r)) - 1
        let growth: Double = a * b * c * e * hardPenalty * easyBonus
        return clampS(s * (growth + 1))
    }

    /// Stability after a lapse (Again). Never more than it had.
    static func forgetStability(_ s: Double, difficulty d: Double, retrievability r: Double,
                                weights: [Double] = defaultWeights) -> Double {
        let a: Double = w(11, weights)
        let b: Double = pow(d, -w(12, weights))
        let c: Double = pow(clampS(s) + 1, w(13, weights)) - 1
        let e: Double = exp(w(14, weights) * (1 - r))
        let fresh: Double = a * b * c * e
        let shortCap: Double = s / exp(w(17, weights) * w(18, weights))
        return clampS(min(fresh, shortCap))
    }

    /// Stability after a review on the same day as the last one - a learning
    /// step, or a card seen twice in one sitting.
    static func shortTermStability(_ s: Double, grade: Int, weights: [Double] = defaultWeights) -> Double {
        let g: Double = Double(clampGrade(grade))
        let power: Double = w(17, weights) * (g - 3 + w(18, weights))
        return clampS(s * exp(power))
    }

    /// The memory after one rating. `previous` nil is a card never rated;
    /// `elapsedDays` is the time since its last rating.
    static func next(_ previous: State?, grade: Int, elapsedDays: Double,
                     weights: [Double] = defaultWeights) -> State {
        let g: Int = clampGrade(grade)
        guard let previous else {
            return State(stability: initialStability(g, weights: weights),
                         difficulty: initialDifficulty(g, weights: weights))
        }
        let d: Double = nextDifficulty(previous.difficulty, grade: g, weights: weights)
        let s: Double
        if elapsedDays < 1 {
            s = shortTermStability(previous.stability, grade: g, weights: weights)
        } else {
            let r: Double = retrievability(elapsedDays: elapsedDays, stability: previous.stability)
            if g == 1 {
                s = forgetStability(previous.stability, difficulty: previous.difficulty,
                                    retrievability: r, weights: weights)
            } else {
                s = recallStability(previous.stability, difficulty: previous.difficulty,
                                    retrievability: r, grade: g, weights: weights)
            }
        }
        return State(stability: s, difficulty: d)
    }

    /// A memory for a card scheduled by Classic before FSRS was switched on:
    /// its interval as stability, and a difficulty that rises with lapses.
    static func estimated(intervalDays: Double, lapses: Int) -> State {
        let s: Double = clampS(max(0.1, intervalDays))
        let d: Double = clampD(5 + Double(max(0, lapses)))
        return State(stability: s, difficulty: d)
    }
}
