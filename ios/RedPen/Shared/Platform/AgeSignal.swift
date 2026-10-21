import Foundation

/// What the system's Declared Age Range says about the person using the
/// app, reduced to the one question the app asks: may community features
/// (shared sets, class leaderboards) be offered?
///
/// Foundation only, so the rule is tested on Linux (PlatformTests). AgeGate
/// (AgeGate.swift) asks the system and keeps the answer.
enum AgeSignal: String, Equatable {
    /// Never asked, not shared, or not available: treated as an adult, with
    /// no prompt of the app's own (there is no UI unless a signal says minor).
    case unknown
    case adult
    case minor

    /// The age gates the app asks about: under 13, 13 to 15, 16 to 17, 18+.
    static let gates: [Int] = [13, 16, 18]

    /// From a shared range. A range whose top is under 18 is a minor; one
    /// whose bottom is 18 or more is an adult; anything else (declined, or a
    /// range with neither end known) says nothing.
    static func from(lowerBound: Int?, upperBound: Int?, declined: Bool) -> AgeSignal {
        if declined { return .unknown }
        if let upper = upperBound, upper < 18 { return .minor }
        if let lower = lowerBound, lower >= 18 { return .adult }
        return .unknown
    }

    /// Whether community sharing and leaderboards are offered.
    var allowsCommunity: Bool { self != .minor }
}
