import Foundation

// MARK: - A cell's membrane: its body and dendrites as one surface
//
// The owner asked for a cell whose dendrites and body are "one entity, not
// multiple stitched things". Drawn as a sphere with tubes pushed into it,
// every piece drew its own glass edge where it met the next; so a cell's
// glass is now one closed mesh. Its surface is the zero set of one distance
// field - the unit soma smoothly united with each dendrite (a chain of round
// cones along the dendrite's curve; the blend itself makes the webbed
// trumpet where it leaves the soma) - meshed by surface nets on a regular
// grid, every vertex pulled onto the surface and given the field's gradient
// as its normal, so the fresnel edge runs unbroken from the soma round
// every dendrite and back.
//
// Plain SIMD3<Float> arithmetic only - no simd module, no SceneKit - so it
// is tested on Linux (Tests/NeuronMembraneTests.swift): closed, in one
// piece, on the surface, normals out. GraphNeuronLook makes the geometry
// from it once per variant.

/// One tapered tube of an arbor, in the soma's unit frame: a quadratic
/// curve from `start` through `bend` to `end`, `r0` thick at the start and
/// `r1` at the tip; `s0`...`s1` its share of the dendrite's length (the
/// shader fades and beads by it). `flare` widens the base into a trumpet
/// (by flare * (1 - t)^4 along it), so a dendrite flows out of the glass
/// round the soma, as in the owner's close-up.
nonisolated struct NeuronBranch: Sendable {
    let start: SIMD3<Float>
    let bend: SIMD3<Float>
    let end: SIMD3<Float>
    let r0: Float
    let r1: Float
    let s0: Float
    let s1: Float
    var flare: Float = 0

    /// The point `t` of the way along the curve (0 to 1).
    func point(_ t: Float) -> SIMD3<Float> {
        let u: Float = 1 - t
        let ab: SIMD3<Float> = start * (u * u) + bend * (2 * u * t)
        return ab + end * (t * t)
    }
}

/// A cell's soma and dendrites as one closed surface, in the soma's unit
/// frame: positions, unit normals pointing out of the cell, and triangles
/// wound counter-clockwise seen from outside.
nonisolated struct NeuronMembrane: Sendable {
    var points: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// Per vertex: x the share along its dendrite (0 on the soma, as the
    /// tubes' u), y how much of it is soma (1 on the soma, 0 out along a
    /// dendrite, between in the webbing).
    var coords: [SIMD2<Float>] = []
    var indices: [Int32] = []

    /// How far the blend reaches (the webbing where a dendrite leaves the
    /// soma), a trumpet's own flare on top of its dendrite's taper (less
    /// than the tubes' 0.5: the blend makes the rest of it, and more would
    /// swallow the dendrite's first stretch into a blob), the round cones
    /// along each dendrite and the grid's step, all in soma radii.
    static let blend: Float = 0.3
    static let flare: Float = 0.15
    static let pieces: Int = 12
    static let step: Float = 0.075

    /// The membrane round `branches` (each from inside the unit soma).
    static func make(_ branches: [NeuronBranch], step: Float = NeuronMembrane.step) -> NeuronMembrane {
        let field = NeuronMembraneField(branches)
        var grid = NeuronMembraneGrid(field: field, step: step)
        grid.fill()
        return grid.mesh()
    }
}

