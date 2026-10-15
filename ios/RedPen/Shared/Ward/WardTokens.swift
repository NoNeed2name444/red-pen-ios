#if canImport(SwiftUI)
import SwiftUI
import UIKit

// The Ward Round palette as SwiftUI colours, type, spacing and radii. Every
// colour comes from WardPalette's table through a dynamic UIColor, so light
// and dark have one source and no colour set can drift, and every one is
// drawn from the one look the app is at (WardLookStore), so a change of
// light or dark, or of section, shifts them all together. The soft UI light
// (WardRelief) is drawn by WardSurfaces.

extension Color {
    /// A palette colour. At rest it resolves from the trait it is drawn in,
    /// as it always has. While the look shifts (WardLookStore), it is this
    /// frame's colour, taken from the one glide every Ward colour shares,
    /// so the whole app is at one point of the shift on every frame.
    /// Reading it in a view's body subscribes the view to the shift.
    static func ward(_ token: WardToken) -> Color {
        let glide = WardLookStore.shared.glide
        if glide.settled { return WardRestColors.color(token, glide.to.section) }
        return Color(uiColor: UIColor { traits in
            Color.uiColor(glide.hex(token, dark: traits.userInterfaceStyle == .dark, held: traits.wardHeld))
        })
    }

    /// A given section's accent ink (WardSection.accent), whatever section
    /// is on show: a mode's own glyph on home. Light and dark only.
    static func wardAccent(_ section: WardSection) -> Color {
        WardRestColors.color(.primaryInk, section)
    }

    static var wardBackground: Color { ward(.background) }
    static var wardSurface: Color { ward(.surface) }
    static var wardRaised: Color { ward(.raised) }
    static var wardWell: Color { ward(.well) }
    static var wardPrimary: Color { ward(.primary) }
    static var wardPrimaryInk: Color { ward(.primaryInk) }
    static var wardOnPrimary: Color { ward(.onPrimary) }
    static var wardEcg: Color { ward(.ecg) }
    static var wardBeam: Color { ward(.beam) }
    static var wardSuccess: Color { ward(.success) }
    static var wardWarning: Color { ward(.warning) }
    static var wardDanger: Color { ward(.danger) }
    static var wardInk: Color { ward(.ink) }
    static var wardInkSecondary: Color { ward(.inkSecondary) }
    static var wardHairline: Color { ward(.hairline) }
    static var wardMonitor: Color { ward(.monitor) }

    /// The ink of an edge and of the paper's grid: the section's own hue
    /// (WardSection.ink), drawn at a spec's edge strength.
    static var wardEdgeInk: Color {
        let glide = WardLookStore.shared.glide
        if glide.settled { return WardRestColors.ink(glide.to.section) }
        return Color(uiColor: UIColor { traits in
            Color.uiColor(glide.ink(dark: traits.userInterfaceStyle == .dark, held: traits.wardHeld))
        })
    }

    /// A control's edge: the section's ink at WardRelief.edgeAlpha, at
    /// least 3:1 on the base, stronger under Increase Contrast.
    static var wardEdge: Color {
        let glide = WardLookStore.shared.glide
        if glide.settled { return WardRestColors.edge(glide.to.section) }
        return Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return Color.uiColor(glide.ink(dark: dark, held: traits.wardHeld),
                           alpha: WardRelief.edgeAlpha(dark: dark, highContrast: traits.accessibilityContrast == .high))
        })
    }

    static func uiColor(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        let (r, g, b) = WardPalette.rgb(hex)
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }

    /// One relief light at its strength.
    init(relief light: WardReliefLight) {
        let (r, g, b) = WardPalette.rgb(light.hex)
        self.init(red: r, green: g, blue: b, opacity: light.alpha)
    }
}

extension WardToken {
    var index: Int { WardRestColors.tokens.firstIndex(of: self) ?? 0 }
}

