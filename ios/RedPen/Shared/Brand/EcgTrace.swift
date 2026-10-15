import Foundation

// MARK: - The master ECG
//
// One normal-sinus beat as lead II records it: the beat the opening's trace
// and home's title squiggle both draw, so the two are the same drawing at two
// sizes, and the beat the launch heartbeat's lub and dub are timed to.
// Foundation only, so the "ecgtrace" suite tests it on Linux; pure values and
// pure functions, safe on any thread.
//
// Time is in seconds from the P wave's onset (the beat's zero), voltage in
// millivolts, up positive. A run repeats the beat every 60 / heart rate
// seconds, the P onset of beat k at k times that.
//
// The beat, at 60 a minute (RR 1.000 s):
//
//     landmark       time (s)   mV
//     P onset        0.000      0
//     P peak         0.050      0.150
//     P end          0.100      0
//     QRS onset      0.160      0
//     Q (lowest)     0.17363   -0.087
//     R              0.200      1.000
//     S (lowest)     0.22645   -0.238
//     J              0.250      0
//     T peak         0.520      0.300
//     T end          0.580      0
//     S1 (the lub)   0.220      R + 0.020
//     S2 (the dub)   0.580      T end, S1 + 0.360
//
// Why each number:
// - Rate 60 a minute (RR 1.000 s): normal sinus rhythm both as conventionally
//   bounded (60-100 a minute) and by Spodick's 50-90 (South Med J
//   1996;89(7):666-7, doi:10.1097/00007611-199607000-00003). At RR 1 s every
//   QT correction leaves QT as it is, Bazett's QT / sqrt(RR) and the
//   Framingham QT + 0.154 (1 - RR) alike (Sagie et al., Am J Cardiol
//   1992;70(7):797-801, doi:10.1016/0002-9149(92)90562-D), so QT is QTc.
// - PR 0.16 s (P onset to QRS onset): normal is 0.12-0.20 s (Goldberger,
//   Goldberger and Shvilkin, Goldberger's Clinical Electrocardiography: A
//   Simplified Approach, 9th ed., Elsevier, 2017), and about 0.16 s is
//   Guyton and Hall's typical value (Hall and Hall, Guyton and Hall Textbook
//   of Medical Physiology, 14th ed., Elsevier, ch. 11).
// - P 0.10 s wide and 0.15 mV tall: under the 0.12 s and 0.25 mV (2.5 mm) a
//   normal lead II P wave stays below (Goldberger, 9th ed.), and inside
//   Guyton and Hall's 0.1-0.3 mV.
// - QRS 0.09 s (QRS onset to J): at most 0.10 s is normal (Goldberger, 9th
//   ed.); 0.11 s and over is a conduction delay (AHA/ACCF/HRS part III,
//   Surawicz et al., Circulation 2009;119(10):e235-40,
//   doi:10.1161/CIRCULATIONAHA.108.191095).
// - R 0.040 s after QRS onset: under the 45 ms upper limit of the R-peak time
//   over the left ventricle (Perez-Riera et al., Ann Noninvasive
//   Electrocardiol 2016;21(1):10-9, doi:10.1111/anec.12323).
// - R 1.000 mV and S -0.238 mV: 1.24 mV from R's top to S's bottom, inside
//   Guyton and Hall's 1.0-1.5 mV for the limb leads.
// - q 0.019 s wide and 0.087 mV deep, a normal septal q: in lead II a Q wave
//   is pathological only from 0.03 s wide and 0.1 mV deep (Fourth Universal
//   Definition of Myocardial Infarction, Thygesen et al., Circulation
//   2018;138(20):e618-51, doi:10.1161/CIR.0000000000000617).
// - J and the ST segment on the baseline: ST elevation counts from 0.1 mV at
//   the J point in leads other than V2-V3 (the same definition).
// - T 0.300 mV: inside Guyton and Hall's 0.2-0.3 mV. Asymmetric, as the T
//   wave is in health (di Bernardo and Murray, Nature 2000;403(6765):40,
//   doi:10.1038/47409); the slower rise out of the ST segment (0.15 s, width
//   0.05 s) and the steeper fall (0.06 s, width 0.02 s) are this file's
//   choice, which ends T where S2 is heard (below).
// - QT 0.40 s as a reader measures it: the tangent to T's steepest fall meets
//   the baseline at 0.5585 s, 0.3985 s after QRS onset (the tangent method,
//   in lead II: Postema and Wilde, Curr Cardiol Rev 2014;10(3):287-94,
//   doi:10.2174/1573403X10666140514103612); the T wave itself meets the
//   baseline 0.42 s after QRS onset. Both are normal QTc: 350-450 ms in men
//   and 360-460 ms in women (the same review), prolonged only from 450 and
//   460 ms (AHA/ACCF/HRS part IV, Rautaharju et al., Circulation
//   2009;119(10):e241-50, doi:10.1161/CIRCULATIONAHA.108.191096).
//
// The heart sounds:
// - S1 0.020 s after R: the mitral part of S1 comes 0.06 s after the Q wave
//   (Waider and Craige, Am J Cardiol 1975;35(3):346-56,
//   doi:10.1016/0002-9149(75)90026-0), and R peaks 0.040 s into the QRS.
// - S2 where the T wave meets the baseline, 0.360 s after S1: in health QT
//   ends 26 +/- 13 ms before S2 (Boudoulas et al., Am J Cardiol
//   1982;50(6):1229-35, doi:10.1016/0002-9149(82)90454-4); here the
//   tangent-read end of T is 21 ms before it. tools/make_heartbeat.py's
//   SYSTOLE is this 0.360 s.
//
// The shape: each wave is a Gaussian, as in McSharry et al.'s model (IEEE
// Trans Biomed Eng 2003;50(3):289-94, doi:10.1109/TBME.2003.808805: the ECG
// as a sum of Gaussian waves P, Q, R, S and T, each with its own time, width
// and height), lowered by a small parabola so it meets the baseline level and
// flat three widths from its peak and is exactly zero beyond. So the
// baseline between beats is exactly flat, and beats join with no step and no
// corner. The T wave has a different width on each side.
//
// Paper: 25 mm a second across and 10 mm a millivolt up, the standard ECG
// (Goldberger, 9th ed.; Guyton and Hall, 14th ed., ch. 11).

