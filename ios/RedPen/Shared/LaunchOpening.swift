import Foundation

/// The launch mark: the owner's stethoscope (14 Oct), the white tube by day
/// and the grey tube by night, cut from their flat grounds by
/// tools/make_launch_logo.py, so the system launch screen and the animated
/// opening (LaunchSplash) draw the same picture on the home screen's base.
/// The art is private: it is not in this repository, and is added to the
/// built app as loose PNGs (LaunchLogo@2x.png, LaunchLogo-dark@2x.png, ...)
/// when the app is downloaded. A build without it draws no mark, only the
/// ground.
enum LaunchArt {
    static let imageName = "LaunchLogo"
    /// The night picture, looked up first by night; the day one otherwise.
    static let darkImageName = "LaunchLogo-dark"

    /// The image's side in points (both modes): the system launch screen
    /// draws it at this size, centred in the safe area.
    static let side: Double = 200

    /// The chest piece's disc in each mode's image, as fractions of the
    /// image's side (x from the left, y from the top, r its radius), measured
    /// by make_launch_logo.py on the cut art: the heartbeat is centred here
    /// and the home screen opens out from here. The two drawings differ a
    /// little, so each has its own.
    static func chest(dark: Bool) -> (x: Double, y: Double, r: Double) {
        dark ? (0.7728, 0.2924, 0.1098) : (0.7770, 0.3022, 0.1123)
    }

    /// The ECG's colour (0xRRGGBB). By night the grey tube's lit side, which
    /// reads on the dark base (about 5.8:1); by day a dark slate, since the
    /// white tube's own colour is too faint as a thin line on the pale base
    /// (about 1.2:1).
    static func trace(dark: Bool) -> UInt32 {
        dark ? 0xA9A8A8 : 0x43566F
    }
}

/// The launch heartbeat (Assets.xcassets/Heartbeat.dataset/heartbeat.caf,
/// made by tools/make_heartbeat.py): where its two sounds start in the file,
/// as that tool measures them. The launchopening suite measures the file the
/// same way and checks these.
enum HeartbeatSound {
    static let asset = "Heartbeat"
    /// S1, the "lub", starts here (seconds into the file).
    static let s1: Double = 0.0304
    /// S2, the "dub": 0.36 s after S1, the master ECG's S1 to S2
    /// (Brand/EcgTrace.swift).
    static let s2: Double = 0.3909
    static let length: Double = 0.56
}

/// The opening's timing, in seconds from the moment the home screen's first
/// real frame is on screen. Nothing here changes opacity: the chest piece
/// beats in scale; with the sound, one ECG complex is drawn under the mark
/// as a stroke trimming in (its R peak on the lub, its T wave ending on the
/// dub); then the hand-off: the splash's ground gives way to home's own (the
/// same ECG paper, so nothing changes), the ECG travels up and shrinks into
/// the squiggle beside the "Stethoscore" title, the stethoscope glides up
/// and shrinks away into the title as its letters settle in, and home's
/// parts spring into place in one wave that follows the ECG up the screen,
/// each whole as it arrives (the page's opening with everything in it at
/// once).
///
/// Foundation only, so the curves are tested on Linux (LaunchOpeningTests);
/// LaunchSplash samples them into Core Animation keyframes, so what plays is
/// exactly what is tested, and it plays in the render server, off the main
/// thread.
struct LaunchOpening: Sendable {
    /// Reduce Motion: no beat and no ECG, only a quick opening (the sound may
    /// still play).
    var reduced: Bool = false

    init(reduced: Bool = false) {
        self.reduced = reduced
    }

    /// The ECG always draws, sound or no sound (muted, the app's sound off,
    /// other audio playing), at the times the sound would be heard: its parts
    /// line up with the heartbeat whether or not the heartbeat is heard.
    var ecg: Bool { !reduced }

    // MARK: when

    /// The R peak, which is when S1 is heard.
    var r: Double {
        if reduced { return HeartbeatSound.s1 }
        // 0.30 s, not 0.33 s: the dub is 0.06 s later than it was, and the
        // opening stays within 1.7 s.
        return 0.30
    }
    /// When S2 is heard (the T wave ends here).
    var s2: Double { r + HeartbeatSound.s2 - HeartbeatSound.s1 }
    /// When the sound file starts, so that S1 is heard on the R peak (the
    /// output latency is allowed for by LaunchSplash, which starts the
    /// drawing that much later when the sound is really started).
    var audioAt: Double { r - HeartbeatSound.s1 }

    // lub and dub: (start relative to S1 / S2, length, rise)
    static let lub = (lead: -0.02, length: 0.17, rise: 0.06)
    static let dub = (lead: -0.02, length: 0.12, rise: 0.04)

