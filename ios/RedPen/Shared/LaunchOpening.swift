import Foundation

/// The launch mark: the owner's stethoscope (14 Oct), the white tube by day
/// and the slate tube by night, cut from their flat grounds by
/// tools/make_launch_logo.py into the LaunchLogo image set, so the system
/// launch screen and the animated opening (LaunchSplash) draw the same
/// picture on the home screen's base.
enum LaunchArt {
    static let imageName = "LaunchLogo"

    /// The image's side in points (both modes): the system launch screen
    /// draws it at this size, centred in the safe area.
    static let side: Double = 200

    /// The chest piece's disc in each mode's image, as fractions of the
    /// image's side (x from the left, y from the top, r its radius), measured
    /// by make_launch_logo.py on the cut art: the heartbeat is centred here
    /// and the home screen opens out from here. The two drawings differ a
    /// little, so each has its own.
    static func chest(dark: Bool) -> (x: Double, y: Double, r: Double) {
        dark ? (0.7750, 0.3065, 0.1108) : (0.7764, 0.3022, 0.1113)
    }

    /// The ECG's colour (0xRRGGBB). By night the slate tube's lit side, which
    /// reads on the dark base; by day the slate-blue of the night tube, since
    /// the white tube's own colour is too faint as a thin line on the pale
    /// base (about 1.2:1).
    static func trace(dark: Bool) -> UInt32 {
        dark ? 0x6584AE : 0x43566F
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
    /// S2, the "dub".
    static let s2: Double = 0.3305
    static let length: Double = 0.56
}

/// The opening's timing, in seconds from the moment the home screen's first
/// real frame is on screen. Nothing here changes opacity: the chest piece
/// beats in scale; with the sound, one ECG complex is drawn under the mark
/// as a stroke trimming in (its R peak on the lub, its T wave ending on the
/// dub) and erased from the left as a monitor sweeps; then the home screen is
/// uncovered by a circular hole that opens from the chest piece while the
/// mark scales up about it.
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
        return 0.33
    }
    /// When S2 is heard (the T wave ends here).
    var s2: Double { r + HeartbeatSound.s2 - HeartbeatSound.s1 }
    /// When the sound file starts, so that S1 is heard on the R peak (the
    /// output latency is allowed for by LaunchSplash, which starts the
    /// drawing that much later when the sound is really started).
    var audioAt: Double { r - HeartbeatSound.s1 }

    // lub and dub: (start relative to S1 / S2, length, rise)
    static let lub = (lead: -0.02, length: 0.17, rise: 0.06)
    static let dub = (lead: -0.02, length: 0.15, rise: 0.04)

    /// The ECG: the flat baseline grows out from its centre over the first
    /// 0.1 s, then the trace is drawn left to right at a steady speed (one
    /// second of trace a second), and the tail runs on 0.1 s past the T wave.
    static let baselineGrow = 0.10
    static let tail = 0.10
    /// Erased from the left, at this many times the drawing speed, starting
    /// just before the T wave ends.
    static let eraseSpeed = 2.4
    static let eraseLead = 0.01

    var traceEnd: Double { s2 + Self.tail }
    var eraseStart: Double { s2 - Self.eraseLead }
    var eraseEnd: Double { eraseStart + traceEnd / Self.eraseSpeed }

    var revealStart: Double {
        reduced ? 0 : s2 + 0.13
    }
    var revealLength: Double { reduced ? 0.18 : 0.58 }
    /// The whole opening; after this the splash is gone.
    var duration: Double { max(revealStart + revealLength, ecg ? eraseEnd : 0) }

    /// How much bigger the mark is by the time the hole has passed it.
    static let markGrowth = 0.14

    // MARK: easing

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func easeIn(_ x: Double) -> Double { let u = clamp(x); return u * u }
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
    /// nil when none is: the baseline growing out from its centre, the head
    /// sweeping right, the tail erased from the left behind it.
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
        if t > eraseStart {
            from = max(from, (t - eraseStart) * Self.eraseSpeed)
        }
        guard from < to else { return nil }
        return (from, to)
    }

    /// How far the hole has opened, 0 (shut) to 1 (past the farthest corner).
    func reveal(at t: Double) -> Double {
        Self.easeIn((t - revealStart) / revealLength)
    }

    /// The whole mark's scale about the chest piece, growing as it is uncovered.
    func markScale(at t: Double) -> Double {
        if reduced { return 1 }
        return 1 + Self.markGrowth * reveal(at: t)
    }

    /// The hole's radius in points for a screen of `width` x `height` opening
    /// from (`x`, `y`): it ends a little past the farthest corner, so the last
    /// frame shows nothing of the splash and removing it changes nothing.
    static func farthest(x: Double, y: Double, width: Double, height: Double) -> Double {
        let dx = max(x, width - x), dy = max(y, height - y)
        return (dx * dx + dy * dy).squareRoot() + 2
    }

    /// Key times for Core Animation, at `rate` a second, from 0 to the end.
    func times(rate: Double = 120) -> [Double] {
        let n = max(2, Int((duration * rate).rounded(.up)))
        return (0...n).map { duration * Double($0) / Double(n) }
    }
}
