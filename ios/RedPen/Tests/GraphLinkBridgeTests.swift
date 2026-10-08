// A Neurons link as one dendrite joining two cells (GraphLinkBridge.swift),
// as the owner asked ("use dendrites and extend them / make the tube
// connected both ways so the 2 cell surfaces connected become
// continuous"): the outline of cell and tube, as seen, is the membrane's
// smooth minimum, so it leaves each cell's disc along it and narrows
// smoothly to the tube's own width; the same at both ends; the samples
// crowd where it curves; nothing breaks for a thick tube, a tiny cell or a
// link pointing at the camera.
//
// Compiled with Features/Notes/GraphLinkBridge.swift, which imports only
// Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func length(_ a: SIMD3<Float>) -> Float { (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() }

let bridge = GraphLinkBridge()

// B1 - the membrane's smooth minimum (the polynomial form it blends with)
var worstMin: Float = 0
for a in stride(from: Float(-1), through: 1, by: 0.05) {
    for b in stride(from: Float(-1), through: 1, by: 0.05) {
        for k in [Float(0.1), 0.3, 0.6] {
            let w: Float = min(max(0.5 + 0.5 * (b - a) / k, 0), 1)
            let poly: Float = b * (1 - w) + a * w - k * w * (1 - w)
            worstMin = max(worstMin, abs(GraphLinkBridge.smin(a, b, k) - poly))
        }
    }
}
check("B1 the smooth minimum is the membrane's", worstMin < 1e-5, "\(worstMin)")

// B2 to B5 - the outline, for the cells the map draws (membrane radius 0.34
// to 0.6, the tube's half width near and far) and a few beyond
let cases: [(Float, Float)] = [(0.34, 0.088), (0.45, 0.088), (0.6, 0.088), (0.34, 0.118), (0.6, 0.118),
                               (1, 0.3), (0.5, 0.05)]
for (r, h) in cases {
    let name = "R \(r) h \(h)"
    let k: Float = bridge.blend * r
    let j: Float = bridge.join(r: r, h: h)
    let f: Float = bridge.flare(r: r, h: h)
    func width(_ x: Float) -> Float { bridge.halfWidth(rho: x, r: r, h: h) }

    check("B2a \(name): the join is beside the centre, before the flare's end", j > 0 && j < r && f > j, "\(j) \(f)")
    let beyond: [Float] = [f, f + 0.001, f * 1.5, f + 10].map(width)
    check("B2b \(name): the tube's own width from the flare's end out", beyond.allSatisfy { $0 == h }, "\(beyond)")

    let atJoin: Float = width(j)
    check("B3a \(name): h + k across at the join", abs(atJoin - (h + k)) < 1e-4 * r, "\(atJoin) for \(h + k)")
    check("B3b \(name): the outline there on the cell's disc", abs(j * j + (h + k) * (h + k) - r * r) < 1e-4 * r * r,
          "\(j * j + (h + k) * (h + k)) for \(r * r)")
    check("B3c \(name): never wider nearer the centre than the join", width(0) == atJoin && width(j * 0.5) == atJoin,
          "\(width(0)) \(width(j * 0.5)) \(atJoin)")

    var previous: Float = .infinity
    var steady: Bool = true
    var inside: Bool = true
    for i in 0...200 {
        let w: Float = width(j + (f - j) * Float(i) / 200)
        if w > previous + 1e-5 * r { steady = false }
        if w < h || w > h + k + 1e-4 * r { inside = false }
        previous = w
    }
    check("B4a \(name): narrows steadily from the join to the flare's end", steady)
    check("B4b \(name): between the tube's width and h + k throughout", inside)
    let middle: Float = width((j + f) * 0.5)
    check("B4c \(name): a real flare (well wider than the tube halfway)", middle > h + 0.05 * k, "\(middle)")

    // the slope just past the join (extrapolated from two steps) is the
    // disc's there, and just before the flare's end the tube's (flat)
    let e: Float = 0.002 * r
    let outA: Float = (width(j + e) - atJoin) / e
    let outB: Float = (width(j + 2 * e) - atJoin) / (2 * e)
    let slope: Float = 2 * outA - outB
    let disc: Float = -j / (h + k)
    check("B5a \(name): leaves the disc along it (tangent at the join)", abs(slope - disc) < 0.05 * max(abs(disc), 1),
          "\(slope) for \(disc)")
    let inA: Float = (h - width(f - e)) / e
    let inB: Float = (h - width(f - 2 * e)) / (2 * e)
    let flat: Float = 2 * inA - inB
    check("B5b \(name): meets the tube along it (flat at the flare's end)", abs(flat) < 0.05, "\(flat)")
}

