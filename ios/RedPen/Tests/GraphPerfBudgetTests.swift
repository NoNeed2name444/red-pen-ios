// The million map's frame budget, on Linux: the rate is the screen's own
// (B1); a device that cannot keep it cuts detail, never the rate, and
// settles under its share of the frame (B2); a fast one opens detail again,
// slowly and without see-sawing (B3); missed refreshes count (B4); the
// streaming budget follows the room left (B5); the depth band is pulled in
// once the split has coarsened, and given back first (B6, plan 4f); the
// Graphics setting no longer caps the rate (B7); a stall is not load, while
// detail lost comes back within seconds (B8); the stage that takes the time
// pays for it, bundles before notes (B9); the exposure lands the bright
// light short of white, follows a change without pumping, and counts the
// saturated share (B10); a missed refresh opens nothing (B11); and the
// GPU's stages from the wall clock where its own times read about 0 (B12).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: - B1 the screen's rate

let pro = GraphPerfFrameBudget(screenFPS: 120)
check("B1 ProMotion: 120 a second, 8.3 ms a refresh", pro.screenFPS == 120 && abs(pro.period - 1.0 / 120) < 1e-9)
check("B1 the map's share of a 120 Hz refresh is 6.25 ms", abs(pro.target - 0.75 / 120) < 1e-9)
check("B1 a 60 Hz screen: 60", GraphPerfFrameBudget(screenFPS: 60).screenFPS == 60)
check("B1 a 144 Hz screen is not held to 120", GraphPerfFrameBudget(screenFPS: 144).screenFPS == 144)
check("B1 never under 30 (an unknown screen reads 0)", GraphPerfFrameBudget(screenFPS: 0).screenFPS == 30)
check("B1 the tier sets only where detail starts, saver coarsest",
      GraphPerfFrameBudget.startingSplit(.saver) > GraphPerfFrameBudget.startingSplit(.smooth)
      && GraphPerfFrameBudget.startingSplit(.smooth) > GraphPerfFrameBudget.startingSplit(.high)
      && GraphPerfFrameBudget(screenFPS: 120, tier: .saver).screenFPS == 120)

// MARK: - a device model: a frame costs a fixed part plus detail, which
// grows with the area cells open over (1 / split squared)

func run(_ budget: inout GraphPerfFrameBudget, speed: Double, frames: Int) -> [Double] {
    var costs: [Double] = []
    for _ in 0..<frames {
        let split = Double(budget.split)
        let gpu = (0.0008 + 2.4 / (split * split)) / speed
        budget.record(cpu: 0.0009, gpu: gpu, interval: 1.0 / 120)
        costs.append(max(gpu, 0.0009))
    }
    return costs
}

// MARK: - B2 a slow device cuts detail and keeps the rate

var slow = GraphPerfFrameBudget(screenFPS: 120)
let slowCosts = run(&slow, speed: 0.15, frames: 600)
let settled = slowCosts.suffix(100)
check("B2 a slow device opens cells later (summaries sooner)", slow.split > GraphPerfFrameBudget.startingSplit(.high),
      "split \(slow.split)")
check("B2 and then fits its frames in the share of a 120 Hz refresh",
      settled.allSatisfy { $0 <= slow.target * 1.0001 }, "worst \(settled.max()! * 1000) ms")
check("B2 the rate it asks for is still the screen's", slow.screenFPS == 120)
var fast = GraphPerfFrameBudget(screenFPS: 120)
_ = run(&fast, speed: 3, frames: 3_000)
check("B2 a fast device keeps more detail than a slow one", fast.split < slow.split, "\(fast.split) vs \(slow.split)")
var hopeless = GraphPerfFrameBudget(screenFPS: 120)
_ = run(&hopeless, speed: 0.02, frames: 2_000)
check("B2 however slow, the split stops at its coarsest", hopeless.split == GraphPerfFrameBudget.coarsest)

// MARK: - B3 detail comes back slowly, without see-sawing

var back = GraphPerfFrameBudget(screenFPS: 120)
_ = run(&back, speed: 0.15, frames: 300)
let coarse = back.split
_ = run(&back, speed: 3, frames: 3_000)
check("B3 once the device is quick again, detail returns", back.split < coarse, "\(back.split) vs \(coarse)")
var steady = GraphPerfFrameBudget(screenFPS: 120)
_ = run(&steady, speed: 0.4, frames: 1_500)
let changesBefore = steady.changes
_ = run(&steady, speed: 0.4, frames: 1_500)
check("B3 at a steady load it settles: few changes over 1,500 frames", steady.changes - changesBefore <= 30,
      "\(steady.changes - changesBefore) changes")
