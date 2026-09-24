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
/// home. Thirty times a second this nudges each note towards its home on a
/// soft spring, while each link acts as a second spring holding its two ends
/// about as far apart as the layout put them. The result:
///
/// - every note drifts in a small slow loop of its own, so the space breathes;
/// - a note that is dragged pulls its neighbours along, and when it is let go
///   everything springs back with a little overshoot;
/// - notes pop into place when they appear or are tapped.
///
/// The work each frame is one pass over the notes and one over the links -
/// there is no every-note-against-every-note step here - so a few hundred
/// notes stay cheap. Labels are sorted only every few frames. With Reduce
/// Motion on there is no drifting, no popping and no overshoot, and nothing
/// is worked out at all while the space is still.
@MainActor
final class GraphSim {
    /// The node every note, link and bubble hangs from.
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
    private let bubbles: [(node: SCNNode, root: UUID?)]
    private let lively: Bool
    /// Past this distance from the camera a note's label is not shown.
    private let labelReach: Float

    private(set) var position: [SIMD3<Float>]
    private var velocity: [SIMD3<Float>]
    private var visible: [Bool]
    private var labelOpacity: [Float]
    private var shownEdges: [Int] = []
    private var lineElement: SCNGeometryElement?
    private var clock: Float = 0
    private var frame: Int = 0
    /// True while nothing is moving and nothing needs to; the frame's work is
    /// skipped then.
    private var resting: Bool = false

    /// The note being dragged, and where the finger wants it.
    private(set) var grabbed: Int?
    var grabTarget = SIMD3<Float>(0, 0, 0)
    /// The last note tapped or dragged; its label stays up.
    private(set) var selected: Int?

    /// Spring towards home: how hard it pulls, and how much of the motion
    /// each second it soaks up. The damping is kept low enough for a visible
    /// bounce; Reduce Motion uses critical damping instead, so nothing
    /// overshoots.
    private let stiffness: Float = 6
    private let damping: Float
    /// How hard each link holds its two ends at their resting distance.
    private let linkStiffness: Float = 4
    /// How far a note drifts from home in its slow loop.
    private let drift: Float = 0.07
    /// How many labels may show at once, besides the selected note's.
    private let labelBudget: Int = 8

    init(world: SCNNode, infos: [GraphNodeInfo], edges pairs: [(UUID, UUID)], lines: SCNNode,
         lineMaterial: SCNMaterial, bubbles: [(node: SCNNode, root: UUID?)],
         lively: Bool, labelReach: Float) {
        self.world = world
        self.lines = lines
        self.lineMaterial = lineMaterial
        self.bubbles = bubbles
        self.lively = lively
        self.labelReach = labelReach
        // critical damping is 2 * sqrt(stiffness), about 4.9
        self.damping = lively ? 2.2 : 4.9

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
            let key: Int = min(i, j) * count + max(i, j)
            guard seen.insert(key).inserted else { continue }
            edgeList.append((i, j))
            restList.append(simd_distance(homeList[i], homeList[j]))
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
        position = start
        velocity = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: infos.count)
        visible = [Bool](repeating: true, count: infos.count)
        labelOpacity = [Float](repeating: 0, count: infos.count)
        resting = !lively

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
    func pop(_ i: Int, delay: TimeInterval = 0) {
        guard i >= 0, i < nodes.count else { return }
        let node = nodes[i]
        node.removeAction(forKey: "pop")
        guard lively else {
            node.scale = SCNVector3(x: 1, y: 1, z: 1)
            return
        }
        let up = SCNAction.scale(to: 1.25, duration: 0.14)
        up.timingMode = .easeOut
        let down = SCNAction.scale(to: 0.95, duration: 0.12)
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
        selected = i
        pop(i)
        resting = false
    }

    // MARK: dragging

    func grab(_ i: Int) {
        guard i >= 0, i < nodes.count else { return }
        grabbed = i
        grabTarget = position[i]
        selected = i
        resting = false
        pop(i)
    }

