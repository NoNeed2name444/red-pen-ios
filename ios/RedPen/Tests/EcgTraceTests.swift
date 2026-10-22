// Stethoscore · the master ECG (EcgTrace): one lead II beat whose landmarks
// come in order and inside their cited normal ranges, R its highest point, a
// flat baseline between beats that join with no step or corner, the lub just
// after R and the dub on T's end, sampling that is deterministic, and the
// trace on ECG paper at 25 mm/s and 10 mm/mV. Light on purpose: under
// 100,000 evaluations of five small waves, well under a second, and no
// check depends on how fast anything runs.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }
func at(_ l: EcgLandmark) -> Double { EcgTrace.time(of: l) }
func mv(_ t: Double) -> Double { EcgTrace.millivolts(at: t) }
func mv(_ l: EcgLandmark) -> Double { EcgTrace.millivolts(of: l) }

// One beat and a little baseline after it, every 0.1 ms.
let dt = 0.0001
let fine: [(t: Double, v: Double)] = (0...6500).map { i in
    let t = Double(i) * dt
    return (t, mv(t))
}
func highest(_ from: Double, _ to: Double) -> (t: Double, v: Double) {
    fine.filter { $0.t >= from && $0.t <= to }.max { $0.v < $1.v }!
}
func lowest(_ from: Double, _ to: Double) -> (t: Double, v: Double) {
    fine.filter { $0.t >= from && $0.t <= to }.min { $0.v < $1.v }!
}

// MARK: the landmarks, in order and where the trace has them

let times = EcgLandmark.allCases.map(at)
check("the landmarks come in order: P onset, P peak, P end, QRS onset, Q, R, S, J, T peak, T end",
      zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "\(times)")
check("the beat runs from its P onset (time 0) to its T end",
      at(.pOnset) == 0 && EcgTrace.duration == at(.tEnd))

let rTop = highest(0, 0.65)
check("R is the beat's highest point, at R's time", near(rTop.t, at(.r), dt) && near(rTop.v, mv(.r)), "\(rTop)")
check("R is 1 mV, and P and T are well below it",
      near(EcgTrace.highest, 1, 1e-12) && mv(.pPeak) < 0.5 * mv(.r) && mv(.tPeak) < 0.5 * mv(.r))
let pTop = highest(at(.pOnset), at(.pEnd)), tTop = highest(at(.j), at(.tEnd))
check("P peaks at P peak and T at T peak", near(pTop.t, at(.pPeak), dt) && near(tTop.t, at(.tPeak), dt),
      "\(pTop) \(tTop)")
let qLow = lowest(at(.qrsOnset), at(.r)), sLow = lowest(at(.r), at(.j))
check("Q and S are the QRS's low points, where named",
      near(qLow.t, at(.q), 2 * dt) && near(sLow.t, at(.s), 2 * dt), "\(qLow) \(sLow)")
let bottom = lowest(0, 0.65)
check("S is the beat's lowest point: no sample below it, the lowest sample beside it",
      bottom.v >= EcgTrace.lowest - 1e-7 && bottom.v - EcgTrace.lowest < 1e-5 && near(bottom.t, at(.s), dt)
      && EcgTrace.lowest < 0, "\(bottom) \(EcgTrace.lowest)")
check("Q and S are named at their true lowest: no sample of either wave below them",
      qLow.v >= mv(.q) - 1e-7 && sLow.v >= mv(.s) - 1e-7, "\(qLow) \(mv(.q)) \(sLow) \(mv(.s))")

// the trace is off the baseline in exactly three stretches: P, QRS and T
var stretches: [(from: Double, to: Double)] = []
for (a, b) in zip(fine, fine.dropFirst()) {
    if a.v == 0 && b.v != 0 { stretches.append((b.t, b.t)) }
    if b.v != 0 { stretches[stretches.count - 1].to = b.t }
}
check("off the baseline only for P, QRS and T", stretches.count == 3, "\(stretches)")
if stretches.count == 3 {
    check("P from P onset to P end", near(stretches[0].from, at(.pOnset), 1.5 * dt) && near(stretches[0].to, at(.pEnd), 1.5 * dt),
          "\(stretches[0])")
    check("QRS from QRS onset to J", near(stretches[1].from, at(.qrsOnset), 1.5 * dt) && near(stretches[1].to, at(.j), 1.5 * dt),
          "\(stretches[1])")
    check("T up to T end", near(stretches[2].to, at(.tEnd), 1.5 * dt), "\(stretches[2])")
}