var once = GraphPerfFrameBudget(screenFPS: 120)
once.record(cpu: 0.02, gpu: 0.02, interval: 1.0 / 120)
check("B3 one slow frame alone changes nothing", once.split == GraphPerfFrameBudget.startingSplit(.high))
once.record(cpu: 0.02, gpu: 0.02, interval: 1.0 / 120)
let afterTwo = once.split
once.record(cpu: 0.02, gpu: 0.02, interval: 1.0 / 120)
once.record(cpu: 0.02, gpu: 0.02, interval: 1.0 / 120)
check("B3 two in a row coarsen once, then it waits out the frames in flight",
      afterTwo > GraphPerfFrameBudget.startingSplit(.high) && once.split == afterTwo)

// MARK: - B4 missed refreshes count, a pause does not

var missing = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<20 { missing.record(cpu: 0.001, gpu: 0.005, interval: 2.0 / 120) }
check("B4 frames within their share that missed a refresh anyway (the system's, the simulator's) cut nothing",
      missing.split == GraphPerfFrameBudget.startingSplit(.high) && missing.bundleShare == 1, "split \(missing.split)")
var missedAndOver = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<2 { missedAndOver.record(cpu: 0.001, gpu: 0.008, interval: 2.0 / 120) }
check("B4 frames over their share coarsen, missed refresh or not", missedAndOver.split > GraphPerfFrameBudget.startingSplit(.high))
var notOurs = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<20 { notOurs.record(cpu: 0.001, gpu: 0.001, interval: 2.0 / 120) }
check("B4 cheap frames that missed a refresh anyway are someone else's: nothing is cut",
      notOurs.split <= GraphPerfFrameBudget.startingSplit(.high) && notOurs.bundleShare == 1, "split \(notOurs.split)")
var paused = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<4 { paused.record(cpu: 0.001, gpu: nil, interval: 3) }
check("B4 a long gap (the map was still, then woken) is not a miss", paused.split == GraphPerfFrameBudget.startingSplit(.high))

// MARK: - B5 the streaming budget follows the room left

var roomy = GraphPerfFrameBudget(screenFPS: 120)
roomy.record(cpu: 0.0005, gpu: 0.0005, interval: 1.0 / 120)
var tight = GraphPerfFrameBudget(screenFPS: 120)
tight.record(cpu: 0.006, gpu: 0.006, interval: 1.0 / 120)
check("B5 more room, more bodies laid out a frame", roomy.bodyBudget > tight.bodyBudget)
check("B5 never nothing (ten leaves' worth at the least)", tight.bodyBudget >= 4_000)
check("B5 the chunk settings carry the split", roomy.settings.split == roomy.split)

// MARK: - B6 the depth band: pulled in once the split has coarsened, given back first

var pulling = GraphPerfFrameBudget(screenFPS: 120)
var cuts: [String] = []
var splitAtFirstPull: Float = 0
for _ in 0..<400 {
    let was = (split: pulling.split, pull: pulling.pull)
    pulling.record(GraphPerfFrameStages(cpu: 0.001, near: 0.02, far: 0.001), interval: 1.0 / 120)
    if pulling.split > was.split { cuts.append("split") }
    if pulling.pull < was.pull {
        cuts.append("pull")
        if splitAtFirstPull == 0 { splitAtFirstPull = pulling.split }
    }
}
let firstPull = cuts.firstIndex(of: "pull") ?? cuts.count
check("B6 notes over budget: the split coarsens to half again its start, then the band is pulled in",
      firstPull > 0 && firstPull < cuts.count && cuts[..<firstPull].allSatisfy { $0 == "split" }
      && splitAtFirstPull >= GraphPerfFrameBudget.startingSplit(.high) * GraphPerfFrameBudget.pullAfter,
      "\(cuts.prefix(10)), split \(splitAtFirstPull) at the first pull")
check("B6 the band comes in to 0.7 of its width and no further, then the split coarsens again; the rate stays",
      abs(pulling.pull - GraphPerfDepthBand.tightest) < 1e-6
      && (cuts.lastIndex(of: "split") ?? -1) > (cuts.lastIndex(of: "pull") ?? cuts.count)
      && pulling.screenFPS == 120, "pull \(pulling.pull)")