    /// Lets go; the note keeps a little of the finger's speed and springs
    /// home.
    func release() {
        if let i = grabbed {
            let speed: Float = simd_length(velocity[i])
            let limit: Float = 8
            if speed > limit {
                let shrink: Float = limit / speed
                velocity[i] *= shrink
            }
            if !lively { velocity[i] = SIMD3<Float>(0, 0, 0) }
        }
        grabbed = nil
        resting = false
    }

    // MARK: showing and hiding

    /// Shows only the notes the filter lets through, the links between them,
    /// and - if wanted - the folder bubbles that still matter.
    func apply(_ filter: GraphFilter, bubbles showBubbles: Bool) {
        for i in nodes.indices {
            let shown: Bool = filter.admits(kind: kinds[i], root: roots[i], degree: degree[i])
            if shown != visible[i] {
                visible[i] = shown
                nodes[i].isHidden = !shown
                if shown { pop(i) }
            }
        }
        var kept: [Int] = []
        for (e, pair) in edges.enumerated() where visible[pair.0] && visible[pair.1] {
            kept.append(e)
        }
        shownEdges = kept
        rebuildLineElement()

        for bubble in bubbles {
            var wanted: Bool = showBubbles
            if case .folder(let id) = filter { wanted = showBubbles && bubble.root == id }
            bubble.node.isHidden = !wanted
        }
        if let chosen = selected, !visible[chosen] { selected = nil }
        updateLines()
        resting = false
    }

    // MARK: each frame

    /// Moves everything on by `rawStep` seconds. `camera` is the camera's
    /// position in the scene, for deciding which labels to show.
    func step(_ rawStep: Float, camera: SIMD3<Float>) {
        frame += 1
        // the labels follow the camera even when the notes are still
        if frame % 3 == 0 { updateLabels(camera: camera) }
        if resting && grabbed == nil { return }

        let dt: Float = min(max(rawStep, 0.001), 0.05)
        clock += dt
        let n: Int = nodes.count
        var force = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: n)

        // each note towards its home, drifting in a small loop of its own
        for i in 0..<n {
            var target: SIMD3<Float> = home[i]
            if lively {
                let t: Float = clock * 0.55 + phase[i]
                let dx: Float = sin(t) * drift
                let dy: Float = sin(t * 1.3 + 1.1) * drift
                let dz: Float = cos(t * 0.8) * drift
                target += SIMD3<Float>(dx, dy, dz)
            }
            let pull: SIMD3<Float> = (target - position[i]) * stiffness
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
            if i == grabbed {
                let moved: SIMD3<Float> = grabTarget - position[i]
                velocity[i] = moved / dt
                position[i] = grabTarget
            } else {
                velocity[i] += force[i] * dt
                let travel: SIMD3<Float> = velocity[i] * dt
                position[i] += travel
            }
            let speed: Float = simd_length_squared(velocity[i])
            fastest = max(fastest, speed)
            nodes[i].simdPosition = position[i]
        }
        updateLines()

        // still, and nothing will set it moving by itself: stop working
        if !lively && grabbed == nil && fastest < 0.000_01 { resting = true }
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
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(shownEdges.count * 2)
        for e in shownEdges {
            let a: SIMD3<Float> = position[edges[e].0]
            let b: SIMD3<Float> = position[edges[e].1]
            vertices.append(SCNVector3(x: a.x, y: a.y, z: a.z))
            vertices.append(SCNVector3(x: b.x, y: b.y, z: b.z))
        }
        let source = SCNGeometrySource(vertices: vertices)
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
            if abs(goal - now) < 0.01 && (goal > 0) == !labels[i].isHidden { continue }
            let eased: Float = lively ? now + (goal - now) * 0.35 : goal
            let settled: Float = abs(goal - eased) < 0.02 ? goal : eased
            labelOpacity[i] = settled
            labels[i].opacity = CGFloat(settled)
            labels[i].isHidden = settled <= 0
        }
    }
}
