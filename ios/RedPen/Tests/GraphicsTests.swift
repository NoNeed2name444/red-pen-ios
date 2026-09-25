// The Graphics setting and the smooth links: which budget Automatic picks on
// which device, that Smooth is cheaper than High in every way it promises,
// that frame steps come out even without the motion drifting from the
// clock, and that a link is ONE smooth curve - no kinks at any sample count
// the budgets use, ends where it should, a continuous distance along it for
// the shader, and long links squeezed evenly rather than frozen at 60 units.
//
// Compiled with Shared/Space/GraphicsQuality.swift and
// Features/Notes/GraphLinkCurve.swift, which import only Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Float, _ b: Float, _ eps: Float = 0.0005) -> Bool { abs(a - b) <= eps }
func near3(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ eps: Float = 0.0005) -> Bool {
    GraphLinkCurve.length(a - b) <= eps
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
check("G2b 60 frames a second at most", lo.maxFPS == 60 && hi.maxFPS == 120)
check("G2c lighter multisampling", lo.msaa < hi.msaa)
check("G2d the shaders' simple path", lo.shaderDetail == 0 && hi.shaderDetail == 1)
check("G2e fewer sparks", lo.particleScale < hi.particleScale)
check("G2f halos thinned sooner", lo.crowdedAbove < hi.crowdedAbove)
check("G2g no twinkle, a still nebula, no haze", !lo.twinkle && !lo.nebulaDrifts && !lo.haze)
check("G2h High keeps all of them", hi.twinkle && hi.nebulaDrifts && hi.haze && hi.starStride == 1)
check("G2i fewer faint stars", lo.starStride > 1)
check("G2j High on a 60 Hz screen asks for 60", hi.frameRate(screen: 60) == 60)
check("G2k High on ProMotion asks for 120", hi.frameRate(screen: 120) == 120)
check("G2l Smooth on ProMotion asks for 60", lo.frameRate(screen: 120) == 60)
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

// MARK: G4 - a link is one smooth curve

/// The largest turn, in degrees, between neighbouring pieces of a sampled
/// curve.
func sharpest(_ points: [SIMD3<Float>], _ n: Int) -> Float {
    var worst: Float = 0
    guard n >= 2 else { return 0 }
    for k in 1..<n {
        let a: SIMD3<Float> = GraphLinkCurve.unit(points[k] - points[k - 1], or: SIMD3<Float>(1, 0, 0))
        let b: SIMD3<Float> = GraphLinkCurve.unit(points[k + 1] - points[k], or: SIMD3<Float>(1, 0, 0))
        let c: Float = min(max(GraphLinkCurve.dot(a, b), -1), 1)
        worst = max(worst, acos(c) * 180 / Float.pi)
    }
    return worst
}

/// How far a point is from the segment a-b.
func gap(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let ab: SIMD3<Float> = b - a
    let squared: Float = GraphLinkCurve.dot(ab, ab)
    guard squared > 1e-12 else { return GraphLinkCurve.length(p - a) }
    let t: Float = min(max(GraphLinkCurve.dot(p - a, ab) / squared, 0), 1)
    return GraphLinkCurve.length(p - (a + ab * t))
}

/// The furthest the strip drawn from `n` samples strays from the true curve
/// (checked at 1024 points along it): what decides whether joints show.
func stray(_ path: GraphLinkPath, samples n: Int) -> Float {
    var drawn: [SIMD3<Float>] = []
    var drawnLengths: [Float] = []
    _ = GraphLinkCurve.sample(path, count: n, points: &drawn, lengths: &drawnLengths)
    var worst: Float = 0
    for j in 0...1024 {
        let q: SIMD3<Float> = GraphLinkCurve.point(path, Float(j) / 1024)
        var best: Float = Float.greatestFiniteMagnitude
        for k in 0..<n { best = min(best, gap(q, drawn[k], drawn[k + 1])) }
        worst = max(worst, best)
    }
    return worst
}

/// The Universe's beam half-width (GraphMotion).
let beamHalf: Float = 0.10

var points: [SIMD3<Float>] = []
var lengths: [Float] = []

// straight
do {
    let path = GraphLinkPath(start: SIMD3<Float>(0, 0, 0), end: SIMD3<Float>(10, 0, 0))
    let total: Float = GraphLinkCurve.sample(path, count: 32, points: &points, lengths: &lengths)
    check("G4a a straight link is its length", near(total, 10, 0.001), "\(total)")
    check("G4b it starts and ends at the trims", near3(points[0], path.start) && near3(points[32], path.end))
    var even: Bool = true
    for k in 1...32 where !near(lengths[k] - lengths[k - 1], 10.0 / 32, 0.001) { even = false }
    check("G4c its samples are evenly spaced", even)
    check("G4d and it has no turn at all", sharpest(points, 32) < 0.01)
}

// arched and bent into a black hole at B and a gas giant at A: the
// Universe's hardest case
let centreA = SIMD3<Float>(0, 0, 0)
let centreB = SIMD3<Float>(12, 2, -3)
let axisA = SIMD3<Float>(0, 1, 0)
let axisB = SIMD3<Float>(0.3, 0.9, 0.3)
let dirAB: SIMD3<Float> = GraphLinkCurve.unit(centreB - centreA, or: SIMD3<Float>(1, 0, 0))
var hard = GraphLinkPath(start: centreA + dirAB * 1.2, end: centreB - dirAB * 1.6)
hard.arch = GraphLinkCurve.unit(GraphLinkCurve.cross(dirAB, SIMD3<Float>(0, 0, 1)), or: SIMD3<Float>(0, 1, 0))
hard.archSize = 0.10 * GraphLinkCurve.length(centreB - centreA)
hard.bendA = GraphLinkBend.forStyle(2, centre: centreA, axis: axisA)
hard.bendB = GraphLinkBend.forStyle(0, centre: centreB, axis: axisB)
check("G4e a black hole and a gas giant bend; a sun does not",
      hard.bendA != nil && hard.bendB != nil && GraphLinkBend.forStyle(5, centre: centreA, axis: axisA) == nil)

do {
    let old: Float = stray(hard, samples: 6)
    let smooth: Float = stray(hard, samples: lo.linkSamples)
    let high: Float = stray(hard, samples: hi.linkSamples)
    check("G4f six segments (the old ribbon) stray by more than the beam's half-width: kinks",
          old > beamHalf, "\(old)")
    check("G4g Smooth strays by under a quarter of the half-width", smooth < beamHalf * 0.25, "\(smooth)")
    check("G4h High strays by under a tenth of it", high < beamHalf * 0.1, "\(high)")
    _ = GraphLinkCurve.sample(hard, count: 6, points: &points, lengths: &lengths)
    let oldTurn: Float = sharpest(points, 6)
    _ = GraphLinkCurve.sample(hard, count: hi.linkSamples, points: &points, lengths: &lengths)
    let highTurn: Float = sharpest(points, hi.linkSamples)
    check("G4i High's sharpest joint turns under a quarter as much as the old one's",
          highTurn < oldTurn / 4, "\(highTurn) vs \(oldTurn) degrees")
    let dA: Float = GraphLinkCurve.length(points[0] - centreA)
    let dB: Float = GraphLinkCurve.length(points[hi.linkSamples] - centreB)
    check("G4j the bent ends keep their distance from each body (still at the trim)",
          near(dA, 1.2, 0.002) && near(dB, 1.6, 0.002), "\(dA) \(dB)")
    var rising: Bool = true
    for k in 1...hi.linkSamples where !(lengths[k] > lengths[k - 1]) { rising = false }
    check("G4k the distance along it only ever grows (continuous flow, no seam)", rising)
    var finite: Bool = true
    for p in points.prefix(hi.linkSamples + 1) where !(p.x.isFinite && p.y.isFinite && p.z.isFinite) { finite = false }
    check("G4l every point is finite", finite)
}

// the same curve at any sample count: finer samples land on the coarser ones
do {
    var fine: [SIMD3<Float>] = []
    var fineLengths: [Float] = []
    _ = GraphLinkCurve.sample(hard, count: 40, points: &fine, lengths: &fineLengths)
    var coarse: [SIMD3<Float>] = []
    var coarseLengths: [Float] = []
    _ = GraphLinkCurve.sample(hard, count: 20, points: &coarse, lengths: &coarseLengths)
    var same: Bool = true
    for k in 0...20 where !near3(coarse[k], fine[k * 2], 0.0001) { same = false }
    check("G4m Smooth and High draw the same curve, only sampled differently", same)
}

// growing in: the grown part is the start of the full curve
do {
    var half = hard
    half.grow = 0.5
    let tip: SIMD3<Float> = GraphLinkCurve.point(half, 1)
    let middle: SIMD3<Float> = GraphLinkCurve.point(hard, 0.5)
    check("G4n a half-grown link reaches exactly the full curve's middle", near3(tip, middle, 0.0001))
    let start: SIMD3<Float> = GraphLinkCurve.point(half, 0)
    check("G4o and starts where the full one does", near3(start, GraphLinkCurve.point(hard, 0), 0.0001))
}

// a link of no length does not blow up
do {
    let path = GraphLinkPath(start: SIMD3<Float>(1, 1, 1), end: SIMD3<Float>(1, 1, 1))
    let total: Float = GraphLinkCurve.sample(path, count: 14, points: &points, lengths: &lengths)
    check("G4p a link of no length samples to one point, length 0", total == 0 && near3(points[14], path.start))
}

// MARK: G5 - the distance along, for the shader

check("G5a a short link keeps its distances", GraphLinkCurve.alongScale(total: 30) == 1)
check("G5b a link of exactly 60 keeps them", GraphLinkCurve.alongScale(total: 60) == 1)
check("G5c a 120-unit link is squeezed by half", near(GraphLinkCurve.alongScale(total: 120), 0.5))
do {
    let long = GraphLinkPath(start: SIMD3<Float>(0, 0, 0), end: SIMD3<Float>(150, 0, 0))
    let total: Float = GraphLinkCurve.sample(long, count: 32, points: &points, lengths: &lengths)
    let scale: Float = GraphLinkCurve.alongScale(total: total)
    let last: Float = lengths[32] * scale
    let before: Float = lengths[31] * scale
    check("G5d a 150-unit link's far end sits at 60, not past it", near(last, 60, 0.01), "\(last)")
    check("G5e and its last stretch still flows (the old cap froze it)", last - before > 1, "\(last - before)")
}

// MARK: G6 - the helpers

check("G6a cross of x and y is z", near3(GraphLinkCurve.cross(SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)),
                                          SIMD3<Float>(0, 0, 1)))
let turned: SIMD3<Float> = GraphLinkCurve.rotate(SIMD3<Float>(1, 0, 0), about: SIMD3<Float>(0, 0, 1), by: Float.pi / 2)
check("G6b a quarter turn about z takes x to y", near3(turned, SIMD3<Float>(0, 1, 0), 0.0001))
let square: SIMD3<Float> = GraphLinkCurve.perpendicular(to: SIMD3<Float>(1, 0, 0))
check("G6c a perpendicular is square and unit", near(GraphLinkCurve.dot(square, SIMD3<Float>(1, 0, 0)), 0)
      && near(GraphLinkCurve.length(square), 1))

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
