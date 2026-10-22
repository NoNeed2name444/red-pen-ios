// The million map's proof tour (plan 4f, D5), on Linux: the interface the
// map view fills and reads (T1); the phases in order with their lengths
// (T2); what each phase asks of the map: the level, the fade, the choice and
// the frames measured (T3); a path that is continuous and eased, with the
// cut to the whole map at far its one jump, the hub on screen all the way
// in, and the same path for the same time (T4); the frame rate's median, 5th
// percentile and 1% low and the stages' times, on frames with known answers
// (T5); the swap after the half turn (T6); and the summary, a line per
// phase and the GPU memory's peak (T7).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

// A million-sized map (the synthetic million's radius and centre), framed as
// the map view frames it: from the usual angle, inside the glass.
func makeMap(width: Float = 393, height: Float = 852, hub: Int? = 4242) -> GraphPerfTourMap {
    let centre = SIMD3<Float>(25.5, -7.4, 24.7)
    let radius: Float = 687.6
    var from = GraphPerfCamera()
    from.yaw = 0.55
    from.pitch = 0.32
    let whole = from.framing(centre: centre, radius: radius, width: width, height: height,
                             insets: (top: 110, left: 0, bottom: 90, right: 0), fill: 0.9)
    // a well-linked note near the front, a little right of the middle
    let at: SIMD3<Float>? = hub == nil ? nil : centre + whole.back * (radius * 0.7) + whole.right * 40
    return GraphPerfTourMap(centre: centre, radius: radius, width: width, height: height, whole: whole, hub: hub,
                            hubPosition: at)
}

let phone = makeMap()
let tablet = makeMap(width: 1194, height: 834)
let names = ["warm", "measure", "front", "turn", "back", "near", "chosen", "far",
             "compare high fade off", "compare high fade on", "compare smooth fade off", "compare smooth fade on",
             "compare saver fade off", "compare saver fade on"]

// MARK: - T1 the interface

let report = GraphPerfFrameReport(interval: 1.0 / 60, cpu: 0.002, gpu: 0.004, drawCalls: 9, instances: 1_000,
                                  gpuMemory: 1_000_000, ramping: 0, shells: SIMD3(1, 2, 3))
let plain = GraphPerfTourStep(camera: phone.whole, phase: "front")
check("T1 a step keeps the user's level, has the fade on, chooses nothing and is not measured unless asked",
      plain.tier == nil && plain.fade && plain.select == nil && !plain.measuring)
let full = GraphPerfTourStep(camera: phone.whole, phase: "compare saver fade off", tier: .saver, fade: false, select: 7,
                             measuring: true)
check("T1 a step carries a pose, a phase, a level, the fade, a choice and whether it counts",
      full.camera == phone.whole && full.phase == "compare saver fade off" && full.tier == .saver && !full.fade
      && full.select == 7 && full.measuring && full != plain)
var changed = report
changed.ramping = 3
check("T1 a frame report carries interval, CPU, GPU, draws, instances, GPU memory, ramping and shells",
      report.interval == 1.0 / 60 && report.cpu == 0.002 && report.gpu == 0.004 && report.drawCalls == 9
      && report.instances == 1_000 && report.gpuMemory == 1_000_000 && report.shells == SIMD3(1, 2, 3)
      && changed != report)
var edited = phone
edited.hub = nil
edited.hubPosition = nil
edited.width = 10
check("T1 the map's fields are the map view's to fill", edited.hub == nil && edited.width == 10 && phone.hub == 4242)
let fresh = GraphPerfTour(map: phone)
check("T1 a new tour has nothing to say yet, and its first step is the whole view",
      fresh.summary.isEmpty && fresh.step(at: 0)?.camera == phone.whole && fresh.step(at: 0)?.phase == "warm")

// MARK: - T2 the phases, in order, and how long each lasts

func sampled(_ tour: GraphPerfTour, every dt: Double) -> [(t: Double, step: GraphPerfTourStep)] {
    var out: [(Double, GraphPerfTourStep)] = []
    var k = 0
    while true {
        let t = Double(k) * dt
        guard let s = tour.step(at: t) else { break }
        out.append((t, s))
        k += 1
    }
    return out
}

