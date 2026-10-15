import SwiftUI
import Observation
import QuartzCore

/// Home's side of the opening's hand-off (LaunchSplash, LaunchOpening).
///
/// While an opening is going to play, home is laid out but none of it is
/// drawn except its base: every part waits at nothing, so when the splash's
/// own ground gives way there is no change to see. At the hand-off, home's
/// parts grow into place in turn (LaunchEntrance), the title's letters
/// settle in (LetterSettle), the ECG paper is drawn outward from the trace
/// (gridReach), and the splash's ECG lands as the squiggle beside the
/// title, which home's own takes over once home is still. Nothing fades:
/// every part moves and scales.
///
/// Every part is posed from one clock, the splash's: the hand-off's moment
/// on the host clock the Core Animation half runs on, read each display
/// refresh for the moment that frame is shown, so a late frame of home
/// stays in step with the ECG and the stethoscope (a main thread held up
/// for longer carries on from where it was: LaunchOpening.carryOn).
/// (SwiftUI's own animations are not used: a List row does not
/// always play them, and their delays start from when the main thread gets
/// round to it. Nor is TimelineView: around a List's sections it would make
/// them one row.)
///
/// Home tells the splash where the title and its squiggle are, so the
/// stethoscope and the ECG can travel there.
@MainActor
@Observable
final class LaunchStage {
    static let shared = LaunchStage()

    /// The opening's time (LaunchOpening's seconds) for the frame being
    /// drawn: 0 while home waits for the hand-off, infinity once home is at
    /// rest. Every part of home is posed from it.
    private(set) var now: Double
    /// The splash has gone: home draws the squiggle the ECG became.
    private(set) var landed: Bool
    /// During the ECG, behind the splash's opaque ground, home is drawn
    /// whole once, so its first full frame (text laid out, images decoded,
    /// the paper drawn) is done before anyone can see it, not in the middle
    /// of the hand-off. It goes back to its starting pose `warmLead`
    /// before the hand-off, still well behind the ground.
    private(set) var warm = false
    static let warmLead = 0.35

    /// The time home is posed at: whole while it warms up.
    var poseTime: Double { warm ? .infinity : now }

    @ObservationIgnored private(set) var reduced = false
    /// The hand-off's moment on the host clock (CACurrentMediaTime).
    @ObservationIgnored private var handoffHost: CFTimeInterval = 0
    @ObservationIgnored private var link: CADisplayLink?
    /// Home's clock at the last display refresh.
    @ObservationIgnored private var lastTime: Double?
    /// The hand-off's smoothness, measured: the longest wait between two
    /// display refreshes reaching the main thread from the hand-off until
    /// home is still (a held-up main thread), and when it ended.
    @ObservationIgnored private var lastStamp: CFTimeInterval?
    @ObservationIgnored private var longestGap: Double = 0
    @ObservationIgnored private var longestGapAt: Double = 0
    @ObservationIgnored private var refreshes = 0
    @ObservationIgnored private var warmEnded: Double?
    /// Where the paper is drawn out from, and the window it fills (window
    /// points): set by the splash as it starts.
    @ObservationIgnored var gridOrigin: CGPoint = .zero
    @ObservationIgnored var window: CGSize = .zero

    /// Where home's title and the squiggle beside it are (window points),
    /// while they are on screen.
    @ObservationIgnored var title: CGRect?
    @ObservationIgnored var squiggle: CGRect?

    /// The longest home waits for an opening before it shows itself anyway.
    static let longestWait: Double = 6

