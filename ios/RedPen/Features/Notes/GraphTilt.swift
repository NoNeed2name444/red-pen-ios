import Foundation

// MARK: - The tilted default view of the Neurons and Space maps (T0057)
//
// The maps open pitched about the screen's horizontal axis, so they read as
// ground seen from above at an angle, with a near side and a far side the
// depth fade can work on (docs/design/depth-fade.md). The camera stands on
// the near (south) side, looking north and down: at `middle + Rx(θ)·(cx, cy,
// D)` with orientation Rx(θ); at θ = 0 that is the face-on pose GraphFraming
// has always used. Performance and the plain graph stay at 0.
//
// `fit` finds the least D for which a shift (cx, cy) across the camera's
// view keeps every framed point, with its pad, inside the window rectangle
// GraphFraming uses at the same fill. A point's depth does not depend on the
// shift, so for one D the check is linear in cx and cy (an interval each);
// and since every interval widens as D grows, the least D is found by
// halving. For a symmetric sheet of half-height h it is D = h·cos θ / t with
// cy = -t·h·sin θ, the focus at F = D and the far edge at (1 + t·tan θ)·F,
// t = tan(27.5°) × fill × share.
//
// Real depth: after each planner's 2D layout every top cluster is lifted to
// z = A·u(id), u from FNV-1a 64 of its stable id (never Swift's hashValue,
// which is seeded per launch), with A the largest of 0.35, 0.25, 0.15 and 0
// times H (half the map's larger extent) that keeps the map legible in the
// canonical default views (`legible`).
//
// Foundation only (stdlib SIMD), tested on Linux (Tests/GraphTiltTests.swift).

/// The part of the view the graph is fitted to (GraphTilt.window).
nonisolated struct GraphWindow: Equatable {
    /// Its width over its height.
    let aspect: Float
    /// Its height, as a share of the whole view's.
    let share: Float
    /// How far its middle is right of the view's middle, in view heights.
    let across: Float
    /// How far its middle is above the view's middle, in view heights.
    let up: Float
}