let tour = GraphPerfTour(map: phone)
let fine = sampled(tour, every: 0.001)
var order: [String] = []
var first: [String: Double] = [:]
var last: [String: Double] = [:]
for (t, s) in fine {
    if order.last != s.phase { order.append(s.phase) }
    if first[s.phase] == nil { first[s.phase] = t }
    last[s.phase] = t
}
check("T2 the phases, in order: warm, measure, front, turn, back, near, chosen, far, then each level with the fade off and on",
      order == names, order.joined(separator: ", "))
let expected: [String: Double] = ["warm": 3, "measure": 11, "front": 8, "turn": 1.2, "back": 8, "near": 13, "chosen": 8,
                                  "far": 8]
var lengths: [String] = []
var lengthsOK = true
for name in names {
    let length = (last[name] ?? 0) - (first[name] ?? 0) + 0.001
    let want = expected[name] ?? 4
    if !near(length, want, 0.0011) { lengthsOK = false }
    lengths.append(name + " " + String(format: "%.3f", length))
}
check("T2 warm 3 s, measure 11 s (10 measured, 1 s to rest), stills 8 s, turn 1.2 s, near 13 s, each comparison 4 s",
      lengthsOK, lengths.joined(separator: "; "))
check("T2 the schedule says the same: 84.2 s in all", near(GraphPerfTour.duration, 84.2, 1e-9)
      && GraphPerfTour.schedule.map(\.name) == names)
check("T2 nil once it is done, and not a moment before",
      tour.step(at: GraphPerfTour.duration) == nil && tour.step(at: GraphPerfTour.duration - 0.0005) != nil
      && tour.step(at: 1e9) == nil && tour.step(at: .infinity) == nil)
check("T2 a time before the start is the start", tour.step(at: -5) == tour.step(at: 0) && tour.step(at: .nan) == tour.step(at: 0))

// MARK: - T3 what each phase asks

var measured: [String: Double] = [:]
var tiers: [String: Set<String>] = [:]
var fades: [String: Set<Bool>] = [:]
var chosen: [String: Set<String>] = [:]
for (_, s) in fine {
    if s.measuring { measured[s.phase, default: 0] += 0.001 }
    tiers[s.phase, default: []].insert(s.tier.map { GraphPerfTour.levelName($0) } ?? "user's")
    fades[s.phase, default: []].insert(s.fade)
    chosen[s.phase, default: []].insert(s.select.map(String.init) ?? "none")
}
let measuredWant: [String: Double] = ["warm": 0, "measure": 10, "front": 8, "turn": 1.2, "back": 8, "near": 10, "chosen": 8,
                                      "far": 8]
var measuredOK = true
var measuredWords: [String] = []
for name in names {
    let want = measuredWant[name] ?? 3
    if !near(measured[name] ?? 0, want, 0.0015) { measuredOK = false }
    measuredWords.append(name + " " + String(format: "%.3f", measured[name] ?? 0))
}
check("T3 measured: none of warm, the measure's 10 s, the stills and the turn whole, near after its 3 s flight, "
      + "each comparison after its 1 s to settle", measuredOK, measuredWords.joined(separator: "; "))
let before = names.prefix(8)
check("T3 until the comparison the user's level holds, with the fade on",
      before.allSatisfy { tiers[$0] == ["user's"] && fades[$0] == [true] })
let compared = names.dropFirst(8).map { (tiers[$0] ?? [], fades[$0] ?? []) }
check("T3 the comparison: high, smooth, saver, each with the fade off and then on",
      compared.map { $0.0 } == [["high"], ["high"], ["smooth"], ["smooth"], ["saver"], ["saver"]]
      && compared.map { $0.1 } == [[false], [true], [false], [true], [false], [true]])
check("T3 the hub is chosen in chosen only; nothing is chosen elsewhere",
      chosen["chosen"] == ["4242"] && names.filter { $0 != "chosen" }.allSatisfy { chosen[$0] == ["none"] })
let measuredInMeasure = fine.filter { $0.step.phase == "measure" && $0.step.measuring }.map(\.t)
check("T3 the measure counts from its first frame to 10 s in, not the easing to rest after",
      near(measuredInMeasure.first ?? 0, 3, 1e-9) && near(measuredInMeasure.last ?? 0, 12.999, 1e-9))
