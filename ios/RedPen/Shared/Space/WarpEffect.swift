import SwiftUI

// MARK: - Warp, only for lift-off
//
// Starting a study session gets a short hyperspace streak - only there, so
// it still feels like something on the fiftieth session. Everyday
// navigation uses the system zoom (category tiles into their pages).
//
// `SpaceWarp.liftOff()` stamps a start time; every backdrop on screen draws
// the streaks from that clock inside its own TimelineView, so no animation
// transaction is started and nothing else on screen is animated by it (the
// lesson recorded at the top of AppBackdrop). The destination is
// interactive from the first frame: the streaks are a non-hit-testing layer
// behind the glass. At SpaceQuality .reduced or .still there is no warp at
// all - the push's own transition is the whole change.

@MainActor
@Observable
final class SpaceWarp {
    static let shared = SpaceWarp()

    /// How long the streak lasts.
    static let duration: TimeInterval = 0.42

    /// When the current warp started, or nil when none is showing.
    private(set) var startedAt: Date?
    @ObservationIgnored private var clearing: Task<Void, Never>?

    private init() {}

    /// A session is starting: streak (at .full), a light tap, a quiet cue.
    static func liftOff() {
        SpaceFeedback.play(.liftOff)
        guard SpaceQuality.current() == .full else { return }
        shared.begin()
    }

    private func begin() {
        startedAt = Date()
        clearing?.cancel()
        clearing = Task { @MainActor [weak self] in
            let wait: UInt64 = UInt64((SpaceWarp.duration + 0.15) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled else { return }
            self?.startedAt = nil
        }
    }
}

/// The streaks themselves, in a backdrop. Present only while a warp runs.
struct WarpStreaks: View {
    let night: Bool

    var body: some View {
        if let start = SpaceWarp.shared.startedAt {
            let night: Bool = self.night
            TimelineView(.animation) { timeline in
                let elapsed: Double = timeline.date.timeIntervalSince(start)
                let p: Double = min(1, max(0, elapsed / SpaceWarp.duration))
                Canvas { context, size in
                    WarpStreaks.draw(progress: p, night: night, in: &context, size: size)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    static func draw(progress p: Double, night: Bool, in context: inout GraphicsContext, size: CGSize) {
        guard p < 1 else { return }
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height * 0.45
        let scale: CGFloat = CGFloat(SkyChart.scale(height: Float(size.height)))
        let reachMax: CGFloat = max(size.width, size.height) * 0.6
        // length grows with an ease-in; the light falls away as it does
        let grow: CGFloat = CGFloat(p * p)
        let fade: Double = 1 - p
        let ink: Color = night ? Color.white : Color(red: 0.30, green: 0.32, blue: 0.62)
        var lines = context
        lines.blendMode = night ? .plusLighter : .normal
        let layers: [[FlatStar]] = [FlatSky.mid, FlatSky.near]
        for (index, layer) in layers.enumerated() {
            let width: CGFloat = index == 0 ? 0.8 : 1.4
            for star in layer {
                let x: CGFloat = cx + CGFloat(star.at.x) * scale
                let y: CGFloat = cy + CGFloat(star.at.y) * scale
                guard x > 0 && y > 0 && x < size.width && y < size.height else { continue }
                let dx: CGFloat = x - cx
                let dy: CGFloat = y - cy
                let distance: CGFloat = max(1, (dx * dx + dy * dy).squareRoot())
                let length: CGFloat = grow * 150 * (distance / reachMax)
                let ux: CGFloat = dx / distance
                let uy: CGFloat = dy / distance
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + ux * length, y: y + uy * length))
                let alpha: Double = star.alpha * fade * 0.9
                let style = StrokeStyle(lineWidth: width, lineCap: .round)
                lines.stroke(path, with: .color(ink.opacity(alpha)), style: style)
            }
        }
        // a faint flash at the vanishing point
        let flash: Double = 0.16 * fade
        let r: CGFloat = max(size.width, size.height) * 0.5
        let colours: [Color] = [ink.opacity(flash), ink.opacity(0)]
        let centre = CGPoint(x: cx, y: cy)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: colours), center: centre, startRadius: 0, endRadius: r)
        let rect = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
        lines.fill(Path(ellipseIn: rect), with: shading)
    }
}

/// Once on a study screen: a session is starting. Fires on the first
/// appearance only - coming back from a pushed results page is not a new
/// lift-off.
struct LiftOffOnAppear: ViewModifier {
    @State private var lifted = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !lifted else { return }
            lifted = true
            SpaceWarp.liftOff()
        }
    }
}

extension View {
    /// Plays the lift-off (warp, haptic, cue) the first time this appears.
    func liftOffOnAppear() -> some View {
        modifier(LiftOffOnAppear())
    }

    /// The category tile side of the zoom: marks this tile as where `id`'s
    /// page zooms out of. Nothing at SpaceQuality .still.
    func skyZoomSource(_ id: String) -> some View {
        modifier(SkyZoomSource(id: id))
    }

    /// The page side of the zoom: the page zooms out of the tile marked
    /// with `id`.
    func skyZoomDestination(_ id: String) -> some View {
        modifier(SkyZoomDestination(id: id))
    }
}

private struct SkyZoomSource: ViewModifier {
    let id: String
    @Environment(\.skyZoom) private var zoom
    @Environment(\.spaceQuality) private var quality

    @ViewBuilder
    func body(content: Content) -> some View {
        if let zoom, quality != .still {
            content.matchedTransitionSource(id: id, in: zoom)
        } else {
            content
        }
    }
}

private struct SkyZoomDestination: ViewModifier {
    let id: String
    @Environment(\.skyZoom) private var zoom
    @Environment(\.spaceQuality) private var quality

    @ViewBuilder
    func body(content: Content) -> some View {
        if let zoom, quality != .still {
            content.navigationTransition(.zoom(sourceID: id, in: zoom))
        } else {
            content
        }
    }
}