/// The colours at rest, made once: the dynamic ones every screen drew
/// before the shift existed, resolved by the trait alone.
enum WardRestColors {
    static let tokens: [WardToken] = [.background, .surface, .raised, .well, .primary, .primaryInk, .onPrimary,
                                      .ecg, .beam, .success, .warning, .danger, .ink, .inkSecondary, .hairline, .monitor]
    static let palette: [Color] = tokens.map { token in
        Color(uiColor: UIColor { traits in
            Color.uiColor(WardPalette.hex(token, dark: traits.userInterfaceStyle == .dark))
        })
    }
    /// The section's accents at rest: its fill (.primary) and its accent
    /// ink (.primaryInk), WardSection.fill and .accent.
    private static let accents: [WardSection: (fill: Color, ink: Color)] = Dictionary(uniqueKeysWithValues: WardSection.allCases.map { section in
        (section, (Color(uiColor: UIColor { traits in
            Color.uiColor(section.fill(dark: traits.userInterfaceStyle == .dark))
        }), Color(uiColor: UIColor { traits in
            Color.uiColor(section.accent(dark: traits.userInterfaceStyle == .dark))
        })))
    })
    static func color(_ token: WardToken, _ section: WardSection) -> Color {
        switch token {
        case .primary: return accents[section]?.fill ?? palette[token.index]
        case .primaryInk: return accents[section]?.ink ?? palette[token.index]
        default: return palette[token.index]
        }
    }
    private static let inks: [WardSection: Color] = Dictionary(uniqueKeysWithValues: WardSection.allCases.map { section in
        (section, Color(uiColor: UIColor { traits in
            Color.uiColor(section.ink(dark: traits.userInterfaceStyle == .dark))
        }))
    })
    private static let edges: [WardSection: Color] = Dictionary(uniqueKeysWithValues: WardSection.allCases.map { section in
        (section, Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            return Color.uiColor(section.ink(dark: dark),
                                 alpha: WardRelief.edgeAlpha(dark: dark, highContrast: traits.accessibilityContrast == .high))
        }))
    })
    static func ink(_ section: WardSection) -> Color { inks[section] ?? palette[WardToken.primaryInk.index] }
    static func edge(_ section: WardSection) -> Color { edges[section] ?? palette[WardToken.hairline.index] }
}

// MARK: - The one animated value

/// The look every Ward colour is drawn from (WardGlide): light or dark, and
/// which section is on show, and the shift between two looks. One value for
/// the whole app, so no frame can show two looks at once; views that read a
/// Ward colour or the glide are redrawn on each step of a shift, in one
/// update, with no animation transaction (so nothing cross-fades).
final class WardLookStore: Observable, @unchecked Sendable {
    static let shared = WardLookStore()

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var current = WardGlide.rest(WardLook(dark: false, section: .questions))
    /// The sections asked for, newest last: a study screen's on top of
    /// home's, so going back returns to home's hue.
    private var sections: [(id: UUID, section: WardSection)] = []

    var glide: WardGlide {
        registrar.access(self, keyPath: \.glide)
        return lock.withLock { current }
    }

    /// The look the app is at, or heading to.
    var target: WardLook { lock.withLock { current.to } }

    func set(_ glide: WardGlide) {
        let changed: Bool = lock.withLock { current != glide }
        guard changed else { return }
        registrar.withMutation(of: self, keyPath: \.glide) {
            lock.withLock { current = glide }
        }
    }

    // sections

    @MainActor func push(_ section: WardSection, id: UUID) {
        if let i = sections.firstIndex(where: { $0.id == id }) {
            sections[i].section = section
        } else {
            sections.append((id, section))
        }
        settleSection()
    }

    @MainActor func pop(id: UUID) {
        sections.removeAll { $0.id == id }
        settleSection()
    }

    @MainActor private func settleSection() {
        let section = sections.last?.section ?? .questions
        WardLookDriver.shared.go(WardLook(dark: target.dark, section: section))
    }
}

/// Runs the shift: light and dark arrive in one step, every Ward colour in
/// the same frame; a new section's hue is stepped by a display link each
/// frame for WardGlide.duration, then left at rest. Under Reduce Motion a
/// new look arrives at once.
@MainActor
final class WardLookDriver: NSObject {
    static let shared = WardLookDriver()

    var reduceMotion = false
    private var link: CADisplayLink?
    private var start: CFTimeInterval = 0
    private var startProgress = 0.0