let noHub = GraphPerfTour(map: makeMap(hub: nil))
let noHubSteps = sampled(noHub, every: 0.01)
check("T3 with no hub nothing is chosen, and the flight goes to the map's centre",
      noHubSteps.allSatisfy { $0.step.select == nil }
      && noHubSteps.last { $0.step.phase == "chosen" }?.step.camera.target == makeMap(hub: nil).centre)

// MARK: - T4 the path: continuous, eased, one cut, the same for the same time

// Each sample's change (radians of turn, log of the distance, the target in
// map radii) and its speed's change: a jump moves far in one sample; an
// unease (a speed that changes at once) shows as a large acceleration.
struct Motion {
    var jumps: [(what: String, at: Double)] = []
    var speed = SIMD3<Double>(0, 0, 0)
    var accel = SIMD3<Double>(0, 0, 0)
}

func motion(_ map: GraphPerfTourMap, every dt: Double) -> Motion {
    let steps = sampled(GraphPerfTour(map: map), every: dt)
    var out = Motion()
    var lastV: SIMD3<Double>?
    for k in 1..<steps.count {
        let a = steps[k - 1].step.camera, b = steps[k].step.camera
        let turn = Double(abs(GraphPerfCamera.wrap(b.yaw - a.yaw)))
        let zoom = Double(abs(log(b.distance) - log(a.distance)))
        let d = b.target - a.target
        let slide = Double((d * d).sum().squareRoot() / map.radius)
        let tip = Double(abs(b.pitch - a.pitch)) + Double(abs(b.fovY - a.fovY))
        let v = SIMD3(turn, zoom, slide) / dt
        if turn > 0.02 || zoom > 0.02 || slide > 0.005 || tip > 1e-4 {
            out.jumps.append((steps[k - 1].step.phase + " to " + steps[k].step.phase, steps[k].t))
            lastV = nil
            continue
        }
        out.speed = SIMD3(max(out.speed.x, v.x), max(out.speed.y, v.y), max(out.speed.z, v.z))
        if let lastV {
            let dv = v - lastV
            let accel = SIMD3(abs(dv.x), abs(dv.y), abs(dv.z)) / dt
            out.accel = SIMD3(max(out.accel.x, accel.x), max(out.accel.y, accel.y), max(out.accel.z, accel.z))
        }
        lastV = v
    }
    return out
}

for (label, map) in [("a phone", phone), ("a tablet on its side", tablet)] {
    let m = motion(map, every: 1.0 / 600)
    check("T4 " + label + ": one jump, the cut from chosen to the whole map at far",
          m.jumps.count == 1 && m.jumps.first?.what == "chosen to far" && abs((m.jumps.first?.at ?? 0) - 52.2) < 0.002,
          m.jumps.map { $0.what + " at " + String(format: "%.4f", $0.at) }.joined(separator: "; "))
    check("T4 " + label + ": eased, no speed changes at once (under 30 rad/s², 30 /s² in the log of the distance, "
          + "10 radii/s²)", m.accel.x < 30 && m.accel.y < 30 && m.accel.z < 10, "\(m.accel)")
    check("T4 " + label + ": the fastest is the half turn, about 225° a second at its peak",
          m.speed.x > 3.8 && m.speed.x < 4.0, "\(m.speed)")
}

func pose(_ tour: GraphPerfTour, _ t: Double) -> GraphPerfCamera { tour.step(at: t)!.camera }
func sameView(_ a: GraphPerfCamera, _ b: GraphPerfCamera, _ tolerance: Float = 1e-4) -> Bool {
    let d = a.target - b.target
    return abs(GraphPerfCamera.wrap(a.yaw - b.yaw)) < tolerance && abs(a.pitch - b.pitch) < tolerance
        && abs(a.distance / b.distance - 1) < tolerance && (d * d).sum().squareRoot() < tolerance * max(a.distance, 1)
        && a.fovY == b.fovY
}

let wholeView = phone.whole
check("T4 the measure turns one whole turn in all: front is the view the tour began with",
      sameView(pose(tour, 14), wholeView) && sameView(pose(tour, 21.99), wholeView))
let steadyTurns = stride(from: 3.0, to: 13.0, by: 0.25).map { t -> Double in
    Double(GraphPerfCamera.wrap(pose(tour, t + 0.01).yaw - pose(tour, t).yaw)) / 0.01
}
check("T4 the measure's turn is steady all its 10 s",
      steadyTurns.allSatisfy { abs($0 - GraphPerfTour.openingSpeed) < 0.002 },
      "\(steadyTurns.min() ?? 0)...\(steadyTurns.max() ?? 0) vs \(GraphPerfTour.openingSpeed)")
