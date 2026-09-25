import SceneKit
import UIKit
import simd

/// Which notes the space is showing.
enum GraphFilter: Hashable {
    case all
    case pages
    case ideas
    /// Only notes joined to at least one other.
    case linked
    /// Only notes somewhere inside this top-level folder.
    case folder(UUID)

    /// Whether a note with this kind, top-level folder and number of links
    /// is shown.
    func admits(kind: NoteKind, root: UUID?, degree: Int) -> Bool {
        switch self {
        case .all: return true
        case .pages: return kind == .page
        case .ideas: return kind == .idea
        case .linked: return degree > 0
        case .folder(let id): return root == id
        }
    }
}

/// Everything the live space needs to know about one note, gathered when the
/// scene is built.
struct GraphNodeInfo {
    let id: UUID
    let node: SCNNode
    let label: SCNNode
    let kind: NoteKind
    let root: UUID?
    let home: SIMD3<Float>
    /// The black sphere's radius.
    let radius: Float
    /// The photon ring: `ringStretch` (inside a billboarded holder, lifted
    /// towards the camera) squashes and stretches it along the note's motion;
    /// `ringLeaf` carries the plane, turned back so its bright side stays on
    /// the right.
    let ringStretch: SCNNode
    let ringLeaf: SCNNode
    let ringGeometry: SCNGeometry
    /// The accretion disk's plane, spun about its own axis inside a tilted
    /// holder.
    let diskLeaf: SCNNode
    /// Nil for a style with no disk (GraphStyleKit).
    let diskGeometry: SCNGeometry?
    /// Where the disk starts in its turn, and how fast it turns at rest
    /// (radians a second).
    let spin: Float
    let spinRate: Float
    /// The note's look (GraphNodeStyles), and its brighter ring and disk
    /// while chosen (nil: it keeps its own; the orbit ring shows instead).
    var style: GraphNodeStyle = .blackHole
    var hotRing: SCNGeometry? = nil
    var hotDisk: SCNGeometry? = nil
    /// How much the ring's glow swells when the note moves (a sun's
    /// corona), how far it stretches along the motion (1 for a black
    /// hole's ring), and how bright it is at rest (from how linked the note
    /// is).
    var swell: Float = 0
    var stretchGain: Float = 1
    var glowGain: Float = 1
}

/// The pieces of the look GraphSim drives that are shared by every note.
struct GraphSimLooks {
    /// Every link, in one geometry.
    let linkMaterial: SCNMaterial
    /// The selected note's ring and disk, brighter.
    let hotRing: SCNGeometry
    let hotDisk: SCNGeometry
    /// Materials whose shader reads the `rpClock` argument.
    let clocked: [SCNMaterial]
    /// Comet-trail emitters (empty with Reduce Motion), each with its system.
    let emitters: [SCNNode]
    let trails: [SCNParticleSystem]
    /// The sky (GraphSpace), kept centred on the camera.
    let sky: SCNNode
    /// Moves each style's own pieces (GraphStyleAnimator); nil draws every
    /// note as the plain black hole it always was.
    var styler: GraphStyleAnimator? = nil
    /// What the scene before this one showed (GraphMemory), so only what
    /// changed pops, grows or fades.
    var recall: GraphRecall = .everything
}

