// The Performance theme's graph: 100,000 notes and their links as plain
// arrays (struct-of-arrays), built in linear time apart from one sort.
//
// Foundation only, and free of Stethoscore types, so the standalone 3D app
// can take it as it is. Everything is in a deterministic order (notes and
// folders sorted by the bytes of their UUIDs), so the same vault gives the
// same map whatever order the store hands it over in.
import Foundation

/// The map's input: indices instead of objects, so the store adapter (or the
/// synthetic generator) fills it once and nothing here hashes a UUID per link.
nonisolated struct GraphPerfInput: Sendable {
    var noteIDs: [UUID]
    var isPage: [Bool]
    /// Each note's folder, an index into `folderIDs`; -1 for a loose note.
    var folderOfNote: [Int32]
    var folderIDs: [UUID]
    /// Each folder's parent, an index into `folderIDs`; -1 at the top.
    var folderParent: [Int32]
    /// Links as pairs of note indices: a0, b0, a1, b1, ... Duplicates, either
    /// direction, self links and unknown ends are all allowed (and dropped).
    var edges: [UInt32]
    /// The room between bodies (the map's link length); sizes do not scale.
    var linkScale: Float = 1
    /// What the name pill says, in input order; empty for a vault whose
    /// titles are made on demand (the synthetic one).
    var noteTitles: [String] = []
    var folderNames: [String] = []

    /// The input from ids, as an app's store holds them: each note's folder
    /// and each folder's parent by id (nil, or an id not among the folders:
    /// none), links as id pairs (an id not among the notes is dropped).
    static func make(noteIDs: [UUID], isPage: [Bool], noteFolders: [UUID?], folderIDs: [UUID],
                     folderParents: [UUID?], links: [(UUID, UUID)], linkScale: Float = 1,
                     noteTitles: [String] = [], folderNames: [String] = []) -> GraphPerfInput {
        var folderIndex: [UUID: Int32] = [:]
        folderIndex.reserveCapacity(folderIDs.count)
        for (k, id) in folderIDs.enumerated() where folderIndex[id] == nil { folderIndex[id] = Int32(k) }
        var noteIndex: [UUID: UInt32] = [:]
        noteIndex.reserveCapacity(noteIDs.count)
        for (k, id) in noteIDs.enumerated() where noteIndex[id] == nil { noteIndex[id] = UInt32(k) }
        let folderOf: [Int32] = noteIDs.indices.map { k in
            guard k < noteFolders.count, let f = noteFolders[k] else { return -1 }
            return folderIndex[f] ?? -1
        }
        let parent: [Int32] = folderIDs.indices.map { k in
            guard k < folderParents.count, let p = folderParents[k] else { return -1 }
            return folderIndex[p] ?? -1
        }
        var edges: [UInt32] = []
        edges.reserveCapacity(links.count * 2)
        for (a, b) in links {
            guard let ia = noteIndex[a], let ib = noteIndex[b] else { continue }
            edges.append(ia)
            edges.append(ib)
        }
        return GraphPerfInput(noteIDs: noteIDs, isPage: isPage, folderOfNote: folderOf, folderIDs: folderIDs,
                              folderParent: parent, edges: edges, linkScale: linkScale,
                              noteTitles: noteTitles, folderNames: folderNames)
    }
}

/// Which notes the map shows (the app's filter, without its types).
nonisolated enum GraphPerfFilter: Sendable, Equatable {
    case all
    case pages
    case ideas
    /// Notes joined to at least one other.
    case linked
    /// Notes anywhere inside this folder (the app passes a top-level one).
    case folder(UUID)
}

