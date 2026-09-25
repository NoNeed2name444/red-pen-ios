import SwiftUI

/// The first frame: the Midnight Enamel mark and the Stethoscore wordmark on
/// Midnight navy, fading out over the app that is already there underneath.
///
/// The Xcode build has a real launch screen (`UILaunchScreen` in project.yml,
/// drawing the same `LaunchLogo` image on the same colour), so there this only
/// carries that picture across into the first SwiftUI frame and dissolves it.
/// The Swift Playgrounds package has no launch screen at all, so there this
/// *is* the launch screen - which is why it is a view and not a plist entry.
///
/// It never holds anything up: the app is built and running beneath it from
/// the first frame, it ignores touches (a tap goes straight through to the
/// screen below, which is what makes it skippable), it is hidden from
/// VoiceOver, and it is gone within `total` seconds.
struct LaunchSplash: View {
    /// Fully visible for `hold`, then a `fade`: 0.7 s in all, under the 0.8 s
    /// budget.
    static let hold: Double = 0.3
    static let fade: Double = 0.4
    static var total: Double { hold + fade }

    /// Midnight, #0A1628: the same as the LaunchBackground colour set, written
    /// out so the splash never depends on the colour set being found.
    static let midnight = Color(red: 10 / 255, green: 22 / 255, blue: 40 / 255)

    /// Once per process: a second window on iPad, or a scene rebuilt after a
    /// memory warning, is not a launch.
    @MainActor private static var shown = false

    /// No splash for CI screenshots, the graph design preview, or a launch
    /// that asks for none (`-noSplash`).
    @MainActor static var wanted: Bool {
        !shown
            && PreviewLaunch.screen == nil
            && !GraphPreview.isOn
            && !ProcessInfo.processInfo.arguments.contains("-noSplash")
    }

    @State private var visible: Bool = LaunchSplash.wanted

    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    LaunchSplash.midnight.ignoresSafeArea()
                    // at its natural point size, centred in the safe area:
                    // exactly where UILaunchScreen puts the same image
                    Image("LaunchLogo")
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard visible else { return }
            LaunchSplash.shown = true
            try? await Task.sleep(nanoseconds: UInt64(LaunchSplash.hold * 1_000_000_000))
            withAnimation(.easeOut(duration: LaunchSplash.fade)) { visible = false }
        }
    }
}

extension View {
    /// Lays the launch splash over this view for the first moment of a launch.
    func launchSplash() -> some View {
        overlay { LaunchSplash() }
    }
}
