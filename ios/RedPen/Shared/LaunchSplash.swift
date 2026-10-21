import SwiftUI

/// The first frame: the mark and the Stethoscore wordmark on the home
/// screen's own base colour (the Ward base, light or dark), then gone at once,
/// uncovering the app that is already there underneath. Same colour before
/// and after, so the launch runs straight on into the home screen. It does
/// not fade: the owner wants no fading in the app.
///
/// The one case where the colours differ: the system launch screen follows
/// the phone's light or dark, and the app can be set to the other one. Then
/// the splash's colour moves from the phone's base to the app's while the
/// logo holds, so the change is a colour shift, not a jump.
///
/// The Xcode build has a real launch screen (`UILaunchScreen` in project.yml,
/// drawing the same `LaunchLogo` image on the same colour), so there this only
/// carries that picture across into the first SwiftUI frame and lifts it.
/// The Swift Playgrounds package has no launch screen at all, so there this
/// *is* the launch screen - which is why it is a view and not a plist entry.
///
/// It never holds anything up: the app is built and running beneath it from
/// the first frame, it ignores touches (a tap goes straight through to the
/// screen below, which is what makes it skippable), it is hidden from
/// VoiceOver, and it is gone within `total` seconds - or, at a launch still
/// reading a big library (Store), as soon as the library is read, and within
/// `longestHold` at most.
struct LaunchSplash: View {
    /// Fully visible for `hold`, then gone, with no fade: 0.3 s in all, under
    /// the 0.8 s budget.
    static let hold: Double = 0.3
    static var total: Double { hold }
    /// The longest it waits for the library to be read: a still picture held
    /// any longer looks hung, so past this it goes anyway, onto the screen
    /// that says the library is opening (LibraryLoadingView).
    static let longestHold: Double = 2

    /// How long the colour takes to move to the app's, when it has to.
    static let shift: Double = 0.25

    /// Whether the phone itself (not the app's setting) is in dark mode: what
    /// the system launch screen, LaunchBackground and LaunchLogo, was drawn
    /// in. The screen's traits are the phone's; a window's can be the app's.
    @MainActor static var phoneIsDark: Bool {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        return screen?.traitCollection.userInterfaceStyle == .dark
    }

    /// The Ward base as the system launch screen drew it: the LaunchBackground
    /// colour set, written out so the splash never depends on it being found.
    static func base(dark: Bool) -> Color {
        let (r, g, b) = WardPalette.rgb(WardPalette.hex(.background, dark: dark))
        return Color(red: r, green: g, blue: b)
    }

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
    /// The phone's light or dark, read once, at launch.
    @State private var phoneDark: Bool = LaunchSplash.phoneIsDark
    /// The colour has moved on to the app's own base.
    @State private var settled: Bool = false

    var body: some View {
        ZStack {
            if visible {
                ZStack {
                    (settled ? Color.wardBackground : LaunchSplash.base(dark: phoneDark))
                        .ignoresSafeArea()
                    // at its natural point size, centred in the safe area:
                    // exactly where UILaunchScreen puts the same image, in
                    // the same light or dark as the system drew it
                    Image("LaunchLogo")
                        .environment(\.colorScheme, phoneDark ? .dark : .light)
                }
                // no fade, even under an animation from around it
                .transition(.identity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard visible else { return }
            LaunchSplash.shown = true
            // a colour shift, not a fade: nothing changes when the app's
            // base is the phone's, which is nearly always
            withAnimation(.easeInOut(duration: LaunchSplash.shift)) { settled = true }
            try? await Task.sleep(nanoseconds: UInt64(LaunchSplash.hold * 1_000_000_000))
            held = true
            try? await Task.sleep(nanoseconds: UInt64((LaunchSplash.longestHold - LaunchSplash.hold) * 1_000_000_000))
            hide()
        }
        // the task sees `ready` as it was when it started, so the two are
        // joined here, where it is current
        .onChange(of: held && ready) { _, go in
            if go { hide() }
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
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
