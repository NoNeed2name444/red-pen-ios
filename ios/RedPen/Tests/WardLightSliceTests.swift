// The Ward relief's lights, drawn once (WardLightSlice): how far each look's
// lights reach, how an image is cut so one serves every size of a rounded
// rectangle, what it is keyed by, and, by drawing both with a Gaussian, that
// stretching a cut image gives the picture drawing the shape at the larger
// size gives.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: reach

for dark in [false, true] {
    let reaches = WardLift.allCases.map { WardLightSlice.reach(WardRelief.raised($0, dark: dark)) }
    check("raised reach, low to peak: offset plus 1.5 blur radii, rounded up, one spare (\(dark ? "dark" : "light"))",
          reaches == [8, 18, 27, 36], "\(reaches)")
    check("an inset face reaches as far as a raised one", WardLift.allCases.allSatisfy {
        WardLightSlice.reach(WardRelief.inset($0, dark: dark)) == WardLightSlice.reach(WardRelief.raised($0, dark: dark))
    })
    check("the reach grows with the lift", reaches == reaches.sorted() && Set(reaches).count == 4)
    let rest = WardLift.allCases.map { WardLightSlice.reach(WardPress.spec($0, depth: 0, dark: dark)) }
    check("a pressable face at rest reaches farther than a raised one by its softening (\(dark ? "dark" : "light"))",
          zip(rest, reaches).allSatisfy { $0 > $1 } && rest == [11, 23, 33, 44], "\(rest)")
}
let unlit = WardReliefLight(hex: 0, alpha: 0, x: 9, y: 9, radius: 9)
check("a light that is not lit reaches nowhere", WardLightSlice.reach(of: unlit) == 0)

// MARK: the cut

let scale = 3.0
let px = { (x: Double) in Int((x * scale).rounded()) }
let lowReach = WardLightSlice.reach(WardRelief.raised(.low, dark: false))   // 8
let midReach = WardLightSlice.reach(WardRelief.raised(.mid, dark: false))   // 18

// a card: radius 16, continuous, standing low
if let card = WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: 300, height: 120,
                                   reach: lowReach, inner: false, scale: scale) {
    check("a card is cut both ways", card.stretchX && card.stretchY)
    // curve 16 x 1.53 = 24.48 -> 25; cap = pad 8 + curve 25 + reach 8
    check("its caps hold the pad, the corner's curve and the lights' reach",
          card.capX == 41 && card.capY == 41 && card.pad == 8, "\(card)")
    check("the cut image is two caps and a core", card.imageWidth == 2 * 41 + WardLightSlice.core
          && card.imageHeight == 2 * 41 + WardLightSlice.core, "\(card.imageWidth) x \(card.imageHeight)")
    check("a cut axis is not keyed by its size", card.keyWidth == 0 && card.keyHeight == 0)
    check("the shape is drawn at the least it needs, with the radius it really has",
          card.width == 68 && card.height == 68 && card.shape == .rounded(radius: 16, continuous: true))
    let shown = WardLightPlan.shown(width: 300, height: 120, pad: card.pad)
    check("shown, it reaches the pad beyond the shape on every side", shown.width == 316 && shown.height == 136)
} else { check("a card has a plan", false) }

// a button: a continuous rounded rectangle too short to cut downwards
if let button = WardLightSlice.plan(.rounded(radius: 14, continuous: true), width: 200, height: 44,
                                     reach: midReach, inner: false, scale: scale) {
    check("a button is cut along its length only", button.stretchX && !button.stretchY, "\(button)")
    check("and keyed by its height in pixels", button.keyWidth == 0 && button.keyHeight == px(44))
    check("drawn at its own height", button.height == 44 && button.capY == 0 && button.capX > 0)
} else { check("a button has a plan", false) }

// a capsule is keyed by its height
let pillTall = WardLightSlice.plan(.capsule(continuous: true), width: 220, height: 44, reach: lowReach,
                                   inner: false, scale: scale)
let pillWide = WardLightSlice.plan(.capsule(continuous: true), width: 340, height: 44, reach: lowReach,
                                   inner: false, scale: scale)
check("a capsule is cut along its length and keyed by its height",
      pillTall?.stretchX == true && pillTall?.stretchY == false && pillTall?.keyHeight == px(44))
