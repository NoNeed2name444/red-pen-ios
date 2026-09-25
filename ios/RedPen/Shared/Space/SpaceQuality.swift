import Foundation
import SwiftUI
import UIKit

// MARK: - How alive the sky may be
//
// One switch every space effect reads, so each new effect gets the
// accessibility and battery rules for free instead of deciding them again
// (and differently):
//
//   full     the nebula drifts, stars twinkle and follow the tilt, lift-off
//            warps, rings run a hot spot, the aurora moves
//   reduced  the nebula drifts; nothing follows the tilt, nothing warps
//   still    one frame; nothing moves at all
//
// Worked out from Reduce Motion, Reduce Transparency, Increase Contrast,
// Low Power Mode and the thermal state. The pop-out's tilt follows it too
// (PopOutMotion.mustStayStill): it only runs at `.full`.

enum SpaceQuality: Int, Comparable, Sendable {
    case still = 0
    case reduced = 1
    case full = 2

    static func < (lhs: SpaceQuality, rhs: SpaceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether anything may move by itself (the nebula's drift).
    var drifts: Bool { self != .still }

    /// Twinkle, tilt, warp, hot spots, a moving aurora.
    var isFull: Bool { self == .full }

    /// Worked out fresh from the system, on the main actor (UIAccessibility).
    @MainActor
    static func current() -> SpaceQuality {
        if UIAccessibility.isReduceMotionEnabled { return .still }
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return .still }
        let thermal: ProcessInfo.ThermalState = info.thermalState
        if thermal == .serious || thermal == .critical { return .still }
        if thermal == .fair { return .reduced }
        if UIAccessibility.isReduceTransparencyEnabled { return .reduced }
        if UIAccessibility.isDarkerSystemColorsEnabled { return .reduced }
        return .full
    }
}

/// Publishes SpaceQuality for SwiftUI, and tells the pop-out when it changes.
/// The notifications (thermal especially) can arrive on any thread; they are
/// taken on the main queue.
@MainActor
@Observable
final class SpaceQualityCenter {
    static let shared = SpaceQualityCenter()

    private(set) var level: SpaceQuality

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        level = SpaceQuality.current()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recompute()
                }
            }
            observers.append(token)
        }
    }

    func recompute() {
        let now: SpaceQuality = SpaceQuality.current()
        guard now != level else { return }
        level = now
        PopOutMotion.shared.refresh()
    }
}

private struct SpaceQualityKey: EnvironmentKey {
    static let defaultValue: SpaceQuality = .full
}

extension EnvironmentValues {
    /// How alive the sky may be; set once at the root (popOutLifecycle).
    var spaceQuality: SpaceQuality {
        get { self[SpaceQualityKey.self] }
        set { self[SpaceQualityKey.self] = newValue }
    }
}

/// The Settings toggles that belong to the sky.
enum SpaceSettings {
    /// Bool, default false: "Always night sky" - the dark nebula (and the
    /// app's dark appearance) even when the system is in light mode.
    static let alwaysNightKey = "vignette.space.alwaysNight"
    /// Bool, default false: "Sounds" - the quiet synthesized cues.
    static let soundsKey = "vignette.space.sounds"

    static var alwaysNight: Bool {
        UserDefaults.standard.object(forKey: alwaysNightKey) as? Bool ?? false
    }

    static var sounds: Bool {
        UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? false
    }
}

// MARK: - The root

private struct SkyZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace the category tiles and the pages they open share for
    /// the zoom transition. Made once at the root.
    var skyZoom: Namespace.ID? {
        get { self[SkyZoomKey.self] }
        set { self[SkyZoomKey.self] = newValue }
    }
}

/// Wraps the whole app (from popOutLifecycle): publishes SpaceQuality and the
/// zoom namespace, and holds the app dark when "Always night sky" is on.
struct SkyRoot<Content: View>: View {
    let content: Content
    @Namespace private var zoom
    @AppStorage(SpaceSettings.alwaysNightKey) private var alwaysNight = false

    var body: some View {
        let level: SpaceQuality = SpaceQualityCenter.shared.level
        let scheme: ColorScheme? = alwaysNight ? .dark : nil
        content
            .environment(\.spaceQuality, level)
            .environment(\.skyZoom, zoom)
            .preferredColorScheme(scheme)
            .onAppear {
                // the cues' tones are made once, ahead of the first one
                if SpaceSettings.sounds { SpaceSounds.shared.prepare() }
            }
    }
}