var givenBack: [String] = []
for _ in 0..<3_000 {
    let was = (split: pulling.split, pull: pulling.pull)
    pulling.record(GraphPerfFrameStages(cpu: 0.0005, near: 0.0005, far: 0.0005), interval: 1.0 / 120)
    if pulling.pull > was.pull { givenBack.append("pull") }
    if pulling.split < was.split { givenBack.append("split") }
}
let lastPullBack = givenBack.lastIndex(of: "pull") ?? -1
check("B6 with room again, the band comes back whole before the split opens anything",
      pulling.pull == 1 && lastPullBack >= 0 && givenBack[...lastPullBack].allSatisfy { $0 == "pull" }
      && givenBack.contains("split"), "\(givenBack.prefix(10))")

// MARK: - B7 the Graphics setting no longer caps the rate

let high = GraphicsBudget.of(.high), smooth = GraphicsBudget.of(.smooth)
check("B7 Smooth on ProMotion asks for 120", smooth.frameRate(screen: 120) == 120)
check("B7 High on ProMotion asks for 120", high.frameRate(screen: 120) == 120)
check("B7 both ask for 60 on a 60 Hz screen", smooth.frameRate(screen: 60) == 60 && high.frameRate(screen: 60) == 60)

// MARK: - B8 a stall is not load, and lost detail comes back quickly

var stalled = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<20 { stalled.record(cpu: 0.33, gpu: 0.33, interval: 0.33) }
check("B8 frames of a third of a second (the build, a wake) leave the detail alone",
      stalled.split == GraphPerfFrameBudget.startingSplit(.high), "split \(stalled.split)")
var warm = GraphPerfFrameBudget(screenFPS: 120, warmUp: GraphPerfFrameBudget.warmUp)
for _ in 0..<GraphPerfFrameBudget.warmUp { warm.record(cpu: 0.02, gpu: 0.02, interval: 1.0 / 120) }
check("B8 the first frames after a map is shown are not counted", warm.split == GraphPerfFrameBudget.startingSplit(.high))
var lost = GraphPerfFrameBudget(screenFPS: 120)
_ = run(&lost, speed: 0.02, frames: 2_000)
check("B8 (it starts at the coarsest)", lost.split == GraphPerfFrameBudget.coarsest)
var frames = 0
while lost.split > 40 && frames < 10_000 {
    lost.record(cpu: 0.0005, gpu: 0.0005, interval: 1.0 / 120)
    frames += 1
}
check("B8 from the coarsest, a quick device is back to fine detail within three seconds at 120",
      lost.split <= 40 && frames <= 360, "\(frames) frames, split \(lost.split)")

// MARK: - B9 the stage that takes the time pays for it

let start = GraphPerfFrameBudget.startingSplit(.high)
func stages(_ cpu: Double, _ near: Double, _ far: Double) -> GraphPerfFrameStages {
    GraphPerfFrameStages(cpu: cpu, near: near, far: far)
}
check("B9 the heaviest stage", stages(0.001, 0.002, 0.009).heaviest == .far
      && stages(0.001, 0.009, 0.002).heaviest == .near && stages(0.009, 0.002, 0.002).heaviest == .cpu
      && abs(stages(0.003, 0.004, 0.005).cost - 0.009) < 1e-12)
var farHeavy = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<2 { farHeavy.record(stages(0.001, 0.001, 0.02), interval: 1.0 / 120) }
check("B9 bundles over budget: fewer bundles, the split untouched",
      farHeavy.bundleShare < 1 && farHeavy.split == start, "share \(farHeavy.bundleShare), split \(farHeavy.split)")
for _ in 0..<2_000 { farHeavy.record(stages(0.001, 0.001, 0.2), interval: 1.0 / 120) }
check("B9 however costly the bundles, the notes are not hidden for them",
      farHeavy.split == start && farHeavy.bundleShare == GraphPerfFrameBudget.fewestBundles,
      "share \(farHeavy.bundleShare), split \(farHeavy.split)")
var nearHeavy = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<2 { nearHeavy.record(stages(0.001, 0.02, 0.001), interval: 1.0 / 120) }
check("B9 notes and links over budget: a coarser split, every bundle kept",
      nearHeavy.split > start && nearHeavy.bundleShare == 1)
