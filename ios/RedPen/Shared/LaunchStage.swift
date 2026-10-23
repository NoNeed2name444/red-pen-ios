import SwiftUI
import Observation
import QuartzCore
import UIKit

/// Home's side of the opening's hand-off (LaunchSplash, LaunchOpening).
///
/// While an opening is going to play, home is laid out but none of it is
/// drawn except its ECG paper, the same ground the launch screen and the
/// splash stand on (home's own: the base with its section's wash and the
/// section's grid, WardGround; the launch screen's LaunchPaper is drawn
/// from the same numbers), with no opening cut in it yet: every part
/// waits at nothing, so when the splash's own ground gives way there is no
/// change to see. At the hand-off home's parts arrive in one wave up the
/// screen behind the ECG (LaunchEntrance, LaunchOpening.arrival): first the
/// page's opening with everything in it, as one piece, then the header's
/// lines as the ECG passes them, the title's letters settling in under the
/// stethoscope (LetterSettle), and the bar above. The splash's ECG lands as
/// the squiggle beside the title, which home's own takes over once home is
/// still. Nothing fades: every part moves and scales.
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
    /// From launch until the opening starts, behind the splash's opaque
    /// ground, home is drawn whole, so its first full frame (text laid out,
    /// images decoded, the paper drawn) is done before anyone can see it,
    /// not in the middle of the hand-off; each part notes where it stands.
    /// It goes back to its starting pose as the splash starts, the ECG's
    /// whole length before the hand-off.
    private(set) var warm = false

    /// From the splash starting the opening until home is still: the hand-off
    /// window, in which nothing may be rendered that could be made before it
    /// (WardLightImages draws live instead and makes its images afterwards).
    var handingOff: Bool { link != nil }

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
    /// Diagnostics for a recorded opening only (LaunchDiagnostics): the long
    /// gaps and what the main thread did in them, and the moments of home's
    /// loads. `playHost` is the hand-off's moment as play() was given it,
    /// which the marks are put on the opening's clock from.
    @ObservationIgnored private var diag = LaunchDiagnostics()
    @ObservationIgnored private var playHost: CFTimeInterval = 0
    @ObservationIgnored private var readoutWritten = false
    /// A recorded opening (`-uiPreviewSplash`) keeps the diagnostics.
    static let recording = ProcessInfo.processInfo.arguments.contains("-uiPreviewSplash")
    /// The recording's relief-off take (`-uiPreviewNoGlows`): every Ward
    /// face draws live, its lights at radius 0 as a 1-pt rim, the ink edge
    /// and every colour kept (WardSurfaces). Read once.
    static let noGlows = ProcessInfo.processInfo.arguments.contains("-uiPreviewNoGlows")
    /// Where the ECG's baseline starts (window points), which the wave of
    /// home's parts follows up: set by the splash as it starts.
    @ObservationIgnored var traceStart: CGPoint = .zero

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
        warm = waiting
        if waiting {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWait) { [weak self] in
                guard let self, self.link == nil, self.now == 0, !self.held else { return }
                self.warm = false
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
        playHost = handoffHost
        mark("handoff", at: handoffHost)
        let o = LaunchOpening(reduced: reduced)
        lastTime = o.handoff + (CACurrentMediaTime() - handoffHost)
        // home back at its starting pose, while the ground still covers it
        if warm {
            warm = false
            warmEnded = lastTime
        }
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
        if Self.recording, !readoutWritten {
            // the main thread's CPU seconds: across a long gap, a thread that
            // was working shows it, a thread that was waiting does not
            let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9
            let counted = lastStamp != nil && raw >= o.handoff
            diag.tick(end: link.targetTimestamp, gap: counted ? link.timestamp - (lastStamp ?? 0) : nil,
                      cpu: cpu, interval: link.targetTimestamp - link.timestamp)
        }
        lastStamp = link.timestamp
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
            // the hand-off is over: the soft lights asked for during it
            WardLightImages.shared.catchUp()
        } else {
            now = t
        }
    }

    /// Notes a moment for the recorded opening's diagnostics (a no-op in any
    /// other launch).
    func mark(_ name: String, at host: CFTimeInterval = CACurrentMediaTime(), once: Bool = false) {
        guard Self.recording, !readoutWritten else { return }
        if once { guard marked.insert(name).inserted else { return } }
        diag.moment(name, at: host)
    }
    @ObservationIgnored private var marked: Set<String> = []

    /// Runs one of home's loads, noting when it starts and ends for the
    /// recorded opening's diagnostics (a plain call in any other launch).
    func measure<T>(_ name: String, _ work: () -> T) -> T {
        guard Self.recording, !readoutWritten else { return work() }
        let start = CACurrentMediaTime()
        let result = work()
        diag.load(name, from: start, to: CACurrentMediaTime())
        return result
    }

    /// Whether a part of home should note where it stands now: while it is
    /// drawn whole (warming up, or at rest), not while it moves.
    var measuring: Bool { warm || !now.isFinite }

    /// The page's opening (window points): WardPaper's panel, its top under
    /// home's header (WardPaperTop).
    var opening: CGRect? {
        guard window.width > 0, let p = WardPaper.panel(width: Double(window.width), height: Double(window.height),
                                                        top: WardPaperTop.shared.y.map { Double($0) } ?? 0,
                                                        pad: WindowDisplay.roundsLikePad) else { return nil }
        return CGRect(x: p.x, y: p.y, width: p.width, height: p.height)
    }
    /// The window home fills (window points): set by the splash as it starts.
    @ObservationIgnored var window: CGSize = .zero

    /// The page's opening at this frame: its scale and how far below its
    /// place it is, or nil before it arrives; (1, 0) at rest.
    func openingPose() -> (scale: CGFloat, drop: CGFloat)? {
        LaunchOpening(reduced: reduced).paperPose(at: poseTime).map { (CGFloat($0.scale), CGFloat($0.drop)) }
    }

    /// A part of home standing at `frame` (window points, when known) at
    /// this frame: its scale about its own middle and how far it is moved.
    /// One in the page's opening moves with it; any other arrives as the
    /// wave reaches its middle.
    func pose(_ frame: CGRect?, inOpening: Bool) -> (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        let t = poseTime
        guard t.isFinite else { return (1, 0, 0) }
        let o = LaunchOpening(reduced: reduced)
        var start = o.openingArrives
        if !inOpening, let frame, let squiggle {
            start = o.arrival(y: Double(frame.midY), from: Double(traceStart.y), to: Double(squiggle.midY))
        }
        let e = o.entrance(from: start, at: t)
        guard inOpening, let frame, let c = opening else { return (CGFloat(e.scale), 0, CGFloat(e.drop)) }
        let d = LaunchOpening.withOpening(scale: e.scale, drop: e.drop,
                                          opening: (Double(c.midX), Double(c.midY)),
                                          own: (Double(frame.midX), Double(frame.midY)))
        return (CGFloat(e.scale), CGFloat(d.dx), CGFloat(d.dy))
    }

    /// How much of the owner's logo is uncovered from left to right at time
    /// `t`, on the same clock and over the same span as the typed title's
    /// letters (`markArrives - 0.02` over `letterStagger * (titleLetters - 1) / 2 + letterLength`).
    static func logoUncover(at t: Double, reduced: Bool) -> Double {
        guard t.isFinite else { return 1 }
        let o = LaunchOpening(reduced: reduced)
        if reduced { return t >= o.handoff ? 1 : 0 }
        let start: Double = o.markArrives - 0.02
        let span: Double = LaunchOpening.letterStagger * Double(LaunchOpening.titleLetters - 1) / 2
            + LaunchOpening.letterLength
        return LaunchOpening.easeInOut((t - start) / span)
    }

    /// For a recorded opening (`-uiPreviewSplash`), what the hand-off
    /// measured, in Caches/launch-handoff.txt, which the Launch recording
    /// workflow reads back after each take. Times are the opening's. The last
    /// field counts the relief faces on screen when home is still, each once,
    /// by how it was drawn, and the images made before the hand-off
    /// (`relief=cached:12,live:plan@0x0:1 made=15/42ms`, WardReliefCensus).
    private func writeReadout(_ o: LaunchOpening, still: Double) {
        readoutWritten = true
        guard Self.recording,
              let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        func s(_ x: Double) -> String { String(format: "%+.2f", x) }
        let line = "gap_ms=\(Int((longestGap * 1000).rounded())) at=\(s(longestGapAt))"
            + " refreshes=\(refreshes) handoff=\(s(o.handoff)) still=\(s(still))"
            + " warm_off=\(warmEnded.map(s) ?? "none")"
            + diag.fields(clock: { o.handoff + ($0 - playHost) }, from: o.handoff, to: still)
            + WardReliefCensus.shared.field() + "\n"
        try? line.write(to: dir.appendingPathComponent("launch-handoff.txt"), atomically: true, encoding: .utf8)
    }

    /// A held preview (`-uiPreviewSplashAt`): home posed at the opening's
    /// time `t` and kept there, for a photograph of that moment.
    func hold(at t: Double, reduced: Bool) {
        guard link == nil else { return }
        self.reduced = reduced
        held = true
        let o = LaunchOpening(reduced: reduced)
        warm = false
        now = t < o.handoff ? 0 : (t >= o.settled + LaunchOpening.runOn ? .infinity : t)
    }
    @ObservationIgnored private var held = false

    /// The splash has gone (taking its ECG with it).
    func land() {
        landed = true
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

/// A part of home that arrives at the hand-off: whole, nearly full size,
/// rising the last few points into place on a spring, when the wave up the
/// screen reaches it, or with the page's opening as one piece when it is
/// in it (`inOpening`). It notes where it stands while home is drawn whole.
struct LaunchEntrance: ViewModifier {
    let inOpening: Bool
    @State private var spot = LaunchSpot()

    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        let p = stage.pose(spot.frame, inOpening: inOpening)
        content
            .scaleEffect(p.scale)
            .offset(x: p.dx, y: p.dy)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                if LaunchStage.shared.measuring { spot.frame = f }
            }
    }
}