/// The membrane's signed distance (negative inside): the unit soma, each
/// dendrite the plain union of its round cones, the dendrites blended into
/// the soma (and the next dendrite) by a polynomial smooth minimum - whose
/// gradient is a blend of unit gradients, so the field never changes faster
/// than distance and the grid can step over empty space by it.
///
/// All in plain floats: a membrane samples the field some fifty thousand
/// times, and in an unoptimised build (the previews, Swift Playgrounds)
/// every SIMD operation is a call of its own.
nonisolated struct NeuronMembraneField: Sendable {
    /// One round cone: a sphere of `ra` at `a` swept to one of `rb` at `b`,
    /// with what IQ's exact distance needs worked out once (`u` is b - a).
    struct Cone: Sendable {
        let ax, ay, az: Float
        let bx, by, bz: Float
        let ux, uy, uz: Float
        let ra, rb: Float
        let sa, sb: Float
        let l2, rr, a2, il2: Float
        /// The side's gradient is `cosine` of the way out from the axis
        /// and rr / l2 of u along it (a unit vector: a2 + rr² is l2).
        let cosine: Float
        /// A sphere holding the cone: its centre (m) and radius.
        let mx, my, mz: Float
        let reach: Float

        init(a: SIMD3<Float>, b: SIMD3<Float>, ra: Float, rb: Float, sa: Float, sb: Float) {
            ax = a.x
            ay = a.y
            az = a.z
            bx = b.x
            by = b.y
            bz = b.z
            ux = b.x - a.x
            uy = b.y - a.y
            uz = b.z - a.z
            self.ra = ra
            self.rb = rb
            self.sa = sa
            self.sb = sb
            l2 = max(ux * ux + uy * uy + uz * uz, 1e-12)
            rr = ra - rb
            a2 = l2 - rr * rr
            il2 = 1 / l2
            cosine = max(a2 * il2, 0).squareRoot()
            mx = (a.x + b.x) * 0.5
            my = (a.y + b.y) * 0.5
            mz = (a.z + b.z) * 0.5
            reach = l2.squareRoot() * 0.5 + max(ra, rb)
        }
    }

    /// One dendrite: its cones (`first` up to `end`), and a sphere holding
    /// them all.
    struct Limb: Sendable {
        let first: Int
        let end: Int
        let x, y, z: Float
        let radius: Float
    }

    /// The field at a point: the signed distance, its gradient (a unit
    /// vector where one shape is nearest, between two in the webbing), s
    /// (the share along a dendrite, 0 on the soma) and w (how much is
    /// soma), blended by the same weights.
    struct Sample: Sendable {
        var d: Float
        var gx: Float
        var gy: Float
        var gz: Float
        var s: Float
        var w: Float
    }

    let cones: [Cone]
    let limbs: [Limb]
    let blend: Float

    init(_ branches: [NeuronBranch], blend: Float = NeuronMembrane.blend, flare: Float = NeuronMembrane.flare,
         pieces: Int = NeuronMembrane.pieces) {
        var cones: [Cone] = []
        var limbs: [Limb] = []
        let steps: Int = max(pieces, 1)
        for branch in branches {
            let first: Int = cones.count
            let trumpet: Float = branch.flare > 0 ? flare : 0
            // as the tubes: pieces crowd towards a flared base, where it curves
            func at(_ j: Int) -> Float {
                let even: Float = Float(j) / Float(steps)
                return branch.flare > 0 ? pow(even, 1.6) : even
            }
            func radius(_ t: Float) -> Float {
                let rest: Float = (1 - t) * (1 - t)
                return branch.r0 + (branch.r1 - branch.r0) * t + trumpet * rest * rest
            }
            var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var ends: [(SIMD3<Float>, Float)] = []
            for j in 0..<steps {
                let t0: Float = at(j)
                let t1: Float = at(j + 1)
                let a: SIMD3<Float> = branch.point(t0)
                let b: SIMD3<Float> = branch.point(t1)
                cones.append(Cone(a: a, b: b, ra: radius(t0), rb: radius(t1),
                                  sa: branch.s0 + (branch.s1 - branch.s0) * t0,
                                  sb: branch.s0 + (branch.s1 - branch.s0) * t1))
                ends.append((a, radius(t0)))
                ends.append((b, radius(t1)))
                lo = pointwiseMin(lo, pointwiseMin(a - radius(t0), b - radius(t1)))
                hi = pointwiseMax(hi, pointwiseMax(a + radius(t0), b + radius(t1)))
            }
            let centre: SIMD3<Float> = (lo + hi) * 0.5
            var reach: Float = 0
            for (point, r) in ends {
                let off: SIMD3<Float> = point - centre
                reach = max(reach, (off.x * off.x + off.y * off.y + off.z * off.z).squareRoot() + r)
            }
            limbs.append(Limb(first: first, end: cones.count, x: centre.x, y: centre.y, z: centre.z, radius: reach))
        }
        self.cones = cones
        self.limbs = limbs
        self.blend = blend
    }

    /// The field at (px, py, pz); its gradient only if `slope`.
    func sample(_ px: Float, _ py: Float, _ pz: Float, slope: Bool = true) -> Sample {
        let r: Float = (px * px + py * py + pz * pz).squareRoot()
        var out = Sample(d: r - 1, gx: 0, gy: 0, gz: 1, s: 0, w: 1)
        if slope && r > 1e-12 {
            out.gx = px / r
            out.gy = py / r
            out.gz = pz / r
        }
        let k: Float = blend
        cones.withUnsafeBufferPointer { all in
            var n: Int = 0
            while n < limbs.count {
                let limb: Limb = limbs[n]
                n += 1
                // a dendrite this far off cannot reach the blend: it would change nothing
                let lx: Float = px - limb.x
                let ly: Float = py - limb.y
                let lz: Float = pz - limb.z
                if (lx * lx + ly * ly + lz * lz).squareRoot() - limb.radius >= out.d + k { continue }
                var b: Float = .greatestFiniteMagnitude
                var along: Float = 0
                var nearest: Int = limb.first
                var part: Int = 0
                var index: Int = limb.first
                while index < limb.end {
                    let cone: Cone = all[index]
                    index += 1
                    // no nearer than the nearest so far: no need to look closer
                    let cx: Float = px - cone.mx
                    let cy: Float = py - cone.my
                    let cz: Float = pz - cone.mz
                    if (cx * cx + cy * cy + cz * cz).squareRoot() - cone.reach >= b { continue }
                    let (e, t, at) = Self.distance(px, py, pz, cone)
                    if e < b {
                        b = e
                        along = cone.sa + (cone.sb - cone.sa) * t
                        nearest = index - 1
                        part = at
                    }
                }
                let mix: Float = 0.5 + 0.5 * (b - out.d) / k
                let h: Float = mix < 0 ? 0 : (mix > 1 ? 1 : mix)
                out.d = b + (out.d - b) * h - k * h * (1 - h)
                out.s = along + (out.s - along) * h
                out.w *= h
                // the polynomial blend's gradient is the plain mix of the two
                if slope && h < 1 {
                    let (nx, ny, nz) = Self.slope(px, py, pz, all[nearest], part)
                    out.gx = nx + (out.gx - nx) * h
                    out.gy = ny + (out.gy - ny) * h
                    out.gz = nz + (out.gz - nz) * h
                }
            }
        }
        return out
    }

    func distance(_ p: SIMD3<Float>) -> Float {
        sample(p.x, p.y, p.z, slope: false).d
    }

    /// IQ's exact distance from (px, py, pz) to a round cone, how far along
    /// it (0 to 1) the nearest point is, and which part is nearest: 0 the
    /// side, 1 the round end at a, 2 the one at b.
    static func distance(_ px: Float, _ py: Float, _ pz: Float, _ c: Cone) -> (Float, Float, Int) {
        let pax: Float = px - c.ax
        let pay: Float = py - c.ay
        let paz: Float = pz - c.az
        let y: Float = pax * c.ux + pay * c.uy + paz * c.uz
        // (comparisons rather than min and max, generic calls when unoptimised)
        let raw: Float = y * c.il2
        let t: Float = raw < 0 ? 0 : (raw > 1 ? 1 : raw)
        // one sphere inside the other: the bigger one
        if c.a2 <= 0 {
            if c.ra >= c.rb { return ((pax * pax + pay * pay + paz * paz).squareRoot() - c.ra, 0, 1) }
            let pbx: Float = px - c.bx
            let pby: Float = py - c.by
            let pbz: Float = pz - c.bz
            return ((pbx * pbx + pby * pby + pbz * pbz).squareRoot() - c.rb, 1, 2)
        }
        let z: Float = y - c.l2
        let qx: Float = pax * c.l2 - c.ux * y
        let qy: Float = pay * c.l2 - c.uy * y
        let qz: Float = paz * c.l2 - c.uz * y
        let x2: Float = qx * qx + qy * qy + qz * qz
        let y2: Float = y * y * c.l2
        let z2: Float = z * z * c.l2
        let k: Float = sign(c.rr) * c.rr * c.rr * x2
        if sign(z) * c.a2 * z2 > k { return ((x2 + z2).squareRoot() * c.il2 - c.rb, t, 2) }
        if sign(y) * c.a2 * y2 < k { return ((x2 + y2).squareRoot() * c.il2 - c.ra, t, 1) }
        return (((x2 * c.a2 * c.il2).squareRoot() + y * c.rr) * c.il2 - c.ra, t, 0)
    }

    /// The gradient of that distance on `part` of the cone: out from the
    /// end's centre on a round end; on the side, out from the axis tilted
    /// by the taper.
    static func slope(_ px: Float, _ py: Float, _ pz: Float, _ c: Cone, _ part: Int) -> (Float, Float, Float) {
        var x: Float = px - c.ax
        var y: Float = py - c.ay
        var z: Float = pz - c.az
        if part == 2 {
            x = px - c.bx
            y = py - c.by
            z = pz - c.bz
        } else if part == 0 {
            let along: Float = (x * c.ux + y * c.uy + z * c.uz) * c.il2
            let qx: Float = x - c.ux * along
            let qy: Float = y - c.uy * along
            let qz: Float = z - c.uz * along
            let size: Float = (qx * qx + qy * qy + qz * qz).squareRoot()
            let lean: Float = c.rr * c.il2
            if size < 1e-12 { return (c.ux * c.il2.squareRoot(), c.uy * c.il2.squareRoot(), c.uz * c.il2.squareRoot()) }
            let out: Float = c.cosine / size
            return (qx * out + c.ux * lean, qy * out + c.uy * lean, qz * out + c.uz * lean)
        }
        let size: Float = (x * x + y * y + z * z).squareRoot()
        return size > 1e-12 ? (x / size, y / size, z / size) : (0, 0, 1)
    }

    static func sign(_ x: Float) -> Float {
        x > 0 ? 1 : (x < 0 ? -1 : 0)
    }
}

