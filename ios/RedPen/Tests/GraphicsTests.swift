// The Graphics setting: which budget Automatic picks on which device, that
// Smooth is cheaper than High in every way it promises, that frame steps
// come out even without the motion drifting from the clock, and how fast
// the sky draws (GraphPace).
//
// Compiled with Shared/Space/GraphicsQuality.swift, which imports only
// Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

let GB: UInt64 = 1_000_000_000

// MARK: G1 - which tier Automatic picks

func device(_ memory: UInt64, lowPower: Bool = false, thermal: Int = 0) -> GraphicsDeviceState {
    var d = GraphicsDeviceState(memory: memory)
    d.lowPower = lowPower
    d.thermal = thermal
    return d
}

let auto: GraphicsChoice = .automatic
check("G1a a 4 GB phone (3.9e9 reported) is Smooth",
      GraphicsResolver.resolve(auto, device: device(3_900_000_000)) == .smooth)
check("G1b a 3 GB phone is Smooth", GraphicsResolver.resolve(auto, device: device(2_900_000_000)) == .smooth)
check("G1c a 6 GB phone (a little under 6e9 reported) is High",
      GraphicsResolver.resolve(auto, device: device(5_700_000_000)) == .high)
check("G1d an 8 GB phone is High", GraphicsResolver.resolve(auto, device: device(8 * GB)) == .high)
check("G1e Low Power Mode is Smooth", GraphicsResolver.resolve(auto, device: device(8 * GB, lowPower: true)) == .smooth)
check("G1f a serious thermal state is Smooth", GraphicsResolver.resolve(auto, device: device(8 * GB, thermal: 2)) == .smooth)
check("G1g a critical thermal state is Smooth", GraphicsResolver.resolve(auto, device: device(8 * GB, thermal: 3)) == .smooth)
check("G1h a fair thermal state stays High", GraphicsResolver.resolve(auto, device: device(8 * GB, thermal: 1)) == .high)
check("G1i unknown memory (0) is not held against it", GraphicsResolver.resolve(auto, device: device(0)) == .high)
check("G1j High quality is High even on a 3 GB phone in Low Power Mode",
      GraphicsResolver.resolve(.high, device: device(3 * GB, lowPower: true, thermal: 3)) == .high)
check("G1k Smooth is Smooth even on an 8 GB phone", GraphicsResolver.resolve(.smooth, device: device(8 * GB)) == .smooth)
check("G1l a missing setting is Automatic", GraphicsChoice.stored(nil) == .automatic)
check("G1m an unknown setting is Automatic", GraphicsChoice.stored("ultra") == .automatic)
check("G1n every choice round-trips", GraphicsChoice.allCases.allSatisfy { GraphicsChoice.stored($0.rawValue) == $0 })
check("G1o the Settings titles", GraphicsChoice.allCases.map(\.title) == ["Automatic", "High quality", "Smooth"])

// MARK: G2 - Smooth is cheaper in every way it promises

let hi: GraphicsBudget = GraphicsBudget.of(.high)
let lo: GraphicsBudget = GraphicsBudget.of(.smooth)
check("G2a fewer link samples", lo.linkSamples < hi.linkSamples, "\(lo.linkSamples) vs \(hi.linkSamples)")
check("G2b no cap below the screen in either tier", lo.maxFPS >= 120 && hi.maxFPS >= 120)
check("G2c lighter multisampling", lo.msaa < hi.msaa)
check("G2d the shaders' simple path", lo.shaderDetail == 0 && hi.shaderDetail == 1)
check("G2e fewer sparks", lo.particleScale < hi.particleScale)
check("G2f halos thinned sooner", lo.crowdedAbove < hi.crowdedAbove)
check("G2g no twinkle, a still nebula, no haze", !lo.twinkle && !lo.nebulaDrifts && !lo.haze)
check("G2h High keeps all of them", hi.twinkle && hi.nebulaDrifts && hi.haze && hi.starStride == 1)
check("G2i fewer faint stars", lo.starStride > 1)
check("G2j High on a 60 Hz screen asks for 60", hi.frameRate(screen: 60) == 60)
check("G2k High on ProMotion asks for 120", hi.frameRate(screen: 120) == 120)
check("G2l Smooth on ProMotion asks for 120 too (it cuts detail, never the rate)", lo.frameRate(screen: 120) == 120)
check("G2m even Smooth's links are finer than the old six segments", lo.linkSamples >= 12)

