// The million map's frame budget, on Linux: the rate is the screen's own
// (B1); a device that cannot keep it cuts detail, never the rate, and
// settles under its share of the frame (B2); a fast one opens detail again,
// slowly and without see-sawing (B3); missed refreshes count (B4); the
// streaming budget follows the room left (B5); the link pages follow memory
// (B6); the Graphics setting no longer caps the rate (B7); and a stall
// is not load, while detail lost comes back within seconds (B8); and the
// stage that takes the time pays for it, bundles before notes (B9).
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
check("B5 more room, more links and bodies prepared a frame",
      roomy.linkBudget > tight.linkBudget && roomy.bodyBudget > tight.bodyBudget)
check("B5 never nothing", tight.linkBudget >= 16_000 && tight.bodyBudget >= 8_000)
check("B5 the chunk settings carry the split", roomy.settings.split == roomy.split)

// MARK: - B6 link pages from memory

let gb: UInt64 = 1 << 30
check("B6 a 4 GB phone (A13) keeps 8 MB of links, 6 GB 24, 8 GB 40",
      GraphPerfMemoryBudget.linkPages(physicalMemory: 3_900_000_000) == 1_024
      && GraphPerfMemoryBudget.linkPages(physicalMemory: 5_900_000_000) == 3_072
      && GraphPerfMemoryBudget.linkPages(physicalMemory: 8 * gb) == 5_120)
check("B6 unknown memory is not held against it", GraphPerfMemoryBudget.linkPages(physicalMemory: 0) == 5_120)

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

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