let zoomed = stride(from: 3.0, through: 13.0, by: 0.01).map { pose(tour, $0).distance }
let nearestZoom = zoomed.min() ?? 0
let dips = zip(zoomed.indices.dropFirst().dropLast(), zip(zoomed.dropFirst(2), zoomed.dropLast(2)))
    .filter { zoomed[$0.0] < $0.1.0 && zoomed[$0.0] < $0.1.1 }.count
check("T4 the measure zooms in twice, to about the map's edge (its radius from the target), and out to the whole view",
      dips == 2 && abs(nearestZoom / phone.radius - 1) < 0.01 && abs(zoomed.last! / wholeView.distance - 1) < 1e-4,
      "dips \(dips), nearest \(nearestZoom)")
check("T4 the turn: half a turn in 1.2 s, then the back still holds it",
      abs(abs(GraphPerfCamera.wrap(pose(tour, 23.2).yaw - pose(tour, 22).yaw)) - Float.pi) < 1e-3
      && pose(tour, 23.2) == pose(tour, 31.19))
let stills = [("front", 14.0, 22.0), ("back", 23.2, 31.2), ("near", 34.2, 44.2), ("chosen", 44.2, 52.2), ("far", 52.2, 60.2)]
check("T4 a still does not move", stills.allSatisfy { s in
    stride(from: s.1 + 0.001, to: s.2 - 0.001, by: 0.1).allSatisfy { pose(tour, $0) == pose(tour, s.1 + 0.001) }
})
let flown = pose(tour, 44.2)
let hubAt = phone.hubPosition!
check("T4 near ends looking at the hub from the front, close (a ball of 0.75% of the map's radius framed)",
      flown.target == hubAt && abs(GraphPerfCamera.wrap(flown.yaw - wholeView.yaw)) < 1e-3
      && flown.distance < phone.radius * 0.05 && flown.distance > phone.radius * 0.01, "\(flown)")
var hubOnScreen = true
var hubWorst: Float = 0
for t in stride(from: 31.2, to: 44.2, by: 0.005) {
    let at = pose(tour, t).project(hubAt, width: phone.width, height: phone.height)
    let off = max(abs(at.x - phone.width / 2) / (phone.width / 2), abs(at.y - phone.height / 2) / (phone.height / 2))
    hubWorst = max(hubWorst, off)
    if at.depth <= 0 || off > 0.9 { hubOnScreen = false }
}
check("T4 the hub stays on screen all the way in", hubOnScreen, "worst \(hubWorst) of the way to an edge")
check("T4 far is the whole map's framing exactly", pose(tour, 52.21) == wholeView && pose(tour, 60.19) == wholeView)
// the off run's pose x seconds into its turn, and the on run's x seconds before its end
func turned(_ name: String, _ at: Double) -> Float {
    let k = GraphPerfTour.schedule.firstIndex { $0.name == name }!
    return GraphPerfCamera.wrap(pose(tour, GraphPerfTour.starts[k] + at).yaw - wholeView.yaw)
}
let sameArcs = GraphPerfTour.levels.allSatisfy { level in
    stride(from: 0.0, through: 2.99, by: 0.01).allSatisfy { x in
        abs(turned(GraphPerfTour.compareName(level, fade: false), 1.005 + x)
            - turned(GraphPerfTour.compareName(level, fade: true), 3.995 - x)) < 1e-4
    }
}
let swept = turned("compare high fade off", 3.999)
check("T4 a level's off and on runs turn over the same 45° arc, one each way",
      sameArcs && abs(swept - Float.pi / 4) < 1e-3 && abs(turned("compare high fade off", 1.0)) < 1e-6, "\(swept)")
let other = GraphPerfTour(map: phone)
var times: [Double] = []
var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
for _ in 0..<2_000 {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    times.append(Double(seed >> 11) / Double(1 << 53) * (GraphPerfTour.duration + 2) - 1)
}
for t in times.prefix(500) { other.record(report, step: other.step(at: t) ?? plain) }
check("T4 the same time gives the same step: twice, on another tour, and whatever was recorded",
      times.allSatisfy { tour.step(at: $0) == tour.step(at: $0) && tour.step(at: $0) == other.step(at: $0) })