// MARK: G3 - even frame steps

var random = UInt64(0x5EED)
func jitter(_ size: Double) -> Double {
    random = random &* 6364136223846793005 &+ 1442695040888963407
    let unit: Double = Double(random >> 11) / Double(UInt64(1) << 53)
    return (unit * 2 - 1) * size
}

// The render loop is called at the display's steady rhythm, each call a
// little early or late: its timestamps wobble, so the raw steps between
// them wobble twice as much, one long step followed by a short one.
func paced(rate: Double, wobble: Double, frames: Int) -> (worst: Double, rawWorst: Double, drift: Double) {
    var pacer = GraphFramePacer()
    let frame: Double = 1 / rate
    var last: Double = 100
    _ = pacer.step(at: last)
    var worst: Double = 0
    var rawWorst: Double = 0
    var drift: Double = 0
    for k in 1...frames {
        let stamp: Double = 100 + Double(k) * frame + jitter(wobble)
        let even: Double = pacer.step(at: stamp)
        worst = max(worst, abs(even - frame))
        rawWorst = max(rawWorst, abs(stamp - last - frame))
        drift = max(drift, abs(pacer.stamp - (100 + Double(k) * frame)))
        last = stamp
    }
    return (worst, rawWorst, drift)
}

do {
    let at120 = paced(rate: 120, wobble: 0.0015, frames: 1200)
    check("G3a 120 Hz, called up to 1.5 ms early or late: every step within 0.2 ms of 1/120", at120.worst < 0.0002,
          "worst \(at120.worst) raw \(at120.rawWorst)")
    check("G3b ...though the raw steps wobbled by up to 3 ms", at120.rawWorst > 0.002)
    check("G3c ...and ten seconds of it stay on the real clock", at120.drift < 0.0015, "\(at120.drift)")
    let at60 = paced(rate: 60, wobble: 0.002, frames: 600)
    check("G3d 60 Hz, up to 2 ms early or late: every step within 0.2 ms of 1/60", at60.worst < 0.0002,
          "worst \(at60.worst) raw \(at60.rawWorst)")
    let at40 = paced(rate: 40, wobble: 0.002, frames: 400)
    check("G3e 40 Hz (a busy ProMotion screen): every step within 0.2 ms of 3 ticks", at40.worst < 0.0002, "\(at40.worst)")
}
do {
    var pacer = GraphFramePacer()
    let first: Double = pacer.step(at: 5)
    check("G3f the first frame is one tick", first == GraphFramePacer.tick)
    let dropped: Double = pacer.step(at: 5 + 3.0 / 120 + 0.001)
    check("G3g a dropped frame is a whole number of ticks", abs(dropped - 3.0 / 120) < 0.0001, "\(dropped)")
    let stall: Double = pacer.step(at: 6)
    check("G3h a stall is capped at 0.05 s", stall == GraphFramePacer.longest, "\(stall)")
    check("G3i ...and the clock starts again from it", pacer.stamp == 6)
    let back: Double = pacer.step(at: 4)
    check("G3j a clock going backwards is one tick", back == GraphFramePacer.tick)
    let nan: Double = pacer.step(at: Double.nan)
    check("G3k a NaN time is one tick", nan - GraphFramePacer.tick == 0)
}

// MARK: G7 - how fast the map draws (GraphPace; Chat-me audit row 109)

func pace(_ fast: Int = 120, lively: Bool = true, covered: Bool = false, quiet: Double,
          busy: Bool = false) -> Int {
    GraphPace.rate(fast: fast, lively: lively, covered: covered, quiet: quiet, busy: busy)
}

check("G7a touched, a lively map draws at the budget's rate", pace(quiet: 0) == 120, "\(pace(quiet: 0))")
check("G7b ...a map that holds still at 60", pace(lively: false, quiet: 0) == 60)
check("G7c a lively map 5 s after the last touch: 60", pace(quiet: 5) == 60)
check("G7d ...and after 20 s: 30", pace(quiet: 25) == 30)
check("G7e a map that holds still, 5 s after: 20", pace(lively: false, quiet: 5) == 20)
check("G7f under a sheet: 20, even while touched", pace(covered: true, quiet: 0, busy: true) == 20)
check("G7g a body held long after the last wake: still fast",
      pace(quiet: 25, busy: true) == 120 && pace(lively: false, quiet: 25, busy: true) == 60)