/// Where a part of home stands, noted while home is drawn whole. A plain
/// object, not view state: noting a frame must never redraw the list it
/// is in, or the rows re-size, move and are noted again, a loop that
/// crashed the design tour and stopped home's list from scrolling.
@MainActor final class LaunchSpot {
    var frame: CGRect?
}

/// The squiggle beside the title: the splash's ECG lands on it and stays as
/// it until the splash goes, when home's own takes over in the same frame.
struct LaunchLanding: ViewModifier {
    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        content.scaleEffect(stage.landed || stage.warm ? 1 : 0.0001)
    }
}

/// A horizontal clip that uncovers the owner's logo from left to right.
struct LaunchLogoUncover: Shape {
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let f: CGFloat = min(max(fraction, 0), 1)
        return Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * f, height: rect.height))
    }
}

/// The title's letters settling in (LetterSettle), or the owner's logo
/// uncovered from left to right over the same span, on the splash's clock.
struct LaunchLetters: ViewModifier {
    var logo = false

    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        if logo {
            content.clipShape(
                LaunchLogoUncover(fraction: CGFloat(LaunchStage.logoUncover(at: stage.poseTime,
                                                                            reduced: stage.reduced)))
            )
        } else {
            content.textRenderer(LetterSettle(time: stage.poseTime, reduced: stage.reduced))
        }
    }
}