// MARK: - T5 the statistics, on frames with known answers

func intervals(_ runs: [(Int, Double)]) -> [Double] { runs.flatMap { Array(repeating: $0.1, count: $0.0) } }
let r1 = GraphPerfTour.rates(intervals([(90, 1.0 / 60), (10, 1.0 / 20)]))
check("T5 90 frames at 60 and 10 at 20: median 60, p5 20, 1% low 20",
      near(r1.median, 60, 1e-9) && near(r1.p5, 20, 1e-9) && near(r1.low, 20, 1e-9), "\(r1)")
var thousand = intervals([(900, 1.0 / 120), (80, 1.0 / 60), (20, 1.0 / 30)])
var shuffler: UInt64 = 42
for k in stride(from: thousand.count - 1, to: 0, by: -1) {
    shuffler = shuffler &* 6_364_136_223_846_793_005 &+ 1
    thousand.swapAt(k, Int(shuffler >> 33) % (k + 1))
}
let r2 = GraphPerfTour.rates(thousand)
check("T5 1,000 frames, 900 at 120, 80 at 60, 20 at 30, in any order: median 120, p5 60, 1% low 30",
      near(r2.median, 120, 1e-9) && near(r2.p5, 60, 1e-9) && near(r2.low, 30, 1e-9), "\(r2)")
let r3 = GraphPerfTour.rates(intervals([(18, 0.01), (1, 0.02), (1, 0.05)]))
check("T5 nearest rank on 20 frames: the 95th percentile interval is the 19th shortest (p5 50), the 99th the longest (1% low 20), median 100",
      near(r3.median, 100, 1e-9) && near(r3.p5, 50, 1e-9) && near(r3.low, 20, 1e-9), "\(r3)")
let r4 = GraphPerfTour.rates([0.01, 0.02, 0.03, 0.04])
check("T5 an even count's median is the mean of the middle two intervals (0.025 s: 40 fps)", near(r4.median, 40, 1e-9),
      "\(r4)")
let r5 = GraphPerfTour.rates([0, -1, .nan, .infinity, 0.02])
check("T5 intervals that are not positive and finite are left out", near(r5.median, 50, 1e-9) && near(r5.low, 50, 1e-9))
let r6 = GraphPerfTour.rates([])
check("T5 no frames: zeros", r6.median == 0 && r6.p5 == 0 && r6.low == 0)
func frame(_ interval: Double, cpu: Double = 0.002, gpu: Double = 0.004, draws: Int = 10, instances: Int = 1_000,
           memory: Int = 100_000_000, ramping: Int = 0, shells: SIMD3<Int32> = SIMD3(1, 2, 3)) -> GraphPerfFrameReport {
    GraphPerfFrameReport(interval: interval, cpu: cpu, gpu: gpu, drawCalls: draws, instances: instances, gpuMemory: memory,
                         ramping: ramping, shells: shells)
}
let stages = (1...100).map { k in
    frame(1.0 / 60, cpu: Double(k) / 10_000, gpu: k <= 20 ? 0 : Double(k) / 1_000, draws: k % 2 == 0 ? 12 : 8,
          instances: k * 100, shells: SIMD3(Int32(k), Int32(2 * k), 5))
}
let n = GraphPerfTour.numbers(stages)
check("T5 the CPU's median and 95th percentile (0.1 to 10 ms: 5.05 and 9.5 ms)",
      near(n.cpu, 0.00505, 1e-12) && near(n.cpuP95, 0.0095, 1e-12), "\(n.cpu) \(n.cpuP95)")
check("T5 the GPU's, of the frames that report it (21 to 100 ms: 60.5 and 96 ms)",
      near(n.gpu ?? 0, 0.0605, 1e-12) && near(n.gpuP95 ?? 0, 0.096, 1e-12), "\(String(describing: n.gpu))")
check("T5 the medians of draws, instances and shells", n.drawCalls == 10 && n.instances == 5_050
      && n.shells == SIMD3(51, 101, 5), "\(n.drawCalls) \(n.instances) \(n.shells)")
let silent = GraphPerfTour.numbers([frame(1.0 / 60, gpu: 0), frame(1.0 / 60, gpu: 0)])
check("T5 a GPU that reports nothing says so", silent.gpu == nil && silent.words.contains("gpu not reported"),
      silent.words)