/// The field sampled on a grid round the cell and meshed by surface nets:
/// a vertex in every cube the surface passes through (where its edges
/// cross zero, averaged, then pulled onto the surface), and a quad round
/// every grid edge whose ends differ in sign.
nonisolated struct NeuronMembraneGrid: Sendable {
    let field: NeuronMembraneField
    let step: Float
    let ox, oy, oz: Float
    let nx: Int
    let ny: Int
    let nz: Int
    /// The field at each grid point; where `exact` is false only its sign
    /// and a bound (the point was stepped over, at least `step` from the
    /// surface).
    var values: [Float]
    var exact: [Bool]

    init(field: NeuronMembraneField, step: Float) {
        self.field = field
        self.step = step
        var lo = SIMD3<Float>(repeating: -1)
        var hi = SIMD3<Float>(repeating: 1)
        for cone in field.cones {
            let a = SIMD3<Float>(cone.ax, cone.ay, cone.az)
            let b = SIMD3<Float>(cone.bx, cone.by, cone.bz)
            lo = pointwiseMin(lo, pointwiseMin(a - cone.ra, b - cone.rb))
            hi = pointwiseMax(hi, pointwiseMax(a + cone.ra, b + cone.rb))
        }
        // the blend swells the surface by at most a quarter of its reach;
        // two steps more keep the outermost points outside
        let margin: Float = field.blend / 4 + 2 * step
        lo -= SIMD3<Float>(repeating: margin)
        hi += SIMD3<Float>(repeating: margin)
        ox = lo.x
        oy = lo.y
        oz = lo.z
        nx = Int(((hi.x - lo.x) / step).rounded(.up)) + 1
        ny = Int(((hi.y - lo.y) / step).rounded(.up)) + 1
        nz = Int(((hi.z - lo.z) / step).rounded(.up)) + 1
        values = [Float](repeating: 1, count: nx * ny * nz)
        exact = [Bool](repeating: false, count: nx * ny * nz)
    }

    func index(_ i: Int, _ j: Int, _ k: Int) -> Int {
        i + nx * (j + ny * k)
    }

    /// Samples every row along x, stepping over the points the last sample
    /// shows are on its side and at least a step from the surface.
    mutating func fill() {
        for k in 0..<nz {
            let z: Float = oz + Float(k) * step
            for j in 0..<ny {
                let y: Float = oy + Float(j) * step
                var i: Int = 0
                while i < nx {
                    let v: Float = field.sample(ox + Float(i) * step, y, z, slope: false).d
                    let at: Int = index(i, j, k)
                    values[at] = v
                    exact[at] = true
                    let skip: Int = min(Int(abs(v) / step) - 1, nx - 1 - i)
                    if skip > 0 {
                        for m in 1...skip {
                            values[at + m] = v > 0 ? v - Float(m) * step : v + Float(m) * step
                        }
                    }
                    i += max(skip, 0) + 1
                }
            }
        }
    }

    /// The field at a grid point, sampling it now if it was stepped over.
    mutating func value(_ i: Int, _ j: Int, _ k: Int) -> Float {
        let at: Int = index(i, j, k)
        if !exact[at] {
            values[at] = field.sample(ox + Float(i) * step, oy + Float(j) * step, oz + Float(k) * step, slope: false).d
            exact[at] = true
        }
        return values[at]
    }

    mutating func mesh() -> NeuronMembrane {
        var out = NeuronMembrane()
        let cx: Int = nx - 1
        let cy: Int = ny - 1
        let cz: Int = nz - 1
        var vertex = [Int32](repeating: -1, count: cx * cy * cz)
        // a cube's corner n is n & 1 along x, n >> 1 & 1 along y, n >> 2 along z
        let plane: Int = nx * ny
        let offsets: [Int] = [0, 1, nx, nx + 1, plane, plane + 1, plane + nx, plane + nx + 1]
        let edges: [(Int, Int)] = [
            (0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        var v = [Float](repeating: 0, count: 8)
        // the field changes no faster than distance, so a corner further
        // from the surface than the cube's diagonal puts all of it on one side
        let clear: Float = 1.75 * step
        // a vertex in every cube the surface passes through
        for k in 0..<cz {
            for j in 0..<cy {
                for i in 0..<cx {
                    let base: Int = index(i, j, k)
                    let corner: Float = values[base]
                    if corner > clear || corner < -clear { continue }
                    var inside: Int = 0
                    for o in offsets where values[base + o] < 0 {
                        inside += 1
                    }
                    if inside == 0 || inside == 8 { continue }
                    for n in 0..<8 {
                        v[n] = value(i + (n & 1), j + (n >> 1 & 1), k + (n >> 2))
                    }
                    var sx: Float = 0
                    var sy: Float = 0
                    var sz: Float = 0
                    var crossings: Float = 0
                    for (e0, e1) in edges where (v[e0] < 0) != (v[e1] < 0) {
                        let t: Float = v[e0] / (v[e0] - v[e1])
                        sx += Float(e0 & 1) + Float((e1 & 1) - (e0 & 1)) * t
                        sy += Float(e0 >> 1 & 1) + Float((e1 >> 1 & 1) - (e0 >> 1 & 1)) * t
                        sz += Float(e0 >> 2) + Float((e1 >> 2) - (e0 >> 2)) * t
                        crossings += 1
                    }
                    vertex[i + cx * (j + cy * k)] = Int32(out.points.count)
                    let (x, y, z, at) = settle(ox + (Float(i) + sx / crossings) * step,
                                               oy + (Float(j) + sy / crossings) * step,
                                               oz + (Float(k) + sz / crossings) * step)
                    out.points.append(SIMD3<Float>(x, y, z))
                    let size: Float = (at.gx * at.gx + at.gy * at.gy + at.gz * at.gz).squareRoot()
                    out.normals.append(size > 1e-6 ? SIMD3<Float>(at.gx / size, at.gy / size, at.gz / size)
                                                   : SIMD3<Float>(0, 0, 1))
                    out.coords.append(SIMD2<Float>(min(max(at.s, 0), 1), min(max(at.w, 0), 1)))
                }
            }
        }
        // a quad round every grid edge whose ends differ in sign, wound so
        // it faces from inside to out
        func cell(_ i: Int, _ j: Int, _ k: Int) -> Int32 {
            vertex[i + cx * (j + cy * k)]
        }
        func quad(_ q0: Int32, _ q1: Int32, _ q2: Int32, _ q3: Int32, flip: Bool) {
            guard q0 >= 0, q1 >= 0, q2 >= 0, q3 >= 0 else { return }
            let r1: Int32 = flip ? q3 : q1
            let r3: Int32 = flip ? q1 : q3
            // split along the shorter diagonal
            let a: SIMD3<Float> = out.points[Int(q0)] - out.points[Int(q2)]
            let b: SIMD3<Float> = out.points[Int(r1)] - out.points[Int(r3)]
            if a.x * a.x + a.y * a.y + a.z * a.z <= b.x * b.x + b.y * b.y + b.z * b.z {
                out.indices.append(contentsOf: [q0, r1, q2, q0, q2, r3])
            } else {
                out.indices.append(contentsOf: [q0, r1, r3, r1, q2, r3])
            }
        }
        for k in 0..<nz {
            for j in 0..<ny {
                for i in 0..<nx {
                    let value: Float = values[index(i, j, k)]
                    if value > step || value < -step { continue }
                    let here: Bool = value < 0
                    if i + 1 < nx, j > 0, k > 0, j < cy, k < cz, here != (values[index(i + 1, j, k)] < 0) {
                        quad(cell(i, j - 1, k - 1), cell(i, j, k - 1), cell(i, j, k), cell(i, j - 1, k), flip: !here)
                    }
                    if j + 1 < ny, i > 0, k > 0, i < cx, k < cz, here != (values[index(i, j + 1, k)] < 0) {
                        quad(cell(i - 1, j, k - 1), cell(i - 1, j, k), cell(i, j, k), cell(i, j, k - 1), flip: !here)
                    }
                    if k + 1 < nz, i > 0, j > 0, i < cx, j < cy, here != (values[index(i, j, k + 1)] < 0) {
                        quad(cell(i - 1, j - 1, k), cell(i, j - 1, k), cell(i, j, k), cell(i - 1, j, k), flip: !here)
                    }
                }
            }
        }
        return out
    }

    /// Pulls a vertex onto the surface by Newton's steps along the
    /// gradient, never more than a step from where surface nets put it;
    /// with the field where it lands (its normal, s and w).
    func settle(_ x0: Float, _ y0: Float, _ z0: Float) -> (Float, Float, Float, NeuronMembraneField.Sample) {
        var x: Float = x0
        var y: Float = y0
        var z: Float = z0
        var at: NeuronMembraneField.Sample = field.sample(x, y, z)
        for _ in 0..<2 {
            let g2: Float = at.gx * at.gx + at.gy * at.gy + at.gz * at.gz
            guard g2 > 1e-8 else { break }
            let move: Float = at.d / g2
            x -= at.gx * move
            y -= at.gy * move
            z -= at.gz * move
            let mx: Float = x - x0
            let my: Float = y - y0
            let mz: Float = z - z0
            let far: Float = (mx * mx + my * my + mz * mz).squareRoot()
            if far > step {
                x = x0 + mx * (step / far)
                y = y0 + my * (step / far)
                z = z0 + mz * (step / far)
            }
            at = field.sample(x, y, z)
        }
        return (x, y, z, at)
    }
}