// MARK: intervals and amplitudes inside their cited normal ranges

check("60 a minute (RR 1 s): normal sinus by 60-100 and by Spodick's 50-90",
      (60...100).contains(EcgTrace.heartRate) && (50...90).contains(EcgTrace.heartRate)
      && EcgTrace.period() == 1)
let pr = at(.qrsOnset) - at(.pOnset)
check("PR 0.12-0.20 s (Goldberger)", (0.12...0.20).contains(pr), "\(pr)")
check("P under 0.12 s wide and 0.25 mV tall (Goldberger), 0.1-0.3 mV (Guyton and Hall)",
      at(.pEnd) - at(.pOnset) < 0.12 && mv(.pPeak) < 0.25 && (0.1...0.3).contains(mv(.pPeak)))
let qrs = at(.j) - at(.qrsOnset)
check("QRS at most 0.10 s (Goldberger), under the 0.11 s of a conduction delay (AHA part III)",
      qrs <= 0.10 && qrs < 0.11, "\(qrs)")
check("R-peak time at most 45 ms (Perez-Riera)", at(.r) - at(.qrsOnset) <= 0.045)
let rToS = EcgTrace.highest - EcgTrace.lowest
check("R's top to S's bottom 1.0-1.5 mV (Guyton and Hall)", (1.0...1.5).contains(rToS), "\(rToS)")
let qEnds = fine.first { $0.t > at(.q) && $0.v > 0 }!.t
check("a normal q: narrower than 0.03 s and shallower than 0.1 mV (Fourth Universal Definition)",
      qEnds - at(.qrsOnset) < 0.03 && -mv(.q) < 0.1 && mv(.q) < 0, "\(qEnds - at(.qrsOnset)) s, \(mv(.q)) mV")
check("J and the ST segment on the baseline (elevation counts from 0.1 mV)",
      abs(mv(.j)) < 1e-12 && stride(from: at(.j), through: at(.j) + 0.085, by: 0.005).allSatisfy { abs(mv($0)) < 1e-12 })
check("T 0.2-0.3 mV (Guyton and Hall)", (0.2...0.3).contains(mv(.tPeak)))
if stretches.count == 3 {
    let tRise = zip(fine, fine.dropFirst()).filter { $0.0.t > stretches[2].from && $0.1.t < at(.tPeak) }
        .map { ($0.1.v - $0.0.v) / dt }.max()!
    let tFall = zip(fine, fine.dropFirst()).filter { $0.0.t > at(.tPeak) && $0.1.t < at(.tEnd) }
        .map { ($0.0.v - $0.1.v) / dt }.max()!
    check("T asymmetric: a slower rise than fall (di Bernardo and Murray), but not a cliff",
          at(.tPeak) - stretches[2].from > at(.tEnd) - at(.tPeak) && tFall > tRise && tFall < 2 * tRise,
          "\(stretches[2]) rise \(tRise) fall \(tFall) mV/s")
}

// QT as a reader measures it: the tangent to T's steepest fall, to the baseline
let fall = zip(fine, fine.dropFirst()).filter { $0.0.t > at(.tPeak) && $0.1.t < at(.tEnd) }
    .map { (t: $0.0.t, v: $0.0.v, slope: ($0.1.v - $0.0.v) / dt) }
