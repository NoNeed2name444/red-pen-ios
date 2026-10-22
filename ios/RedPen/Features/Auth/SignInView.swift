import SwiftUI
import AuthenticationServices

/// The way in.
///
/// What the app is, up top; the doors at the bottom, under the thumb. The one
/// that works on its own - start without an account - is the lowest and the
/// one raised highest, its words in the section's accent; above it Apple, which on this platform is one
/// tap and gives away the least; Google, because most students are already
/// signed in to it in Safari - in a build that carries a Google client id; and
/// a code, for a second iPhone or iPad joining the library of the first.
///
/// What this screen does not do is ask for a password. Nothing here stores one,
/// so nothing here can leak one.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore

    @Environment(\.colorScheme) private var scheme
    @State private var joining = false

    /// The section's accent, for the door that works on its own: the tone
    /// that reads as words on the soft base.
    private static var pen: Color { .wardPrimaryInk }

    private static let door = RoundedRectangle(cornerRadius: WardRadius.button, style: .continuous)

    /// The pane the doors stand on: their corners plus its 12-point margin.
    private static let pane = RoundedRectangle(cornerRadius: WardRadius.button + 12, style: .continuous)

    var body: some View {
        ZStack {
            WardBackground()
            upper
                // every door in one stack at the bottom; nothing is ever
                // drawn over them
                .safeAreaInset(edge: .bottom, spacing: 0) { doors.wardUnlit() }
        }
        .sheet(isPresented: $joining) { LinkDeviceView(joinOnly: true) }
        .alert(L10n.string("Couldn't sign in"), isPresented: troubleShown) {
            Button(L10n.string("Done"), role: .cancel) {}
        } message: {
            Text(account.trouble ?? "")
        }
        // after an Apple account is deleted: the steps from Apple's own
        // support article, the account's last link being in Settings
        .alert(L10n.string("Account deleted"), isPresented: $account.appleStepsDue) {
            Button(L10n.string("Done"), role: .cancel) {}
        } message: {
            Text(l10n: "Your Apple Account still lists \(Brand.name) under Sign in with Apple. To remove it, open Settings, tap your name, then Sign in with Apple. Choose \(Brand.name) and tap Delete.")
        }
    }

    private var troubleShown: Binding<Bool> {
        Binding(get: { account.trouble != nil },
                set: { shown in if !shown { account.trouble = nil } })
    }

    // MARK: Up top

    /// Centred in the room above the doors when it fits; scrolls when a large
    /// text size makes it taller than that.
    private var upper: some View {
        ViewThatFits(in: .vertical) {
            story
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                story
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var story: some View {
        VStack(spacing: 20) {
            masthead
            smallPrint
            agreement
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: 480)
    }

    private var masthead: some View {
        VStack(spacing: 10) {
            // the launch's stethoscope, white by day and grey by night (the
            // owner, 22 Oct), where the three mode tiles stood
            SignInLaunchMark()
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(Brand.name).font(WardType.display).foregroundStyle(Color.wardInk)
            Text(l10n: "Turn your lectures into questions and flashcards.")
                .font(.body).foregroundStyle(Color.wardInkSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var smallPrint: some View {
        // one line of small print instead of two: what each choice means,
        // and that nothing is shared
        Text(l10n: "No account needed to start \u{2014} you can link an iPad or another phone later in Account. Nothing is shared with anyone else.")
            .font(.footnote)
            .foregroundStyle(Color.wardInkSecondary)
            .multilineTextAlignment(.center)
    }

    /// What continuing agrees to, with the Terms and the Privacy Policy one
    /// tap away. One sentence for translators: the links are placeholders
    /// (`legal://`) that LegalLinks turns into the worker's pages.
    private var agreement: some View {
        Text("By continuing you agree to the [Terms](legal://terms) and [Privacy Policy](legal://privacy).")
            .font(WardType.caption)
            .foregroundStyle(Color.wardInkSecondary)
            .tint(Color.wardPrimaryInk) // links are text: primaryInk keeps 4.5:1 in dark mode
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in
                guard let page = LegalLinks.resolve(url) else { return .systemAction }
                return .systemAction(page)
            })
            .accessibilityIdentifier("signInAgreement")
    }

    // MARK: The doors

    /// Top to bottom: a code, Google, Apple, and - lowest, under the thumb -
    /// straight in. Centred in the same 480-point column on an iPad. Google
    /// only when the build is set up for it: without a client id its door
    /// could only fail.
    ///
    /// On a soft pane raised high off the base, so that when a large text size makes the story
    /// scroll it goes under the pane rather than showing between the doors.
    /// The pane is a background (never over `localSignIn`), so every door
    /// keeps its full height above it.
    private var doors: some View {
        VStack(spacing: 12) {
            codeDoor
            if GoogleSignIn.isConfigured { googleDoor }
            appleDoor
            localDoor
        }
        .padding(12)
        .wardRaised(in: SignInView.pane, lift: .high)
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    /// A second iPhone or iPad joins the library of the first.
    private var codeDoor: some View {
        Button {
            joining = true
        } label: {
            Label(L10n.string("I have a code from another device"), systemImage: "ipad.and.iphone")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.wardSecondary)
        .disabled(account.busy)
        .accessibilityIdentifier("joinWithCode")
    }

    /// Google's own branded button (the owner, 22 Oct), as Google's sign-in
    /// branding guidelines draw it: the multicolour G on the left, "Sign in
    /// with Google", Google's light theme by day (white, a grey hairline) and
    /// its dark theme by night - Apple's height and corners beside it. Its
    /// colours are Google's, exempt from the ten hexes, as Apple's are.
    private var googleDoor: some View {
        let theme = GoogleButtonTheme(dark: scheme == .dark)
        return Button {
            Task { await account.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if account.busy {
                    EcgLoader()
                } else {
                    GoogleG()
                        .frame(width: 20, height: 20)
                }
                // Google's guidelines: the label at 14 pt, medium, here
                // scaled with Dynamic Type like the rest of the screen
                Text(L10n.string("Sign in with Google"))
                    .scaledFont(GoogleButtonTheme.labelSize, relativeTo: .body, weight: .medium)
                    .foregroundStyle(theme.text)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(theme.fill, in: SignInView.door)
            .overlay(SignInView.door.strokeBorder(theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(SignInView.door)
        // the iPad pointer lifts it like the other three doors
        .contentShape(.hoverEffect, SignInView.door)
        .hoverEffect(.lift)
        .disabled(account.busy)
    }

    /// Apple's own button, left as Apple draws it.
    private var appleDoor: some View {
        let style: SignInWithAppleButton.Style = scheme == .dark ? .white : .black
        return SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = account.beginApple()
        } onCompletion: { result in
            Task { await account.finishApple(result) }
        }
        .signInWithAppleButtonStyle(style)
        .frame(height: 56)
        .clipShape(SignInView.door)
    }

    /// Personal build: straight in, no Apple or Google account and no server.
    /// The screen's one hero, because it is the one that works on its own.
    private var localDoor: some View {
        Button {
            account.useThisDeviceOnly(name: "")
        } label: {
            doorLabel(L10n.string("Start without an account"), symbol: "iphone.gen3")
                .frame(minHeight: 40)
        }
        .buttonStyle(.wardPrimary)
        .tint(SignInView.pen)
        .keyboardShortcut(.defaultAction)
        .accessibilityHint(L10n.string("Everything stays on this device"))
        .accessibilityIdentifier("localSignIn")
    }

    private func doorLabel(_ title: String, symbol: String, busy: Bool = false) -> some View {
        HStack(spacing: 8) {
            if busy {
                EcgLoader()
            } else {
                Image(systemName: symbol).scaledFont(17, relativeTo: .body, weight: .semibold, maxSize: 28)
            }
            Text(title).scaledFont(19, relativeTo: .body, weight: .medium)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The launch mark over "Stethoscore" on sign-in and account-deleted: the
/// owner's stethoscope, the white one by day and the grey one by night, the
/// same private art the launch draws (LaunchArt). It is not in this
/// repository and no build step here adds it: the owner's private
/// Claude-Code repository's tools/inject_brand_art.py (commit 1adb11e) writes
/// it into a downloaded IPA, from its design/brand-art/red-pen-ios-fed0105/
/// ios/RedPen/Assets.xcassets/LaunchLogo.imageset/launch-logo{,-dark}@{1,2,3}x.png,
/// as Payload/<App>.app/LaunchLogo{,@2x,@3x}.png and LaunchLogo-dark{,@2x,@3x}.png,
/// which UIImage(named:) finds by LaunchArt.names. So every app CI builds
/// (the simulator tours, the IPA before that tool runs on it) shows the
/// stand-in: a stethoscope in the ink, the same size.
private struct SignInLaunchMark: View {
    @Environment(\.colorScheme) private var scheme

    /// The mark's side in points, a little over half the launch's own.
    static let side: CGFloat = 120

    var body: some View {
        let dark: Bool = scheme == .dark
        Group {
            if let art = Self.art(dark: dark) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "stethoscope")
                    .resizable()
                    .scaledToFit()
                    .padding(Self.side / 5)
                    .foregroundStyle(Color.wardInkSecondary)
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    /// The mode's picture, or the day one by night when only that is there.
    private static func art(dark: Bool) -> UIImage? {
        LaunchArt.names(dark: dark).lazy.compactMap { UIImage(named: $0) }.first
    }
}

/// Google's sign-in button colours, from its branding guidelines (light:
/// white, #747775 hairline, #1F1F1F words; dark: #131314, #8E918F
/// hairline, #E3E3E3 words). Google's, not the app's: exempt from the ten
/// hexes, as Apple's black and white button is.
private struct GoogleButtonTheme {
    /// The label's size in Google's guidelines, before Dynamic Type.
    static let labelSize: CGFloat = 14

    let fill: Color
    let stroke: Color
    let text: Color

    init(dark: Bool) {
        fill = GoogleButtonTheme.rgb(dark ? 0x131314 : 0xFFFFFF)
        stroke = GoogleButtonTheme.rgb(dark ? 0x8E918F : 0x747775)
        text = GoogleButtonTheme.rgb(dark ? 0xE3E3E3 : 0x1F1F1F)
    }

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

/// Google's "G", in its four colours, drawn from Google's own 48-point
/// artwork and scaled to the frame it is given.
private struct GoogleG: View {
    enum Part: CaseIterable { case red, blue, yellow, green }

    var body: some View {
        Canvas { context, size in
            let scale: CGFloat = min(size.width, size.height) / 48
            for part in Part.allCases {
                context.fill(Self.path(part, scale: scale), with: .color(Self.color(part)))
            }
        }
        .accessibilityHidden(true)
    }

    static func color(_ part: Part) -> Color {
        switch part {
        case .red: return GoogleButtonTheme.rgb(0xEA4335)
        case .blue: return GoogleButtonTheme.rgb(0x4285F4)
        case .yellow: return GoogleButtonTheme.rgb(0xFBBC05)
        case .green: return GoogleButtonTheme.rgb(0x34A853)
        }
    }

    static func path(_ part: Part, scale: CGFloat) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        var p = Path()
        switch part {
        case .red:
            p.move(to: pt(24, 9.5))
            p.addCurve(to: pt(33.21, 13.1), control1: pt(27.54, 9.5), control2: pt(30.71, 10.72))
            p.addLine(to: pt(40.06, 6.25))
            p.addCurve(to: pt(24, 0), control1: pt(35.9, 2.38), control2: pt(30.47, 0))
            p.addCurve(to: pt(2.56, 13.22), control1: pt(14.62, 0), control2: pt(6.51, 5.38))
            p.addLine(to: pt(10.54, 19.41))
            p.addCurve(to: pt(24, 9.5), control1: pt(12.43, 13.72), control2: pt(17.74, 9.5))
            p.closeSubpath()
        case .blue:
            p.move(to: pt(46.98, 24.55))
            p.addCurve(to: pt(46.6, 20), control1: pt(46.98, 22.98), control2: pt(46.83, 21.46))
            p.addLine(to: pt(24, 20))
            p.addLine(to: pt(24, 29.02))
            p.addLine(to: pt(36.94, 29.02))
            p.addCurve(to: pt(32.16, 36.2), control1: pt(36.36, 31.98), control2: pt(34.68, 34.5))
            p.addLine(to: pt(39.89, 42.2))
            p.addCurve(to: pt(46.98, 24.55), control1: pt(44.4, 38.02), control2: pt(46.98, 31.84))
            p.closeSubpath()
        case .yellow:
            p.move(to: pt(10.53, 28.59))
            p.addCurve(to: pt(9.77, 24), control1: pt(10.05, 27.14), control2: pt(9.77, 25.6))
            p.addCurve(to: pt(10.53, 19.41), control1: pt(9.77, 22.4), control2: pt(10.04, 20.86))
            p.addLine(to: pt(2.55, 13.22))
            p.addCurve(to: pt(0, 24), control1: pt(0.92, 16.46), control2: pt(0, 20.12))
            p.addCurve(to: pt(2.56, 34.78), control1: pt(0, 27.88), control2: pt(0.92, 31.54))
            p.addLine(to: pt(10.53, 28.59))
            p.closeSubpath()
        case .green:
            p.move(to: pt(24, 48))
            p.addCurve(to: pt(39.89, 42.19), control1: pt(30.48, 48), control2: pt(35.93, 45.87))
            p.addLine(to: pt(32.16, 36.19))
            p.addCurve(to: pt(24, 38.49), control1: pt(30.01, 37.64), control2: pt(27.24, 38.49))
            p.addCurve(to: pt(10.53, 28.58), control1: pt(17.74, 38.49), control2: pt(12.43, 34.27))
            p.addLine(to: pt(2.55, 34.77))
            p.addCurve(to: pt(24, 48), control1: pt(6.51, 42.62), control2: pt(14.62, 48))
            p.closeSubpath()
        }
        return p
    }
}
