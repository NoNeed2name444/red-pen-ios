import Foundation
import simd

/// Arranging and framing the space so the whole graph reads as one
/// constellation that fills the screen.
///
/// ForceLayout3D pushes groups of notes that are not linked to each other far
/// apart (every note repels every other; only links pull). Left as it is,
/// two clusters end up at the screen's edges with empty space between them.
/// So after the layout:
///
/// 1. each connected group is kept exactly as laid out, but the groups are
///    packed close together, largest first, each slid in towards the middle
///    along its own direction until it just clears the ones already placed;
/// 2. the whole is turned so its longest spread runs along y, the next along
///    x, and its thinnest into the screen (z) - the view then looks at its
///    broadest face, and y can be put along the screen's long side;
/// 3. the camera stands exactly far enough back for every note to fit in 80%
///    of the screen (see `distance`).
nonisolated enum GraphFraming {
    /// Room left between packed groups, in the space's units.
    static let groupGap: Float = 0.6
    /// How much of the screen the graph fills, across its shorter side.
    static let fill: Float = 0.8
    /// The camera's vertical field of view, in degrees.
    static let fieldOfView: Float = 55

    /// A page's sphere radius, from how far apart linked notes sit: big
    /// enough that at the fitted framing a note - ring, lensed arcs and disk
    /// - is some 40 to 60 points across on a phone, small enough that
    /// neighbours' disks do not swamp each other. Ideas are 0.62 of it.
    static func pageRadius(_ positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)]) -> Float {
        var lengths: [Float] = []
        for (a, b) in edges {
            guard let p = positions[a], let q = positions[b] else { continue }
            lengths.append(simd_distance(p, q))
        }
        guard !lengths.isEmpty else { return 0.3 }
        lengths.sort()
        let median: Float = lengths[lengths.count / 2]
        let radius: Float = median * 0.16
        return min(max(radius, 0.2), 0.6)
    }

    /// Packs and turns the layout (steps 1 and 2). `pad` is how far each
    /// note's look reaches beyond its centre (its disk).
    static func arrange(_ positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)],
                        pad: Float) -> [UUID: SIMD3<Float>] {
        let order: [UUID] = positions.keys.sorted { $0.uuidString < $1.uuidString }
        guard order.count > 1 else { return positions }
        var slot: [UUID: Int] = [:]
        for (i, id) in order.enumerated() { slot[id] = i }
        var points: [SIMD3<Float>] = order.map { positions[$0] ?? SIMD3<Float>(0, 0, 0) }

        pack(&points, groups: groups(count: order.count, slot: slot, edges: edges), pad: pad)
        turn(&points)
        centreOnBox(&points)

        var result: [UUID: SIMD3<Float>] = [:]
        for (i, id) in order.enumerated() { result[id] = points[i] }
        return result
    }

    /// The connected groups, as lists of indices, largest first.
    private static func groups(count: Int, slot: [UUID: Int], edges: [(UUID, UUID)]) -> [[Int]] {
        var parent: [Int] = Array(0..<count)
        func root(_ i: Int) -> Int {
            var r: Int = i
            while parent[r] != r {
                parent[r] = parent[parent[r]]
                r = parent[r]
            }
            return r
        }
        for (a, b) in edges {
            guard let i = slot[a], let j = slot[b] else { continue }
            let ri: Int = root(i)
            let rj: Int = root(j)
            if ri != rj { parent[ri] = rj }
        }
        var members: [Int: [Int]] = [:]
        for i in 0..<count { members[root(i), default: []].append(i) }
        let lists: [[Int]] = Array(members.values)
        return lists.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return (lhs.first ?? 0) < (rhs.first ?? 0)
        }
    }

    private static func pack(_ points: inout [SIMD3<Float>], groups: [[Int]], pad: Float) {
        guard groups.count > 1 else { return }
        // no note of one group nearer than this to a note of another
        let clearance: Float = pad * 2 + groupGap
        var placed: [Int] = []
        for group in groups {
            var centre = SIMD3<Float>(0, 0, 0)
            for i in group { centre += points[i] }
            centre /= Float(group.count)
            // slide in from where it was, towards the middle, as far as it can
            var chosen: SIMD3<Float> = centre
            var scale: Float = 0
            while scale < 1 {
                let spot: SIMD3<Float> = centre * scale
                let shift: SIMD3<Float> = spot - centre
                if clears(group, shift: shift, placed: placed, points: points, clearance: clearance) {
                    chosen = spot
                    break
                }
                scale += 0.02
            }
            let shift: SIMD3<Float> = chosen - centre
            for i in group { points[i] += shift }
            placed.append(contentsOf: group)
        }
        // centred on the origin again
        var middle = SIMD3<Float>(0, 0, 0)
        for p in points { middle += p }
        middle /= Float(points.count)
        for i in points.indices { points[i] -= middle }
    }

    /// Whether `group`, moved by `shift`, keeps every note at least
    /// `clearance` from every note already placed.
    private static func clears(_ group: [Int], shift: SIMD3<Float>, placed: [Int],
                               points: [SIMD3<Float>], clearance: Float) -> Bool {
        let limit: Float = clearance * clearance
        for i in group {
            let moved: SIMD3<Float> = points[i] + shift
            for j in placed where simd_distance_squared(moved, points[j]) < limit {
                return false
            }
        }
        return true
    }

    /// Centres the points across the screen (x and y) on the middle of
    /// their extent rather than their average, so the graph sits in the
    /// middle of the screen with equal room on either side.
    private static func centreOnBox(_ points: inout [SIMD3<Float>]) {
        guard let first = points.first else { return }
        var low: SIMD3<Float> = first
        var high: SIMD3<Float> = first
        for p in points {
            low = simd_min(low, p)
            high = simd_max(high, p)
        }
        let middle: SIMD3<Float> = (low + high) * 0.5
        let shift = SIMD3<Float>(middle.x, middle.y, 0)
        for i in points.indices { points[i] -= shift }
    }

    /// Turns the points so their longest spread runs along y, the next along
    /// x and the thinnest along z (the principal axes of their spread).
    private static func turn(_ points: inout [SIMD3<Float>]) {
        var cov = simd_float3x3(0)
        for p in points {
            let outer = simd_float3x3(p * p.x, p * p.y, p * p.z)
            cov += outer
        }
        let (values, vectors) = eigen(cov)
        // indices of the eigenvalues from largest to smallest
        var rank: [Int] = [0, 1, 2]
        rank.sort { values[$0] > values[$1] }
        let longest: SIMD3<Float> = vectors[rank[0]]
        let middle: SIMD3<Float> = vectors[rank[1]]
        // a right-handed frame: x = middle, y = longest, z = x cross y
        let depth: SIMD3<Float> = simd_cross(middle, longest)
        for i in points.indices {
            let p: SIMD3<Float> = points[i]
            let x: Float = simd_dot(p, middle)
            let y: Float = simd_dot(p, longest)
            let z: Float = simd_dot(p, depth)
            points[i] = SIMD3<Float>(x, y, z)
        }
    }

    /// Eigenvalues and unit eigenvectors of a symmetric 3x3 matrix, by
    /// Jacobi rotations.
    private static func eigen(_ m: simd_float3x3) -> ([Float], [SIMD3<Float>]) {
        var a: [[Float]] = [
            [m[0][0], m[1][0], m[2][0]],
            [m[0][1], m[1][1], m[2][1]],
            [m[0][2], m[1][2], m[2][2]]
        ]
        var v: [[Float]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<24 {
            // the largest off-diagonal entry
            var p: Int = 0
            var q: Int = 1
            if abs(a[0][2]) > abs(a[p][q]) { p = 0; q = 2 }
            if abs(a[1][2]) > abs(a[p][q]) { p = 1; q = 2 }
            if abs(a[p][q]) < 1e-7 { break }
            let diff: Float = a[q][q] - a[p][p]
            let theta: Float = diff / (2 * a[p][q])
            let sign: Float = theta >= 0 ? 1 : -1
            let root: Float = (theta * theta + 1).squareRoot()
            let t: Float = sign / (abs(theta) + root)
            let c: Float = 1 / (t * t + 1).squareRoot()
            let s: Float = t * c
            for k in 0..<3 {
                let akp: Float = a[k][p]
                let akq: Float = a[k][q]
                a[k][p] = c * akp - s * akq
                a[k][q] = s * akp + c * akq
            }
            for k in 0..<3 {
                let apk: Float = a[p][k]
                let aqk: Float = a[q][k]
                a[p][k] = c * apk - s * aqk
                a[q][k] = s * apk + c * aqk
            }
            for k in 0..<3 {
                let vkp: Float = v[k][p]
                let vkq: Float = v[k][q]
                v[k][p] = c * vkp - s * vkq
                v[k][q] = s * vkp + c * vkq
            }
        }
        let values: [Float] = [a[0][0], a[1][1], a[2][2]]
        var vectors: [SIMD3<Float>] = []
        for j in 0..<3 {
            let column = SIMD3<Float>(v[0][j], v[1][j], v[2][j])
            vectors.append(simd_normalize(column))
        }
        return (values, vectors)
    }

    /// How far back, along +z, the camera must stand (looking at the origin
    /// down -z) for every point, plus `pad` round it, to fit within `fill`
    /// of the screen in both directions. `aspect` is width over height.
    /// Points nearer the camera (larger z) need more room, so each is taken
    /// at its own depth.
    static func distance(points: [SIMD3<Float>], pad: Float, aspect: Float) -> Float {
        let half: Float = fieldOfView * Float.pi / 360
        let tanUp: Float = tan(half) * fill
        let tanSide: Float = tanUp * max(aspect, 0.1)
        var need: Float = 1
        for p in points {
            let across: Float = (abs(p.x) + pad) / tanSide
            let upDown: Float = (abs(p.y) + pad) / tanUp
            let back: Float = p.z + pad
            let here: Float = back + max(across, upDown)
            need = max(need, here)
        }
        return need
    }
}