/// One of the beat's named points, in time order.
nonisolated enum EcgLandmark: String, CaseIterable, Sendable {
    /// Where the P wave leaves the baseline: the beat's time zero.
    case pOnset
    case pPeak
    case pEnd
    /// Where the QRS complex leaves the baseline (the Q wave's start): PR
    /// runs to here, and QT from here.
    case qrsOnset
    /// The Q wave's lowest point.
    case q
    /// The R wave's peak, the beat's highest point.
    case r
    /// The S wave's lowest point, the beat's lowest.
    case s
    /// The J point: the QRS complex's end, where the S wave meets the
    /// baseline and the ST segment starts.
    case j
    case tPeak
    /// Where the T wave meets the baseline; S2 is heard here.
    case tEnd
}

/// A point of a sampled trace: its time in seconds (from the P onset of the
/// beat, or of a run's beat 0), and where it is drawn, x to the right and y
/// down, in the caller's points.
nonisolated struct EcgPoint: Sendable, Equatable {
    var t: Double
    var x: Double
    var y: Double
}

/// ECG paper at the standard speed and gain (25 mm a second across, 10 mm a
/// millivolt up), drawn at `scale` points a millimetre, with time `start` at
/// x = `left` and 0 mV at y = `baseline` (y grows down, as drawn).
nonisolated struct EcgPaper: Sendable, Equatable {
    static let millimetresPerSecond = 25.0
    static let millimetresPerMillivolt = 10.0

    /// Points a millimetre.
    var scale: Double
    /// The time drawn at x = `left`, in seconds.
    var start: Double
    var left: Double
    /// Where 0 mV is drawn, y down.
    var baseline: Double

    init(scale: Double, start: Double = 0, left: Double = 0, baseline: Double = 0) {
        self.scale = scale
        self.start = start
        self.left = left
        self.baseline = baseline
    }

    /// Where time `seconds` is drawn across.
    func x(_ seconds: Double) -> Double {
        left + (seconds - start) * Self.millimetresPerSecond * scale
    }

    /// Where `millivolts` is drawn down (up positive on the paper, so a
    /// higher voltage is a smaller y).
    func y(_ millivolts: Double) -> Double {
        baseline - millivolts * Self.millimetresPerMillivolt * scale
    }

    /// The largest paper on which the trace from `start` to `end` seconds, at
    /// the beat's full height (from S, its lowest point, to R, its highest),
    /// fits a `width` x `height` box, centred in it. The same window fitted
    /// to two boxes gives the same drawing at two sizes. An empty window or
    /// box gives a paper of scale 0.
    static func fitting(from start: Double, to end: Double, width: Double, height: Double) -> EcgPaper {
        let across = (end - start) * millimetresPerSecond
        let tall = (EcgTrace.highest - EcgTrace.lowest) * millimetresPerMillivolt
        guard across.isFinite, width.isFinite, height.isFinite,
              across > 0, tall > 0, width > 0, height > 0 else {
            return EcgPaper(scale: 0, start: start.isFinite ? start : 0)
        }
        let scale = min(width / across, height / tall)
        let top = (height - tall * scale) / 2
        return EcgPaper(scale: scale, start: start, left: (width - across * scale) / 2,
                        baseline: top + EcgTrace.highest * millimetresPerMillivolt * scale)
    }
}

