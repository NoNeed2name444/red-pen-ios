import SwiftUI
import AuthenticationServices

/// The way in.
///
/// What the app is, up top; the doors at the bottom, under the thumb. The one
/// that works on its own - start without an account - is the lowest and the
/// highest out of the glass; above it Apple, which on this platform is one
/// tap and gives away the least; Google, because most students are already
/// signed in to it in Safari; and a code, for a second iPhone or iPad joining
/// the library of the first.
///
/// What this screen does not do is ask for a password. Nothing here stores one,
/// so nothing here can leak one.
struct SignInView: View {
    @EnvironmentObject var account: AccountStore

    @Environment(\.colorScheme) private var scheme
    @State private var joining = false

    /// The app's pen red, for the door that works on its own.
    private static let pen = Color(red: 0.78, green: 0.16, blue: 0.16)

    private static let door = RoundedRectangle(cornerRadius: 12, style: .continuous)

    /// The pane the doors stand on: their 12-point corners plus its 12-point
    /// margin.
    private static let pane = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        ZStack {
            LibraryBackdrop()
            upper
                // every door in one stack at the bottom; nothing is ever
                // drawn over them
                .safeAreaInset(edge: .bottom, spacing: 0) { doors }
        }
        .sheet(isPresented: $joining) { LinkDeviceView(joinOnly: true) }
        .alert(L10n.string("Couldn't sign in"), isPresented: troubleShown) {
            Button(L10n.string("OK"), role: .cancel) {}
        } message: {
            Text(account.trouble ?? "")
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: 480)
    }

    private var masthead: some View {
        VStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach([StudySetKind.mcq, .anki, .qa], id: \.self) { kind in
                    mastTile(kind)
                }
            }
            .padding(.bottom, 6)
            // a picture, not a row: fanned the same way in either direction
            .keepsLeftToRight()
            .accessibilityHidden(true)
            Text(Brand.name).font(.largeTitle.weight(.bold))
            Text(l10n: "Turn your lectures into questions and flashcards.")
                .font(.body).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// One of the three fanned tiles, each at its own height out of the
    /// glass. Lifted before it is turned, so its slab side turns with it.
    private func mastTile(_ kind: StudySetKind) -> some View {
        let corner: CGFloat = 52 * 0.28
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let plane: PopOutPlane = SignInView.tilePlane(kind)
        let angle: Double = SignInView.tileAngle(kind)
        let layer: Double = SignInView.tileLayer(kind)
        return ModeTile(kind: kind, size: 52)
            .popOut(plane, in: shape)
            .rotationEffect(.degrees(angle))
            .zIndex(layer)
    }

    /// Questions to the left, cards upright in the middle, cases to the right.
    private static func tileAngle(_ kind: StudySetKind) -> Double {
        switch kind {
        case .anki: return 0
        case .mcq: return -10
        default: return 10
        }
    }

    /// The middle tile highest, the right one next, the left one lowest.
    private static func tilePlane(_ kind: StudySetKind) -> PopOutPlane {
        switch kind {
        case .anki: return .hero
        case .qa: return .floating
        default: return .raised
        }
    }

    /// The highest tile is drawn on top of its neighbours.
    private static func tileLayer(_ kind: StudySetKind) -> Double {
        switch kind {
        case .anki: return 2
        case .qa: return 1
        default: return 0
        }
    }

    private var smallPrint: some View {
        // one line of small print instead of two: what each choice means,
        // and that nothing is shared
        Text(l10n: "No account needed to start \u{2014} you can link an iPad or another phone later in Account. Nothing is shared with anyone else.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: The doors

    /// Top to bottom: a code, Google, Apple, and - lowest, under the thumb -
    /// straight in. Centred in the same 480-point column on an iPad.
    ///
    /// On a pane of material, so that when a large text size makes the story
    /// scroll it goes under the pane rather than showing between the doors.
    /// The pane is a background (never over `localSignIn`) and lies on the
    /// glass, so every door keeps its full height above it.
    private var doors: some View {
        VStack(spacing: 12) {
            codeDoor
            googleDoor
            appleDoor
            localDoor
        }
        .padding(12)
        .background(.regularMaterial, in: SignInView.pane)
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
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .controlSize(.large)
        .popOut(.raised, in: SignInView.door)
        .disabled(account.busy)
        .accessibilityIdentifier("joinWithCode")
    }

    /// Drawn to match Apple's button - same height, corners, weight and
    /// colours - so the two read as one pair, and moving the same way: only
    /// sideways, never leaning.
    private var googleDoor: some View {
        let dark: Bool = scheme == .dark
        let ink: Color = dark ? Color.black : Color.white
        let fill: Color = dark ? Color.white : Color.black
        return Button {
            Task { await account.signInWithGoogle() }
        } label: {
            doorLabel(L10n.string("Sign in with Google"), symbol: "globe", busy: account.busy)
                .frame(height: 56)
                .foregroundStyle(ink)
                .background(fill, in: SignInView.door)
        }
        .buttonStyle(.plain)
        .contentShape(SignInView.door)
        .popOut(.raised, in: SignInView.door, cues: [])
        // the iPad pointer lifts it like the other three doors
        .contentShape(.hoverEffect, SignInView.door)
        .hoverEffect(.lift)
        .disabled(account.busy)
    }

    /// Apple's own button, left as Apple draws it: it only moves sideways.
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
        .popOut(.raised, in: SignInView.door, cues: [])
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
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .controlSize(.large)
        .tint(SignInView.pen)
        .popOut(.hero, in: SignInView.door)
        .keyboardShortcut(.defaultAction)
        .accessibilityHint(L10n.string("Everything stays on this device"))
        .accessibilityIdentifier("localSignIn")
    }

    private func doorLabel(_ title: String, symbol: String, busy: Bool = false) -> some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            }
            Text(title).font(.system(size: 19, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }
}