let steepest = fall.min { $0.slope < $1.slope }!
let tangentEnd = steepest.t - steepest.v / steepest.slope
let qtRead = tangentEnd - at(.qrsOnset), qtWhole = at(.tEnd) - at(.qrsOnset)
check("QT about 0.38 s by the tangent method (Postema and Wilde)", near(qtRead, 0.38, 0.01), "\(qtRead)")
let tpeRead = (tangentEnd - at(.tPeak)) / qtRead, tpeWhole = (at(.tEnd) - at(.tPeak)) / qtWhole
check("Tp-e/QT either side of health's 0.21 (Gupta), read or to T's end, and near it",
      tpeRead < 0.21 && tpeWhole > 0.21 && tpeRead > 0.15 && tpeWhole < 0.27, "\(tpeRead) \(tpeWhole)")
let rr = EcgTrace.period()
let corrected = [qtRead, qtWhole].flatMap { [$0 / rr.squareRoot(), $0 + 0.154 * (1 - rr)] }
check("QTc normal, read or to T's end, by Bazett or Framingham: 0.36-0.45 s (Postema and Wilde)",
      corrected.allSatisfy { (0.36...0.45).contains($0) }, "\(corrected)")

// MARK: the heart sounds

check("S1 to S2 is 0.36 s", near(EcgTrace.s2() - EcgTrace.s1(), 0.36), "\(EcgTrace.s2() - EcgTrace.s1())")
let lastOff = fine.last { $0.v != 0 }!.t
check("S2 is at T's end within 10 ms, as the trace draws it",
      abs(EcgTrace.s2() - lastOff) <= 0.010 && EcgTrace.s2() == at(.tEnd), "\(lastOff)")
check("and T is still well off the baseline 50 ms before S2", mv(EcgTrace.s2() - 0.05) > 0.05)
check("S1 shortly after R: 20 ms, 0.06 s after QRS onset (Q to mitral closure, Waider and Craige)",
      near(EcgTrace.s1() - at(.r), 0.020) && near(EcgTrace.s1() - at(.qrsOnset), 0.06, 0.005))
check("the tangent-read end of T is 13-39 ms before S2 (26 +/- 13 ms, Boudoulas)",
      (0.013...0.039).contains(EcgTrace.s2() - tangentEnd), "\(EcgTrace.s2() - tangentEnd)")

// MARK: runs: a flat baseline between beats, joined with no step or corner

for rate in Array(stride(from: EcgTrace.rates.lowerBound, through: EcgTrace.rates.upperBound, by: 1)) {
    let rrc = EcgTrace.period(heartRate: rate)
    let qtc = [qtRead, qtWhole].flatMap { [$0 / rrc.squareRoot(), $0 + 0.154 * (1 - rrc)] }
    check("\(Int(rate)) a minute: QTc normal by Bazett and Framingham, read or to T's end (0.36 to under 0.45 s)",
          qtc.allSatisfy { $0 >= 0.36 && $0 < 0.45 }, "\(qtc)")
}
check("the allowed rates are normal sinus (Spodick's 50-90)", EcgTrace.rates.lowerBound >= 50 && EcgTrace.rates.upperBound <= 90)
for rate in [55.0, 60, 68] {
    let rr = EcgTrace.period(heartRate: rate)
    check("\(Int(rate)) a minute: a beat every \(60 / rate) s", near(rr, 60 / rate, 1e-12))
    let shifted = stride(from: 0.0, to: rr, by: 0.0013).allSatisfy { u in
        (-2...3).allSatisfy { k in near(EcgTrace.millivolts(at: Double(k) * rr + u, heartRate: rate), mv(u), 1e-12) }
    }
    check("\(Int(rate)) a minute: each beat of a run is the beat, moved", shifted)
    let flat = (0...2).allSatisfy { k in
        stride(from: EcgTrace.s2(beat: k, heartRate: rate) + 1e-6, to: EcgTrace.time(of: .pOnset, beat: k + 1, heartRate: rate),
               by: 0.0011).allSatisfy { EcgTrace.millivolts(at: $0, heartRate: rate) == 0 }
    }
    check("\(Int(rate)) a minute: the baseline is flat from each T end to the next P onset", flat)
    let joins = (1...3).allSatisfy { k in
        let join = Double(k) * rr
        return [-1e-4, -1e-7, 0, 1e-7, 1e-4].allSatisfy { abs(EcgTrace.millivolts(at: join + $0, heartRate: rate)) < 1e-5 }
    }
    check("\(Int(rate)) a minute: beats join on the baseline", joins)
    check("\(Int(rate)) a minute: S1 to S2 is 0.36 s in every beat, S2 on its T end",
          (-1...3).allSatisfy { k in
              near(EcgTrace.s2(beat: k, heartRate: rate) - EcgTrace.s1(beat: k, heartRate: rate), 0.36)
              && EcgTrace.s2(beat: k, heartRate: rate) == EcgTrace.time(of: .tEnd, beat: k, heartRate: rate) })
}
check("a rate outside 55-68 is held to it", EcgTrace.period(heartRate: 200) == 60 / 68.0
      && EcgTrace.period(heartRate: 10) == 60 / 55.0 && EcgTrace.period(heartRate: .nan) == 1)