    /// The ECG: the flat baseline grows out from its centre over the first
    /// 0.1 s, then the trace is drawn left to right at a steady speed (one
    /// second of trace a second), and the tail runs on 0.1 s past the T wave.
    static let baselineGrow = 0.10
    static let tail = 0.10

    var traceEnd: Double { s2 + Self.tail }

    // MARK: the hand-off

    /// When the hand-off starts: the trace has been drawn whole. Under Reduce
    /// Motion, once the mark has shrunk away where it stands.
    var handoff: Double { reduced ? Self.reducedShrink : traceEnd }
    static let reducedShrink = 0.18
    /// The ECG's journey into the title's squiggle, and the stethoscope's
    /// into the title.
    static let travel = 0.45
    static let markTravel = 0.40
    /// Home's parts arrive in one wave that follows the ECG up the screen:
    /// what is at or below where the ECG starts (the page's opening, with
    /// the round card and everything else in it, the dock, New set) this
    /// long into the hand-off, each part between there and the title as the
    /// ECG's middle passes it, and what is above the title (the date, the
    /// search field and the account button) after the ECG has landed, as if
    /// the ECG had gone on up at its top speed, at most `topLead` after.
    static let entranceLead = 0.06
    static let topLead = 0.10
    /// Each part arrives whole and nearly full size, at `contentScale`, a
    /// few points (`rise`) below its place, and springs the rest of the
    /// way: never a small copy of itself, never an empty frame.
    static let contentScale = 0.94
    static let rise = 10.0
    static let spring = (response: 0.36, damping: 0.76)
    /// The stethoscope perches on the title at about its letters' height,
    /// over the middle of the name, then shrinks into it while the letters
    /// spread out from under it, the middle first.
    static let perch = 0.17
    static let markShrink = 0.12
    static let titleLetters = 11
    static let letterStagger = 0.025
    static let letterLength = 0.24

    /// When the ECG lands as the squiggle.
    var landed: Double { handoff + (reduced ? 0 : Self.travel) }
    /// When the stethoscope reaches the title, and when it has gone into it.
    var markArrives: Double { handoff + (reduced ? 0 : Self.markTravel) }
    var markGone: Double { reduced ? handoff : markArrives + Self.markShrink }
    /// The splash's own animation: until the ECG has landed and the
    /// stethoscope has gone into the title.
    var duration: Double { max(landed, markGone) }
    /// When the page's opening arrives, with everything in it: first.
    var openingArrives: Double { reduced ? handoff : handoff + Self.entranceLead }
    /// When a part of home whose middle is `y` down the window arrives, for
    /// an ECG that starts with its baseline at `from` and lands on the
    /// squiggle, whose middle is at `to` (window points, `to` above `from`).
    func arrival(y: Double, from y0: Double, to y1: Double) -> Double {
        let first = openingArrives
        guard !reduced, y.isFinite, y0 - y1 > 1 else { return first }
        if y >= y0 { return first }
        if y > y1 {
            // the moment the ECG's middle is level with it
            let u = Self.easeInOutInverse((y0 - y) / (y0 - y1))
            return max(first, handoff + Self.travel * u)
        }
        // smoothstep's top speed is one and a half times its mean
        let top = 1.5 * (y0 - y1) / Self.travel
        return landed + min(Self.topLead, (y1 - y) / top)
    }
    /// A part of home arriving at `start`, at time `t`: its scale and how
    /// far below its place it is, in points. Before it arrives it is not
    /// drawn (scale 0.0001); it arrives whole at `contentScale` and springs
    /// into place. Infinity is at rest. Under Reduce Motion it is simply
    /// there from the hand-off.
    func entrance(from start: Double, at t: Double) -> (scale: Double, drop: Double) {
        guard t.isFinite else { return (1, 0) }
        if reduced { return t >= handoff ? (1, 0) : (0.0001, Self.rise) }
        let since = t - start
        guard since > 0 else { return (0.0001, Self.rise) }
        let s = Self.spring(since)
        return (Self.contentScale + (1 - Self.contentScale) * s, Self.rise * (1 - s))
    }
    /// The paper's cut uses the content's pose. Infinity is also the warm-up
    /// frame: the actual mask is drawn at rest before the reveal starts.
    /// Before arrival, no hole is cut and the paper still covers the screen.
    func paperPose(at t: Double) -> (scale: Double, drop: Double)? {
        let e = entrance(from: openingArrives, at: t)
        return e.scale < 0.5 ? nil : e
    }