var cpuHeavy = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<2 { cpuHeavy.record(GraphPerfFrameStages(cpu: 0.02, near: 0.001, far: 0.001, plan: 0.015), interval: 1.0 / 120) }
check("B9 planning over budget: a coarser split (planning grows with what is open)", cpuHeavy.split > start)
var cpuOther = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<2_000 { cpuOther.record(GraphPerfFrameStages(cpu: 0.02, near: 0, far: 0, plan: 0.002), interval: 1.0 / 120) }
check("B9 CPU over budget but not in planning (encoding, a debug build): the split is not what costs, it stays",
      cpuOther.split == start && cpuOther.bundleShare == 1, "split \(cpuOther.split)")
check("B9 bundles drawn: all at first, at least one, none of none",
      GraphPerfFrameBudget(screenFPS: 120).bundleLimit(29_763) == 29_763
      && farHeavy.bundleLimit(29_763) == Int((29_763 * GraphPerfFrameBudget.fewestBundles).rounded(.up))
      && farHeavy.bundleLimit(3) == 1 && farHeavy.bundleLimit(0) == 0)

// a device whose bundles are costly: the far stage scales with the share drawn
func runStaged(_ budget: inout GraphPerfFrameBudget, speed: Double, bundles: Double, frames: Int) -> [Double] {
    var costs: [Double] = []
    for _ in 0..<frames {
        let split = Double(budget.split)
        let near = (0.0008 + 2.4 / (split * split)) / speed
        let far = bundles * budget.bundleShare
        let s = stages(0.0009, near, far)
        budget.record(s, interval: 1.0 / 120)
        costs.append(s.cost)
    }
    return costs
}
var heavy = GraphPerfFrameBudget(screenFPS: 120)
let heavyCosts = runStaged(&heavy, speed: 2, bundles: 0.03, frames: 1_500)
check("B9 costly bundles (30 ms all drawn): it settles under the share with the notes still opening at the tier's split",
      heavy.split == start && heavyCosts.suffix(100).allSatisfy { $0 <= heavy.target * 1.0001 },
      "split \(heavy.split), share \(heavy.bundleShare), worst \(heavyCosts.suffix(100).max()! * 1000) ms")

// coming back: the notes first, then the bundles
var both = GraphPerfFrameBudget(screenFPS: 120)
for _ in 0..<40 { both.record(stages(0.001, 0.02, 0.001), interval: 1.0 / 120) }
for _ in 0..<40 { both.record(stages(0.001, 0.001, 0.02), interval: 1.0 / 120) }
let cutBoth = both.split > start && both.bundleShare < 1
var order: [String] = []
for _ in 0..<3_000 {
    let before = (both.split, both.bundleShare)
    both.record(stages(0.0005, 0.0005, 0.0005), interval: 1.0 / 120)
    if both.split < before.0 { order.append("split") }
    if both.bundleShare > before.1 { order.append("bundles") }
}
let firstBundle = order.firstIndex(of: "bundles") ?? order.count
check("B9 with room again, the split returns to the tier's before any bundle comes back, then every bundle",
      cutBoth && !order[..<firstBundle].isEmpty && order[firstBundle...].allSatisfy { $0 != "split" || both.bundleShare == 1 }
      && both.bundleShare == 1 && both.split <= start, "\(order.prefix(12))")

// MARK: - B10 exposure

func measure(_ light: [Float], _ shown: [Float]) -> [Float] {
    var out: [Float] = []
    for i in 0..<light.count { out += [light[i], shown[i]] }
    return out
}
func feed(_ e: inout GraphPerfExposure, _ samples: [Float], _ seconds: Double) {
    samples.withUnsafeBufferPointer { e.update(samples: $0, seconds: seconds) }
}
// a frame mostly dark, its lit part spread from 0.02 to 8
var lights: [Float] = Array(repeating: 0, count: 3_000)
for i in 0..<1_096 { lights.append(0.02 * pow(400, Float(i) / 1_095)) }
var shownFrame: [Float] = Array(repeating: 0.1, count: 4_096)
for i in 0..<41 { shownFrame[i] = 1 }
var exposure = GraphPerfExposure()
feed(&exposure, measure(lights, shownFrame), 1.0 / 60)
let litOnly = lights.filter { $0 >= GraphPerfExposure.lit }.sorted()
let p97 = litOnly[Int(Float(litOnly.count) * 0.97)]
let landed = 1 - exp(-exposure.k * p97)
let overWhite = litOnly.filter { 1 - exp(-exposure.k * $0) >= GraphPerfExposure.white }.count
check("B10 the lit samples' 97th percentile lands near 0.6 of white (dark samples don't count)",
      abs(landed - GraphPerfExposure.level) < 0.08, "landed \(landed), k \(exposure.k), high \(exposure.high)")
