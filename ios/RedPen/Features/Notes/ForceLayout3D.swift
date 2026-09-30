import Foundation

/// Where each note floats in the 3D space.
///
/// A plain force-directed layout, the kind Obsidian's graph uses: every note
/// pushes every other away, each connection pulls its two ends together like a
/// spring, and notes in the same folder drift towards that folder's middle so
/// a folder reads as a cluster. A faint pull to the centre keeps loose ideas
/// from wandering off.
///
/// Pure and deterministic - the same notes and links always settle in the same
/// shape, because the starting scatter comes from a fixed seed and the notes
/// are taken in a fixed order - so the space does not rearrange itself every
/// time it is opened, and the layout can be tested without a screen.
enum ForceLayout3D {
    /// - Parameters:
    ///   - nodes: every note to place.
    ///   - edges: connections between them; ends that are not in `nodes` are
    ///     ignored.
    ///   - groups: each note's folder, for notes in one.
    /// - Returns: a position for every node, centred on the origin.
    static func layout(nodes: [UUID], edges: [(UUID, UUID)], groups: [UUID: UUID],
                       iterations: Int = 200, seed: UInt64 = 0x5EED) -> [UUID: SIMD3<Float>] {
        // a fixed order, so the result does not depend on the order passed in
        let order = Array(Set(nodes)).sorted { $0.uuidString < $1.uuidString }
        guard !order.isEmpty else { return [:] }
        guard order.count > 1 else { return [order[0]: SIMD3<Float>(0, 0, 0)] }

        var slot: [UUID: Int] = [:]
        for (i, id) in order.enumerated() { slot[id] = i }
        let n = order.count

        // the ideal distance between two joined notes
        let k: Float = 1.6
        var random = SplitMix64(seed: seed)
        let spread = k * Float(n).squareRoot()
        var position: [SIMD3<Float>] = []
        position.reserveCapacity(n)
        for _ in 0..<n {
            let x: Float = random.unit() * spread
            let y: Float = random.unit() * spread
            let z: Float = random.unit() * spread
            position.append(SIMD3<Float>(x, y, z))
        }

        var springs: [(Int, Int)] = []
        var seenPairs = Set<Int>()
        for (a, b) in edges {
            guard let i = slot[a], let j = slot[b], i != j else { continue }
            let key = min(i, j) * n + max(i, j)
            if seenPairs.insert(key).inserted { springs.append((i, j)) }
        }

        // each group as a list of slots
        var members: [UUID: [Int]] = [:]
        for (i, id) in order.enumerated() {
            if let group = groups[id] { members[group, default: []].append(i) }
        }
        let clusters = members.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { members[$0] }

        var temperature = spread * 0.5
        let cooling = temperature / Float(max(iterations, 1))

        for _ in 0..<max(iterations, 0) {
            var push = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n)

            // every pair pushes apart, harder the closer they are
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let delta: SIMD3<Float> = position[i] - position[j]
                    let distance: Float = max(length(delta), 0.05)
                    let strength: Float = k * k / distance
                    let force: SIMD3<Float> = delta * (strength / distance)
                    push[i] += force
                    push[j] -= force
                }
            }

            // each connection pulls its ends together
            for (i, j) in springs {
                let delta: SIMD3<Float> = position[j] - position[i]
                let distance: Float = max(length(delta), 0.05)
                let strength: Float = distance * distance / k
                let force: SIMD3<Float> = delta * (strength / distance)
                push[i] += force
                push[j] -= force
            }

            // notes in one folder drift to its middle
            for cluster in clusters where cluster.count > 1 {
                var centre = SIMD3<Float>(0, 0, 0)
                for i in cluster { centre += position[i] }
                centre /= Float(cluster.count)
                for i in cluster {
                    let towards: SIMD3<Float> = centre - position[i]
                    push[i] += towards * Float(0.6)
                }
            }

            // and everything, faintly, to the centre
            for i in 0..<n {
                let inward: SIMD3<Float> = position[i] * Float(0.05)
                push[i] -= inward
                // never further in one step than the temperature allows
                let size: Float = length(push[i])
                if size > 0 {
                    let step: Float = min(size, temperature) / size
                    position[i] += push[i] * step
                }
            }
            temperature = max(temperature - cooling, 0.01)
        }

        // centred on the origin, so the camera can look at (0, 0, 0)
        var middle = SIMD3<Float>(0, 0, 0)
        for p in position { middle += p }
        middle /= Float(n)
        var result: [UUID: SIMD3<Float>] = [:]
        for (i, id) in order.enumerated() { result[id] = position[i] - middle }
        return result
    }

    private static func length(_ v: SIMD3<Float>) -> Float {
        (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    }
}

/// A tiny seeded random number generator, so the layout starts from the same
/// scatter every time.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number between -1 and 1.
    mutating func unit() -> Float {
        let top53: UInt64 = next() >> 11
        let fraction: Double = Double(top53) / 9_007_199_254_740_992.0 // 2^53
        return Float(fraction) * 2 - 1
    }
}