    init() {
        let waiting = LaunchSplash.wanted
        now = waiting ? 0 : .infinity
        landed = !waiting
        if waiting {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWait) { [weak self] in
                guard let self, self.link == nil, self.now == 0 else { return }
                self.now = .infinity
                self.landed = true
            }
        }
    }

    /// The splash has started: the hand-off is at `handoffHost` on the host
    /// clock.
    func play(reduced: Bool, handoffHost: CFTimeInterval) {
        guard now == 0, link == nil else { return }
        self.reduced = reduced
        self.handoffHost = handoffHost
        let o = LaunchOpening(reduced: reduced)
        lastTime = o.handoff + (CACurrentMediaTime() - handoffHost)
        // warm up only with room to: home must be back at its starting pose
        // well before the ground gives way
        warm = !reduced && handoffHost - CACurrentMediaTime() > Self.warmLead + 0.1
        let ticker = LaunchTicker { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: ticker, selector: #selector(LaunchTicker.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func tick(_ link: CADisplayLink) {
        let o = LaunchOpening(reduced: reduced)
        let raw = o.handoff + (link.targetTimestamp - handoffHost)
        if let last = lastStamp, raw >= o.handoff {
            let gap = link.timestamp - last
            if gap > longestGap { longestGap = gap; longestGapAt = raw }
            refreshes += 1
        }
        lastStamp = link.timestamp
        if warm && raw >= o.handoff - Self.warmLead {
            warm = false
            warmEnded = raw
        }
        let t = lastTime.map { o.carryOn(from: $0, to: raw, frame: link.targetTimestamp - link.timestamp) } ?? raw
        if t != raw { handoffHost = link.targetTimestamp - (t - o.handoff) }
        lastTime = t
        // before the hand-off home is wholly at nothing: nothing to redraw
        guard t >= o.handoff else { return }
        if t >= o.settled + LaunchOpening.runOn {
            now = .infinity
            link.invalidate()
            self.link = nil
            writeReadout(o, still: raw)
        } else {
            now = t
        }
    }

    /// For a recorded opening (`-uiPreviewSplash`), what the hand-off
    /// measured, in Caches/launch-handoff.txt, which the Launch recording
    /// workflow reads back after each take. Times are the opening's.
    private func writeReadout(_ o: LaunchOpening, still: Double) {
        guard ProcessInfo.processInfo.arguments.contains("-uiPreviewSplash"),
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        func s(_ x: Double) -> String { String(format: "%+.2f", x) }
        let line = "gap_ms=\(Int((longestGap * 1000).rounded())) at=\(s(longestGapAt))"
            + " refreshes=\(refreshes) handoff=\(s(o.handoff)) still=\(s(still))"
            + " warm_off=\(warmEnded.map(s) ?? "none")\n"
        try? line.write(to: dir.appendingPathComponent("launch-handoff.txt"), atomically: true, encoding: .utf8)
    }

    /// The splash has gone (taking its ECG with it).
    func land() {
        landed = true
    }

    /// How far the ECG paper is drawn out: nil once whole, else the reach of
    /// its lines, in window points, across (x) and down (y).
    func gridReach() -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>)? {
        let f = CGFloat(LaunchOpening(reduced: reduced).gridReach(at: poseTime))
        if f >= 1 { return nil }
        let p = gridOrigin
        let dx = max(p.x, window.width - p.x) + 2, dy = max(p.y, window.height - p.y) + 2
        return ((p.x - f * dx)...(p.x + f * dx), (p.y - f * dy)...(p.y + f * dy))
    }
}

/// The display link's target: CADisplayLink needs an NSObject, and holds it
/// strongly, so it calls back weakly.
@MainActor
private final class LaunchTicker: NSObject {
    let action: @MainActor (CADisplayLink) -> Void
    init(_ action: @escaping @MainActor (CADisplayLink) -> Void) { self.action = action }
    @objc func tick(_ link: CADisplayLink) { action(link) }
}

/// A part of home that enters at the hand-off, `order`-th in turn: it grows
/// from nothing and rises the last few points into place on a spring.
struct LaunchEntrance: ViewModifier {
    let order: Int

    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        let e = LaunchOpening(reduced: stage.reduced).entrance(order, at: stage.poseTime)
        content
            .scaleEffect(CGFloat(e.scale))
            .offset(y: CGFloat(e.drop))
    }
}

/// The squiggle beside the title: the splash's ECG lands on it and stays as
/// it until the splash goes, when home's own takes over in the same frame.
struct LaunchLanding: ViewModifier {
    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        content.scaleEffect(stage.landed || stage.warm ? 1 : 0.0001)
    }
}

/// The title's letters settling in (LetterSettle), on the splash's clock.
struct LaunchLetters: ViewModifier {
    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        content.textRenderer(LetterSettle(time: stage.poseTime, reduced: stage.reduced))
    }
}

extension View {
    /// Enters at the opening's hand-off, `order`-th in turn (0 first).
    @MainActor
    func launchEntrance(_ order: Int) -> some View {
        modifier(LaunchEntrance(order: min(order, LaunchOpening.lastOrder)))
    }

    /// Shown once the opening's ECG has landed here.
    @MainActor
    func launchLanding() -> some View { modifier(LaunchLanding()) }

    /// The app's name as home's title: its letters settle in at the opening's
    /// hand-off.
    @MainActor
    func launchLetters() -> some View { modifier(LaunchLetters()) }

    /// Tells the opening where this is on screen (the title, or its squiggle).
    @MainActor
    func launchTarget(_ target: LaunchTarget) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            switch target {
            case .title: LaunchStage.shared.title = frame
            case .squiggle: LaunchStage.shared.squiggle = frame
            }
        }
    }
}

enum LaunchTarget { case title, squiggle }

/// The title's letters, settling in one after another at the hand-off: each
/// grows from nothing and rises the last few points into place. At rest it
/// draws the text exactly as SwiftUI would.
struct LetterSettle: TextRenderer {
    /// The opening's time (LaunchOpening); infinity at rest.
    var time: Double
    var reduced: Bool

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let o = LaunchOpening(reduced: reduced)
        if time >= o.settled {
            for line in layout { context.draw(line) }
            return
        }
        let n = layout.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        var i = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let l = o.letter(i, of: n, at: time)
                    i += 1
                    guard l.scale > 0.001 else { continue }
                    let b = slice.typographicBounds.rect
                    var c = context
                    c.translateBy(x: b.midX, y: b.midY + CGFloat(l.drop))
                    c.scaleBy(x: CGFloat(l.scale), y: CGFloat(l.scale))
                    c.translateBy(x: -b.midX, y: -b.midY)
                    c.draw(slice)
                }
            }
        }
    }
}