// B6 - nothing breaks: a tube thicker than the cell, a vanishing cell, no tube
var broken: [String] = []
for (r, h) in [(Float(0), Float(0.1)), (0.00001, 0.1), (0.1, 0.5), (0.2, 0.2), (0.34, 0), (1, 2), (0.34, 0.088)] {
    for rho in [Float(0), 0.05, 0.2, 0.5, 1, 3] {
        let w: Float = bridge.halfWidth(rho: rho, r: r, h: h)
        if !w.isFinite || w < h { broken.append("width \(w) at \(rho) for R \(r) h \(h)") }
    }
    for sine in [Float(0), 0.2, 0.5, 1] {
        let t: Float = bridge.trim(r: r, h: h, sine: sine)
        if !t.isFinite || t < 0 { broken.append("trim \(t) at sine \(sine) for R \(r) h \(h)") }
    }
    if !bridge.join(r: r, h: h).isFinite || !bridge.flare(r: r, h: h).isFinite { broken.append("join or flare for R \(r) h \(h)") }
}
check("B6 finite, never narrower than the tube, whatever the sizes", broken.isEmpty, "\(broken.prefix(4))")

// B7 - the samples: 0 to 1, always further on, crowded at both ends alike
let steps: Int = 400
var onwards: Bool = true
for i in 0..<steps where GraphLinkBridge.warp(Float(i + 1) / Float(steps)) <= GraphLinkBridge.warp(Float(i) / Float(steps)) {
    onwards = false
}
check("B7a runs from 0 to 1, always further on",
      abs(GraphLinkBridge.warp(0)) < 1e-6 && abs(GraphLinkBridge.warp(1) - 1) < 1e-5 && onwards)
let du: Float = 0.001
let atEnd: Float = (GraphLinkBridge.warp(du) - GraphLinkBridge.warp(0)) / du
let atMiddle: Float = (GraphLinkBridge.warp(0.5 + du) - GraphLinkBridge.warp(0.5 - du)) / (2 * du)
check("B7b crowded at the ends, sparse in the middle", abs(atEnd - 0.15) < 0.01 && abs(atMiddle - 1.85) < 0.01,
      "\(atEnd) \(atMiddle)")
let mirrored: Bool = (0...100).allSatisfy { i in
    let u: Float = Float(i) / 100
    return abs(GraphLinkBridge.warp(1 - u) - (1 - GraphLinkBridge.warp(u))) < 1e-5
}
check("B7c the same at both ends", mirrored)

// B8 - the flare eases out as the link turns towards the view
let gates: [Float] = stride(from: Float(0), through: 1, by: 0.01).map { GraphLinkBridge.gate(sine: $0) }
let rising: Bool = zip(gates, gates.dropFirst()).allSatisfy { $0 <= $1 }
check("B8 no flare within about 17 degrees of the view, all of it from 30, steadily between",
      GraphLinkBridge.gate(sine: 0.3) == 0 && GraphLinkBridge.gate(sine: 0.5) == 1 && GraphLinkBridge.gate(sine: 1) == 1
      && abs(GraphLinkBridge.gate(sine: 0.4) - 0.5) < 1e-5 && rising)

// B9 - seen from the camera
let up = SIMD3<Float>(0, 0, 1)
let slant: Float = GraphLinkBridge.sine(SIMD3<Float>(1, 0, 1) / Float(2).squareRoot(), up)
check("B9a the sine of the link's angle to the view",
      abs(GraphLinkBridge.sine(SIMD3<Float>(1, 0, 0), up) - 1) < 1e-6 && GraphLinkBridge.sine(up, up) < 1e-3
      && abs(slant - Float(0.5).squareRoot()) < 1e-5, "\(slant)")
check("B9b how far a point is from a cell as seen",
      abs(GraphLinkBridge.seen(SIMD3<Float>(3, 4, 7), view: up) - 5) < 1e-5
      && GraphLinkBridge.seen(SIMD3<Float>(0, 0, 9), view: up) < 1e-5)