check("two capsules of one height share a key whatever their length", pillTall.flatMap { a in
    pillWide.map { b in
        let key = { (p: WardLightPlan) in
            WardLightSlice.key(p, look: .raised, lift: .low, control: true, dark: false, strong: false,
                               fill: 0xF2F4F8FF, scale: scale)
        }
        return key(a) == key(b)
    }
} == true)
let pillShort = WardLightSlice.plan(.capsule(continuous: true), width: 50, height: 44, reach: midReach,
                                    inner: false, scale: scale)
check("a capsule too short to cut is drawn and keyed at its own size",
      pillShort?.stretchX == false && pillShort?.keyWidth == px(50) && pillShort?.keyHeight == px(44),
      "\(String(describing: pillShort))")

// a circle is keyed by its diameter
let dot = WardLightSlice.plan(.circle, width: 44, height: 44, reach: lowReach, inner: false, scale: scale)
check("a circle is drawn at its diameter and keyed by it",
      dot?.stretchX == false && dot?.stretchY == false && dot?.keyWidth == px(44) && dot?.keyHeight == px(44))
let basePlan0 = WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: 300, height: 120, reach: 8,
                                    inner: false, scale: 3)
// a circle in a box that is not square is its shorter side across, in the middle
let offSquare = WardLightSlice.plan(.circle, width: 44, height: 60, reach: lowReach, inner: false, scale: scale)
check("a circle in a box that is not square is drawn at the shorter side and shown in the middle",
      offSquare?.width == 44 && offSquare?.height == 44 && offSquare?.centred == true
      && offSquare?.keyWidth == px(44) && offSquare?.keyHeight == px(44), "\(String(describing: offSquare))")
check("so a tall and a wide box of the same diameter share a key", offSquare.flatMap { a in
    WardLightSlice.plan(.circle, width: 70, height: 44, reach: lowReach, inner: false, scale: scale).map { b in
        let key = { (p: WardLightPlan) in
            WardLightSlice.key(p, look: .raised, lift: .low, control: true, dark: false, strong: false,
                               fill: 0xF2F4F8FF, scale: scale)
        }
        return key(a) == key(b)
    }
} == true)
check("a rounded rectangle and a capsule fill their box", basePlan0?.centred == false && pillTall?.centred == false)

// a readiness ring's groove: a ring `width` wide in the box's circle, pressed in
let groove = WardLightSlice.plan(.annulus(width: 10), width: 72, height: 72, reach: lowReach, inner: true, scale: scale)
check("a ring is drawn at its box, keyed by it, with no room round it for inset lights",
      groove?.shape == .annulus(width: 10) && groove?.centred == true && groove?.pad == 0
      && groove?.stretchX == false && groove?.keyWidth == px(72), "\(String(describing: groove))")
let thinner = WardLightSlice.plan(.annulus(width: 8), width: 72, height: 72, reach: lowReach, inner: true, scale: scale)
check("a ring's width and a circle each change the key", groove.flatMap { g in
    thinner.flatMap { t in
        WardLightSlice.plan(.circle, width: 72, height: 72, reach: lowReach, inner: true, scale: scale).map { c in
            let key = { (p: WardLightPlan) in
                WardLightSlice.key(p, look: .inset, lift: .low, control: false, dark: false, strong: false,
                                   fill: 0xF2F4F8FF, scale: scale)
            }
            return key(g) != key(t) && key(g) != key(c) && key(t) != key(c)
        }
    }
} == true)
check("a ring in a box that is not square is its shorter side across",
      WardLightSlice.plan(.annulus(width: 10), width: 72, height: 90, reach: lowReach, inner: true, scale: scale)?.width == 72)
check("no plan for a ring that is not one",
      WardLightSlice.plan(.annulus(width: -1), width: 72, height: 72, reach: 8, inner: true, scale: scale) == nil
      && WardLightSlice.plan(.annulus(width: .nan), width: 72, height: 72, reach: 8, inner: true, scale: scale) == nil)

// an inset face's lights fall inside it: nothing is drawn round it
let well = WardLightSlice.plan(.rounded(radius: 12, continuous: true), width: 300, height: 56, reach: lowReach,
                               inner: true, scale: scale)
