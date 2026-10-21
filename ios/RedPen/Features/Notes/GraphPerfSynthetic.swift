// A seeded synthetic vault for the Performance theme: 100,000 notes shaped
// like a real one (a few big folders and many small ones, hubs that gather
// links, most links inside a folder), for the tests, the design preview and
// the UI test. Foundation only; the same seed always gives the same vault.
import Foundation

nonisolated enum GraphPerfSynthetic {
    /// The vault's shape. The defaults are the 100k design target.
    struct Spec: Sendable {
        var notes: Int = 100_000
        var topFolders: Int = 24
        var maxDepth: Int = 3
        var meanSubfolders: Double = 3
        var zipf: Double = 0.8
        var pageShare: Double = 0.15
        var looseShare: Double = 0.02
        /// Links a note makes: 1 + Poisson(meanExtraLinks), at most maxLinks.
        var meanExtraLinks: Double = 1.4
        var maxLinks: Int = 12
        /// Where a link goes: own folder, else own region, else anywhere.
        var ownFolder: Double = 0.85
        var ownRegion: Double = 0.12
        var seed: UInt64 = 0x5EED_0100_000A
    }

    /// The vault as the renderer's input (bypassing the note store).
    static func make(_ spec: Spec = Spec()) -> GraphPerfInput {
        var rng = Random(seed: spec.seed)

        // folders: the top ones, then children breadth first, to maxDepth
        var parent: [Int32] = [], top: [Int32] = [], depth: [Int] = []
        for t in 0..<spec.topFolders { parent.append(-1); top.append(Int32(t)); depth.append(0) }
        var f = 0
        while f < parent.count && parent.count < 8_192 - 16 {
            if depth[f] < spec.maxDepth {
                for _ in 0..<min(rng.poisson(spec.meanSubfolders), 8) {
                    parent.append(Int32(f)); top.append(top[f]); depth.append(depth[f] + 1)
                }
            }
            f += 1
        }
        let fc = parent.count

        // Zipf weights over the folders in a shuffled order, as a running total
        var perm = Array(0..<fc)
        if fc > 1 { for i in stride(from: fc - 1, to: 0, by: -1) { perm.swapAt(i, rng.below(i + 1)) } }
        var weight = [Double](repeating: 0, count: fc)
        for r in 0..<fc { weight[perm[r]] = 1 / pow(Double(r + 1), spec.zipf) }
        let total = weight.reduce(0, +)
        var cumulative = [Double](repeating: 0, count: fc)
        var running = 0.0
        for i in 0..<fc { running += weight[i] / total; cumulative[i] = running }

        // notes: kind, then loose or a folder drawn by weight
        let n = spec.notes
        var isPage = [Bool](repeating: false, count: n)
        var folderOf = [Int32](repeating: -1, count: n)
        for i in 0..<n {
            isPage[i] = rng.unit() < spec.pageShare
            if rng.unit() < spec.looseShare || fc == 0 { continue }
            let u = rng.unit()
            var lo = 0, hi = fc - 1
            while lo < hi { let mid = (lo + hi) / 2; if cumulative[mid] < u { lo = mid + 1 } else { hi = mid } }
            folderOf[i] = Int32(lo)
        }

        // links: each note links to earlier notes drawn from endpoint pools
        // (a note appears once per link it has, so the linked get linked:
        // preferential attachment, which grows realistic hubs)
        var folderPool = [[Int32]](repeating: [], count: fc)
        var regionPool = [[Int32]](repeating: [], count: fc)
        var anywhere: [Int32] = []
        var edges: [UInt32] = []
        edges.reserveCapacity(n * 5)
        var chosen: [Int32] = []
        for i in 0..<n {
            let fi = Int(folderOf[i]), ri = fi >= 0 ? Int(top[fi]) : -1
            let want = min(1 + rng.poisson(spec.meanExtraLinks), spec.maxLinks)
            chosen.removeAll(keepingCapacity: true)
            for _ in 0..<want {
                let u = rng.unit()
                let a: Int32
                if u < spec.ownFolder && fi >= 0 && !folderPool[fi].isEmpty {
                    a = folderPool[fi][rng.below(folderPool[fi].count)]
                } else if u < spec.ownFolder + spec.ownRegion && ri >= 0 && !regionPool[ri].isEmpty {
                    a = regionPool[ri][rng.below(regionPool[ri].count)]
                } else if !anywhere.isEmpty {
                    a = anywhere[rng.below(anywhere.count)]
                } else { continue }
                guard a != Int32(i), !chosen.contains(a) else { continue }
                chosen.append(a)
                edges.append(UInt32(i)); edges.append(UInt32(a))
                let fa = Int(folderOf[Int(a)])
                if fa >= 0 { folderPool[fa].append(a); regionPool[Int(top[fa])].append(a) }
                anywhere.append(a)
            }
            for _ in 0...chosen.count {
                if fi >= 0 { folderPool[fi].append(Int32(i)) }
                anywhere.append(Int32(i))
            }
            if fi >= 0 { regionPool[ri].append(Int32(i)) }
        }

        // ids last, from their own stream, so the structure above does not
        // depend on them
        var ids = Random(seed: spec.seed ^ 0x1D5_1D5_1D5)
        return GraphPerfInput(noteIDs: (0..<n).map { _ in ids.uuid() }, isPage: isPage, folderOfNote: folderOf,
                              folderIDs: (0..<fc).map { _ in ids.uuid() }, folderParent: parent,
                              edges: edges, linkScale: 1)
    }

    /// A made-up title for note `index`, computed when shown, never stored:
    /// 100k titles would cost megabytes for words nobody reads at once.
    static func title(_ index: Int) -> String {
        let word = words[index % words.count]
        let number = String(index)
        return word + " " + String(repeating: "0", count: max(0, 5 - number.count)) + number
    }

    private static let words: [String] = [
        "Cardiology", "Renal", "Sepsis", "Asthma", "Stroke", "Anaemia", "Thyroid", "Diabetes",
        "Hepatitis", "Pneumonia", "Arrhythmia", "Lupus", "Gout", "Migraine", "Eczema", "Glaucoma"
    ]

    /// SplitMix64, a copy of ForceLayout3D's (same constants) so the
    /// standalone app does not need that file.
    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// In [0, 1), from the top 53 bits.
        mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }

        /// In 0..<n (0 when n is 0).
        mutating func below(_ n: Int) -> Int { n > 0 ? Int(next() % UInt64(n)) : 0 }

        /// Knuth's method; the means here are small.
        mutating func poisson(_ mean: Double) -> Int {
            let limit = exp(-mean)
            var p = 1.0, k = 0
            repeat { k += 1; p *= unit() } while p > limit
            return k - 1
        }

        /// A version 4 UUID from 128 random bits.
        mutating func uuid() -> UUID {
            var b = (next(), next())
            return withUnsafeMutableBytes(of: &b) { raw -> UUID in
                raw[6] = raw[6] & 0x0F | 0x40   // version 4
                raw[8] = raw[8] & 0x3F | 0x80   // RFC 4122 variant
                return UUID(uuid: raw.load(as: uuid_t.self))
            }
        }
    }
}