/// The built graph. Notes are slots 0..<noteCount in UUID order; each folder
/// also has a hub, node noteCount + folder, so positions run notes then hubs.
///
/// A "system" is what the layout places as one ball: every folder, then the
/// loose-note groups (folderCount ..< systemCount), which have no hub.
nonisolated struct GraphPerfGraph: Sendable {
    /// Bumped whenever the build or the layout changes what it gives, so a
    /// cached layout keyed by `signature` is never read back wrongly.
    static let algorithmVersion: UInt64 = 2
    /// The most loose groups kept as their own systems; smaller ones join
    /// the pool with the singletons.
    static let maxLooseGroups: Int = 256

    let noteCount: Int
    let folderCount: Int
    let linkScale: Float

    let noteIDs: [UUID]
    let isPage: [Bool]
    /// Slot to the caller's index, and back.
    let inputOfNote: [Int32]
    let noteOfInput: [Int32]
    /// Each note's folder slot, -1 when loose.
    let folder: [Int32]

    let folderIDs: [UUID]
    let inputOfFolder: [Int32]
    /// After cycles are cut: -1 for a top folder.
    let folderParent: [Int32]
    let folderDepth: [Int32]
    /// The top folder each folder sits under (its region).
    let folderRegion: [Int32]
    /// Children of folder f: folderChildren[folderChildStart[f] ..< folderChildStart[f + 1]].
    let folderChildStart: [Int32]
    let folderChildren: [Int32]
    /// Notes in a folder and all its subfolders (sizes the hub).
    let folderSubtreeCount: [Int32]

    /// Folders, then loose groups (largest first, singletons pooled last).
    let systemCount: Int
    let systemOfNote: [Int32]
    /// Members of system s, in slot order: systemNotes[systemNoteStart[s] ..< systemNoteStart[s + 1]].
    let systemNoteStart: [Int32]
    let systemNotes: [Int32]

    /// Unique links, a < b, sorted.
    let edgeA: [Int32]
    let edgeB: [Int32]
    /// CSR adjacency: neighbours of i are adjacency[adjStart[i] ..< adjStart[i + 1]], ascending.
    let adjStart: [Int32]
    let adjacency: [Int32]

    /// FNV-64 of everything the layout depends on, for the layout cache.
    let signature: UInt64

    var linkCount: Int { edgeA.count }
    var nodeCount: Int { noteCount + folderCount }
    var looseGroupCount: Int { systemCount - folderCount }
    func degree(_ i: Int) -> Int { Int(adjStart[i + 1] - adjStart[i]) }
    func hubNode(_ folder: Int) -> Int { noteCount + folder }
    /// The region a note belongs to: its top folder, or folderCount + its loose group.
    func region(ofNote i: Int) -> Int {
        let f = Int(folder[i])
        return f >= 0 ? Int(folderRegion[f]) : Int(systemOfNote[i])
    }

    init(_ input: GraphPerfInput) {
        let n = input.noteIDs.count
        let fc = input.folderIDs.count
        linkScale = input.linkScale

        // deterministic order: by UUID bytes (uuidString would allocate a
        // string per note and sort case-sensitively), then input index
        let noteOrder = Self.order(input.noteIDs)
        let folderOrder = Self.order(input.folderIDs)
        var noteOf = [Int32](repeating: -1, count: n)
        for (slot, i) in noteOrder.enumerated() { noteOf[Int(i)] = Int32(slot) }
        var folderOf = [Int32](repeating: -1, count: fc)
        for (slot, i) in folderOrder.enumerated() { folderOf[Int(i)] = Int32(slot) }
        noteCount = n
        folderCount = fc
        inputOfNote = noteOrder
        noteOfInput = noteOf
        inputOfFolder = folderOrder
        noteIDs = noteOrder.map { input.noteIDs[Int($0)] }
        folderIDs = folderOrder.map { input.folderIDs[Int($0)] }
        isPage = noteOrder.map { Int($0) < input.isPage.count && input.isPage[Int($0)] }
        folder = noteOrder.map { i -> Int32 in
            let f = Int(i) < input.folderOfNote.count ? Int(input.folderOfNote[Int(i)]) : -1
            return f >= 0 && f < fc ? folderOf[f] : -1
        }

        // the folder tree: a missing parent, or one closing a cycle, makes
        // the folder top level; a cycle is cut at its lowest slot, as
        // GraphUniverse does, so the cut does not depend on input order
        var parent = folderOrder.map { i -> Int32 in
            let p = Int(i) < input.folderParent.count ? Int(input.folderParent[Int(i)]) : -1
            return p >= 0 && p < fc ? folderOf[p] : -1
        }
        for f in 0..<fc where parent[f] == Int32(f) { parent[f] = -1 }
        var state = [UInt8](repeating: 0, count: fc) // 0 new, 1 on this walk, 2 done
        var walk: [Int32] = []
        for start in 0..<fc where state[start] == 0 {
            walk.removeAll(keepingCapacity: true)
            var cur = Int32(start)
            while cur >= 0 && state[Int(cur)] == 0 {
                state[Int(cur)] = 1
                walk.append(cur)
                cur = parent[Int(cur)]
            }
            if cur >= 0 && state[Int(cur)] == 1, let from = walk.firstIndex(of: cur) {
                let cut = walk[from...].min()!
                parent[Int(cut)] = -1
            }
            for w in walk { state[Int(w)] = 2 }
        }
        folderParent = parent

        // depth and region, memoised walk up (each folder settled once)
        var depth = [Int32](repeating: -1, count: fc)
        var region = [Int32](repeating: -1, count: fc)
        for start in 0..<fc where depth[start] < 0 {
            walk.removeAll(keepingCapacity: true)
            var cur = Int32(start)
            while cur >= 0 && depth[Int(cur)] < 0 {
                walk.append(cur)
                cur = parent[Int(cur)]
            }
            var d: Int32 = cur >= 0 ? depth[Int(cur)] : -1
            let r: Int32 = cur >= 0 ? region[Int(cur)] : walk.last!
            for w in walk.reversed() {
                d += 1
                depth[Int(w)] = d
                region[Int(w)] = r
            }
        }
        folderDepth = depth
        folderRegion = region
        let kids = Self.buckets(count: fc, keys: parent)
        folderChildStart = kids.start
        folderChildren = kids.items

        // unique links: pack (low, high) into one UInt64, radix sort, dedupe
        var keys: [UInt64] = []
        keys.reserveCapacity(input.edges.count / 2)
        var e = 0
        while e + 1 < input.edges.count {
            let a = Int(input.edges[e]), b = Int(input.edges[e + 1])
            e += 2
            guard a < n, b < n else { continue }
            let sa = UInt64(noteOf[a]), sb = UInt64(noteOf[b])
            guard sa != sb else { continue }
            keys.append(sa < sb ? sa << 32 | sb : sb << 32 | sa)
        }
        Self.radixSort(&keys, maxKey: UInt64(max(n, 1)) << 32)
        var ea: [Int32] = [], eb: [Int32] = []
        ea.reserveCapacity(keys.count)
        eb.reserveCapacity(keys.count)
        var last = UInt64.max
        for k in keys where k != last {
            last = k
            ea.append(Int32(truncatingIfNeeded: k >> 32))
            eb.append(Int32(truncatingIfNeeded: k & 0xFFFF_FFFF))
        }
        edgeA = ea
        edgeB = eb

        // CSR: count, prefix sum, fill; links are in (low, high) order, so
        // every row comes out ascending
        var start = [Int32](repeating: 0, count: n + 1)
        for k in 0..<ea.count {
            start[Int(ea[k]) + 1] += 1
            start[Int(eb[k]) + 1] += 1
        }
        for i in 0..<n { start[i + 1] += start[i] }
        var fill = start
        var nbr = [Int32](repeating: 0, count: ea.count * 2)
        for k in 0..<ea.count {
            let a = Int(ea[k]), b = Int(eb[k])
            nbr[Int(fill[a])] = Int32(b); fill[a] += 1
            nbr[Int(fill[b])] = Int32(a); fill[b] += 1
        }
        adjStart = start
        adjacency = nbr

        // subtree counts: direct notes, then added up the tree deepest first
        var subtree = [Int32](repeating: 0, count: fc)
        for f in folder where f >= 0 { subtree[Int(f)] += 1 }
        for f in Self.deepestFirst(depth) where parent[f] >= 0 { subtree[Int(parent[f])] += subtree[f] }
        folderSubtreeCount = subtree

        // loose notes: connected components over links between loose notes
        // (union-find, as GraphFraming.groups), largest first, ties by first
        // member; singletons pooled into one last group, so a folderless
        // vault still shows its clusters without a ball per lonely note. Past
        // the `maxLooseGroups` largest, the rest join the pool too: the
        // packing of the top level is quadratic in its systems
        var uf = [Int32](repeating: -1, count: n)
        for i in 0..<n where folder[i] < 0 { uf[i] = Int32(i) }
        func root(_ i: Int) -> Int {
            var r = i
            while uf[r] != Int32(r) { uf[r] = uf[Int(uf[r])]; r = Int(uf[r]) }
            return r
        }
        for k in 0..<ea.count where uf[Int(ea[k])] >= 0 && uf[Int(eb[k])] >= 0 {
            let ra = root(Int(ea[k])), rb = root(Int(eb[k]))
            if ra != rb { uf[max(ra, rb)] = Int32(min(ra, rb)) } // the lowest slot stays root
        }
        var size = [Int32](repeating: 0, count: n)
        for i in 0..<n where uf[i] >= 0 { size[root(i)] += 1 }
        // roots are each component's lowest member, so slot order is first-member order
        var roots: [Int32] = (0..<n).compactMap { uf[$0] == Int32($0) && size[$0] > 1 ? Int32($0) : nil }
        roots.sort { size[Int($0)] != size[Int($1)] ? size[Int($0)] > size[Int($1)] : $0 < $1 }
        if roots.count > Self.maxLooseGroups { roots.removeLast(roots.count - Self.maxLooseGroups) }
        var groupOfRoot = [Int32](repeating: -1, count: n)
        for (g, r) in roots.enumerated() { groupOfRoot[Int(r)] = Int32(g) }
        let pooled = roots.count
        var anySingle = false
        var system = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            if folder[i] >= 0 { system[i] = folder[i]; continue }
            let g = groupOfRoot[root(i)]
            if g >= 0 { system[i] = Int32(fc) + g } else { system[i] = Int32(fc + pooled); anySingle = true }
        }
        systemCount = fc + pooled + (anySingle ? 1 : 0)
        systemOfNote = system
        let members = Self.buckets(count: systemCount, keys: system)
        systemNoteStart = members.start
        systemNotes = members.items

        // the signature: ids, kinds, folders, tree, links, scale, version
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        Self.fnv(&h, UInt64(n)); Self.fnv(&h, UInt64(fc))
        for i in 0..<n {
            let (hi, lo) = Self.words(noteIDs[i])
            Self.fnv(&h, hi); Self.fnv(&h, lo)
            Self.fnv(&h, UInt64(UInt32(bitPattern: folder[i])) << 1 | (isPage[i] ? 1 : 0))
        }
        for f in 0..<fc {
            let (hi, lo) = Self.words(folderIDs[f])
            Self.fnv(&h, hi); Self.fnv(&h, lo); Self.fnv(&h, UInt64(UInt32(bitPattern: parent[f])))
        }
        for k in keys.indices where k == 0 || keys[k] != keys[k - 1] { Self.fnv(&h, keys[k]) }
        Self.fnv(&h, UInt64(input.linkScale.bitPattern))
        Self.fnv(&h, Self.algorithmVersion)
        signature = h
    }

    // MARK: - The filter

    /// Which bodies (notes, then hubs) the filter lets through; nil for all
    /// of them. A folder's hub shows while any note under it does, and under
    /// a folder filter every hub inside that folder shows.
    func mask(_ filter: GraphPerfFilter) -> [Bool]? {
        var shown = [Bool](repeating: false, count: nodeCount)
        switch filter {
        case .all:
            return nil
        case .pages:
            for i in 0..<noteCount { shown[i] = isPage[i] }
        case .ideas:
            for i in 0..<noteCount { shown[i] = !isPage[i] }
        case .linked:
            for i in 0..<noteCount { shown[i] = degree(i) > 0 }
        case .folder(let id):
            guard let wanted = folderIDs.firstIndex(of: id) else { return shown }
            // a folder is inside `wanted` if walking up reaches it (the tree
            // is acyclic once cut; depth bounds the walk)
            var inside = [Bool](repeating: false, count: folderCount)
            for f in 0..<folderCount {
                var cur = Int32(f), steps = 0
                while cur >= 0 && steps <= folderCount {
                    if Int(cur) == wanted { inside[f] = true; break }
                    cur = folderParent[Int(cur)]
                    steps += 1
                }
                shown[noteCount + f] = inside[f]
            }
            for i in 0..<noteCount where folder[i] >= 0 { shown[i] = inside[Int(folder[i])] }
            return shown
        }
        // hubs: any shown note in the subtree, children before parents
        var any = [Bool](repeating: false, count: folderCount)
        for i in 0..<noteCount where shown[i] && folder[i] >= 0 { any[Int(folder[i])] = true }
        for f in Self.deepestFirst(folderDepth) where any[f] && folderParent[f] >= 0 { any[Int(folderParent[f])] = true }
        for f in 0..<folderCount { shown[noteCount + f] = any[f] }
        return shown
    }

    // MARK: - Helpers

    /// A UUID as two big-endian words, so comparing words compares bytes.
    static func words(_ id: UUID) -> (UInt64, UInt64) {
        withUnsafeBytes(of: id.uuid) { raw in
            (UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self)),
             UInt64(bigEndian: raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)))
        }
    }

    /// Indices of `ids` in byte order (ties, a duplicated id, by index).
    private static func order(_ ids: [UUID]) -> [Int32] {
        var keyed = ids.enumerated().map { (i, id) -> (UInt64, UInt64, Int32) in
            let (hi, lo) = words(id)
            return (hi, lo, Int32(i))
        }
        keyed.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 < $1.2 }
        return keyed.map { $0.2 }
    }

    /// Items 0..<keys.count bucketed by key (counting sort; -1 left out), in index order.
    static func buckets(count: Int, keys: [Int32]) -> (start: [Int32], items: [Int32]) {
        var start = [Int32](repeating: 0, count: count + 1)
        for k in keys where k >= 0 { start[Int(k) + 1] += 1 }
        for b in 0..<count { start[b + 1] += start[b] }
        var fill = start
        var items = [Int32](repeating: 0, count: Int(start[count]))
        for (i, k) in keys.enumerated() where k >= 0 {
            items[Int(fill[Int(k)])] = Int32(i)
            fill[Int(k)] += 1
        }
        return (start, items)
    }

    /// Folder slots by depth, deepest first (children before parents).
    static func deepestFirst(_ depth: [Int32]) -> [Int] {
        let deepest = Int(depth.max() ?? 0)
        let byDepth = buckets(count: deepest + 1, keys: depth.map { Int32(deepest) - $0 })
        return byDepth.items.map { Int($0) }
    }

    /// Least significant digit radix sort, 16 bits a pass, only as many
    /// passes as the largest key needs (three at 100k notes).
    static func radixSort(_ a: inout [UInt64], maxKey: UInt64) {
        guard a.count > 1 else { return }
        let bits = 64 - maxKey.leadingZeroBitCount
        var b = [UInt64](repeating: 0, count: a.count)
        var count = [Int](repeating: 0, count: 65_537)
        var shift = 0
        while shift < bits {
            for i in count.indices { count[i] = 0 }
            for k in a { count[Int((k >> UInt64(shift)) & 0xFFFF) + 1] += 1 }
            for d in 0..<65_536 { count[d + 1] += count[d] }
            for k in a {
                let d = Int((k >> UInt64(shift)) & 0xFFFF)
                b[count[d]] = k
                count[d] += 1
            }
            swap(&a, &b)
            shift += 16
        }
    }

    /// FNV-1a over the eight bytes of `v`.
    static func fnv(_ h: inout UInt64, _ v: UInt64) {
        var x = v
        for _ in 0..<8 {
            h = (h ^ (x & 0xFF)) &* 0x0000_0100_0000_01B3
            x >>= 8
        }
    }
}