extension View {
    /// Arrives at the opening's hand-off as the wave up the screen reaches
    /// it, or, `inOpening`, with the page's opening, as one piece with it.
    @MainActor
    func launchEntrance(inOpening: Bool = false) -> some View {
        modifier(LaunchEntrance(inOpening: inOpening))
    }

    /// Shown once the opening's ECG has landed here.
    @MainActor
    func launchLanding() -> some View { modifier(LaunchLanding()) }

    /// The app's name as home's title: its letters settle in at the opening's
    /// hand-off, or the owner's logo is uncovered from left to right over the
    /// same span (`logo: true`).
    @MainActor
    func launchLetters(logo: Bool = false) -> some View { modifier(LaunchLetters(logo: logo)) }

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
/// draws the same glyph slices at identity, over an invisible box.
///
/// The box is the most the letters ever cover (a letter at its overshoot,
/// and its rise below), drawn at every moment, at rest too, so the layer
/// SwiftUI draws the title into keeps one size. Drawn bare, the layer
/// followed the letters as they spread out (148, 192, 196, then 194 points
/// wide) and was made anew each time it grew: a 28 ms reallocation in the
/// middle of the hand-off (run 38721011808's display census).
struct LetterSettle: TextRenderer {
    /// The opening's time (LaunchOpening); infinity at rest.
    var time: Double
    var reduced: Bool

    /// Around the text's own bounds: a letter scaled up to its overshoot
    /// (LaunchOpening.easeOutBack, 1.07) about its middle, and dropped up to
    /// 6 points below its place.
    static var reach: EdgeInsets { EdgeInsets(top: 4, leading: 4, bottom: 10, trailing: 4) }
    /// Below 1/255 in any channel on any background: never seen.
    static let boxOpacity = 0.001

    var displayPadding: EdgeInsets { Self.reach }

    /// The box the letters stay within, for this layout.
    static func box(_ layout: Text.Layout) -> CGRect? {
        let bounds = layout.reduce(CGRect.null) { $0.union($1.typographicBounds.rect) }
        guard !bounds.isNull, !bounds.isEmpty else { return nil }
        return CGRect(x: bounds.minX - reach.leading, y: bounds.minY - reach.top,
                      width: bounds.width + reach.leading + reach.trailing,
                      height: bounds.height + reach.top + reach.bottom)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if let box = Self.box(layout) {
            context.fill(Path(box), with: .color(.black.opacity(Self.boxOpacity)))
        }
        let o = LaunchOpening(reduced: reduced)
        // Use the slice renderer during warm-up and at rest too. Drawing
        // whole lines there left slice drawing cold until the first letter
        // appeared mid-hand-off. At infinity letter() returns (1, 0), so the
        // same layout and drawing path also supplies the final home title.
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