// B10 - the trim: at the join side on, capped towards the view
let joinNear: Float = bridge.join(r: 0.45, h: 0.088)
check("B10 starts at the join side on, further out slanting, capped within 30 degrees",
      bridge.trim(r: 0.45, h: 0.088, sine: 1) == joinNear
      && abs(bridge.trim(r: 0.45, h: 0.088, sine: 0.7) - joinNear / 0.7) < 1e-6
      && bridge.trim(r: 0.45, h: 0.088, sine: 0.1) == joinNear / 0.5)

// B11 - a whole link as GraphRibbonWriter draws it: two cells side on, the
// strip continuous with both (its first and last edges on their discs),
// flared at both ends, its own width in the middle
let h: Float = 0.088
let eye = SIMD3<Float>(1.5, 0, 40)
let pa = SIMD3<Float>(0, 0, 0)
let pb = SIMD3<Float>(3, 0, 0)
let dir = SIMD3<Float>(1, 0, 0)
let endA: GraphLinkBridge.End = bridge.end(centre: pa, radius: 0.36, eye: eye, dir: dir, h: h, length: 3)
let endB: GraphLinkBridge.End = bridge.end(centre: pb, radius: 0.48, eye: eye, dir: dir, h: h, length: 3)
let start: SIMD3<Float> = pa + dir * endA.trim
let finish: SIMD3<Float> = pb - dir * endB.trim
let n: Int = 40
var widths: [Float] = []
var points: [SIMD3<Float>] = []
for i in 0...n {
    let t: Float = GraphLinkBridge.warp(Float(i) / Float(n))
    let p: SIMD3<Float> = start + (finish - start) * t
    points.append(p)
    widths.append(bridge.halfWidth(at: p, endA, endB, h: h))
}
check("B11a the cells' membrane radii, both flares drawn", abs(endA.radius - 0.45) < 1e-6 && abs(endB.radius - 0.6) < 1e-6
      && endA.gate > 0.999 && endB.gate > 0.999, "\(endA) \(endB)")
let firstEdge: Float = length(points[0] + SIMD3<Float>(0, widths[0], 0) - pa)
let lastEdge: Float = length(points[n] + SIMD3<Float>(0, widths[n], 0) - pb)
check("B11b continuous with both cells: the strip's first and last edges on their discs",
      abs(firstEdge - endA.radius) < 0.002 && abs(lastEdge - endB.radius) < 0.002, "\(firstEdge) \(lastEdge)")
check("B11c flared at both ends, its own width in the middle",
      widths[0] > h + 0.9 * bridge.blend * endA.radius && widths[n] > h + 0.9 * bridge.blend * endB.radius
      && widths[n / 2] == h, "\(widths[0]) \(widths[n / 2]) \(widths[n])")
let gaps: [Float] = zip(points, points.dropFirst()).map { length($1 - $0) }
check("B11d samples closest at the ends", (gaps.first ?? 0) < 0.3 * gaps[n / 2] && (gaps.last ?? 0) < 0.3 * gaps[n / 2],
      "\(gaps.first ?? 0) \(gaps[n / 2]) \(gaps.last ?? 0)")
let towards: GraphLinkBridge.End = bridge.end(centre: pa, radius: 0.36, eye: SIMD3<Float>(40, 0, 0.5), dir: dir, h: h,
                                              length: 3)
check("B11e a link pointing at the camera: no flare, the trim capped",
      towards.gate == 0 && abs(towards.trim - bridge.join(r: towards.radius, h: h) / 0.5) < 1e-6, "\(towards)")
let close: GraphLinkBridge.End = bridge.end(centre: pa, radius: 0.36, eye: eye, dir: dir, h: h, length: 0.5)
check("B11f a short link: each trim at most 0.45 of it", close.trim <= 0.225 + 1e-6, "\(close.trim)")
let same: GraphLinkBridge.End = bridge.end(centre: pa, radius: 0.36, eye: pa, dir: dir, h: h, length: 3)
check("B11g the eye at a cell's centre: a view all the same", length(same.view) > 0.999 && same.trim.isFinite)