    /// A part inside the page's opening moves as one piece with it: scaled
    /// about the opening's middle `c`, not its own `r`. Drawn scaled about
    /// its own middle, that is this much further across and down (points).
    static func withOpening(scale: Double, drop: Double, opening c: (x: Double, y: Double),
                            own r: (x: Double, y: Double)) -> (dx: Double, dy: Double) {
        ((1 - scale) * (c.x - r.x), (1 - scale) * (c.y - r.y) + drop)
    }
    /// The longest home's clock may leap between two frames. When the main
    /// thread is held up longer than this (a first launch's work, say), home
    /// carries on from where it was rather than jumping its parts ahead; the
    /// splash's ECG simply waits on the squiggle a little longer.
    static let longestLeap = 0.1
    /// Home's clock for a frame due at `raw` (the splash's time), the last
    /// frame having been at `last`, a frame lasting `frame` seconds.
    func carryOn(from last: Double, to raw: Double, frame: Double) -> Double {
        guard raw > handoff, raw - last > Self.longestLeap else { return raw }
        return min(raw, max(handoff, last) + frame)
    }
    /// How long home keeps moving after `settled`, so the springs' last
    /// fraction of a point is played out rather than cut.
    static let runOn = 0.30
    /// When the last of home is still (its spring within a point of rest).
    var settled: Double {
        if reduced { return handoff }
        let last = landed + Self.topLead + Self.settleTime
        let letters = markArrives - 0.02 + Self.letterStagger * Double(Self.titleLetters - 1) / 2
            + Self.letterLength
        return max(last, letters, landed, markGone)
    }

        // MARK: easing

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeIn(_ x: Double) -> Double { let u = clamp(x); return u * u }
    static func easeOut(_ x: Double) -> Double { let u = 1 - clamp(x); return 1 - u * u * u }
    static func easeInOut(_ x: Double) -> Double { let u = clamp(x); return u * u * (3 - 2 * u) }
    /// Where easeInOut reaches `y`.
    static func easeInOutInverse(_ y: Double) -> Double {
        0.5 - sin(asin(1 - 2 * clamp(y)) / 3)
    }
    /// A slight overshoot and back, for a letter settling.
    static func easeOutBack(_ x: Double) -> Double {
        let u = clamp(x) - 1, c = 1.4
        return 1 + (c + 1) * u * u * u + c * u * u
    }