// every wave meets the baseline level and flat: no step, and no corner
let edges: [EcgLandmark] = [.pOnset, .pEnd, .qrsOnset, .j, .tEnd]
check("each wave leaves and meets the baseline with no step and no corner",
      edges.allSatisfy { l in [-1e-4, -1e-7, 1e-7, 1e-4].allSatisfy { abs(mv(at(l) + $0)) < 1e-5 } })
let steepestAnywhere = zip(fine, fine.dropFirst()).map { abs($0.1.v - $0.0.v) / dt }.max()!
let run = (0...30000).map { EcgTrace.millivolts(at: -0.5 + Double($0) * dt, heartRate: 68) }
check("a run has no jump anywhere (sampled every 0.1 ms)",
      zip(run, run.dropFirst()).allSatisfy { abs($1 - $0) <= steepestAnywhere * dt * 1.001 }, "\(steepestAnywhere)")
check("one beat alone: the baseline either side of it",
      mv(-0.3) == 0 && mv(0) == 0 && mv(EcgTrace.duration) == 0 && mv(0.9) == 0 && mv(.nan) == 0)

// MARK: sampling

let big = EcgTrace.points(from: -0.2, to: 1.4, heartRate: 75, width: 320, height: 90)
let again = EcgTrace.points(from: -0.2, to: 1.4, heartRate: 75, width: 320, height: 90)
check("sampling is deterministic: the same call, the same points", big.points == again.points && big.paper == again.paper)
check("in time order, from the window's start to its end exactly",
      zip(big.points, big.points.dropFirst()).allSatisfy { $0.t < $1.t }
      && big.points.first?.t == -0.2 && big.points.last?.t == 1.4)
check("a point every millisecond or less", zip(big.points, big.points.dropFirst()).allSatisfy { $1.t - $0.t <= 0.001 + 1e-12 })
check("evenly spaced: nothing but the grid", zip(big.points, big.points.dropFirst()).allSatisfy { near($1.t - $0.t, 0.001, 1e-9) })
let bigTop = big.points.min { $0.y < $1.y }!
check("each R drawn within 0.2% of its height at 1 ms",
      (big.paper.baseline - bigTop.y) / (10 * big.paper.scale) > 0.998, "\(bigTop)")
// windows of the same length, starting anywhere, pair point for point
let paper = EcgPaper(scale: 3)
for (a, b, rate) in [(-0.1, -0.1005, nil), (0.0, 0.0004, 60.0), (0.0, 1.0, 68.0), (-0.2, 0.37, 55.0)] as [(Double, Double, Double?)] {
    let len = rate == nil ? 0.8 : 3.0
    let one = EcgTrace.points(from: a, to: a + len, heartRate: rate, on: paper)
    let two = EcgTrace.points(from: b, to: b + len, heartRate: rate, on: paper)
    check("a window shifted by \(b - a) s pairs point for point (\(rate.map { "\(Int($0)) a minute" } ?? "one beat"))",
          one.count == two.count && zip(one, two).allSatisfy { near($0.t - a, $1.t - b, 1e-9) }, "\(one.count) \(two.count)")
}
// no step, however small, crashes or runs out of memory
let tiny = EcgTrace.points(from: 0, to: 1, on: paper, step: 1e-300)
let hour = EcgTrace.points(from: 0, to: 3600, heartRate: 60, on: paper, step: 1e-7)
check("a tiny step is held to 0.01 ms, and an hour to \(EcgTrace.maxPoints) points",
      tiny.count == 100_001 && hour.count == EcgTrace.maxPoints + 1 && hour.last?.t == 3600, "\(tiny.count) \(hour.count)")
