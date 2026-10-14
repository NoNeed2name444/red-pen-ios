// The million map's frame budget, on Linux: the rate is the screen's own
// (B1); a device that cannot keep it cuts detail, never the rate, and
// settles under its share of the frame (B2); a fast one opens detail again,
// slowly and without see-sawing (B3); missed refreshes count (B4); the
// streaming budget follows the room left (B5); the link pages follow memory
// (B6); and the Graphics setting no longer caps the rate (B7).
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
_ = run(&hopeless, speed: 0.001, frames: 2_000)
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
for _ in 0..<2 { missing.record(cpu: 0.001, gpu: 0.001, interval: 2.0 / 120) }
check("B4 cheap frames that still missed a refresh coarsen", missing.split > GraphPerfFrameBudget.startingSplit(.high))
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

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
