import Combine
import SwiftUI
import UIKit
#if canImport(DeclaredAgeRange) && !SWIFT_PACKAGE
import DeclaredAgeRange
#endif

// MARK: - Age gating before community features
//
// Texas SB 2420 (in force since June 2026, with Utah and Louisiana following)
// expects an app to use the platform's age signal before it offers features
// meant for adults. Stethoscore asks the system's Declared Age Range only
// when a community entry point is about to open (a shared-set link, a class
// leaderboard), never at launch, and shows nothing of its own unless the
// answer says the person is a minor - then those entry points are hidden.
//
// Wiring for the lanes that add them: before presenting a community screen,
// `if await AgeGate.shared.allowsCommunity() { ...present... }`; to hide an
// entry point, `.communityOnly()`.
//
// Xcode build only: the request needs the Declared Age Range entitlement
// (project.yml). In the Playgrounds build the answer is always "unknown",
// which allows everything, as before.

@MainActor
final class AgeGate: ObservableObject {
    static let shared = AgeGate()

    static let key = "platform.ageSignal"

    @Published private(set) var signal: AgeSignal

    private init() {
        let raw: String = UserDefaults.standard.string(forKey: AgeGate.key) ?? ""
        signal = AgeSignal(rawValue: raw) ?? .unknown
    }

    /// Asks the system once (it remembers the person's choice) and says
    /// whether community features may open.
    func allowsCommunity() async -> Bool {
        if signal == .unknown { await ask() }
        return signal.allowsCommunity
    }

    private func ask() async {
        #if canImport(DeclaredAgeRange) && !SWIFT_PACKAGE
        guard let presenter = AgeGate.presenter() else { return }
        do {
            let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18, in: presenter)
            switch response {
            case .sharing(let range):
                remember(AgeSignal.from(lowerBound: range.lowerBound, upperBound: range.upperBound, declined: false))
            case .declinedSharing:
                remember(.unknown)
            @unknown default:
                break
            }
        } catch {
            // not available (no entitlement, older system, no account age):
            // no signal, nothing shown
        }
        #endif
    }

    private func remember(_ value: AgeSignal) {
        signal = value
        UserDefaults.standard.set(value.rawValue, forKey: AgeGate.key)
    }

    /// The view controller on top of the key window, to present over.
    private static func presenter() -> UIViewController? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active: UIWindowScene? = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top: UIViewController? = active?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension View {
    /// Hidden when the age signal says the person is a minor (AgeGate).
    func communityOnly() -> some View {
        modifier(CommunityOnly())
    }
}

private struct CommunityOnly: ViewModifier {
    @ObservedObject private var gate = AgeGate.shared

    func body(content: Content) -> some View {
        if gate.signal.allowsCommunity {
            content
        }
    }
}