check("a step of 0, below 0, or not a number still draws",
      [0, -1, Double.nan, .infinity].allSatisfy { !EcgTrace.points(from: 0, to: 1, on: paper, step: $0).isEmpty })
let small = EcgTrace.points(from: -0.2, to: 1.4, heartRate: 75, width: 34, height: 18)
check("two sizes give the same times, so they pair point for point", small.points.map(\.t) == big.points.map(\.t))
check("and the same drawing: each small point is the big one, scaled",
      zip(big.points, small.points).allSatisfy { b, s in
          near((b.x - big.paper.left) / big.paper.scale, (s.x - small.paper.left) / small.paper.scale, 1e-9)
          && near((b.y - big.paper.baseline) / big.paper.scale, (s.y - small.paper.baseline) / small.paper.scale, 1e-9) })
let one = EcgTrace.points(from: -0.1, to: 0.7, width: 160, height: 60)
check("one beat: its R is drawn at R's place, the highest point",
      one.points.min { $0.y < $1.y }.map { near($0.t, at(.r), 0.0006) && near($0.y, one.paper.y(1), 0.002 * 10 * one.paper.scale) } ?? false)
check("no points for an empty or reversed window", EcgTrace.points(from: 1, to: 1, on: EcgPaper(scale: 1)).isEmpty
      && EcgTrace.points(from: 1, to: 0, on: EcgPaper(scale: 1)).isEmpty)

// MARK: the paper

let mm = EcgPaper(scale: 1)
check("1 s is 25 mm across", near(mm.x(1) - mm.x(0), 25) && near(mm.x(0.2) - mm.x(0), 5))
check("1 mV is 10 mm up (y grows down)", near(mm.y(0) - mm.y(1), 10) && near(mm.y(0) - mm.y(-0.5), -5))
for (w, h) in [(320.0, 90.0), (34.0, 18.0), (100.0, 400.0)] {
    let fit = EcgTrace.points(from: -0.1, to: 0.7, width: w, height: h)
    let p = fit.paper
    check("\(Int(w)) x \(Int(h)): still paper scale, 2.5 times as far across a second as up a millivolt",
          near((p.x(1) - p.x(0)) / (p.y(0) - p.y(1)), 2.5, 1e-12))
    let xs = fit.points.map(\.x), ys = fit.points.map(\.y)
    let inside = xs.min()! >= -1e-9 && xs.max()! <= w + 1e-9 && ys.min()! >= -1e-9 && ys.max()! <= h + 1e-9
    let fills = near(xs.max()! - xs.min()!, w, 1e-9) || near(ys.max()! - ys.min()!, h, 0.002 * h)
    check("\(Int(w)) x \(Int(h)): inside the box and filling it one way", inside && fills, "\(p)")
}
check("an empty box gives scale 0", EcgPaper.fitting(from: 0, to: 1, width: 0, height: 10).scale == 0
      && EcgPaper.fitting(from: 0, to: 1, width: 100, height: 4, lineWidth: 4).scale == 0)
for (w, h) in [(176.0, 36.0), (34.0, 18.0)] {
    let fit = EcgTrace.points(from: -0.1, to: 0.7, width: w, height: h, lineWidth: 4)
    let xs = fit.points.map(\.x), ys = fit.points.map(\.y)
    check("\(Int(w)) x \(Int(h)), a 4 pt line: half the line clear of every edge",
          xs.min()! >= 2 - 1e-9 && xs.max()! <= w - 2 + 1e-9 && ys.min()! >= 2 - 1e-9 && ys.max()! <= h - 2 + 1e-9, "\(fit.paper)")
}

print(failures.isEmpty ? "\nALL ECG TRACE TESTS PASS" : "\n\(failures.count) ECG TRACE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