check("an inset face needs no room round its shape", well?.pad == 0 && well?.imageWidth == well?.width)
check("but its caps still hold the curve and the reach", well?.capX == 19 + lowReach, "\(String(describing: well))")

// a radius larger than the box is held to the box, as SwiftUI does
let held = WardLightSlice.plan(.rounded(radius: 30, continuous: false), width: 40, height: 40, reach: lowReach,
                               inner: false, scale: scale)
check("a radius larger than half the box is held to it", held?.shape == .rounded(radius: 20, continuous: false),
      "\(String(describing: held))")

// sizes that are not sizes
for (w, h) in [(0.0, 10.0), (10.0, 0.0), (-1.0, 10.0), (Double.nan, 10.0), (10.0, Double.infinity)] {
    check("no plan for \(w) x \(h)",
          WardLightSlice.plan(.rounded(radius: 8, continuous: true), width: w, height: h, reach: 8,
                              inner: false, scale: scale) == nil)
}
check("no plan for a scale that is not one",
      WardLightSlice.plan(.circle, width: 10, height: 10, reach: 8, inner: false, scale: 0) == nil
      && WardLightSlice.plan(.circle, width: 10, height: 10, reach: 8, inner: false, scale: .nan) == nil)
check("no plan for a radius that is not one",
      WardLightSlice.plan(.rounded(radius: -1, continuous: true), width: 99, height: 99, reach: 8,
                          inner: false, scale: 2) == nil)

// the boundary: exactly two caps and a core is cut, a point less is not
let least = 2.0 * (25 + 8) + WardLightSlice.core
check("a side of exactly two caps and a core is cut",
      WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: least, height: least, reach: 8,
                          inner: false, scale: 2)?.stretchX == true)
check("a side a point shorter is drawn whole",
      WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: least - 1, height: least, reach: 8,
                          inner: false, scale: 2)?.stretchX == false)

// MARK: keys

let basePlan = WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: 300, height: 120, reach: 8,
                                   inner: false, scale: 3)!
func key(_ plan: WardLightPlan = basePlan, look: WardLightLook = .raised, lift: WardLift = .low,
         control: Bool = false, dark: Bool = false, strong: Bool = false, fill: UInt32 = 0xF2F4F8FF,
         scale: Double = 3) -> WardLightKey {
    WardLightSlice.key(plan, look: look, lift: lift, control: control, dark: dark, strong: strong,
                       fill: fill, scale: scale)
}
let wider = WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: 411.3, height: 97, reach: 8,
                                inner: false, scale: 3)!
check("every size of a cut rounded rectangle shares one key", key() == key(wider))
check("the look, the lift and the control edge each change the key",
      key() != key(look: .inset) && key() != key(look: .press) && key() != key(lift: .mid)
      && key() != key(control: true))
check("the colour scheme, Increase Contrast and the fill each change the key",
      key() != key(dark: true) && key() != key(strong: true) && key() != key(fill: 0x1E232BFF))
check("the display scale changes the key", key() != key(scale: 2))
let radius12 = WardLightSlice.plan(.rounded(radius: 12, continuous: true), width: 300, height: 120, reach: 8,
                                   inner: false, scale: 3)!
let circular16 = WardLightSlice.plan(.rounded(radius: 16, continuous: false), width: 300, height: 120, reach: 8,
                                     inner: false, scale: 3)!
check("the radius and the corner style change the key", key() != key(radius12) && key() != key(circular16))
let h44 = WardLightSlice.plan(.capsule(continuous: true), width: 200, height: 44, reach: 8, inner: false, scale: 3)!
let h44b = WardLightSlice.plan(.capsule(continuous: true), width: 200, height: 44.1, reach: 8, inner: false, scale: 3)!
let h45 = WardLightSlice.plan(.capsule(continuous: true), width: 200, height: 44.4, reach: 8, inner: false, scale: 3)!
check("an uncut axis is keyed by its pixel, not its fraction of one", key(h44) == key(h44b) && key(h44) != key(h45))
check("a capsule is not a rounded rectangle", key(h44) != key(basePlan))
check("fills pack to RGBA bytes",
      WardLightSlice.pack(red: 1, green: 0, blue: 0.5, alpha: 1) == 0xFF0080FF
      && WardLightSlice.pack(red: -1, green: 2, blue: 0, alpha: 0) == 0x00FF0000)