/// Keeps the space gently alive, and drives the black holes' motion.
///
/// The force layout (ForceLayout3D) decides where every note belongs - its
/// home. Every frame this nudges each note towards its home on a soft spring,
/// while each link acts as a second spring holding its two ends about as far
/// apart as the layout put them. The result:
///
/// - every note drifts in a small slow loop of its own, so the space breathes;
/// - a note that is dragged follows the finger exactly and pulls its
///   neighbours along; let go, it keeps the finger's speed, glides, and
///   springs home with a little overshoot;
/// - notes pop into place when they appear or are tapped.
///
/// It runs on SceneKit's own render loop (it is the view's renderer
/// delegate), so every frame drawn is a frame stepped, at whatever rate the
/// screen runs - 120 a second on ProMotion. Gestures on the main thread only
/// leave a note of where the finger is; the render loop does the moving. The
/// two meet under a lock that is never held while calling into SceneKit from
/// the main thread.
///
/// Each note wears its style (GraphNodeStyles: black hole, sun, planet,
/// gas giant, pulsar or comet). At rest its disk turns slowly, each at its
/// own speed, and its glow shimmers (in the shaders). Moving - dragged,
/// flung, or springing home - its disk spins faster with its speed, its
/// glow brightens and stretches a little along the way it is going (a
/// sun's corona swells), and the few fastest notes trail sparks in their
/// style's colour; let go, all of it eases back. Everything else a style
/// does is GraphStyleAnimator's, called from here each frame.
///
/// Notes pop in, out and bounce on a size spring (stepPops) with a bloom of
/// light; links grow in from their sending end and draw back into it
/// (stepLinks); after a rebuild only what changed does either
/// (GraphMemory).
///
/// Links are one geometry of camera-facing ribbons (GraphRibbonWriter),
/// rebuilt from the notes' positions each frame they move, bent into black
/// holes' disks; their look, and what each end's style does to it, is in
/// the link shader.
///
/// Names: a note's name shows only for the note under the pointer, the
/// note being pressed (held down) and the note being dragged. It pops in - from 85%
/// to full size in about an eighth of a second - and goes at once when it is
/// no longer wanted; it is never half see-through.
///
/// The window: the whole graph hangs from a tilt rig, which the device's
/// tilt (PopOutMotion.snapshot, readable from this render thread) turns a
/// few hundredths of a radian about the camera's own up and right, and the
/// sky half as much - so the notes shift against the stars as if seen
/// through the screen. It holds still while a note is dragged, and stays
/// square with Reduce Motion, or when the pop-out effect is still or off.
///
/// The work each frame is one pass over the notes and one over the links -
/// there is no every-note-against-every-note step here - so a few hundred
/// notes stay cheap. With Reduce Motion on there is no drifting, no popping,
/// no overshoot, no spin, no shimmer, no sparks and no tilt, and nothing is
/// worked out at all while the space and the camera are still.
nonisolated final class GraphSim: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    /// The node every note and link hangs from.
    let world: SCNNode
    /// The node `world` hangs from, turned by the device's tilt.
    private let rig: SCNNode
    /// Which note sits at which index.
    let index: [UUID: Int]
    /// Which note sits at each index: the other way round from `index`.
    let ids: [UUID]

    private let nodes: [SCNNode]
    private let labels: [SCNNode]
    private let kinds: [NoteKind]
    private let roots: [UUID?]
    private let degree: [Int]
    private let home: [SIMD3<Float>]
    /// Where in its slow loop each note starts, so they do not move in step.
    private let phase: [Float]
    private let edges: [(Int, Int)]
    /// How far apart the layout put each link's two ends.
    private let rest: [Float]
    private let lines: SCNNode
    private let lineMaterial: SCNMaterial
    private let lively: Bool

    // the black holes
    private let radius: [Float]
    private let ringStretch: [SCNNode]
    private let ringLeaf: [SCNNode]
    private let ringGeometry: [SCNGeometry]
    private let diskLeaf: [SCNNode]
    private let diskGeometry: [SCNGeometry?]
    private let spinRate: [Float]
    private let hotRingOf: [SCNGeometry?]
    private let hotDiskOf: [SCNGeometry?]
    private let swell: [Float]
    private let stretchGain: [Float]
    private let glowGain: [Float]
    /// Each note's style code (GraphNodeStyle.code), for the links.
    private let codes: [Int]
    private let styler: GraphStyleAnimator?
    private let ribbons = GraphRibbonWriter()
    private var ribbonLinks: [GraphRibbonLink] = []
    private let hotRing: SCNGeometry
    private let hotDisk: SCNGeometry
    private let clocked: [SCNMaterial]
    private let emitters: [SCNNode]
    private let trails: [SCNParticleSystem]
    private let sky: SCNNode
    /// The note whose ring and disk are the bright ones. Main thread only.
    private var highlighted: Int?
    /// Kept from when names showed by distance; no longer read.
    private let labelReach: Float
    /// The eye, smoothed once more for the rig. Render thread only.
    private var tiltEye = SIMD2<Float>(0, 0)
    /// True while the rig and the sky are square. Render thread only.
    private var rigSquare: Bool = true

    /// Guards everything below that both the main thread and the render loop
    /// touch.
    private let lock = NSLock()

    private var position: [SIMD3<Float>]
    private var velocity: [SIMD3<Float>]
    /// Reused every step, so a frame allocates nothing for forces.
    private var force: [SIMD3<Float>]
    private var visible: [Bool]
    /// How far each shown name is through popping in, 0 to 1.
    private var labelPop: [Float]
    /// The names up now, and the ones wanted this frame (at most three).
    private var labelsUp: [Int] = []
    private var labelsWanted: [Int] = []
    private var shownEdges: [Int] = []
    /// Set when the shown links change; the render loop redraws them.
    private var linesDirty: Bool = true
    /// Each note's size while it pops in, out or bounces (a spring towards
    /// `popGoal`, after `popWait` seconds), and the glow that blooms as it
    /// appears. Render thread, under the lock.
    private var popScale: [Float]
    private var popVelocity: [Float]
    private var popGoal: [Float]
    private var popWait: [Float]
    private var popHidden: [Bool]
    private var bloom: [Float]
    private var shownBloom: [Float]
    private var shownTurn: [Float]
    /// How far each link has grown (0 to 1), and how long a new one waits
    /// for its notes before it grows; links gone since the last scene,
    /// fading back into their sending note.
    private var linkGrow: [Float]
    private var linkWait: [Float]
    private var ghostEdges: [(Int, Int)]
    private var ghostGrow: [Float]
    /// The shaders' own time (wrapped clock, times rpMotion), for the
    /// styles that must keep in step with them.
    private var shaderTime: Float = 0
    /// The camera, in the space's own coordinates, when last seen.
    private var lastEye = SIMD3<Float>(0, 0, 0)
    /// How far through its turn each disk is.
    private var spin: [Float]
    /// How much each note is moving, 0 to 1, eased.
    private var level: [Float]
    /// What each ring was last shaped with, so an unchanged ring is left alone.
    private var shownFit: [Float]
    private var shownLevel: [Float]
    /// The fastest few moving notes this frame, and which note each trail
    /// emitter is following.
    private var picks: [(Int, Float)] = []
    private var wanted: [Int] = []
    private var owner: [Int?]
    private var clock: Float = 0
    private var frame: Int = 0
    private var lastTime: TimeInterval = 0
    /// True while nothing is moving and nothing needs to; the frame's work is
    /// skipped then.
    private var resting: Bool = false

    /// The note being dragged, where the finger wants it, and how fast the
    /// finger has lately been moving it (smoothed, so a jittery last touch
    /// does not fling it).
    private var grabbed: Int?
    private var grabTarget = SIMD3<Float>(0, 0, 0)
    private var dragVelocity = SIMD3<Float>(0, 0, 0)
    /// The last note tapped or dragged; its ring stays bright (its name
    /// shows only while it is pressed or hovered).
    private var selected: Int?
    /// The note under the pointer (iPad trackpad, mouse, Pencil hover).
    private var hovered: Int?
    /// The note a finger, Pencil or click is down on right now; nil once it
    /// lifts.
    private var pressedNote: Int?

    /// Spring towards home: how hard it pulls, and how much of the motion
    /// each second it soaks up. Lively uses a damping ratio of 0.6 for a
    /// soft bounce that settles smoothly; Reduce Motion uses critical
    /// damping, so nothing overshoots.
    private let stiffness: Float = 6
    private let damping: Float
    /// How hard each link holds its two ends at their resting distance.
    private let linkStiffness: Float = 4
    /// How far a note drifts from home in its slow loop.
    private let drift: Float = 0.07
    /// How long a name takes to pop in, in seconds.
    private let labelPopTime: Float = 0.12
    /// How far the rig turns (radians) for a full unit of eye movement:
    /// about the camera's up for left and right, its right for up and down.
    private let tiltYaw: Float = 0.05
    private let tiltPitch: Float = 0.035
    /// The longest single integration step; longer frames are split.
    private let maxSubstep: Float = 1.0 / 120.0
    /// The fastest a let-go note may fly off.
    private let flingLimit: Float = 8
    /// The speed (units a second) at which a note counts as fully moving.
    private let fullSpeed: Float = 2.5
    /// Below this speed a note leaves no trail.
    private let trailSpeed: Float = 0.9

    init(world: SCNNode, rig: SCNNode, infos: [GraphNodeInfo], edges pairs: [(UUID, UUID)],
         lines: SCNNode, looks: GraphSimLooks, lively: Bool, labelReach: Float) {
        self.world = world
        self.rig = rig
        self.lines = lines
        self.lineMaterial = looks.linkMaterial
        self.lively = lively
        self.hotRing = looks.hotRing
        self.hotDisk = looks.hotDisk
        self.clocked = looks.clocked
        self.emitters = looks.emitters
        self.trails = looks.trails
        self.sky = looks.sky
        self.labelReach = labelReach
        // critical damping is 2 * sqrt(stiffness), about 4.9
        let critical: Float = 2 * stiffness.squareRoot()
        self.damping = lively ? critical * 0.6 : critical

        var lookup: [UUID: Int] = [:]
        var idList: [UUID] = []
        var nodeList: [SCNNode] = []
        var labelList: [SCNNode] = []
        var kindList: [NoteKind] = []
        var rootList: [UUID?] = []
        var homeList: [SIMD3<Float>] = []
        var phaseList: [Float] = []
        var random = SplitMix64(seed: 0xB0B)
        for (i, info) in infos.enumerated() {
            lookup[info.id] = i
            idList.append(info.id)
            nodeList.append(info.node)
            labelList.append(info.label)
            kindList.append(info.kind)
            rootList.append(info.root)
            homeList.append(info.home)
            let turn: Float = random.unit() * Float.pi
            phaseList.append(turn)
        }
        index = lookup
        ids = idList
        nodes = nodeList
        labels = labelList
        kinds = kindList
        roots = rootList
        home = homeList
        phase = phaseList
        radius = infos.map(\.radius)
        ringStretch = infos.map(\.ringStretch)
        ringLeaf = infos.map(\.ringLeaf)
        ringGeometry = infos.map(\.ringGeometry)
        diskLeaf = infos.map(\.diskLeaf)
        diskGeometry = infos.map(\.diskGeometry)
        spinRate = infos.map(\.spinRate)
        hotRingOf = infos.map(\.hotRing)
        hotDiskOf = infos.map(\.hotDisk)
        swell = infos.map(\.swell)
        stretchGain = infos.map(\.stretchGain)
        glowGain = infos.map(\.glowGain)
        codes = infos.map { $0.style.code }
        styler = looks.styler
        spin = infos.map(\.spin)
        level = [Float](repeating: 0, count: infos.count)
        // impossible values, so every ring is shaped on the first frame
        shownFit = [Float](repeating: -1, count: infos.count)
        shownLevel = [Float](repeating: 1, count: infos.count)
        owner = [Int?](repeating: nil, count: looks.emitters.count)

        var edgeList: [(Int, Int)] = []
        var restList: [Float] = []
        var degreeList = [Int](repeating: 0, count: infos.count)
        var seen = Set<Int>()
        let count: Int = infos.count
        for (a, b) in pairs {
            guard let i = lookup[a], let j = lookup[b], i != j else { continue }
            let low: Int = min(i, j)
            let high: Int = max(i, j)
            let key: Int = low * count + high
            guard seen.insert(key).inserted else { continue }
            edgeList.append((i, j))
            let gap: Float = simd_distance(homeList[i], homeList[j])
            restList.append(gap)
            degreeList[i] += 1
            degreeList[j] += 1
        }
        edges = edgeList
        rest = restList
        degree = degreeList

        // Lively, on first showing: start a little way in from home, so the
        // space blooms outward as it opens. On a rebuild, each known note
        // starts where it was and glides to its new home; a new one pops in
        // at home. Still: start at home and stay there.
        let recall: GraphRecall = looks.recall
        var start: [SIMD3<Float>] = []
        start.reserveCapacity(homeList.count)
        var scales: [Float] = []
        var waits: [Float] = []
        for (k, p) in homeList.enumerated() {
            let id: UUID = idList[k]
            var from: SIMD3<Float> = p
            if lively, let known = recall.starts[id] {
                from = known
            } else if lively && recall.fresh == nil {
                from = p * Float(0.7)
            }
            start.append(from)
            let isFresh: Bool = recall.fresh?.contains(id) ?? true
            let wait: Float = recall.fresh == nil ? min(Float(k) * 0.004, 0.6) : 0.05
            scales.append(lively && isFresh ? 0 : 1)
            waits.append(lively && isFresh ? wait : 0)
        }
        popScale = scales
        popWait = waits
        popVelocity = [Float](repeating: 0, count: infos.count)
        popGoal = [Float](repeating: 1, count: infos.count)
        popHidden = [Bool](repeating: false, count: infos.count)
        bloom = [Float](repeating: 0, count: infos.count)
        shownBloom = [Float](repeating: 1, count: infos.count)
        shownTurn = [Float](repeating: 9, count: infos.count)

        // links: new ones grow once both their notes are in; links gone
        // since the last scene fade back into their sending note
        var grows: [Float] = []
        var linkWaits: [Float] = []
        for (i, j) in edgeList {
            let key: String = GraphMemory.key(idList[i], idList[j])
            let isFresh: Bool = recall.freshLinks?.contains(key) ?? true
            grows.append(lively && isFresh ? 0 : 1)
            linkWaits.append(max(waits[i], waits[j]) + 0.25)
        }
        linkGrow = grows
        linkWait = linkWaits
        var ghostList: [(Int, Int)] = []
        if lively {
            for (a, b) in recall.ghosts {
                guard let i = lookup[a], let j = lookup[b] else { continue }
                ghostList.append((i, j))
            }
        }
        ghostEdges = ghostList
        ghostGrow = [Float](repeating: 1, count: ghostList.count)
        let zero = SIMD3<Float>(0, 0, 0)
        position = start
        velocity = [SIMD3<Float>](repeating: zero, count: infos.count)
        force = [SIMD3<Float>](repeating: zero, count: infos.count)
        visible = [Bool](repeating: true, count: infos.count)
        labelPop = [Float](repeating: 0, count: infos.count)
        resting = !lively
        super.init()

        for (i, node) in nodes.enumerated() {
            node.simdPosition = position[i]
            let size: Float = max(popScale[i], 0.001)
            node.simdScale = SIMD3<Float>(size, size, size)
            // names are either fully there or not there at all
            labels[i].opacity = 1
            labels[i].isHidden = true
        }
        shownEdges = Array(edges.indices)
        // the first frame builds the links, once it knows where the camera is
        linesDirty = true
    }

    // MARK: appearing and popping

    /// Every new note grows in with a small bounce and a bloom of light, a
    /// few at a time (the render loop runs the springs; see stepPops). The
    /// sizes were set up in init; this only wakes the loop.
    func appear() {
        guard lively else { return }
        lock.lock()
        resting = false
        lock.unlock()
    }

    /// A springy pop: a kick to the note's size spring, so it swells a
    /// little, dips and settles, with a small bloom. Called without the
    /// lock held.
    func pop(_ i: Int, delay: TimeInterval = 0) {
        guard i >= 0, i < nodes.count, lively else { return }
        lock.lock()
        popWait[i] = max(popWait[i], Float(delay))
        popVelocity[i] += 3.2
        bloom[i] = max(bloom[i], 0.45)
        resting = false
        lock.unlock()
    }

    /// Marks a note as the one being looked at: its ring stays bright.
    func select(_ i: Int) {
        guard i >= 0, i < nodes.count else { return }
        lock.lock()
        selected = i
        resting = false
        lock.unlock()
        highlight(i)
        pop(i)
    }

    /// Lets the chosen note go: its ring dims. Called without the lock held.
    func clearSelection() {
        lock.lock()
        let had: Bool = selected != nil
        selected = nil
        resting = false
        lock.unlock()
        if had || highlighted != nil { highlight(nil) }
    }

    /// The chosen note, if any.
    var selectedNote: Int? {
        lock.lock()
        defer { lock.unlock() }
        return selected
    }

    /// The note under the pointer, or nil when the pointer is over none or
    /// has left. Only noted here; the render loop shows its name.
    func hover(_ i: Int?) {
        var note: Int? = i
        if let i, i < 0 || i >= nodes.count { note = nil }
        lock.lock()
        hovered = note
        lock.unlock()
    }

    /// The note being pressed (touch down, held), or nil when the press
    /// ends. Only noted here; the render loop shows its name while held.
    func press(_ i: Int?) {
        var note: Int? = i
        if let i, i < 0 || i >= nodes.count { note = nil }
        lock.lock()
        pressedNote = note
        lock.unlock()
    }

    /// Whether note `i` is let through by the filter.
    func isVisible(_ i: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard i >= 0, i < visible.count else { return false }
        return visible[i]
    }

    /// Every shown note and where it is now, in the space's own coordinates,
    /// read under one lock - for finding the note nearest a finger.
    func visiblePositions() -> [(Int, SIMD3<Float>)] {
        lock.lock()
        defer { lock.unlock() }
        var found: [(Int, SIMD3<Float>)] = []
        found.reserveCapacity(position.count)
        for i in position.indices where visible[i] {
            found.append((i, position[i]))
        }
        return found
    }

    /// Gives note `i` the bright ring and disk, and the one that had them
    /// back its own. Main thread, without the lock.
    private func highlight(_ i: Int?) {
        if let old = highlighted, old != i {
            ringLeaf[old].geometry = ringGeometry[old]
            diskLeaf[old].geometry = diskGeometry[old]
        }
        if let i {
            // a styled note brings its own bright pair, or none (the orbit
            // ring marks it); the plain space keeps the shared pair
            if styler == nil {
                ringLeaf[i].geometry = hotRing
                diskLeaf[i].geometry = hotDisk
            } else {
                if let hot = hotRingOf[i] { ringLeaf[i].geometry = hot }
                if let hot = hotDiskOf[i] { diskLeaf[i].geometry = hot }
            }
        }
        highlighted = i
    }

    /// The note with the most links among those shown, for the design
    /// preview's drag.
    func busiestNote() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        var best: Int?
        var most: Int = -1
        for i in nodes.indices where visible[i] && degree[i] > most {
            best = i
            most = degree[i]
        }
        return best
    }

    // MARK: dragging

    /// Where a note is now, in the space's own coordinates.
    func currentPosition(_ i: Int) -> SIMD3<Float> {
        lock.lock()
        defer { lock.unlock() }
        guard i >= 0, i < position.count else { return SIMD3<Float>(0, 0, 0) }
        return position[i]
    }

    var isDragging: Bool {
        lock.lock()
        defer { lock.unlock() }
        return grabbed != nil
    }

    func grab(_ i: Int) {
        guard i >= 0, i < nodes.count else { return }
        lock.lock()
        grabbed = i
        grabTarget = position[i]
        dragVelocity = SIMD3<Float>(0, 0, 0)
        velocity[i] = SIMD3<Float>(0, 0, 0)
        selected = i
        resting = false
        lock.unlock()
        highlight(i)
        pop(i)
    }

    /// Where the finger wants the dragged note. Only noted here; the render
    /// loop moves it on its next frame.
    func drag(to target: SIMD3<Float>) {
        lock.lock()
        grabTarget = target
        lock.unlock()
    }

    /// Lets go; the note keeps the finger's speed, glides, and springs home.
    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard let i = grabbed else { return }
        var fling: SIMD3<Float> = dragVelocity
        let speed: Float = simd_length(fling)
        if speed > flingLimit {
            let shrink: Float = flingLimit / speed
            fling *= shrink
        }
        if !lively { fling = SIMD3<Float>(0, 0, 0) }
        velocity[i] = fling
        grabbed = nil
        resting = false
    }

    // MARK: showing and hiding

    /// Shows only the notes the filter lets through and the links between
    /// them.
    @MainActor
    func apply(_ filter: GraphFilter) {
        var changed: [(Int, Bool)] = []
        lock.lock()
        for i in nodes.indices {
            let shown: Bool = filter.admits(kind: kinds[i], root: roots[i], degree: degree[i])
            if shown != visible[i] {
                visible[i] = shown
                changed.append((i, shown))
            }
        }
        var kept: [Int] = []
        for (e, pair) in edges.enumerated() where visible[pair.0] && visible[pair.1] {
            kept.append(e)
        }
        shownEdges = kept
        linesDirty = true
        if let chosen = selected, !visible[chosen] { selected = nil }
        if let pointed = hovered, !visible[pointed] { hovered = nil }
        if let held = pressedNote, !visible[held] { pressedNote = nil }
        let stillSelected: Int? = selected
        resting = false
        if lively {
            // shrink away, or grow back in with a bloom (stepPops)
            for (i, shown) in changed {
                popGoal[i] = shown ? 1 : 0
                if shown { popWait[i] = 0 }
            }
        }
        lock.unlock()
        if stillSelected == nil { highlight(nil) }
        if lively { return }

        // SceneKit is touched only once the lock is let go
        for (i, shown) in changed {
            nodes[i].isHidden = !shown
        }
    }

    // MARK: each frame

    /// SceneKit calls this on its render thread once before every frame it
    /// draws.
    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let raw: TimeInterval = lastTime == 0 ? 1.0 / 60.0 : time - lastTime
        lastTime = time
        let pov: SCNNode? = renderer.pointOfView
        let eye: SIMD3<Float> = pov?.simdWorldPosition ?? SIMD3<Float>(0, 0, 10)
        let pose: simd_float4x4 = pov?.simdWorldTransform ?? matrix_identity_float4x4
        let right = SIMD3<Float>(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z)
        let up = SIMD3<Float>(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        // the window: turned by the tilt before anything is stepped; the
        // rig is touched outside the lock
        lock.lock()
        let held: Bool = grabbed != nil
        lock.unlock()
        tilt(right: right, up: up, held: held)
        if lively { tickShaders(time) }
        // the sky stays centred on the camera, so it is at infinity
        sky.simdWorldPosition = eye
        lock.lock()
        step(Float(raw), eye: eye, right: right, up: up)
        lock.unlock()
        SCNTransaction.commit()
    }

    /// Turns the rig a few hundredths of a radian with the device's tilt,
    /// about the camera's own up (left and right) and right (up and down),
    /// and the sky by half as much. Moving the eye right shows a little more
    /// of the notes' right side. Holds its pose while a note is dragged, so
    /// the note stays under the finger; square when not lively.
    private func tilt(right: SIMD3<Float>, up: SIMD3<Float>, held: Bool) {
        guard lively else {
            if !rigSquare { squareRig() }
            return
        }
        if held { return }
        let raw: SIMD2<Float> = PopOutMotion.snapshot.read()
        let change: SIMD2<Float> = (raw - tiltEye) * 0.2
        tiltEye += change
        let quiet: Bool = abs(tiltEye.x) < 0.0005 && abs(tiltEye.y) < 0.0005
        if quiet {
            if !rigSquare { squareRig() }
            return
        }
        let upAxis: SIMD3<Float> = Self.axis(up, or: SIMD3<Float>(0, 1, 0))
        let rightAxis: SIMD3<Float> = Self.axis(right, or: SIMD3<Float>(1, 0, 0))
        let yawAngle: Float = -tiltEye.x * tiltYaw
        let pitchAngle: Float = -tiltEye.y * tiltPitch
        let yaw = simd_quatf(angle: yawAngle, axis: upAxis)
        let pitch = simd_quatf(angle: pitchAngle, axis: rightAxis)
        rig.simdOrientation = yaw * pitch
        let skyYaw = simd_quatf(angle: yawAngle * 0.5, axis: upAxis)
        let skyPitch = simd_quatf(angle: pitchAngle * 0.5, axis: rightAxis)
        sky.simdOrientation = skyYaw * skyPitch
        rigSquare = false
    }

    private func squareRig() {
        let square = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        rig.simdOrientation = square
        sky.simdOrientation = square
        tiltEye = SIMD2<Float>(0, 0)
        rigSquare = true
    }

    /// `v` made unit length, or `fallback` when it has none.
    private static func axis(_ v: SIMD3<Float>, or fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length: Float = simd_length(v)
        guard length > 0.0001 else { return fallback }
        return v / length
    }

    /// Hands the shaders the time, wrapped so a 32-bit float keeps it fine
    /// (see GraphShaders).
    private func tickShaders(_ time: TimeInterval) {
        let wrapped: Double = time.truncatingRemainder(dividingBy: GraphShape.clockPeriod)
        let clock = NSNumber(value: Float(wrapped))
        shaderTime = Float(wrapped)
        for material in clocked {
            material.setValue(clock, forKey: "rpClock")
        }
    }

    /// Moves everything on by `rawStep` seconds. `worldEye`, `worldRight`
    /// and `worldUp` are the camera's position and its screen's right and up
    /// in the scene. Called with the lock held.
    private func step(_ rawStep: Float, eye worldEye: SIMD3<Float>,
                      right worldRight: SIMD3<Float>, up worldUp: SIMD3<Float>) {
        frame += 1
        let eye: SIMD3<Float> = world.simdConvertPosition(worldEye, from: nil)
        let right: SIMD3<Float> = world.simdConvertVector(worldRight, from: nil)
        let up: SIMD3<Float> = world.simdConvertVector(worldUp, from: nil)
        let turned: Bool = simd_distance_squared(eye, lastEye) > 1e-8
        lastEye = eye
        var linksStale: Bool = turned
        if linesDirty {
            linesDirty = false
            linksStale = true
        }
        // names pop in and go every frame, even when the notes are still
        let labelStep: Float = min(max(rawStep, 0.001), 0.05)
        updateLabels(labelStep)
        if resting && grabbed == nil {
            // the ribbons face the camera and the rings are sized for it, so
            // both follow it even when nothing else moves
            if linksStale { updateLines(eye: eye) }
            if turned {
                poseStyles(0, eye: eye, right: right, up: up)
                fitRings(eye: eye)
            }
            return
        }

        let dt: Float = min(max(rawStep, 0.001), 0.05)

        // the dragged note sits exactly under the finger
        if let g = grabbed {
            let moved: SIMD3<Float> = grabTarget - position[g]
            let instant: SIMD3<Float> = moved / dt
            // smooth the finger's speed over about the last 50 ms
            let blend: Float = 1 - exp(-dt / 0.05)
            let change: SIMD3<Float> = (instant - dragVelocity) * blend
            dragVelocity += change
            position[g] = grabTarget
            velocity[g] = dragVelocity
        }

        // long frames are split, so the springs stay steady at any frame rate
        let pieces: Int = max(1, Int((dt / maxSubstep).rounded(.up)))
        let h: Float = dt / Float(pieces)
        var fastest: Float = 0
        for _ in 0..<pieces {
            fastest = integrate(h)
        }

        for i in nodes.indices {
            nodes[i].simdPosition = position[i]
        }
        if lively {
            stepPops(dt)
            stepLinks(dt)
        }
        updateLines(eye: eye)
        if lively {
            animateLooks(dt, eye: eye, right: right, up: up)
        } else {
            poseStyles(0, eye: eye, right: right, up: up)
            fitRings(eye: eye)
        }

        // still, and nothing will set it moving by itself: stop working
        if !lively && grabbed == nil && fastest < 0.000_01 { resting = true }
    }

    /// One semi-implicit Euler step of `h` seconds. Returns the largest
    /// squared speed, to tell when everything has settled.
    private func integrate(_ h: Float) -> Float {
        clock += h
        let n: Int = nodes.count

        // each note towards its home, drifting in a small loop of its own
        for i in 0..<n {
            let target: SIMD3<Float> = driftTarget(i)
            let offset: SIMD3<Float> = target - position[i]
            let pull: SIMD3<Float> = offset * stiffness
            let brake: SIMD3<Float> = velocity[i] * damping
            force[i] = pull - brake
        }

        // each link holds its ends at the distance the layout gave them
        for (e, pair) in edges.enumerated() {
            let a: Int = pair.0
            let b: Int = pair.1
            let delta: SIMD3<Float> = position[b] - position[a]
            let length: Float = simd_length(delta)
            guard length > 0.0001 else { continue }
            let stretch: Float = length - rest[e]
            let scale: Float = linkStiffness * stretch / length
            let pull: SIMD3<Float> = delta * scale
            force[a] += pull
            force[b] -= pull
        }

        var fastest: Float = 0
        for i in 0..<n {
            if i == grabbed { continue }
            let kick: SIMD3<Float> = force[i] * h
            velocity[i] += kick
            let travel: SIMD3<Float> = velocity[i] * h
            position[i] += travel
            let speed: Float = simd_length_squared(velocity[i])
            fastest = max(fastest, speed)
        }
        return fastest
    }

    /// Where note `i` is heading this instant: home, plus its slow loop.
    private func driftTarget(_ i: Int) -> SIMD3<Float> {
        let base: SIMD3<Float> = home[i]
        guard lively else { return base }
        let t: Float = clock * 0.55 + phase[i]
        let dx: Float = sin(t) * drift
        let dy: Float = sin(t * 1.3 + 1.1) * drift
        let dz: Float = cos(t * 0.8) * drift
        let wobble = SIMD3<Float>(dx, dy, dz)
        return base + wobble
    }

    // MARK: links

    /// Redraws every shown link as a ribbon between the rings of its two
    /// notes, turned to face the camera, bending into a black hole's disk
    /// or towards a gas giant's ring, grown as far as it has grown (see
    /// GraphRibbonWriter, which also packs what the link shader reads into
    /// the texture coordinates). All the links are one geometry, so this is
    /// one draw however many there are. Each link runs from the end with
    /// the higher style code (a sun, a pulsar) to the lower (a black hole
    /// swallows).
    private func updateLines(eye: SIMD3<Float>) {
        ribbonLinks.removeAll(keepingCapacity: true)
        for (e, pair) in edges.enumerated() {
            let shown: Bool = visible[pair.0] && visible[pair.1]
            let grow: Float = lively ? linkGrow[e] : (shown ? 1 : 0)
            guard grow > 0.001 else { continue }
            addRibbon(pair.0, pair.1, seed: e, grow: grow)
        }
        for (g, pair) in ghostEdges.enumerated() {
            let grow: Float = ghostGrow[g]
            guard grow > 0.001, visible[pair.0], visible[pair.1] else { continue }
            addRibbon(pair.0, pair.1, seed: g + 7, grow: grow)
        }
        let focus: Int = grabbed ?? selected ?? -1
        let axes: [SIMD3<Float>]? = styler?.axis
        let geometry: SCNGeometry? = ribbons.write(links: ribbonLinks, position: position, radius: radius,
                                                   codes: codes, axis: axes, focus: focus, eye: eye)
        geometry?.materials = [lineMaterial]
        lines.geometry = geometry
    }

    private func addRibbon(_ i: Int, _ j: Int, seed: Int, grow: Float) {
        let eased: Float = grow * grow * (3 - 2 * grow)
        let swap: Bool = codes[j] > codes[i]
        let a: Int = swap ? j : i
        let b: Int = swap ? i : j
        ribbonLinks.append(GraphRibbonLink(a: a, b: b, seed: seed, grow: eased))
    }

    /// Grows new links once both their notes have popped in (0.7 s), draws
    /// links whose notes are filtered away back into their sending end
    /// (0.45 s), and fades the links gone since the last scene.
    private func stepLinks(_ dt: Float) {
        for (e, pair) in edges.enumerated() {
            let want: Bool = visible[pair.0] && visible[pair.1]
            if want && linkGrow[e] < 1 && linkWait[e] > 0 {
                linkWait[e] -= dt
                continue
            }
            let change: Float = want ? dt / 0.7 : -dt / 0.45
            linkGrow[e] = min(max(linkGrow[e] + change, 0), 1)
        }
        guard !ghostEdges.isEmpty else { return }
        for g in ghostGrow.indices { ghostGrow[g] -= dt / 0.6 }
        if ghostGrow.allSatisfy({ $0 <= 0 }) {
            ghostEdges.removeAll()
            ghostGrow.removeAll()
        }
    }

    /// Each note's size spring: a new note waits its turn, then grows from
    /// nothing with a small overshoot and a bloom of light; a note the
    /// filter hides shrinks away (without overshoot) and is then hidden; a
    /// pop is a kick to the spring.
    private func stepPops(_ dt: Float) {
        let omega: Float = 15
        let fade: Float = exp(-dt / 0.35)
        for i in nodes.indices {
            if bloom[i] > 0.0005 { bloom[i] *= fade } else { bloom[i] = 0 }
            if popWait[i] > 0 {
                popWait[i] -= dt
                if popWait[i] > 0 { continue }
                if popScale[i] < 0.01 { bloom[i] = 1 }
            }
            let goal: Float = popGoal[i]
            var s: Float = popScale[i]
            var v: Float = popVelocity[i]
            if goal > 0.5 && popHidden[i] {
                nodes[i].isHidden = false
                popHidden[i] = false
                s = 0
                bloom[i] = 1
            }
            if abs(goal - s) < 0.0005 && abs(v) < 0.0005 {
                if s != goal {
                    popScale[i] = goal
                    let size: Float = max(goal, 0.001)
                    nodes[i].simdScale = SIMD3<Float>(size, size, size)
                }
                continue
            }
            let zeta: Float = goal > 0.5 ? 0.42 : 1
            let pieces: Int = max(1, Int((dt * 240).rounded(.up)))
            let h: Float = dt / Float(pieces)
            for _ in 0..<pieces {
                let pull: Float = (goal - s) * omega * omega
                let brake: Float = v * 2 * zeta * omega
                v += (pull - brake) * h
                s += v * h
            }
            if goal < 0.5 && s <= 0.02 {
                s = 0
                v = 0
                if !popHidden[i] {
                    nodes[i].isHidden = true
                    popHidden[i] = true
                }
            }
            s = max(s, 0)
            popScale[i] = s
            popVelocity[i] = v
            let size: Float = max(s, 0.001)
            nodes[i].simdScale = SIMD3<Float>(size, size, size)
        }
    }

    /// Any direction square to `dir`, for a link seen exactly end on.
    private static func perpendicular(to dir: SIMD3<Float>) -> SIMD3<Float> {
        let helper: SIMD3<Float> = abs(dir.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let cross: SIMD3<Float> = simd_cross(dir, helper)
        return simd_normalize(cross)
    }

    // MARK: the black holes

    /// Once a frame while lively: spins each disk (faster the faster its note
    /// moves), shapes each ring, and sends the trail emitters after the
    /// fastest notes.
    private func animateLooks(_ dt: Float, eye: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        poseStyles(dt, eye: eye, right: right, up: up)
        let ease: Float = 1 - exp(-dt / 0.15)
        let fullTurn: Float = 2 * Float.pi
        picks.removeAll(keepingCapacity: true)
        let trailSlots: Int = grabbed == nil ? emitters.count : emitters.count - 1
        for i in nodes.indices where visible[i] {
            let speed: Float = simd_length(velocity[i])
            let goal: Float = min(speed / fullSpeed, 1)
            let change: Float = (goal - level[i]) * ease
            level[i] += change
            let m: Float = level[i]
            let boost: Float = 1 + 5 * m
            let rate: Float = spinRate[i] * boost
            var angle: Float = spin[i] + rate * dt
            if angle > fullTurn { angle -= fullTurn }
            spin[i] = angle
            diskLeaf[i].simdEulerAngles = SIMD3<Float>(0, 0, angle)
            shapeRing(i, eye: eye, right: right, up: up)
            if i != grabbed && speed > trailSpeed && trailSlots > 0 {
                consider(i, speed: speed, limit: trailSlots)
            }
        }
        updateTrails()
    }

    /// Keeps `picks` as the fastest `limit` notes seen so far, fastest first.
    private func consider(_ i: Int, speed: Float, limit: Int) {
        if picks.count == limit {
            guard let slowest = picks.last, speed > slowest.1 else { return }
            picks.removeLast()
        }
        var at: Int = picks.count
        while at > 0 && picks[at - 1].1 < speed { at -= 1 }
        picks.insert((i, speed), at: at)
    }

    /// Points each emitter at a moving note - the dragged one first, then the
    /// fastest - keeping a note on the emitter it already has, and sets how
    /// many sparks it throws by how fast that note is going.
    private func updateTrails() {
        guard !emitters.isEmpty else { return }
        wanted.removeAll(keepingCapacity: true)
        if let g = grabbed, visible[g] { wanted.append(g) }
        for pick in picks where wanted.count < emitters.count { wanted.append(pick.0) }
        for slot in owner.indices {
            if let note = owner[slot], !wanted.contains(note) { owner[slot] = nil }
        }
        for note in wanted where !owner.contains(where: { $0 == note }) {
            guard let free = owner.firstIndex(where: { $0 == nil }) else { continue }
            owner[free] = note
            // sparks in the note's own colour: embers, sunfire, dust, ice
            if let styler { trails[free].particleColor = styler.sparkColor(note) }
        }
        for slot in emitters.indices {
            let system: SCNParticleSystem = trails[slot]
            guard let note = owner[slot] else {
                if system.birthRate != 0 { system.birthRate = 0 }
                continue
            }
            emitters[slot].simdPosition = position[note]
            let rate: Float = 160 * level[note]
            system.birthRate = CGFloat(rate)
        }
    }

    /// Hands the frame to the style animator (GraphStyleAnimator): with
    /// `dt` 0 and Reduce Motion it only poses (beams, tails and rings
    /// turned to the camera), nothing runs.
    private func poseStyles(_ dt: Float, eye: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        guard let styler else { return }
        let keyWorld: SIMD3<Float> = simd_normalize(GraphStyleUniforms.key)
        let key: SIMD3<Float> = world.simdConvertVector(keyWorld, from: nil)
        let frame = GraphStyleFrame(dt: dt, time: lively ? shaderTime : 0, eye: eye, right: right, up: up,
                                    key: key, toScene: world.simdWorldTransform, grabbed: grabbed,
                                    selected: selected, lively: lively)
        styler.step(frame, position: position, velocity: velocity, level: level, visible: visible,
                    pop: popScale)
    }

    /// Sizes every shown ring for the camera, with no motion.
    private func fitRings(eye: SIMD3<Float>) {
        let none = SIMD3<Float>(0, 0, 0)
        for i in nodes.indices where visible[i] {
            shapeRing(i, eye: eye, right: none, up: none)
        }
    }

    /// Sizes note `i`'s ring so that, lifted towards the camera, it still
    /// hugs the sphere's silhouette; and squashes and stretches it along the
    /// way the note is moving on screen, a little brighter the faster it
    /// goes. Left alone when nothing about it has changed.
    private func shapeRing(_ i: Int, eye: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>) {
        let distance: Float = simd_distance(eye, position[i])
        let fit: Float = ringFit(distance: distance, radius: radius[i])
        let m: Float = level[i]
        let b: Float = bloom[i]
        let turn: Float = styler?.leafTurn[i] ?? 0
        let quiet: Bool = m < 0.002 && shownLevel[i] < 0.002 && b < 0.002 && shownBloom[i] < 0.002
        let same: Bool = abs(fit - shownFit[i]) < 0.002 && abs(turn - shownTurn[i]) < 0.001
        if quiet && same { return }
        shownFit[i] = fit
        shownLevel[i] = m
        shownBloom[i] = b
        shownTurn[i] = turn

        var angle: Float = 0
        if m >= 0.002 {
            let v: SIMD3<Float> = velocity[i]
            let vx: Float = simd_dot(v, right)
            let vy: Float = simd_dot(v, up)
            if vx * vx + vy * vy > 0.000_001 { angle = atan2(vy, vx) }
        }
        let stretch: Float = 1 + 0.22 * m * stretchGain[i]
        // a sun's corona swells as it moves; every glow blooms as it appears
        let swellBy: Float = 1 + swell[i] * m + 0.6 * b
        let along: Float = fit * stretch * swellBy
        let across: Float = fit / stretch.squareRoot() * swellBy
        let axis = SIMD3<Float>(0, 0, 1)
        ringStretch[i].simdOrientation = simd_quatf(angle: angle, axis: axis)
        ringStretch[i].simdScale = SIMD3<Float>(along, across, 1)
        // turned back, then on to where the style wants its bright side
        ringLeaf[i].simdOrientation = simd_quatf(angle: turn - angle, axis: axis)
        let base: Float = 0.85 + 0.15 * m + 0.35 * b
        let glow: Float = min(base * glowGain[i], 1)
        ringStretch[i].opacity = CGFloat(glow)
    }

    /// How much to shrink a ring lifted towards the camera so it looks the
    /// size of the sphere's silhouette.
    ///
    /// Seen from `distance` away, a sphere of radius r fills an angle whose
    /// tangent is r / sqrt(d^2 - r^2). The ring's plane is lifted
    /// ringLift * r towards the camera, so at (d - lift) away the same angle
    /// is (d - lift) * r / sqrt(d^2 - r^2) across: its scale is that over r.
    /// A little under 1 from afar, less up close.
    private func ringFit(distance d: Float, radius r: Float) -> Float {
        let lift: Float = r * GraphShape.ringLift
        guard d > lift + r * 0.5 else { return 1 }
        let squared: Float = max(d * d - r * r, 0.000_1)
        let fit: Float = (d - lift) / squared.squareRoot()
        return min(max(fit, 0.5), 1.05)
    }

    // MARK: labels

    /// Shows the names of the hovered, pressed and dragged notes (when they
    /// are shown at all) and no others: a chosen note keeps its bright ring
    /// but not its name once the finger lifts. A name pops in from 85% to
    /// full size over about 0.12 s - at once without Reduce Motion's
    /// liveliness - and goes the instant it is not wanted. Called with the
    /// lock held.
    private func updateLabels(_ dt: Float) {
        labelsWanted.removeAll(keepingCapacity: true)
        wantLabel(hovered)
        wantLabel(pressedNote)
        wantLabel(grabbed)
        for i in labelsUp where !labelsWanted.contains(i) {
            labels[i].isHidden = true
        }
        let growth: Float = dt / labelPopTime
        for i in labelsWanted {
            if !labelsUp.contains(i) {
                labelPop[i] = lively ? 0 : 1
                shapeLabel(i)
                labels[i].isHidden = false
            } else if labelPop[i] < 1 {
                labelPop[i] = min(1, labelPop[i] + growth)
                shapeLabel(i)
            }
        }
        swap(&labelsUp, &labelsWanted)
    }

    private func wantLabel(_ i: Int?) {
        guard let i, i >= 0, i < nodes.count, visible[i] else { return }
        if labelsWanted.contains(i) { return }
        labelsWanted.append(i)
    }

    /// Sizes a popping name: 85% to 100%, easing out.
    private func shapeLabel(_ i: Int) {
        let t: Float = labelPop[i]
        let left: Float = 1 - t
        let eased: Float = 1 - left * left
        let size: Float = 0.85 + 0.15 * eased
        labels[i].simdScale = SIMD3<Float>(size, size, size)
    }
}
