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
        // UI tests that check what taps do: a simulator draws the moving sky
        // on the CPU, and a main thread that busy loses taps
        if info.arguments.contains("-stillSky") { return .still }
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
    /// The Graphics setting in force (GraphicsQuality.swift): what every
    /// look may spend. Also published to the render thread (GraphQuality).
    private(set) var graphics: GraphicsBudget
    /// True while something opaque covers the whole backdrop (the 3D map):
    /// the backdrop's clocks, twinkle and tilt then stop, as nothing of
    /// them can be seen.
    private(set) var skyCovered: Bool = false

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var coverTokens: Set<String> = []

    private init() {
        level = SpaceQuality.current()
        graphics = GraphQuality.refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
            // the Graphics setting itself
            UserDefaults.didChangeNotification,
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
        let budget: GraphicsBudget = GraphQuality.refresh()
        let now: SpaceQuality = SpaceQuality.current()
        let graphicsChanged: Bool = budget != graphics
        if graphicsChanged { graphics = budget }
        guard now != level || graphicsChanged else { return }
        if now != level { level = now }
        PopOutMotion.shared.refresh()
    }

    /// Something opaque now covers the whole backdrop (`token` is the
    /// cover's own); `uncover` with the same token when it goes.
    func cover(_ token: String) {
        coverTokens.insert(token)
        if !skyCovered { skyCovered = true }
    }

    func uncover(_ token: String) {
        coverTokens.remove(token)
        let covered: Bool = !coverTokens.isEmpty
        if skyCovered != covered { skyCovered = covered }
    }
}

// MARK: - The Graphics setting, for everyone

/// The one place the 3D looks read the Graphics budget from: safe on any
/// thread (SceneKit's render loop reads it). SpaceQualityCenter keeps it up
/// to date; before that has run it works the budget out itself.
nonisolated enum GraphQuality {
    private static let box = GraphQualityBox()

    /// Where the Graphics choice is stored (SpaceSettings.graphicsKey).
    static let key: String = "vignette.space.graphics"

    /// The budget in force now.
    static var current: GraphicsBudget { box.read().0 }

    /// The frame rate the 3D looks ask for: the budget's cap, never more
    /// than the screen can show.
    static var frameRate: Int {
        let now: (GraphicsBudget, Int) = box.read()
        return now.0.frameRate(screen: now.1)
    }

    /// The owner's Graphics choice, as stored.
    static var choice: GraphicsChoice {
        let raw: String? = UserDefaults.standard.string(forKey: key)
        return GraphicsChoice.stored(raw)
    }

    /// Works the budget out afresh (the setting, the device, and the
    /// `-graphicsSmooth` / `-graphicsHigh` launch arguments), stores it for
    /// the render thread and returns it.
    @discardableResult
    static func refresh() -> GraphicsBudget {
        let info = ProcessInfo.processInfo
        var picked: GraphicsChoice = choice
        if info.arguments.contains("-graphicsSmooth") { picked = .smooth }
        if info.arguments.contains("-graphicsHigh") { picked = .high }
        let screen: Int = box.screenFPS()
        var device = GraphicsDeviceState(memory: info.physicalMemory)
        device.lowPower = info.isLowPowerModeEnabled
        device.thermal = info.thermalState.rawValue
        device.screenFPS = screen
        let tier: GraphicsTier = GraphicsResolver.resolve(picked, device: device)
        let budget: GraphicsBudget = GraphicsBudget.of(tier)
        box.write(budget, screen: nil)
        return budget
    }

    /// The screen's fastest rate, from the main actor.
    static func noteScreen(_ fps: Int) {
        box.write(nil, screen: max(fps, 30))
    }
}

/// GraphQuality's lock-guarded store.
nonisolated final class GraphQualityBox: @unchecked Sendable {
    private let lock = NSLock()
    private var budget: GraphicsBudget?
    private var screen: Int = 120

    func read() -> (GraphicsBudget, Int) {
        lock.lock()
        let stored: GraphicsBudget? = budget
        let fps: Int = screen
        lock.unlock()
        if let stored { return (stored, fps) }
        return (GraphQuality.refresh(), fps)
    }

    func screenFPS() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return screen
    }

    func write(_ value: GraphicsBudget?, screen fps: Int?) {
        lock.lock()
        if let value { budget = value }
        if let fps { screen = fps }
        lock.unlock()
    }
}

private struct GraphicsBudgetKey: EnvironmentKey {
    static let defaultValue: GraphicsBudget = .high
}

extension EnvironmentValues {
    /// What every look may spend (the Graphics setting); set once at the
    /// root (SkyRoot).
    var graphics: GraphicsBudget {
        get { self[GraphicsBudgetKey.self] }
        set { self[GraphicsBudgetKey.self] = newValue }
    }
}

extension View {
    /// Marks this view as covering the whole backdrop while it is on
    /// screen (the 3D map), so the backdrop stops drawing under it.
    func coversSky() -> some View {
        modifier(SkyCoverToken())
    }
}

private struct SkyCoverToken: ViewModifier {
    @State private var token = UUID().uuidString

    func body(content: Content) -> some View {
        content
            .onAppear { SpaceQualityCenter.shared.cover(token) }
            .onDisappear { SpaceQualityCenter.shared.uncover(token) }
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
    /// String (GraphicsChoice.rawValue), default "automatic": "Graphics" -
    /// Automatic, High quality or Smooth (GraphicsQuality.swift).
    static let graphicsKey: String = GraphQuality.key
    /// Double, default 1: "Link length" - how far apart linked bodies stand
    /// in the Ideas map, 0.6 (Shorter) to 1.8 (Longer) (GraphLinkLength,
    /// GraphicsQuality.swift). The map's Look menu sets the same value.
    static let linkLengthKey: String = GraphLinkLength.key
    /// Bool, default false (Curved): "Lines" - Curved or Straight links in
    /// both Ideas modes, the 3D map and the 2D board (GraphLineStyle,
    /// GraphLineStyle.swift). Both Look menus set the same value.
    static let straightLinesKey: String = GraphLineStyle.key

    static var alwaysNight: Bool {
        UserDefaults.standard.object(forKey: alwaysNightKey) as? Bool ?? false
    }

    static var sounds: Bool {
        UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? false
    }

    static var linkLength: Double {
        GraphLinkLength.stored(UserDefaults.standard.object(forKey: linkLengthKey) as? Double)
    }

    static var lineStyle: GraphLineStyle {
        GraphLineStyle.stored(UserDefaults.standard.object(forKey: straightLinesKey) as? Bool)
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
        let center = SpaceQualityCenter.shared
        let level: SpaceQuality = center.level
        let budget: GraphicsBudget = center.graphics
        let scheme: ColorScheme? = alwaysNight ? .dark : nil
        content
            .environment(\.spaceQuality, level)
            .environment(\.graphics, budget)
            .environment(\.skyZoom, zoom)
            .preferredColorScheme(scheme)
            .onAppear {
                // the cues' tones are made once, ahead of the first one
                if SpaceSettings.sounds { SpaceSounds.shared.prepare() }
                // the screen's top rate, for the 3D looks' frame rate
                GraphQuality.noteScreen(SkyRoot.screenFPS())
                center.recompute()
            }
    }

    /// The fastest the screen can show (120 on ProMotion, else 60).
    static func screenFPS() -> Int {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let fps: Int = scenes.first?.screen.maximumFramesPerSecond ?? 60
        return fps
    }
}