// MARK: stretching a cut image is drawing the shape larger

// A rounded rectangle's lights drawn the way the app draws them: the shape's
// coverage moved by the light's offset and blurred by a Gaussian (SwiftUI's
// shadow radius is twice its deviation), the face's own coverage blurred by
// the press's softening. The corner is a circle of the curve's length, the
// widest the continuous curve gets.
func gaussian(_ sigma: Double) -> [Double] {
    guard sigma > 0 else { return [1] }
    let n = Int((4 * sigma).rounded(.up))
    let k = (-n...n).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let total = k.reduce(0, +)
    return k.map { $0 / total }
}

func blur(_ grid: [[Double]], sigma: Double) -> [[Double]] {
    let k = gaussian(sigma), n = k.count / 2
    let h = grid.count, w = grid[0].count
    var across = grid
    for y in 0..<h { for x in 0..<w {
        var sum = 0.0
        for i in -n...n { let xx = x + i; if xx >= 0 && xx < w { sum += grid[y][xx] * k[i + n] } }
        across[y][x] = sum
    } }
    var down = across
    for y in 0..<h { for x in 0..<w {
        var sum = 0.0
        for i in -n...n { let yy = y + i; if yy >= 0 && yy < h { sum += across[yy][x] * k[i + n] } }
        down[y][x] = sum
    } }
    return down
}

/// Coverage of a rounded rectangle at (0,0) of size w x h, sampled at cell
/// centres, with shifts.
func coverage(w: Double, h: Double, corner: Double, pad: Int, dx: Double, dy: Double) -> [[Double]] {
    let rows = Int(h) + 2 * pad, cols = Int(w) + 2 * pad
    var grid = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
    for y in 0..<rows { for x in 0..<cols {
        let px = Double(x - pad) + 0.5 - dx - w / 2, py = Double(y - pad) + 0.5 - dy - h / 2
        let qx = abs(px) - (w / 2 - corner), qy = abs(py) - (h / 2 - corner)
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        let inside = min(max(qx, qy), 0)
        grid[y][x] = outside + inside - corner <= 0 ? 1 : 0
    } }
    return grid
}

/// What a raised face (or a pressable one at rest, with `soften`) draws
/// outside its shape: the shade and the highlight, each at its strength.
func lights(w: Double, h: Double, radius: Double, spec: WardReliefSpec, soften: Double, pad: Int) -> [[Double]] {
    let corner = (radius * WardLightSlice.continuousCurve).rounded(.up)
    var total: [[Double]]?
    for light in [spec.shade, spec.highlight] {
        var g = coverage(w: w, h: h, corner: corner, pad: pad, dx: light.x, dy: light.y)
        let sigma = (light.radius / 2 * light.radius / 2 + soften * soften).squareRoot()
        g = blur(g, sigma: sigma).map { $0.map { $0 * light.alpha } }
        total = total.map { zip($0, g).map { zip($0, $1).map(+) } } ?? g
    }
    return total!
}

func compare(look: String, lift: WardLift, spec: WardReliefSpec, soften: Double, reach: Int) {
    let radius = 16.0
    guard let plan = WardLightSlice.plan(.rounded(radius: radius, continuous: true), width: 400, height: 400,
                                         reach: reach, inner: false, scale: 1) else {
        check("\(look) \(lift): a plan", false); return
    }
    let small = lights(w: plan.width, h: plan.height, radius: radius, spec: spec, soften: soften, pad: plan.pad)
    let (bigW, bigH) = (plan.width + 37, plan.height + 23)
    let big = lights(w: bigW, h: bigH, radius: radius, spec: spec, soften: soften, pad: plan.pad)
    var worst = 0.0
    for y in 0..<big.count {
        let sy = WardLightSlice.sourceIndex(y, shown: big.count, source: small.count, cap: plan.capY)
        for x in 0..<big[0].count {
            let sx = WardLightSlice.sourceIndex(x, shown: big[0].count, source: small[0].count, cap: plan.capX)
            worst = max(worst, abs(big[y][x] - small[sy][sx]))
        }
    }
    // an 8-bit channel steps by 1/255
    check("\(look) \(lift): the stretched slice matches the larger drawing to within one 8-bit step",
          worst < 1.0 / 255, "worst \(worst * 255) steps")
}

