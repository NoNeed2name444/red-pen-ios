import Foundation
#if canImport(HealthKit) && !SWIFT_PACKAGE
import HealthKit
#endif

// MARK: - Mindful minutes in Apple Health
//
// Settings > "Log focus rounds to Health" (PlatformSettingsSection, off by
// default). When a focus round ends, whoever runs the timer posts
// PlatformNotice.focusRoundEnded with its start and end; this writes it to
// Health as a Mindful Session. Nothing is read from Health.
//
// Xcode build only: HealthKit needs its entitlement and
// NSHealthUpdateUsageDescription (project.yml), which the Playgrounds package
// cannot declare, so there the toggle is hidden and nothing is written.

@MainActor
enum MindfulMinutes {
    /// Bool, default false.
    static let key = "platform.mindfulMinutes"

    /// Rounds shorter than this are not worth a Health entry.
    static let shortest: TimeInterval = 60

    private static var token: NSObjectProtocol?

    static var available: Bool {
        #if canImport(HealthKit) && !SWIFT_PACKAGE
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    static var isOn: Bool {
        available && UserDefaults.standard.bool(forKey: key)
    }

    #if canImport(HealthKit) && !SWIFT_PACKAGE
    private static let health = HKHealthStore()
    private static var mindful: HKCategoryType { HKCategoryType(.mindfulSession) }
    #endif

    /// Once, from the root: log each round as it ends.
    static func listen() {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(forName: PlatformNotice.focusRoundEnded,
                                                       object: nil, queue: .main) { note in
            let start: Date? = note.userInfo?["start"] as? Date
            let end: Date? = note.userInfo?["end"] as? Date
            guard let start, let end else { return }
            MainActor.assumeIsolated {
                Task { await log(start: start, end: end) }
            }
        }
    }

    /// Asks for permission to write mindful minutes; true when it may.
    static func requestAccess() async -> Bool {
        #if canImport(HealthKit) && !SWIFT_PACKAGE
        guard available else { return false }
        do {
            try await health.requestAuthorization(toShare: [mindful], read: [])
        } catch {
            return false
        }
        return health.authorizationStatus(for: mindful) == .sharingAuthorized
        #else
        return false
        #endif
    }

    static func log(start: Date, end: Date) async {
        guard isOn, end.timeIntervalSince(start) >= shortest else { return }
        #if canImport(HealthKit) && !SWIFT_PACKAGE
        guard health.authorizationStatus(for: mindful) == .sharingAuthorized else { return }
        let sample = HKCategorySample(type: mindful, value: HKCategoryValue.notApplicable.rawValue,
                                      start: start, end: end)
        try? await health.save(sample)
        #endif
    }
}