    func go(_ look: WardLook) {
        let store = WardLookStore.shared
        let now = store.glide
        guard look != now.to else { return }
        if reduceMotion {
            stop()
            WardLookDriver.still { store.set(.rest(look)) }
            return
        }
        // light and dark in one step; a section's hue shifts (WardGlide.toward)
        let next = WardGlide.toward(look, from: now)
        WardLookDriver.still { store.set(next) }
        if next.settled {
            stop()
            return
        }
        startProgress = next.progress
        start = CACurrentMediaTime()
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        let store = WardLookStore.shared
        var glide = store.glide
        glide.progress = min(1, startProgress + (CACurrentMediaTime() - start) / WardGlide.duration)
        WardLookDriver.still {
            store.set(glide.progress >= 1 ? .rest(glide.to) : glide)
        }
        if glide.progress >= 1 { stop() }
    }

    /// A step of the shift is a new colour, never an animation of one: a
    /// change made inside someone's withAnimation (a dock tap) must not
    /// cross-fade the colours (the grey films of the first recording).
    static func still(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }
}

// MARK: - Held in one mode

/// A part drawn in one mode whatever the app's is (the vitals monitor,
/// bedtime's dark room): it keeps its colours while the app shifts. Bridged
/// to the trait collection so the colours' providers can see it.
struct WardHeldTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
}

extension UITraitCollection {
    var wardHeld: Bool { self[WardHeldTrait.self] }
}

extension UIMutableTraits {
    var wardHeld: Bool {
        get { self[WardHeldTrait.self] }
        set { self[WardHeldTrait.self] = newValue }
    }
}

struct WardHeldKey: EnvironmentKey, UITraitBridgedEnvironmentKey {
    static let defaultValue = false
    static func read(from traitCollection: UITraitCollection) -> Bool { traitCollection.wardHeld }
    static func write(to mutableTraits: inout any UIMutableTraits, value: Bool) { mutableTraits.wardHeld = value }
}

extension EnvironmentValues {
    var wardHeld: Bool {
        get { self[WardHeldKey.self] }
        set { self[WardHeldKey.self] = newValue }
    }
}

extension View {
    /// Drawn in `scheme` whatever the app's look, and kept out of the shift.
    func wardHeld(_ scheme: ColorScheme) -> some View {
        environment(\.colorScheme, scheme).environment(\.wardHeld, true)
    }
}

/// The type: system fonts only (SF Pro, SF Mono for observations), every one
/// a text style so Dynamic Type scales it.
enum WardType {
    static let display = Font.largeTitle.bold()
    static let title = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let caption = Font.caption
    /// Observations: BP 128/82
    static let obs = Font.system(.body, design: .monospaced)
    static let obsLarge = Font.system(.title2, design: .monospaced).weight(.semibold)
}

/// Gaps and padding, every one a step of WardScale (4, 8, 12, 16, 24, 32).
enum WardSpace {
    static let xs = CGFloat(WardScale.xs), s = CGFloat(WardScale.s), m = CGFloat(WardScale.m)
    /// the screen's side gutter, and a card's padding
    static let gutter = CGFloat(WardScale.l)
    static let l = CGFloat(WardScale.l), xl = CGFloat(WardScale.xl), xxl = CGFloat(WardScale.xxl)
    /// between the sections of a page
    static let section = CGFloat(WardScale.xl)
    /// extra room between the lines of a paragraph
    static let leading = CGFloat(WardScale.leading)
}

/// Corner radii, on the same scale.
enum WardRadius {
    static let card = CGFloat(WardScale.l)
    static let tile = CGFloat(WardScale.xl)
    static let button = CGFloat(WardScale.l)
    static let field = CGFloat(WardScale.m)
    static let icon = CGFloat(WardScale.m)
    static let bar = CGFloat(WardScale.xl)
}

/// The root of the shift: the window's light or dark (the system's, or
/// Always night sky's) is handed to WardLookDriver the moment it changes,
/// both from UIKit's trait change on the window (before SwiftUI redraws)
/// and from SwiftUI's own scheme, whichever comes first. The window and
/// every Ward colour change together, in one step (WardGlide.toward). Set
/// once at the root, outside the paper and the base.
struct WardLookRoot: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background { WardWindowWatch().frame(width: 0, height: 0).accessibilityHidden(true) }
            .onAppear {
                WardLookDriver.shared.reduceMotion = reduceMotion
                let store = WardLookStore.shared
                if store.glide.settled && store.target.dark != (scheme == .dark) {
                    store.set(.rest(WardLook(dark: scheme == .dark, section: store.target.section)))
                }
            }
            .onChange(of: reduceMotion) { _, now in WardLookDriver.shared.reduceMotion = now }
            .onChange(of: scheme) { _, now in
                let store = WardLookStore.shared
                WardLookDriver.shared.go(WardLook(dark: now == .dark, section: store.target.section))
            }
    }
}

