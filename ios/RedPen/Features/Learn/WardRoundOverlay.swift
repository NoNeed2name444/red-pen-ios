import SwiftUI
import UIKit

// MARK: - The ward round over the whole app
//
// While a ward round runs, a small chip floats at the bottom of the screen,
// in the same band as the library's New set button over the dock - and it
// stays there wherever the student goes: into a deck, a quiz in a sheet, the
// 3D map. Tapping it opens the round in a glass panel over everything;
// dragging it moves it to another corner, out of a screen's way.
//
// It lives in a window of its own, one level above the app's, because
// nothing inside the app's window can float over its sheets and full-screen
// covers. The window is only there while a round is, and only the chip (or
// the open panel) takes touches - everything else falls through to the app
// beneath, which also keeps the keyboard, the status bar and the rotation.

@MainActor
final class WardRoundOverlay {
    static let shared = WardRoundOverlay()

    let model = WardRoundOverlayModel()
    private var window: WardRoundWindow?
    private var sceneWatch: NSObjectProtocol?

    private init() {
        // iPad, two windows: the chip follows whichever is in front
        sceneWatch = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification,
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                WardRoundOverlay.shared.follow()
            }
        }
    }

    /// Shows the chip while there is a round; takes the window away after.
    func sync(showing: Bool) {
        guard showing else {
            model.expanded = false
            window?.isHidden = true
            window = nil
            return
        }
        attach()
    }

    /// Opens the round's panel (the tile's "Open the round").
    func open() {
        attach()
        model.expanded = true
    }

    private func follow() {
        guard window != nil else { return }
        attach()
    }

    private func attach() {
        guard let scene = Self.frontScene() else { return }
        if let window, window.windowScene === scene {
            Self.matchStyle(window, in: scene)
            return
        }
        window?.isHidden = true
        let fresh = WardRoundWindow(windowScene: scene)
        fresh.model = model
        fresh.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        fresh.backgroundColor = .clear
        Self.matchStyle(fresh, in: scene)
        let host = WardRoundHost(rootView: WardRoundFloat(model: model))
        host.view.backgroundColor = .clear
        fresh.rootViewController = host
        fresh.isHidden = false
        window = fresh
    }

    /// The app's own light or dark ("Always night sky" holds it dark),
    /// looked at again on every change of the round (a pause, a phase
    /// ending, the panel opened from the tile), so a switch made while a
    /// round runs does not leave the chip in the other look for long.
    private static func matchStyle(_ own: UIWindow, in scene: UIWindowScene) {
        let others: [UIWindow] = scene.windows.filter { $0 !== own && !$0.isHidden }
        let beneath: UIWindow? = others.first { $0.isKeyWindow } ?? others.first
        own.overrideUserInterfaceStyle = beneath?.traitCollection.userInterfaceStyle ?? .unspecified
    }

    private static func frontScene() -> UIWindowScene? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

/// Where the chip sits and whether the panel is open.
@MainActor
final class WardRoundOverlayModel: ObservableObject {
    @Published var expanded = false
    /// The chip's frame in the window, for the window to know what to catch.
    var chipFrame: CGRect = .zero
}

/// Catches touches only on the chip, or everywhere while the panel is open.
final class WardRoundWindow: UIWindow {
    weak var model: WardRoundOverlayModel?

    /// Never the key window: a tap on the chip must not take the keyboard
    /// from a field beneath, and screens that present from the key window's
    /// root (sign in, the age check, Reasoning's share) must keep finding
    /// the app's own window rather than this one, where nothing but the
    /// chip takes a touch.
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let model else { return nil }
        let onChip: Bool = model.chipFrame.insetBy(dx: -6, dy: -6).contains(point)
        guard model.expanded || onChip else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Leaves the status bar and the rotation to whatever the app is showing.
final class WardRoundHost: UIHostingController<WardRoundFloat> {
    private var beneath: UIViewController? {
        guard let own = view.window, let scene = own.windowScene else { return nil }
        let main: UIWindow? = scene.windows.first { $0 !== own && $0.windowLevel == .normal && !$0.isHidden }
        var top: UIViewController? = main?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        beneath?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        beneath?.prefersStatusBarHidden ?? false
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        beneath?.supportedInterfaceOrientations ?? .all
    }
}

/// The window's content: the chip in its corner, or the open panel.
struct WardRoundFloat: View {
    @ObservedObject var model: WardRoundOverlayModel
    @ObservedObject private var clock = WardRoundClock.shared
    @AppStorage("wardRound.corner") private var cornerRaw = WardRoundCorner.bottomLeading.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @State private var drag: CGSize = .zero
    /// The window's size, for working out which corner a throw aims at.
    @State private var area: CGSize = .zero

    private var corner: WardRoundCorner { WardRoundCorner(rawValue: cornerRaw) ?? .bottomLeading }

    var body: some View {
        ZStack {
            if let round = clock.round {
                if model.expanded {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { setExpanded(false) }
                        .accessibilityHidden(true)
                    WardRoundPanel(round: round, notice: clock.notice) { setExpanded(false) }
                        .frame(maxWidth: 440)
                        // VoiceOver stays in the open panel; the escape
                        // gesture (two fingers, a Z) folds it away
                        .accessibilityAddTraits(.isModal)
                        .accessibilityAction(.escape) { setExpanded(false) }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    chip(round)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
        .tint(Color(red: 0.78, green: 0.16, blue: 0.16))
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: model.expanded)
    }

    private func setExpanded(_ open: Bool) {
        model.expanded = open
    }

    private func chip(_ round: WardRound) -> some View {
        WardRoundChip(round: round, notice: clock.notice) { setExpanded(true) }
            .offset(drag)
            .gesture(moving)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                model.chipFrame = frame
            }
            .padding(.horizontal, 16)
            .padding(.vertical, corner.isBottom ? 84 : 52)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }

    /// Dragged, the chip goes to the corner it was thrown towards.
    private var moving: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in drag = value.translation }
            .onEnded { value in
                let across: CGFloat = value.predictedEndLocation.x / max(1, area.width)
                let down: CGFloat = value.predictedEndLocation.y / max(1, area.height)
                // leading is on the right in a right-to-left language
                let leading: CGFloat = direction == .rightToLeft ? 1 - across : across
                let next = WardRoundCorner.nearest(x: leading, y: down)
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                    cornerRaw = next.rawValue
                    drag = .zero
                }
            }
    }
}

/// The four places the chip can sit.
enum WardRoundCorner: String {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var isBottom: Bool { self == .bottomLeading || self == .bottomTrailing }

    /// `x` (from the leading edge) and `y` as fractions of the window.
    static func nearest(x: CGFloat, y: CGFloat) -> WardRoundCorner {
        let leading: Bool = x < 0.5
        if y < 0.5 { return leading ? .topLeading : .topTrailing }
        return leading ? .bottomLeading : .bottomTrailing
    }
}
