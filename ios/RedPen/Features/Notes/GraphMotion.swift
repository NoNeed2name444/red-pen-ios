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
}

/// Keeps the space gently alive.
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
/// The work each frame is one pass over the notes and one over the links -
/// there is no every-note-against-every-note step here - so a few hundred
/// notes stay cheap. Labels are sorted only every few frames. With Reduce
/// Motion on there is no drifting, no popping and no overshoot, and nothing
/// is worked out at all while the space is still.
nonisolated final class GraphSim: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    /// The node every note and link hangs from.
    let world: SCNNode
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
    /// Past this distance from the camera a note's label is not shown.
    private let labelReach: Float

    /// Guards everything below that both the main thread and the render loop
    /// touch.
    private let lock = NSLock()

    private var position: [SIMD3<Float>]
    private var velocity: [SIMD3<Float>]
    /// Reused every step, so a frame allocates nothing for forces.
    private var force: [SIMD3<Float>]
    private var visible: [Bool]
    private var labelOpacity: [Float]
    private var shownEdges: [Int] = []
    private var lineElement: SCNGeometryElement?
    /// Set when the shown links change; the render loop rebuilds them.
    private var linesDirty: Bool = true
    private var vertexBuffer: [SCNVector3] = []
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
    /// The last note tapped or dragged; its label stays up.
    private var selected: Int?

    /// Spring towards home: how hard it pulls, and how much of the motion
    /// each second it soaks up. Lively uses a damping ratio of about 0.5 for
    /// a visible, soft bounce; Reduce Motion uses critical damping, so
    /// nothing overshoots.
    private let stiffness: Float = 6
    private let damping: Float
    /// How hard each link holds its two ends at their resting distance.
    private let linkStiffness: Float = 4
    /// How far a note drifts from home in its slow loop.
    private let drift: Float = 0.07
    /// How many labels may show at once, besides the selected note's.
    private let labelBudget: Int = 8
    /// The longest single integration step; longer frames are split.
    private let maxSubstep: Float = 1.0 / 120.0
    /// The fastest a let-go note may fly off.
    private let flingLimit: Float = 8

    init(world: SCNNode, infos: [GraphNodeInfo], edges pairs: [(UUID, UUID)], lines: SCNNode,
         lineMaterial: SCNMaterial, lively: Bool, labelReach: Float) {
        self.world = world
        self.lines = lines
        self.lineMaterial = lineMaterial
        self.lively = lively
        self.labelReach = labelReach
        // critical damping is 2 * sqrt(stiffness), about 4.9
        let critical: Float = 2 * stiffness.squareRoot()
        self.damping = lively ? critical * 0.5 : critical

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

        // Lively: start a little way in from home, so the space blooms outward
        // as it opens. Still: start at home and stay there.
        var start: [SIMD3<Float>] = []
        start.reserveCapacity(homeList.count)
        for p in homeList {
            let from: SIMD3<Float> = lively ? p * Float(0.7) : p
            start.append(from)
        }
        let zero = SIMD3<Float>(0, 0, 0)
        position = start
        velocity = [SIMD3<Float>](repeating: zero, count: infos.count)
        force = [SIMD3<Float>](repeating: zero, count: infos.count)
        visible = [Bool](repeating: true, count: infos.count)
        labelOpacity = [Float](repeating: 0, count: infos.count)
        resting = !lively
        super.init()

        for (i, node) in nodes.enumerated() {
            node.simdPosition = position[i]
            labels[i].opacity = 0
            labels[i].isHidden = true
        }
        shownEdges = Array(edges.indices)
        rebuildLineElement()
        updateLines()
    }

    // MARK: appearing and popping

    /// Every note grows in with a small bounce, a few at a time.
    func appear() {
        guard lively else { return }
        for (i, node) in nodes.enumerated() {
            node.scale = SCNVector3(x: 0.01, y: 0.01, z: 0.01)
            let wait: Double = min(Double(i) * 0.004, 0.6)
            pop(i, delay: wait)
        }
    }

    /// A springy pop: a little too big, a little too small, then settled.
    /// Called without the lock held.
    func pop(_ i: Int, delay: TimeInterval = 0) {
        guard i >= 0, i < nodes.count else { return }
        let node = nodes[i]
        node.removeAction(forKey: "pop")
        guard lively else {
            node.scale = SCNVector3(x: 1, y: 1, z: 1)
            return
        }
        let up = SCNAction.scale(to: 1.18, duration: 0.14)
        up.timingMode = .easeOut
        let down = SCNAction.scale(to: 0.96, duration: 0.12)
        down.timingMode = .easeInEaseOut
        let settle = SCNAction.scale(to: 1.0, duration: 0.16)
        settle.timingMode = .easeOut
        var steps: [SCNAction] = []
        if delay > 0 { steps.append(SCNAction.wait(duration: delay)) }
        steps.append(up)
        steps.append(down)
        steps.append(settle)
        node.runAction(SCNAction.sequence(steps), forKey: "pop")
    }

    /// Marks a note as the one being looked at: its label stays up.
    func select(_ i: Int) {
        guard i >= 0, i < nodes.count else { return }
        lock.lock()
        selected = i
        resting = false
        lock.unlock()
        pop(i)
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
        resting = false
        lock.unlock()

        // SceneKit is touched only once the lock is let go
        for (i, shown) in changed {
            nodes[i].isHidden = !shown
            if shown { pop(i) }
        }
    }

    // MARK: each frame

    /// SceneKit calls this on its render thread once before every frame it
    /// draws.
    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let raw: TimeInterval = lastTime == 0 ? 1.0 / 60.0 : time - lastTime
        lastTime = time
        let eye: SIMD3<Float> = renderer.pointOfView?.simdWorldPosition ?? SIMD3<Float>(0, 0, 10)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        lock.lock()
        step(Float(raw), camera: eye)
        lock.unlock()
        SCNTransaction.commit()
    }

    /// Moves everything on by `rawStep` seconds. `camera` is the camera's
    /// position in the scene, for deciding which labels to show. Called with
    /// the lock held.
    private func step(_ rawStep: Float, camera: SIMD3<Float>) {
        frame += 1
        if linesDirty {
            linesDirty = false
            rebuildLineElement()
            updateLines()
        }
        // the labels follow the camera even when the notes are still
        if frame % 3 == 0 { updateLabels(camera: camera) }
        if resting && grabbed == nil { return }

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
        updateLines()

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

    private func rebuildLineElement() {
        var indices: [Int32] = []
        indices.reserveCapacity(shownEdges.count * 2)
        var next: Int32 = 0
        for _ in shownEdges {
            indices.append(next)
            indices.append(next + 1)
            next += 2
        }
        lineElement = indices.isEmpty ? nil : SCNGeometryElement(indices: indices, primitiveType: .line)
    }

    /// Redraws every shown link between where its two notes are now. All the
    /// links are one geometry, so this is one draw however many there are.
    private func updateLines() {
        guard let element = lineElement, !shownEdges.isEmpty else {
            lines.geometry = nil
            return
        }
        vertexBuffer.removeAll(keepingCapacity: true)
        for e in shownEdges {
            let a: SIMD3<Float> = position[edges[e].0]
            let b: SIMD3<Float> = position[edges[e].1]
            vertexBuffer.append(SCNVector3(x: a.x, y: a.y, z: a.z))
            vertexBuffer.append(SCNVector3(x: b.x, y: b.y, z: b.z))
        }
        let source = SCNGeometrySource(vertices: vertexBuffer)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.materials = [lineMaterial]
        lines.geometry = geometry
    }

    // MARK: labels

    /// Shows the titles of the few notes nearest the camera, fading out with
    /// distance, plus the selected note's. Coming closer brings more into
    /// reach; far away, none show and the space is just points and threads.
    private func updateLabels(camera: SIMD3<Float>) {
        let eye: SIMD3<Float> = world.simdConvertPosition(camera, from: nil)
        var near: [(Int, Float)] = []
        for i in nodes.indices where visible[i] {
            let d: Float = simd_distance(position[i], eye)
            if d < labelReach { near.append((i, d)) }
        }
        near.sort { $0.1 < $1.1 }
        var target = [Float](repeating: 0, count: nodes.count)
        let fullAt: Float = labelReach * 0.6
        let band: Float = max(labelReach - fullAt, 0.001)
        for entry in near.prefix(labelBudget) {
            let into: Float = (labelReach - entry.1) / band
            target[entry.0] = min(max(into, 0), 1)
        }
        if let chosen = selected, chosen < target.count, visible[chosen] { target[chosen] = 1 }

        for i in nodes.indices {
            let now: Float = labelOpacity[i]
            let goal: Float = target[i]
            let shownNow: Bool = !labels[i].isHidden
            if abs(goal - now) < 0.01 && (goal > 0) == shownNow { continue }
            let eased: Float = lively ? now + (goal - now) * 0.35 : goal
            let settled: Float = abs(goal - eased) < 0.02 ? goal : eased
            labelOpacity[i] = settled
            labels[i].opacity = CGFloat(settled)
            labels[i].isHidden = settled <= 0
        }
    }
}