    /// SwiftUI's spring(response:dampingFraction:) from 0 to 1, `t` seconds
    /// in: what home's parts follow, sampled for the parts UIKit draws.
    static func spring(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / spring.response
        let zeta = spring.damping
        let wd = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * t) * (cos(wd * t) + zeta * omega / wd * sin(wd * t))
    }
    /// How long the spring takes to come within 1% of rest and stay there.
    static var settleTime: Double {
        var t = 2.0
        while t > 0, abs(1 - spring(t)) < 0.01 { t -= 0.005 }
        return t + 0.005
    }
    /// A smooth bump: 0 at both ends, 1 in the middle, flat at the ends so
    /// the beat starts and ends without a jolt.
    static func bump(_ x: Double) -> Double {
        guard x > 0, x < 1 else { return 0 }
        let s = sin(Double.pi * x)
        return s * s
    }
    static func gauss(_ t: Double, _ centre: Double, _ width: Double) -> Double {
        let z = (t - centre) / width
        return exp(-0.5 * z * z)
    }

    // MARK: the curves

    /// The chest piece's scale: 1, a lub to 1.06 with S1, back, a dub to
    /// 1.04 with S2, back.
    func beat(at t: Double) -> Double {
        if reduced { return 1 }
        let a = Self.lub, b = Self.dub
        return 1 + a.rise * Self.bump((t - r - a.lead) / a.length)
                 + b.rise * Self.bump((t - s2 - b.lead) / b.length)
    }

    /// The ECG's height at trace time `t` (seconds of trace from its left
    /// end), in R-peak heights, up positive: P, Q, R on S1, S, then T ending
    /// on S2 (its last 2% reaching the baseline there).
    func ecgHeight(at t: Double) -> Double {
        let T = (width: 0.032, rise: 0.26)
        let tEnd = s2 - 2.8 * T.width
        return 0.12 * Self.gauss(t, r - 0.15, 0.022)
             - 0.10 * Self.gauss(t, r - 0.022, 0.007)
             + 1.00 * Self.gauss(t, r, 0.008)
             - 0.22 * Self.gauss(t, r + 0.022, 0.008)
             + T.rise * Self.gauss(t, tEnd, T.width)
    }

    /// The trace as points, `width` x `height` points, y down (as drawn),
    /// sampled every millisecond of trace, with each point's distance along
    /// the line: the stroke's trim is a fraction of that length.
    func trace(width: Double, height: Double) -> (points: [(x: Double, y: Double)], lengths: [Double]) {
        let n = Int((traceEnd * 1000).rounded())
        var points: [(x: Double, y: Double)] = []
        var lengths: [Double] = []
        points.reserveCapacity(n + 1)
        var run = 0.0
        for i in 0...n {
            let t = traceEnd * Double(i) / Double(n)
            let p = (x: width * t / traceEnd, y: -height * ecgHeight(at: t))
            if let last = points.last {
                run += ((p.x - last.x) * (p.x - last.x) + (p.y - last.y) * (p.y - last.y)).squareRoot()
            }
            points.append(p)
            lengths.append(run)
        }
        return (points, lengths)
    }

    /// The fraction of the trace's length up to trace time `t`.
    static func fraction(_ t: Double, of trace: (points: [(x: Double, y: Double)], lengths: [Double]),
                         end: Double) -> Double {
        guard let total = trace.lengths.last, total > 0 else { return 0 }
        let i = Double(trace.lengths.count - 1) * clamp(t / end)
        let lo = Int(i.rounded(.down)), hi = min(lo + 1, trace.lengths.count - 1)
        let l = trace.lengths[lo] + (trace.lengths[hi] - trace.lengths[lo]) * (i - Double(lo))
        return l / total
    }

    /// The stretch of trace drawn at time `t`, in trace time (from, to), or
    /// nil when none is: the baseline growing out from its centre, then the
    /// head sweeping right, until the whole trace is drawn.
    func ecgDrawn(at t: Double) -> (from: Double, to: Double)? {
        guard ecg, t > 0 else { return nil }
        let grow = Self.baselineGrow
        let mid = grow / 2
        var from: Double, to: Double
        if t < grow {
            from = mid - t / 2
            to = mid + t / 2
        } else {
            from = 0
            to = min(t, traceEnd)
        }
        guard from < to else { return nil }
        return (from, to)
    }

    /// The ECG's journey into the squiggle, 0 to 1.
    func travel(at t: Double) -> Double {
        reduced ? 0 : Self.easeInOut((t - handoff) / Self.travel)
    }

    /// The stethoscope's glide into the title, 0 to 1 (Reduce Motion: it
    /// shrinks where it stands, before the hand-off).
    func markTravel(at t: Double) -> Double {
        if reduced { return Self.easeIn(t / Self.reducedShrink) }
        return Self.easeInOut((t - handoff) / Self.markTravel)
    }

    /// The whole mark's scale about the chest piece: 1 until the hand-off,
    /// shrinking to `perch` as it glides onto the title, then into it as the
    /// letters come out from under it.
    func markScale(at t: Double) -> Double {
        if reduced { return max(0.0001, 1 - markTravel(at: t)) }
        if t <= markArrives { return 1 - (1 - Self.perch) * markTravel(at: t) }
        return max(0.0001, Self.perch * (1 - Self.easeIn((t - markArrives) / Self.markShrink)))
    }

    /// Letter `i` of the title's `n`: its scale (0 to 1, a touch over on the
    /// way) and how far below its place it is. They grow from the middle
    /// out, the middle ones under the perched stethoscope as it shrinks.
    func letter(_ i: Int, of n: Int = LaunchOpening.titleLetters, at t: Double) -> (scale: Double, drop: Double) {
        guard t.isFinite else { return (1, 0) }
        if reduced { return t >= handoff ? (1, 0) : (0, 0) }
        let fromMiddle = abs(Double(i) - Double(n - 1) / 2)
        let start = markArrives - 0.02 + Self.letterStagger * fromMiddle
        let p = Self.clamp((t - start) / Self.letterLength)
        return (Self.easeOutBack(p), (1 - Self.easeOut(p)) * 6)
    }

    // MARK: the storyboard's moments

    /// The opening's named moments, in order (docs/design/opening-storyboard.md):
    /// the Launch recording holds the opening at each and photographs it
    /// (`-uiPreviewSplashAt <name>`), from the launch screen to home at rest.
    var moments: [(name: String, t: Double)] {
        if reduced {
            return [("launch", 0), ("shrink", handoff / 2), ("handoff", handoff), ("still", settled + Self.runOn)]
        }
        let letters = markArrives - 0.02 + Self.letterStagger * Double(Self.titleLetters - 1) / 2
        return [
            ("launch", 0),
            ("baseline", Self.baselineGrow),
            ("lub", r),
            ("dub", s2),
            ("handoff", handoff),
            ("arc", handoff + Self.markTravel / 2),
            ("perch", markArrives),
            ("landed", landed),
            ("letters", letters + Self.letterLength / 2),
            ("still", settled + Self.runOn),
        ]
    }

    /// The time of a named moment, or of a number of seconds given instead.
    func moment(_ name: String) -> Double? {
        moments.first { $0.name == name }?.t ?? Double(name).flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
    }

    // MARK: the ECG becoming the squiggle

    /// The line of the squiggle beside home's title, in points: the ECG's
    /// line thins to it as it lands.
    static let squiggleLine: Double = 2

    /// The squiggle beside the title (WardVitals' EcgSquiggle): x as a
    /// fraction of its width, y as a fraction of its height from the middle,
    /// up negative. The R peak is the sixth point.
    static let squiggle: [(u: Double, v: Double)] = [
        (0, 0), (0.30, 0), (0.36, -0.12), (0.42, 0), (0.48, 0.10), (0.54, -0.50),
        (0.60, 0.30), (0.66, 0), (0.78, -0.14), (0.88, 0), (1, 0),
    ]

    /// The trace (points `width` wide, as `trace(width:height:)` gives them)
    /// paired point for point with the squiggle, so one can become the
    /// other: every point of the trace, each with where it goes, plus a point
    /// on the trace for every corner of the squiggle, so both ends are drawn
    /// exactly (the R peak goes to the squiggle's R; the trace's ends to its
    /// ends). `to` is in the squiggle's fractions (u, v).
    func morph(_ points: [(x: Double, y: Double)], width: Double)
        -> [(from: (x: Double, y: Double), to: (u: Double, v: Double))] {
        let xR = width * r / traceEnd
        let uR = Self.squiggle[5].u
        func u(_ x: Double) -> Double { x <= xR ? uR * x / xR : uR + (1 - uR) * (x - xR) / (width - xR) }
        func x(_ u: Double) -> Double { u <= uR ? xR * u / uR : xR + (width - xR) * (u - uR) / (1 - uR) }
        func traceY(at x: Double) -> Double {
            guard let hi = points.firstIndex(where: { $0.x >= x }) else { return points.last?.y ?? 0 }
            if hi == 0 { return points[0].y }
            let a = points[hi - 1], b = points[hi]
            return b.x == a.x ? b.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        }
        func squiggleV(at u: Double) -> Double {
            let s = Self.squiggle
            guard let hi = s.firstIndex(where: { $0.u >= u }) else { return s.last!.v }
            if hi == 0 { return s[0].v }
            let a = s[hi - 1], b = s[hi]
            return b.u == a.u ? b.v : a.v + (b.v - a.v) * (u - a.u) / (b.u - a.u)
        }
        var all: [(x: Double, y: Double, u: Double)] = points.map { ($0.x, $0.y, u($0.x)) }
        // a corner within half a sample of a point of the trace takes that
        // point (so the R peak's own sample lands on the squiggle's R);
        // otherwise a point is added on the trace for it
        let half = points.count > 1 ? 0.5 * width / Double(points.count - 1) : 0
        for corner in Self.squiggle {
            let cx = x(corner.u)
            if let i = all.indices.min(by: { abs(all[$0].x - cx) < abs(all[$1].x - cx) }),
               abs(all[i].x - cx) <= half + 1e-9 {
                all[i].u = corner.u
            } else {
                all.append((cx, traceY(at: cx), corner.u))
            }
        }
        all.sort { $0.u < $1.u }
        return all.map { p in
            let exact = Self.squiggle.first { abs($0.u - p.u) < 1e-9 }
            return ((p.x, p.y), (p.u, exact?.v ?? squiggleV(at: p.u)))
        }
    }

    /// Where the hand-off's ECG is at progress `e` (0 the trace, 1 the
    /// squiggle), for a trace drawn at `origin` and a squiggle in `target`
    /// (x, y, width, height), all in the same space.
    static func morphed(_ pairs: [(from: (x: Double, y: Double), to: (u: Double, v: Double))], at e: Double,
                        origin: (x: Double, y: Double),
                        target: (x: Double, y: Double, width: Double, height: Double)) -> [(x: Double, y: Double)] {
        pairs.map { p in
            let ax = origin.x + p.from.x, ay = origin.y + p.from.y
            let bx = target.x + p.to.u * target.width, by = target.y + target.height / 2 + p.to.v * target.height
            return (ax + (bx - ax) * e, ay + (by - ay) * e)
        }
    }

    /// Key times for Core Animation, at `rate` a second, from 0 to the end.
    func times(rate: Double = 120) -> [Double] {
        let n = max(2, Int((duration * rate).rounded(.up)))
        return (0...n).map { duration * Double($0) / Double(n) }
    }
}
