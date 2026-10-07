#if canImport(ActivityKit) && !SWIFT_PACKAGE
import ActivityKit
import Foundation

/// The ward round's Live Activity: "Round 2 of 4 · 12:40 · 38 cards" on the
/// Lock Screen and in the Dynamic Island while a round runs.
///
/// Xcode build only, like ExamDayAttributes beside it. Compiled into the
/// app, which starts, updates and ends it (WardRoundActivity in
/// WardRoundClock.swift), and the extension, which draws it
/// (StethoscoreWidgets/WardRoundLiveActivity.swift). The clock itself is the
/// system's timer text counting to `endsAt`, so nothing has to be sent each
/// second.
struct WardRoundAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var round: Int
        var rounds: Int
        /// WardRound.Phase's raw value: "focus", "rest", "ready" or "done".
        var phase: String
        /// When the running clock reaches zero; nil when nothing is running.
        var endsAt: Date?
        /// The time left, held, while paused.
        var heldSeconds: Double?
        /// Cards, questions and steps studied during the rounds.
        var items: Int
    }

    var focusMinutes: Int
    var breakMinutes: Int
}
#endif