// MARK: - T6 the swap: from the turn's end until nothing ramps

func turnLine(_ tour: GraphPerfTour) -> String {
    tour.summary.split(separator: "\n").first { $0.hasPrefix("turn:") }.map(String.init) ?? ""
}
func recordRun(_ tour: GraphPerfTour, _ phase: String, _ frames: [GraphPerfFrameReport], measuring: Bool = true) {
    for f in frames { tour.record(f, step: GraphPerfTourStep(camera: phone.whole, phase: phase, measuring: measuring)) }
}
let swapTour = GraphPerfTour(map: phone)
recordRun(swapTour, "turn", Array(repeating: frame(1.0 / 60, ramping: 9), count: 72))
recordRun(swapTour, "back", [6, 3, 1].map { frame(1.0 / 60, ramping: $0) })
check("T6 while cells still ramp after the turn the swap is pending", turnLine(swapTour).hasPrefix("turn: swap pending"),
      turnLine(swapTour))
recordRun(swapTour, "back", [0, 0, 2].map { frame(1.0 / 60, ramping: $0) })
check("T6 four frames of 1/60 s after the turn's last, the first with nothing ramping: a 67 ms swap",
      turnLine(swapTour).hasPrefix("turn: swap 67 ms \u{00B7} "), turnLine(swapTour))
let quick = GraphPerfTour(map: phone)
recordRun(quick, "turn", [frame(1.0 / 60, ramping: 4), frame(1.0 / 60, ramping: 0)])
recordRun(quick, "back", [frame(0.008, ramping: 0)])
check("T6 timed from the turn's last frame: nothing ramping at the first frame after it is one frame (8 ms)",
      turnLine(quick).hasPrefix("turn: swap 8 ms"), turnLine(quick))
let slowSwap = GraphPerfTour(map: phone)
recordRun(slowSwap, "turn", [frame(1.0 / 60, ramping: 9)])
recordRun(slowSwap, "back", Array(repeating: frame(1.0 / 60, ramping: 5), count: 480))
recordRun(slowSwap, "near", [frame(1.0 / 60)], measuring: false)
check("T6 a back still that ends with cells ramping says how long it was and how many were left",
      turnLine(slowSwap).hasPrefix("turn: swap over 8,000 ms (5 cells still ramping) \u{00B7} "), turnLine(slowSwap))

// MARK: - T7 the summary: a line per phase, the GPU memory's peak

// a whole tour at 60 frames a second: the comparisons' fade off at 40, a
// moment of 250 MB in near, cells ramping for three frames after the turn
let run = GraphPerfTour(map: phone)
var k = 0
var midway = ""
var rampAfterTurn = 0
var counted: [String: (all: Int, measured: Int)] = [:]
while let s = run.step(at: Double(k) / 60) {
    counted[s.phase, default: (0, 0)].all += 1
    if s.measuring { counted[s.phase, default: (0, 0)].measured += 1 }
    let off = s.phase.hasPrefix("compare") && !s.fade
    var f = frame(off ? 1.0 / 40 : 1.0 / 60, ramping: s.phase == "turn" ? 7 : 0, shells: SIMD3(812, 1_940, 3_377))
    if s.phase == "back" && rampAfterTurn < 3 {
        f.ramping = 3 - rampAfterTurn
        rampAfterTurn += 1
    }
    if s.phase == "near" && s.measuring && k % 97 == 0 { f.gpuMemory = 250_000_000 }
    run.record(f, step: s)
    if s.phase == "measure" && midway.isEmpty && k == 400 { midway = run.summary }
    k += 1
}
let lines = run.summary.split(separator: "\n").map(String.init)
check("T7 one line per phase, in order, then done", lines.map { String($0.prefix { $0 != ":" }) } == names + ["done"],
      lines.map { String($0.prefix(24)) }.joined(separator: " | "))
check("T7 warm: its frames, not measured", lines.first == "warm: 180 frames in 3.0 s, not measured", lines.first ?? "")
let measureLine = "measure: 60.0 fps (p5 60.0, 1% low 60.0) \u{00B7} cpu 2.0 (p95 2.0) \u{00B7} gpu 4.0 (p95 4.0) ms "
    + "\u{00B7} 10 draws \u{00B7} 1,000 instances \u{00B7} cells 812/1,940/3,377 \u{00B7} GPU 100.0 MB \u{00B7} 600 of 660 frames"