/// The master beat and runs of it: the voltage at any time, each landmark's
/// time, the heart sounds' times, and points to draw on ECG paper.
nonisolated enum EcgTrace {
    // MARK: rate

    /// The beat's own rate: at RR 1 s, QT is QTc.
    static let heartRate = 60.0
    /// The rates a run can be drawn at. The beat keeps its shape at any rate,
    /// so only the baseline between beats changes; up to 100 a minute (RR
    /// 0.6 s) there is baseline between every T end and the next P onset.
    static let rates: ClosedRange<Double> = 40...100

    /// The time from one beat's P onset to the next (RR), in seconds, at
    /// `heartRate` held within `rates`.
    static func period(heartRate: Double = EcgTrace.heartRate) -> Double {
        let rate = heartRate.isFinite ? min(max(heartRate, rates.lowerBound), rates.upperBound) : Self.heartRate
        return 60 / rate
    }

    // MARK: landmarks

    /// When `landmark` comes, in seconds from the beat's P onset.
    static func time(of landmark: EcgLandmark) -> Double {
        switch landmark {
        case .pOnset: 0
        case .pPeak: 0.050
        case .pEnd: 0.100
        case .qrsOnset: 0.160
        case .q: 0.17363
        case .r: 0.200
        case .s: 0.22645
        case .j: 0.250
        case .tPeak: 0.520
        case .tEnd: 0.580
        }
    }

    /// When `landmark` of beat `beat` of a run at `heartRate` comes, in
    /// seconds from beat 0's P onset.
    static func time(of landmark: EcgLandmark, beat: Int, heartRate: Double = EcgTrace.heartRate) -> Double {
        Double(beat) * period(heartRate: heartRate) + time(of: landmark)
    }

    /// The voltage at `landmark`, in millivolts.
    static func millivolts(of landmark: EcgLandmark) -> Double {
        millivolts(at: time(of: landmark))
    }

    /// The beat's length, P onset to T end, in seconds.
    static var duration: Double { time(of: .tEnd) }
    /// The beat's highest point (R) and lowest (S), in millivolts.
    static var highest: Double { millivolts(of: .r) }
    static var lowest: Double { millivolts(of: .s) }

    // MARK: the heart sounds

    /// S1, the lub, comes this long after R: the mitral part of S1 is 0.06 s
    /// after QRS onset (Waider and Craige 1975), R 0.04 s.
    static let s1AfterR = 0.020

    /// When S1 is heard in beat `beat` of a run at `heartRate`.
    static func s1(beat: Int = 0, heartRate: Double = EcgTrace.heartRate) -> Double {
        time(of: .r, beat: beat, heartRate: heartRate) + s1AfterR
    }

    /// When S2, the dub, is heard: where the T wave meets the baseline.
    static func s2(beat: Int = 0, heartRate: Double = EcgTrace.heartRate) -> Double {
        time(of: .tEnd, beat: beat, heartRate: heartRate)
    }

    // MARK: the voltage

    /// One beat's voltage at `t` seconds from its P onset, in millivolts:
    /// exactly 0 before the P onset and after the T end.
    static func millivolts(at t: Double) -> Double {
        guard t > 0, t < duration else { return 0 }
        var sum = 0.0
        for wave in waves { sum += wave.millivolts(at: t) }
        return sum
    }

    /// A run's voltage at `t` seconds from beat 0's P onset, a beat every
    /// `period(heartRate:)` seconds (and before beat 0 as after it).
    static func millivolts(at t: Double, heartRate: Double) -> Double {
        guard t.isFinite else { return 0 }
        let rr = period(heartRate: heartRate)
        return millivolts(at: t - (t / rr).rounded(.down) * rr)
    }

    // MARK: points to draw

    /// The trace from `start` to `end` seconds on `paper`: one beat when
    /// `heartRate` is nil (the baseline either side of it), or a run at
    /// `heartRate`. A point every `step` seconds or less, from `start` to
    /// `end` exactly, plus one at every landmark inside, so the peaks and the
    /// wave ends are drawn exactly; in time order. The same window and step
    /// give the same times at any size, so two drawings pair point for point.
    /// A window longer than an hour, or not finite, gives no points.
    static func points(from start: Double, to end: Double, heartRate: Double? = nil,
                       on paper: EcgPaper, step: Double = 0.001) -> [EcgPoint] {
        guard start.isFinite, end.isFinite, end > start, end - start <= 3600,
              abs(start) < 1e6, abs(end) < 1e6 else { return [] }
        let step = step.isFinite && step > 0 ? step : 0.001
        let n = max(1, Int(((end - start) / step).rounded(.up)))
        func grid(_ i: Double) -> Double { i >= Double(n) ? end : start + (end - start) * i / Double(n) }
        var times = (0...n).map { grid(Double($0)) }
        let marks: [Double]
        if let rate = heartRate {
            let rr = period(heartRate: rate)
            let first = Int(((start - duration) / rr).rounded(.down))
            let last = Int((end / rr).rounded(.up))
            marks = (first...last).flatMap { k in EcgLandmark.allCases.map { time(of: $0, beat: k, heartRate: rate) } }
        } else {
            marks = EcgLandmark.allCases.map { time(of: $0) }
        }
        for m in marks where m > start && m < end {
            let nearest = grid(((m - start) / (end - start) * Double(n)).rounded())
            if abs(nearest - m) > 1e-9 { times.append(m) }
        }
        times.sort()
        return times.map { t in
            let v = heartRate.map { millivolts(at: t, heartRate: $0) } ?? millivolts(at: t)
            return EcgPoint(t: t, x: paper.x(t), y: paper.y(v))
        }
    }

    /// The same, on the largest paper that fits a `width` x `height` box
    /// (`EcgPaper.fitting`), with that paper, so a landmark can be placed:
    /// `paper.x(EcgTrace.time(of: .r))`.
    static func points(from start: Double, to end: Double, heartRate: Double? = nil,
                       width: Double, height: Double, step: Double = 0.001) -> (paper: EcgPaper, points: [EcgPoint]) {
        let paper = EcgPaper.fitting(from: start, to: end, width: width, height: height)
        return (paper, points(from: start, to: end, heartRate: heartRate, on: paper, step: step))
    }

    // MARK: the waves

    /// A wave: a Gaussian of height `millivolts` peaking at `centre`, `rise`
    /// wide before the peak and `fall` wide after it (seconds), cut to zero
    /// three widths out (`lobe`).
    private nonisolated struct Wave: Sendable {
        let centre: Double
        let millivolts: Double
        let rise: Double
        let fall: Double

        func millivolts(at t: Double) -> Double {
            let z = t < centre ? (t - centre) / rise : (t - centre) / fall
            return millivolts * EcgTrace.lobe(z)
        }
    }

    /// P, Q, R, S and T (see the table above). Their edges are the
    /// landmarks: P from 0 to 0.10 s, Q from 0.16 s (QRS onset), S to 0.25 s
    /// (J) and T to 0.58 s (T end); R's own edges, 0.17 and 0.23 s, fall
    /// inside the QRS, and Q ends before R's peak and S starts on it, so R's
    /// peak is exactly R's height.
    private static let waves: [Wave] = [
        Wave(centre: 0.050, millivolts: 0.15, rise: 0.05 / 3, fall: 0.05 / 3),
        Wave(centre: 0.175, millivolts: -0.10, rise: 0.005, fall: 0.005),
        Wave(centre: 0.200, millivolts: 1.00, rise: 0.010, fall: 0.010),
        Wave(centre: 0.225, millivolts: -0.25, rise: 0.025 / 3, fall: 0.025 / 3),
        Wave(centre: 0.520, millivolts: 0.30, rise: 0.05, fall: 0.02),
    ]

    /// How many widths out a wave ends.
    static let cut = 3.0
    private static let edge = exp(-0.5 * cut * cut)
    private static let top = 1 - edge * (1 + 0.5 * cut * cut)

    /// A Gaussian lowered by a parabola so it is 1 at z = 0 and meets the
    /// baseline level and flat at z = +/-`cut`, and 0 beyond: e^(-z^2/2)
    /// less e^(-cut^2/2) (1 + (cut^2 - z^2) / 2), over its value at 0.
    static func lobe(_ z: Double) -> Double {
        guard abs(z) < cut else { return 0 }
        return (exp(-0.5 * z * z) - edge * (1 + 0.5 * (cut * cut - z * z))) / top
    }
}