/// How much of the space's view, on each side, is under glass, in points.
/// Left and right as on screen, whatever the writing direction.
nonisolated struct GraphInsets: Equatable {
    var top: Float = 0
    var left: Float = 0
    var bottom: Float = 0
    var right: Float = 0

    init(top: Float = 0, left: Float = 0, bottom: Float = 0, right: Float = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// One tilted framing: the camera `distance` back along its own axis and
/// shifted by `shift` across its view, the focus (the middle) at depth
/// `focus`, the deepest framed point at `deepest`, and the reach the depth
/// band is measured in.
nonisolated struct GraphTiltFit: Equatable {
    let distance: Float
    let shift: SIMD2<Float>
    let focus: Float
    let deepest: Float
    /// (deepest / focus) - 1, kept within GraphTilt.reachRange.
    let reach: Float
}

nonisolated enum GraphTilt {
    /// The camera's vertical field of view (GraphFraming.fieldOfView).
    static let fieldOfView: Float = 55
    /// The default pitch, in degrees: Neurons 35, Space 45.
    static let neuronsDegrees: Float = 35
    static let spaceDegrees: Float = 45
    /// The extra pitch for a wide window: none (only a repair may raise it).
    static let wideExtraDegrees: Float = 0
    /// How far a vertical drag may pitch the map, in degrees.
    static let lowestDegrees: Float = 10
    static let highestDegrees: Float = 75
    /// The reach is never taken as less or more than these.
    static let reachRange: ClosedRange<Float> = 0.15...1.0
    /// The share of the reach that stays crisp in the whole view: the depth
    /// band's `a` (graphtilt checks they agree).
    static let crispShare: Float = 0.20
    /// The canonical framings' fill (the Universe's envelope).
    static let canonicalFill: Float = 0.88
    /// The legibility rule's limit: overlap and cover at most this share.
    static let mostCovered: Float = 0.15
    /// The amplitudes tried, as shares of H, largest first.
    static let amplitudes: [Float] = [0.35, 0.25, 0.15]

    static func radians(_ degrees: Float) -> Float { degrees * Float.pi / 180 }

    /// A theme's default pitch (radians); 0 for Performance.
    static func angle(_ theme: GraphTheme, wide: Bool = false) -> Float {
        let base: Float
        switch theme {
        case .neurons: base = neuronsDegrees
        case .space: base = spaceDegrees
        case .performance: return 0
        }
        return radians(base + (wide ? wideExtraDegrees : 0))
    }

    /// `v` turned by `angle` about x (Rx).
    static func rotX(_ angle: Float, _ v: SIMD3<Float>) -> SIMD3<Float> {
        let c: Float = cos(angle)
        let s: Float = sin(angle)
        return SIMD3<Float>(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
    }

    /// The camera's place for a fit, from the middle: Rx(θ)·(cx, cy, D).
    static func offset(_ fit: GraphTiltFit, tilt: Float) -> SIMD3<Float> {
        rotX(tilt, SIMD3<Float>(fit.shift.x, fit.shift.y, fit.distance))
    }

    // MARK: the window

    static var tanHalf: Float { tan(fieldOfView * Float.pi / 360) }

    /// The part of a `width` by `height` view (points) that is not under
    /// glass: the bars at the top, and the switcher, capture row, dock or
    /// keyboard at the bottom. Never less than a third of the view each way.
    static func window(width: Float, height: Float, insets: GraphInsets) -> GraphWindow {
        let wide: Float = max(width, 1)
        let tall: Float = max(height, 1)
        let sides: Float = insets.left + insets.right
        let ends: Float = insets.top + insets.bottom
        let seenWidth: Float = max(wide - sides, wide / 3)
        let seenHeight: Float = max(tall - ends, tall / 3)
        let aspect: Float = seenWidth / seenHeight
        let share: Float = seenHeight / tall
        // the window's middle from the view's, in view heights
        let across: Float = (insets.left - insets.right) / 2 / tall
        let up: Float = (insets.bottom - insets.top) / 2 / tall
        return GraphWindow(aspect: aspect, share: share, across: across, up: up)
    }

    /// The canonical default views the amplitude is judged in: the
    /// preview's iPhone portrait and iPad landscape windows (their glass as
    /// the preview lays it out, near enough).
    static let canonical: [GraphWindow] = [
        window(width: 393, height: 852, insets: GraphInsets(top: 118, bottom: 158)),
        window(width: 1194, height: 834, insets: GraphInsets(top: 86, bottom: 112))
    ]

    // MARK: the fit

    /// The least distance, and the shift, that keep every point (relative
    /// to the middle the camera orbits) with its pad inside `fill` of
    /// `window`, seen pitched by `tilt`.
    static func fit(points: [SIMD3<Float>], pads: [Float], window: GraphWindow, fill: Float,
                    tilt: Float) -> GraphTiltFit {
        let seen: [SIMD3<Float>] = points.map { rotX(-tilt, $0) }
        let pad: [Float] = points.indices.map { $0 < pads.count ? max(pads[$0], 0) : 0 }
        guard !seen.isEmpty else {
            return GraphTiltFit(distance: 1, shift: .zero, focus: 1, deepest: 1, reach: reachRange.lowerBound)
        }
        var low: Float = 0
        var high: Float = 1
        for (p, r) in zip(seen, pad) { high = max(high, p.z + r * 2 + 1) }
        var tries: Int = 0
        while shift(seen: seen, pads: pad, window: window, fill: fill, distance: high) == nil, tries < 80 {
            low = high
            high *= 2
            tries += 1
        }
        for _ in 0..<64 {
            let mid: Float = (low + high) * 0.5
            guard mid > low, mid < high else { break }
            if shift(seen: seen, pads: pad, window: window, fill: fill, distance: mid) != nil {
                high = mid
            } else {
                low = mid
            }
        }
        let d: Float = high
        let s: SIMD2<Float> = shift(seen: seen, pads: pad, window: window, fill: fill, distance: d) ?? .zero
        var deepest: Float = d
        for p in seen { deepest = max(deepest, d - p.z) }
        let raw: Float = deepest / d - 1
        let reach: Float = min(max(raw, reachRange.lowerBound), reachRange.upperBound)
        return GraphTiltFit(distance: d, shift: s, focus: d, deepest: deepest, reach: reach)
    }

    /// The shift (cx, cy) that keeps every point inside at `distance`, the
    /// middle of what is allowed; nil when none does.
    static func shift(points: [SIMD3<Float>], pads: [Float], window: GraphWindow, fill: Float, tilt: Float,
                      distance: Float) -> SIMD2<Float>? {
        let seen: [SIMD3<Float>] = points.map { rotX(-tilt, $0) }
        let pad: [Float] = points.indices.map { $0 < pads.count ? max(pads[$0], 0) : 0 }
        return shift(seen: seen, pads: pad, window: window, fill: fill, distance: distance)
    }

    private static func shift(seen: [SIMD3<Float>], pads: [Float], window: GraphWindow, fill: Float,
                              distance: Float) -> SIMD2<Float>? {
        let tanUp: Float = tanHalf * fill * window.share
        let tanSide: Float = tanUp * max(window.aspect, 0.1)
        let leanX: Float = window.across * 2 * tanHalf
        let leanY: Float = window.up * 2 * tanHalf
        var xLow: Float = -.infinity, xHigh: Float = .infinity
        var yLow: Float = -.infinity, yHigh: Float = .infinity
        for (p, r) in zip(seen, pads) {
            let depth: Float = distance - p.z
            // room each way at this depth, the pad taken at its nearest
            let roomX: Float = (depth - r) * tanSide - r
            let roomY: Float = (depth - r) * tanUp - r
            guard roomX >= 0, roomY >= 0 else { return nil }
            let mx: Float = p.x - depth * leanX
            let my: Float = p.y - depth * leanY
            xLow = max(xLow, mx - roomX)
            xHigh = min(xHigh, mx + roomX)
            yLow = max(yLow, my - roomY)
            yHigh = min(yHigh, my + roomY)
        }
        guard xLow <= xHigh, yLow <= yHigh else { return nil }
        return SIMD2<Float>((xLow + xHigh) * 0.5, (yLow + yHigh) * 0.5)
    }

    /// Where a point (relative to the middle) is seen from the fit's camera:
    /// across and up in tangents, and its depth along the view.
    static func project(_ p: SIMD3<Float>, fit: GraphTiltFit, tilt: Float) -> (x: Float, y: Float, depth: Float) {
        let q: SIMD3<Float> = rotX(-tilt, p)
        let depth: Float = fit.distance - q.z
        let safe: Float = max(depth, 0.000_001)
        return ((q.x - fit.shift.x) / safe, (q.y - fit.shift.y) / safe, depth)
    }

    // MARK: real depth

    /// A stable number in [-1, 1) from a cluster's id: FNV-1a 64 of its
    /// UTF-8, the same on every launch and whatever the order.
    static func u(_ id: String) -> Float {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let unit: Double = Double(hash >> 11) / 9_007_199_254_740_992
        return Float(unit * 2 - 1)
    }

    /// One top cluster as the planners hand it over: its stable id, its
    /// centre on the sheet and its radius.
    typealias Cluster = (id: String, centre: SIMD2<Float>, radius: Float)

    /// Half the map's larger in-plane extent.
    static func half(_ clusters: [Cluster]) -> Float {
        guard let first = clusters.first else { return 0 }
        var low: SIMD2<Float> = first.centre - first.radius
        var high: SIMD2<Float> = first.centre + first.radius
        for c in clusters {
            low = pointwiseMin(low, c.centre - c.radius)
            high = pointwiseMax(high, c.centre + c.radius)
        }
        let size: SIMD2<Float> = high - low
        return max(size.x, size.y) * 0.5
    }

    /// The amplitude A for a theme's top clusters: the largest candidate
    /// share of H the map stays legible at in every canonical view, else 0.
    static func amplitude(clusters: [Cluster], theme: GraphTheme) -> Float {
        let tilt: Float = angle(theme)
        guard tilt > 0, !clusters.isEmpty else { return 0 }
        return choose(half: half(clusters)) { legible(clusters: clusters, tilt: tilt, amplitude: $0) }
    }

    /// The first candidate amplitude (largest first, times `half`) that
    /// `passes`, else 0.
    static func choose(half h: Float, passes: (Float) -> Bool) -> Float {
        for share in amplitudes where passes(share * h) { return share * h }
        return 0
    }

    /// A cluster's z at amplitude `a`.
    static func z(_ id: String, amplitude a: Float) -> Float { a * u(id) }

    /// The legibility rule, at amplitude `a`, in every canonical view: two
    /// crisp clusters' projected discs overlap by at most 15% of the smaller
    /// disc in the whole view, and each cluster, flown to, is covered by
    /// nearer ones by at most 15%. A wide window turns the map a quarter, as
    /// Graph3DView does.
    static func legible(clusters: [Cluster], tilt: Float, amplitude a: Float) -> Bool {
        for window in canonical {
            let wide: Bool = window.aspect > 1
            let points: [SIMD3<Float>] = clusters.map { c in
                let xy: SIMD2<Float> = wide ? SIMD2<Float>(c.centre.y, -c.centre.x) : c.centre
                return SIMD3<Float>(xy.x, xy.y, z(c.id, amplitude: a))
            }
            let radii: [Float] = clusters.map { $0.radius }
            if !legible(points: points, radii: radii, window: window, tilt: tilt) { return false }
        }
        return true
    }

    /// The same in one window, for clusters already placed in 3D.
    static func legible(points: [SIMD3<Float>], radii: [Float], window: GraphWindow, tilt: Float) -> Bool {
        guard points.count > 1 else { return true }
        // the whole view: crisp pairs
        let middle: SIMD3<Float> = box(points, radii)
        let around: [SIMD3<Float>] = points.map { $0 - middle }
        let whole: GraphTiltFit = fit(points: around, pads: radii, window: window, fill: canonicalFill, tilt: tilt)
        let crispTo: Float = whole.focus * (1 + crispShare * whole.reach)
        var discs: [(x: Float, y: Float, r: Float, crisp: Bool)] = []
        for (p, r) in zip(around, radii) {
            let s = project(p, fit: whole, tilt: tilt)
            discs.append((s.x, s.y, r / max(s.depth, 0.000_001), s.depth <= crispTo))
        }
        for i in discs.indices where discs[i].crisp {
            for j in discs.indices where j > i && discs[j].crisp {
                let d: Float = hypot(discs[i].x - discs[j].x, discs[i].y - discs[j].y)
                let shared: Float = overlap(discs[i].r, discs[j].r, apart: d)
                let smaller: Float = Float.pi * pow(min(discs[i].r, discs[j].r), 2)
                if shared > mostCovered * smaller { return false }
            }
        }
        // each flown to: covered by nearer clusters, measured as angles
        // from the eye (a flown-in camera is close, so a neighbour's disc
        // is its true angular size, not its size over its depth)
        for i in points.indices {
            let flown: GraphTiltFit = fit(points: [.zero], pads: [radii[i]], window: window, fill: canonicalFill,
                                          tilt: tilt)
            let eye: SIMD3<Float> = offset(flown, tilt: tilt)
            let forward: SIMD3<Float> = rotX(tilt, SIMD3<Float>(0, 0, -1))
            let toMe: SIMD3<Float> = -eye
            let meDistance: Float = length(toMe)
            let mine: Float = asin(min(radii[i] / meDistance, 1))
            let myDepth: Float = dot(toMe, forward)
            var covered: Float = 0
            for j in points.indices where j != i {
                let v: SIMD3<Float> = points[j] - points[i] - eye
                let distance: Float = length(v)
                // one holding the eye covers everything
                if distance <= radii[j] { return false }
                guard dot(v, forward) < myDepth, dot(v, forward) > -radii[j] else { continue }
                let apart: Float = acos(min(max(dot(v, toMe) / (distance * meDistance), -1), 1))
                covered += overlap(mine, asin(min(radii[j] / distance, 1)), apart: apart)
            }
            if covered > mostCovered * Float.pi * mine * mine { return false }
        }
        return true
    }

    private static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { (a * b).sum() }
    private static func length(_ a: SIMD3<Float>) -> Float { dot(a, a).squareRoot() }

    /// The middle of the clusters' box (GraphMapBounds' rule, padded).
    private static func box(_ points: [SIMD3<Float>], _ radii: [Float]) -> SIMD3<Float> {
        guard let first = points.first else { return .zero }
        var low: SIMD3<Float> = first
        var high: SIMD3<Float> = first
        for (p, r) in zip(points, radii) {
            low = pointwiseMin(low, p - r)
            high = pointwiseMax(high, p + r)
        }
        return (low + high) * 0.5
    }

    /// The area two discs of radii `a` and `b`, `apart` between centres,
    /// share.
    static func overlap(_ a: Float, _ b: Float, apart d: Float) -> Float {
        let r1: Float = max(a, 0)
        let r2: Float = max(b, 0)
        guard d < r1 + r2 else { return 0 }
        if d <= abs(r1 - r2) { return Float.pi * pow(min(r1, r2), 2) }
        let one: Float = r1 * r1 * acos(min(max((d * d + r1 * r1 - r2 * r2) / (2 * d * r1), -1), 1))
        let two: Float = r2 * r2 * acos(min(max((d * d + r2 * r2 - r1 * r1) / (2 * d * r2), -1), 1))
        let k: Float = (-d + r1 + r2) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)
        return one + two - 0.5 * max(k, 0).squareRoot()
    }
}