for lift in WardLift.allCases {
    let raised = WardRelief.raised(lift, dark: false)
    compare(look: "raised", lift: lift, spec: raised, soften: 0, reach: WardLightSlice.reach(raised))
    let press = WardPress.spec(lift, depth: 0, dark: false)
    compare(look: "press at rest", lift: lift, spec: raised, soften: press.blur,
            reach: WardLightSlice.reach(press))
}

// a cap one point too small shows the test can fail
do {
    let raised = WardRelief.raised(.high, dark: false)
    let reach = WardLightSlice.reach(raised)
    let plan = WardLightSlice.plan(.rounded(radius: 16, continuous: true), width: 400, height: 400, reach: reach,
                                   inner: false, scale: 1)!
    let small = lights(w: plan.width, h: plan.height, radius: 16, spec: raised, soften: 0, pad: plan.pad)
    let tooSmall = lights(w: 40, h: 40, radius: 16, spec: raised, soften: 0, pad: plan.pad)
    var differs = false
    for x in 0..<min(small[0].count, tooSmall[0].count) where abs(small[plan.capY][x] - tooSmall[plan.capY][x]) > 1.0 / 255 {
        differs = true
    }
    check("a shape smaller than the cut needs is not the same picture (so it is drawn whole)", differs)
}

// MARK: counting the faces

check("a path's tag says how it was drawn",
      WardReliefPath.cached.tag == "cached" && WardReliefPath.live(.shape).tag == "live:shape"
      && WardReliefPath.live(.plan(width: 12, height: 40)).tag == "live:plan@12x40"
      && WardReliefPath.live(.bare).tag == "live:none" && WardReliefPath.live(.late).tag == "live:late"
      && WardReliefPath.live(.fill).tag == "live:fill" && WardReliefPath.live(.failed).tag == "live:failed"
      && WardReliefPath.live(.press).tag == "live:press" && WardReliefPath.live(.off).tag == "live:off"
      && WardReliefPath.live(.empty).tag == "live:empty")
check("a face with lights that drew live is a miss; cached, lightless and empty ones are not",
      WardReliefPath.live(.shape).missed && WardReliefPath.live(.late).missed && WardReliefPath.live(.press).missed
      && WardReliefPath.live(.plan(width: 1, height: 1)).missed && WardReliefPath.live(.failed).missed
      && !WardReliefPath.cached.missed && !WardReliefPath.live(.bare).missed && !WardReliefPath.live(.empty).missed)
let sample: [WardReliefPath] = [.live(.plan(width: 0, height: 0)), .cached, .live(.shape), .cached, .live(.plan(width: 0, height: 0)),
                                .cached, .live(.plan(width: 0, height: 0))]
check("the field counts the faces by tag, cached first, then the images made",
      WardReliefCensus.field(paths: sample, made: 15, seconds: 0.0424)
      == " relief=cached:3,live:plan@0x0:3,live:shape:1 made=15/42ms",
      WardReliefCensus.field(paths: sample, made: 15, seconds: 0.0424))
check("with no faces it says none; failures are added after",
      WardReliefCensus.field(paths: [], made: 0, seconds: 0) == " relief=none made=0/0ms"
      && WardReliefCensus.field(paths: [.cached], made: 1, seconds: 0.002, failures: 2) == " relief=cached:1 made=1/2ms failed=2")
check("the field is one line", !WardReliefCensus.field(paths: sample, made: 1, seconds: 1).contains("\n"))

let census = WardReliefCensus()
let first = census.newFace(), second = census.newFace()
check("faces are numbered from 1, each its own", first >= 1 && second == first + 1)
census.note(first, .live(.late)); census.note(second, .cached)
census.note(first, .cached)
census.made(seconds: 0.010); census.made(seconds: 0.005); census.failure()
check("a face redrawn counts once, as it was last drawn",
      census.field() == " relief=cached:2 made=2/15ms failed=1", census.field())
census.forget(second)
check("a face that goes is dropped from the count", census.field() == " relief=cached:1 made=2/15ms failed=1", census.field())

print(failures.isEmpty ? "\nALL WARD LIGHT SLICE TESTS PASS"
                       : "\n\(failures.count) WARD LIGHT SLICE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