check("B10 only the top of the lit light reaches 250 (under 3% of what is lit)",
      Double(overWhite) / Double(litOnly.count) < 0.03, "\(overWhite) of \(litOnly.count)")
check("B10 the saturated share is the screen's share at 250 or more",
      abs(exposure.saturated - 41.0 / 4_096) < 1e-9, "\(exposure.saturated)")

// a sudden ten-times brighter frame: smoothed over about 0.3 s, never past it
let before = exposure.k
let brighter = measure(lights.map { $0 * 10 }, shownFrame).withUnsafeBufferPointer { Array($0) }
var ks: [Float] = []
for _ in 0..<180 {
    feed(&exposure, brighter, 1.0 / 120)
    ks.append(exposure.k)
}
let goal = GraphPerfExposure.strength(for: exposure.high)
let at300ms = ks[35]
let covered = log(before / at300ms) / log(before / goal)
check("B10 a ten-times jump is followed smoothly: about 63% of the way (in the log) after 0.3 s",
      ks.first! < before && ks.first! > before * 0.9 && covered > 0.55 && covered < 0.72,
      "first \(ks.first!), covered \(covered)")
check("B10 the exposure never overshoots and settles within 1.5 s",
      zip(ks, ks.dropFirst()).allSatisfy { $1 <= $0 } && ks.allSatisfy { $0 >= goal * 0.999 } && abs(ks.last! / goal - 1) < 0.05,
      "last \(ks.last!), goal \(goal)")

// nothing lit: the strength stays where it was; strengths stay in range
var dark = exposure
feed(&dark, measure(Array(repeating: 0, count: 4_096), Array(repeating: 0, count: 4_096)), 1.0 / 60)
check("B10 an empty frame keeps the exposure and reads 0% saturated",
      dark.k == exposure.k && dark.saturated == 0 && dark.high == 0)
check("B10 the strength stays in its range",
      GraphPerfExposure.strength(for: 1e-6) == GraphPerfExposure.range.upperBound
      && GraphPerfExposure.strength(for: 1e6) == GraphPerfExposure.range.lowerBound)

// MARK: - B11 a missed refresh opens nothing

var blind = GraphPerfFrameBudget(screenFPS: 60)
let blindStart = blind.split
for _ in 0..<600 { blind.record(stages(0.001, 0, 0), interval: 2.0 / 60) }
check("B11 cheap frames that miss refreshes (a GPU that reports 0) neither open nor close detail",
      blind.split == blindStart && blind.bundleShare == 1, "split \(blind.split)")
var seeing = GraphPerfFrameBudget(screenFPS: 60)
for _ in 0..<600 { seeing.record(stages(0.001, 0, 0), interval: 1.0 / 60) }
check("B11 the same frames on time open detail", seeing.split < blindStart, "split \(seeing.split)")

// MARK: - B12 the GPU's stages from the wall clock (the simulator's own read about 0)

let wall = GraphPerfWallStages.stages(commitA: 1.000, doneA: 1.004, doneB: 1.007, doneC: 1.009, lastDoneC: 0.998)
check("B12 near: from its commit to done, and the screen pass after the far one; far: between them",
      abs(wall.near - 0.006) < 1e-9 && abs(wall.far - 0.003) < 1e-9, "\(wall)")
let queued = GraphPerfWallStages.stages(commitA: 1.000, doneA: 1.012, doneB: 1.013, doneC: 1.014, lastDoneC: 1.008)
check("B12 a frame queued behind the one before counts from when that one was done",
      abs(queued.near - 0.005) < 1e-9 && abs(queued.far - 0.001) < 1e-9, "\(queued)")
check("B12 the GPU's own times are used while believable, the wall's when they read about 0",
      GraphPerfWallStages.gpuTimesUsable(gpu: 0.004, wall: 0.006)
      && !GraphPerfWallStages.gpuTimesUsable(gpu: 0.0001, wall: 0.006)
      && GraphPerfWallStages.gpuTimesUsable(gpu: 0, wall: 0))

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