check("T7 measure: rate, its 5th percentile and 1% low, CPU and GPU, draws, instances, cells, GPU memory, frames",
      lines.count > 1 && lines[1] == measureLine, lines.count > 1 ? lines[1] : "")
check("T7 a still counts all its frames", lines.count > 2 && lines[2].hasSuffix("\u{00B7} 480 frames"),
      lines.count > 2 ? lines[2] : "")
check("T7 the turn's line has the swap (4 frames of 1/60 s: 67 ms)", lines.count > 3 && lines[3].hasPrefix("turn: swap 67 ms \u{00B7} 60.0 fps"),
      lines.count > 3 ? lines[3] : "")
func frameWords(_ phase: String) -> String {
    let c = counted[phase] ?? (0, 0)
    return GraphPerfTour.grouped(c.measured) + (c.measured == c.all ? "" : " of " + GraphPerfTour.grouped(c.all)) + " frames"
}
check("T7 near and chosen name the hub, near counting only after its flight (about 600 of 780 frames)",
      lines.count > 6 && lines[5].hasPrefix("near: hub 4242 \u{00B7} 60.0 fps") && lines[5].hasSuffix(frameWords("near"))
      && abs((counted["near"]?.measured ?? 0) - 600) <= 1 && abs((counted["near"]?.all ?? 0) - 780) <= 1
      && lines[6].hasPrefix("chosen: hub 4242 \u{00B7} "), lines.count > 6 ? lines[5] + " / " + lines[6] : "")
check("T7 a phase's own GPU memory peak", lines.count > 6 && lines[5].contains("GPU 250.0 MB")
      && lines[6].contains("GPU 100.0 MB"))
let offLine = lines.first { $0.hasPrefix("compare saver fade off: ") } ?? ""
let onLine = lines.first { $0.hasPrefix("compare saver fade on: ") } ?? ""
check("T7 each comparison has its own numbers: the fade off at 40, on at 60",
      offLine.hasPrefix("compare saver fade off: 40.0 fps (p5 40.0, 1% low 40.0)")
      && onLine.hasPrefix("compare saver fade on: 60.0 fps (p5 60.0, 1% low 60.0)")
      && offLine.hasSuffix(frameWords("compare saver fade off")) && onLine.hasSuffix(frameWords("compare saver fade on")),
      offLine + " / " + onLine)
check("T7 done: the time, the frames and the whole tour's GPU memory peak",
      lines.last.map { $0.hasPrefix("done: ") && $0.hasSuffix(" frames \u{00B7} GPU memory peak 250.0 MB") } ?? false,
      lines.last ?? "")
check("T7 while a phase runs, its line counts frames so far, and there is no done line",
      midway == "warm: 180 frames in 3.0 s, not measured\nmeasure: 221 frames so far", midway)
let unknown = GraphPerfTour(map: phone)
unknown.record(report, step: GraphPerfTourStep(camera: phone.whole, phase: "somewhere else", measuring: true))
check("T7 a frame of no phase of the tour is left out", unknown.summary.isEmpty)
let settled = run.summary.split(separator: "\n")
recordRun(run, "warm", [frame(1.0 / 60)], measuring: false)
let resettled = run.summary.split(separator: "\n")
check("T7 a late frame changes its own phase's line (and the totals), no other",
      resettled.first == "warm: 181 frames in 3.0 s, not measured" && resettled.dropFirst().dropLast() == settled.dropFirst().dropLast()
      && resettled.last != settled.last, resettled.first.map(String.init) ?? "")
check("T7 numbers in words, the same in every locale",
      GraphPerfTour.tenths(59.94) == "59.9" && GraphPerfTour.tenths(59.95) == "60.0" && GraphPerfTour.millis(0.00214) == "2.1"
      && GraphPerfTour.grouped(1_234_567) == "1,234,567" && GraphPerfTour.grouped(-1_000) == "-1,000"
      && GraphPerfTour.megabytes(412_700_000) == "412.7 MB" && GraphPerfTour.wholeMillis(1.3404) == "1,340"
      && GraphPerfTour.tenths(.nan) == "0.0")

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
