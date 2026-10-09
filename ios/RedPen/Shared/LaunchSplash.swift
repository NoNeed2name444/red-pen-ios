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
/// VoiceOver, and it is gone within `total` seconds - or, at a launch still
/// reading a big library (Store), as soon as the library is read, and within
/// `longestHold` + `fade` at most.
struct LaunchSplash: View {
    /// Fully visible for `hold`, then a `fade`: 0.7 s in all, under the 0.8 s
    /// budget.
    static let hold: Double = 0.3
    static let fade: Double = 0.4
    static var total: Double { hold + fade }
    /// The longest it waits for the library to be read: a still picture held
    /// any longer looks hung, so past this it fades anyway, onto the screen
    /// that says the library is opening (LibraryLoadingView).
    static let longestHold: Double = 2

    /// Midnight, #0A1628: the same as the LaunchBackground colour set, written
    /// out so the splash never depends on the colour set being found. The
    /// launch colour is the owner's choice, outside the Ward palette.
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

    /// False while the library is still being read: the splash waits for it,
    /// so the screen saying it is opening seldom shows at all.
    var ready: Bool = true

    @State private var visible: Bool = LaunchSplash.wanted
    /// `hold` has passed.
    @State private var held: Bool = false

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
            held = true
            try? await Task.sleep(nanoseconds: UInt64((LaunchSplash.longestHold - LaunchSplash.hold) * 1_000_000_000))
            fadeOut()
        }
        // the task sees `ready` as it was when it started, so the two are
        // joined here, where it is current
        .onChange(of: held && ready) { _, go in
            if go { fadeOut() }
        }
    }

    private func fadeOut() {
        guard visible else { return }
        withAnimation(.easeOut(duration: LaunchSplash.fade)) { visible = false }
    }
}

/// What shows beneath the splash while a big library is still being read
/// (Store): the matte base and a spinner, and no screen that could show the
/// library, or write into it, before it is in.
struct LibraryLoadingView: View {
    var body: some View {
        VStack(spacing: WardSpace.m) {
            ProgressView()
            Text("Opening your library…")
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wardScreen()
    }
}

extension View {
    /// Lays the launch splash over this view for the first moment of a
    /// launch, and longer while `ready` is false (the library still being read).
    func launchSplash(until ready: Bool = true) -> some View {
        overlay { LaunchSplash(ready: ready) }
    }
}