/// Hears the window's light or dark change in UIKit, ahead of SwiftUI's
/// redraw, so every Ward colour takes the new style in the same frame.
private struct WardWindowWatch: UIViewRepresentable {
    func makeUIView(context: Context) -> WatchView { WatchView() }
    func updateUIView(_ view: WatchView, context: Context) {}

    final class WatchView: UIView {
        private var registration: (any UITraitChangeRegistration)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let registration, let old = oldWindow { old.unregisterForTraitChanges(registration) }
            registration = nil
            oldWindow = window
            guard let window else { return }
            registration = window.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (window: UIWindow, _: UITraitCollection) in
                let dark = window.traitCollection.userInterfaceStyle == .dark
                let store = WardLookStore.shared
                WardLookDriver.shared.go(WardLook(dark: dark, section: store.target.section))
                // the status bar's words take the new style in this frame
                // too, and again once every bar has taken its traits
                WatchView.settleStatusBar(in: window)
                DispatchQueue.main.async { WatchView.settleStatusBar(in: window) }
            }
            let dark = window.traitCollection.userInterfaceStyle == .dark
            let store = WardLookStore.shared
            if store.glide.settled && store.target.dark != dark {
                store.set(.rest(WardLook(dark: dark, section: store.target.section)))
            }
        }

        private weak var oldWindow: UIWindow?

        /// Asks every screen in the window for its status bar style with
        /// no animation, so the clock and icons switch with the page
        /// rather than fading across from the old style.
        static func settleStatusBar(in window: UIWindow) {
            UIView.performWithoutAnimation {
                var stack: [UIViewController] = window.rootViewController.map { [$0] } ?? []
                while let controller = stack.popLast() {
                    controller.setNeedsStatusBarAppearanceUpdate()
                    stack.append(contentsOf: controller.children)
                    if let shown = controller.presentedViewController { stack.append(shown) }
                }
            }
        }
    }
}

extension UINavigationController {
    /// A study screen's bar (a navigation bar on show) has UIKit fade the
    /// status bar's words for a third of a second when the app turns light,
    /// leaving white words on the light page; nothing in the app hides or
    /// shows the status bar, so its changes can all be immediate.
    open override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }

    /// The status bar's words for the bar's own light or dark, named
    /// outright. Left to the default style, the status bar worked the
    /// colour out itself and faded to it (r8: still 22 frames of white
    /// words on the light page); a named style changes when asked, with
    /// the page. The bar's traits, not the controller's, so a bar held
    /// dark over a light app (Bedtime review) keeps light words.
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        navigationBar.traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }
}

/// A screen's section: its hue tints the paper's grid and the controls'
/// edges while it is on show, and the hue shifts to the next screen's
/// with the same glide as light and dark.
private struct WardSectionMark: ViewModifier {
    let section: WardSection
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            // system controls (toggles, sliders, links, plain buttons) in
            // the section's accent, moving with its hue
            .tint(Color.wardPrimaryInk)
            .onAppear { WardLookStore.shared.push(section, id: id) }
            .onDisappear { WardLookStore.shared.pop(id: id) }
            .onChange(of: section) { _, now in WardLookStore.shared.push(now, id: id) }
    }
}

extension View {
    /// The app's root: light and dark shift as one (WardLookRoot).
    func wardLookRoot() -> some View { modifier(WardLookRoot()) }

    /// This screen's section (WardSection): its hue on the grid and edges.
    func wardSection(_ section: WardSection) -> some View { modifier(WardSectionMark(section: section)) }
}

/// A small-caps label ("TODAY'S WARD ROUND"): the source string stays in
/// mixed case so VoiceOver reads words, not letters. Its letters are spaced
/// at the standard sizes, where they are small; at the accessibility sizes
/// they are big enough to read apart, and a wrapped date with the spacing
/// ran past its frame (the AX5 audit's "Text clipped", 15 Oct).
struct WardSmallCaps: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(typeSize.isAccessibilitySize ? 0 : 0.8)
            .foregroundStyle(Color.wardInkSecondary)
    }
}

extension View {
    func wardSmallCaps() -> some View { modifier(WardSmallCaps()) }
}
#endif