check("G7h Smooth (60): 60, 60, 30, and 20 when still",
      pace(60, quiet: 0) == 60 && pace(60, quiet: 5) == 60 && pace(60, quiet: 25) == 30
      && pace(60, lively: false, quiet: 5) == 20)
check("G7i never above the budget's rate (a 30 a second screen)",
      pace(30, quiet: 0) == 30 && pace(30, quiet: 5) == 30 && pace(30, covered: true, quiet: 0) == 20)
check("G7j a NaN or backwards clock counts as just touched",
      pace(quiet: Double.nan) == 120 && pace(quiet: -4) == 120)

do {
    // every rate it can ask for is a whole number of pacer ticks, 6 at most
    var odd: [String] = []
    for fast in [30, 60, 120] {
        for lively in [true, false] {
            for covered in [true, false] {
                for busy in [true, false] {
                    for quiet in stride(from: 0.0, through: 40, by: 0.5) {
                        let r: Int = pace(fast, lively: lively, covered: covered, quiet: quiet, busy: busy)
                        let ticks: Double = (1 / Double(r)) / GraphFramePacer.tick
                        let whole: Bool = abs(ticks - ticks.rounded()) < 0.000_1
                        if !whole || ticks.rounded() > 6 || r > fast { odd.append("\(fast) \(lively) \(quiet): \(r)") }
                    }
                }
            }
        }
    }
    check("G7k every rate is 1 to 6 whole pacer ticks, never above the budget", odd.isEmpty,
          odd.prefix(3).joined(separator: "; "))
    let at20 = paced(rate: 20, wobble: 0.002, frames: 200)
    check("G7l at 20 a second each frame is a whole step, not a stall", at20.worst < 0.0002, "\(at20.worst)")
    let at15 = paced(rate: 15, wobble: 0.002, frames: 150)
    check("G7m ...where at 15 every frame would be a capped stall (so 20 is the floor)", at15.worst > 0.01,
          "\(at15.worst)")
}

func look(lively: Bool = true, covered: Bool = false, quiet: Double, busy: Bool = false) -> Double? {
    GraphPace.recheck(lively: lively, covered: covered, quiet: quiet, busy: busy)
}

check("G7n just touched: look again just past 3 s", look(quiet: 0).map { abs($0 - 3.05) < 0.000_1 } == true)
check("G7o 2 s after: in about 1 s", look(quiet: 2).map { abs($0 - 1.05) < 0.000_1 } == true)
check("G7p a lively map 5 s after: just past 20 s", look(quiet: 5).map { abs($0 - 15.05) < 0.000_1 } == true)
check("G7q nothing more to change: no look (still and settled, resting, under a sheet)",
      look(lively: false, quiet: 5) == nil && look(quiet: 25) == nil && look(covered: true, quiet: 0) == nil)
check("G7r a body held: once a second", look(quiet: 30, busy: true) == 1)

do {
    // following its own looks from a touch, with nothing else happening
    func steps(lively: Bool) -> [Int] {
        var t: Double = 0
        var rates: [Int] = [pace(lively: lively, quiet: t)]
        while let wait = look(lively: lively, quiet: t), rates.count < 10 {
            t += wait
            rates.append(pace(lively: lively, quiet: t))
        }
        return rates
    }
    let lively: [Int] = steps(lively: true)
    let still: [Int] = steps(lively: false)
    check("G7s a lively map: fast, 60, then 30, and the looks stop", lively == [120, 60, 30], "\(lively)")
    check("G7t a still map: 60, then 20, and the looks stop", still == [60, 20], "\(still)")
    var shortest: Double = 99
    for quiet in stride(from: -1.0, through: 30, by: 0.01) {
        if let wait = look(quiet: quiet) { shortest = min(shortest, wait) }
    }
    check("G7u a look is never sooner than 0.1 s (no spinning)", shortest >= 0.1, "\(shortest)")
}

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