// B12 - where a link leaves each cell, for the membrane to hide its rim
// across: the outline's half width at the join over the membrane radius,
// opening with the strip
check("B12a a mouth as wide as the outline at the join",
      abs(bridge.mouthWidth(r: 0.45, h: h) - (h / 0.45 + 0.3)) < 1e-6 && bridge.mouthWidth(r: 0, h: h) == 0,
      "\(bridge.mouthWidth(r: 0.45, h: h))")
let shut: (first: Float, second: Float) = GraphLinkBridge.open(grow: 0)
let leaving: (first: Float, second: Float) = GraphLinkBridge.open(grow: 0.025)
let left: (first: Float, second: Float) = GraphLinkBridge.open(grow: 0.05)
let midway: (first: Float, second: Float) = GraphLinkBridge.open(grow: 0.9)
let grown: (first: Float, second: Float) = GraphLinkBridge.open(grow: 1)
check("B12b the first mouth opens as the strip leaves its cell, the second as it arrives",
      shut.first == 0 && shut.second == 0 && leaving.first > 0.2 && leaving.first < 0.8 && left.first == 1
      && midway.first == 1 && midway.second == 0 && grown.first == 1 && grown.second == 1,
      "\(shut) \(leaving) \(left) \(midway) \(grown)")
if let both = bridge.mouths(from: pa, to: pb, ra: 0.36, rb: 0.48, h: h, grow: 1) {
    check("B12c two mouths facing each other, each its cell's width",
          length(both.first.dir - dir) < 1e-6 && length(both.second.dir + dir) < 1e-6
          && abs(both.first.width - (h / 0.45 + 0.3)) < 1e-6 && abs(both.second.width - (h / 0.6 + 0.3)) < 1e-6,
          "\(both)")
} else {
    check("B12c two mouths facing each other, each its cell's width", false, "nil")
}
let half = bridge.mouths(from: pa, to: pb, ra: 0.36, rb: 0.48, h: h, grow: 0.5)
check("B12d half grown: the first mouth open, the second shut",
      half.map { abs(length($0.first.dir) - 1) < 1e-6 && length($0.second.dir) == 0 } ?? false, "\(String(describing: half))")
check("B12e two cells in one place: no mouths", bridge.mouths(from: pa, to: pa, ra: 0.36, rb: 0.48, h: h, grow: 1) == nil)

// B13 - a frame's mouths: at most four a cell, the most open as seen first;
// none for a link pointing at the camera or a mouth still shut
var table = GraphLinkMouths()
let front = SIMD3<Float>(0, 0, 40)
let opens: [Float] = [0.2, 0.9, 0.5, 1.0, 0.7]
for (i, open) in opens.enumerated() {
    let side: SIMD3<Float> = i % 2 == 0 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
    table.add(GraphLinkBridge.Mouth(dir: side * open, width: 0.5), cell: 0, centre: pa, eye: front)
}
let kept: [Float] = table.mouths(of: 0).map { length($0.dir) }
check("B13a four a cell, the most open first", kept.count == 4 && zip(kept, [1.0, 0.9, 0.7, 0.5]).allSatisfy { abs($0 - $1) < 1e-6 },
      "\(kept)")
table.add(GraphLinkBridge.Mouth(dir: SIMD3<Float>(0, 0, 1), width: 0.5), cell: 1, centre: pa, eye: front)
table.add(GraphLinkBridge.Mouth(dir: SIMD3<Float>(0, 0, 0), width: 0.5), cell: 2, centre: pa, eye: front)
check("B13b none pointing at the camera, none shut", table.mouths(of: 1).isEmpty && table.mouths(of: 2).isEmpty)
let aslant: SIMD3<Float> = SIMD3<Float>(0.4, 0, (1 - 0.16 as Float).squareRoot())
table.add(GraphLinkBridge.Mouth(dir: aslant, width: 0.5), cell: 3, centre: pa, eye: front)
table.add(GraphLinkBridge.Mouth(dir: SIMD3<Float>(0.6, 0, 0), width: 0.5), cell: 3, centre: pa, eye: front)
let ranked: [Float] = table.mouths(of: 3).map { length($0.dir) }
check("B13c a link half turned to the camera ranks below a wide-open one seen side on",
      ranked.count == 2 && abs(ranked[0] - 0.6) < 1e-6 && abs(ranked[1] - 1) < 1e-5, "\(ranked)")
table.removeAll()
check("B13d a new frame starts empty", table.mouths(of: 0).isEmpty && table.mouths(of: 3).isEmpty)

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
