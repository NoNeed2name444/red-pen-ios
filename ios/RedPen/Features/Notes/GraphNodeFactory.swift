import SceneKit
import UIKit
import simd

/// One note's pieces, as GraphStyleKit made them; GraphSceneBuilder adds
/// the name label and hands the rest to GraphSim.
@MainActor
struct GraphStyledParts {
    let node: SCNNode
    let ringStretch: SCNNode
    let ringLeaf: SCNNode
    let ringGeometry: SCNGeometry
    let hotRing: SCNGeometry?
    let diskLeaf: SCNNode
    let diskGeometry: SCNGeometry?
    let hotDisk: SCNGeometry?
    /// The radius links are trimmed to and rings fitted to.
    let radius: Float
    let spin: Float
    let spinRate: Float
    /// How much the glow swells when the note moves (the sun's corona).
    let swell: Float
    /// How far the ring stretches along the motion, over the black hole's.
    let stretchGain: Float
}

/// How the Universe dresses a body (GraphUniverse); .plain is the graph
/// look, unchanged.
nonisolated enum GraphBodyLook: Equatable, Sendable {
    case plain
    /// A top-level folder's black hole; a dormant one has no disk.
    case galaxy(empty: Bool)
    /// A folder's star in its tier's colour; a dark star has no corona.
    case star(tier: Int, dark: Bool)
    /// No decorative moon; a gas giant's ring only for a long read.
    case planet(ringed: Bool)
    /// A real note as a moon: the grey mottled sphere and a faint glow.
    case moon
    /// An Oort comet rests with no tail.
    case comet(active: Bool)
}

/// Where a body's lit materials take their light from.
nonisolated enum GraphLight: Equatable, Sendable {
    /// The graph look: the four busiest suns, shared.
    case shared
    /// Never a sun: the key light only.
    case key
    /// Its owner star or black hole (a body index).
    case fixed(Int)
    /// Its own materials, lit each frame by the nearest light (a comet;
    /// the body's own index).
    case nearest(Int)
}

/// Builds every note in its style, sharing geometry and materials: one
/// unit sphere and one unit plane per material, one material per style
/// (and per folder where the folder tints or picks a palette), never one
/// per note. Collects the materials whose shaders read the clock or the
/// suns, and each note's pieces for GraphStyleAnimator.
///
/// Every note is built the same way:
///
///     note (named "note:<id>", no geometry; GraphSim moves and scales it)
///       tilt (the note's own frame: its disk, ring or spin axis is z)
///         disk (a flat plane: black hole's disk, gas giant's ring, or empty)
///         body (the sphere, category 1 - what a tap hits)
///       ring holder (billboarded) > stretch > ring (the glow in front)
///       moon, beams or tail (rocky planet, pulsar, comet)
///       label (added by the builder)
///
/// A style whose shaders failed GraphStyleProbe is still built, from plain
/// pieces: the old black-hole materials, flat bodies and soft glows.
@MainActor
final class GraphStyleKit {
    private let store: NoteStore
    private let shaders: GraphShaderSupport
    private let support: GraphStyleSupport
    private let lively: Bool
    private let detail: Float
    private(set) var clocked: [SCNMaterial] = []
    private(set) var lit: [SCNMaterial] = []
    private(set) var rigs: [GraphStyleRig] = []
    /// Lit materials with a fixed owner (a planet's star), and a comet's
    /// own, lit by the nearest light (the Universe; GraphStyleAnimator).
    private(set) var owned: [(SCNMaterial, Int)] = []
    private(set) var nearest: [(SCNMaterial, Int)] = []
    private var cache: [String: SCNGeometry] = [:]
    /// Each folder's tone where the caller knows better than the store's
    /// top-level walk (the Universe: its planned galaxy's tone).
    var tones: [UUID: UIColor] = [:]
    /// Where the body being made takes its light from, and its key ending.
    private var lightNow: GraphLight = .shared
    private var lightKey: String = ""

    init(store: NoteStore, shaders: GraphShaderSupport, support: GraphStyleSupport,
         lively: Bool, detail: Float) {
        self.store = store
        self.shaders = shaders
        self.support = support
        self.lively = lively
        self.detail = detail
    }

    // MARK: a note

    /// A note in the graph look: every piece as it has always been.
    func make(note: Note, style: GraphNodeStyle, radius r: Float,
              random: inout SplitMix64) -> GraphStyledParts {
        let palette: Int = GraphStyleChoice.palette(for: note.folderId)
        return make(name: "note:\(note.id.uuidString)", folder: note.folderId, style: style, radius: r,
                    random: &random, look: .plain, light: .shared, palette: palette)
    }

    /// Any body: a note, a folder's star or black hole, or the home star.
    /// `look` is how the Universe dresses it (.plain: the graph look);
    /// `light` where its lit materials take their light from; `palette`
    /// its planets' family (GraphStyleArt).
    func make(name: String, folder: UUID?, style: GraphNodeStyle, radius r: Float,
              random: inout SplitMix64, look: GraphBodyLook, light: GraphLight,
              palette: Int) -> GraphStyledParts {
        lightNow = light
        lightKey = Self.suffix(light)
        let node = SCNNode()
        node.name = name
        let seed: Float = random.unit()

        // the note's frame: tilted so a disk is seen a little from above,
        // each note a little differently
        let tilt = SCNNode()
        let lean: Float = 0.26 + random.unit() * 0.14
        let roll: Float = random.unit() * 0.3
        let yaw: Float = random.unit() * Float.pi
        let flat = simd_quatf(angle: lean - Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let rolled = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
        let turned = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let base: simd_quatf = turned * rolled * flat
        tilt.simdOrientation = base
        node.addChildNode(tilt)

        let bodyRadius: Float = r * Self.bodyScale(style)
        let body = SCNNode(geometry: bodyGeometry(style, palette: palette, look: look))
        body.categoryBitMask = 1
        body.simdScale = SIMD3<Float>(bodyRadius, bodyRadius, bodyRadius)
        let bodyTurn = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        body.simdOrientation = bodyTurn
        tilt.addChildNode(body)

        // the disk slot: a black hole's disk (none when dormant), a gas
        // giant's ring (in the Universe only from 250 words)
        let disk = SCNNode()
        let hasDisk: Bool = Self.hasDisk(style, look: look)
        let diskGeometry: SCNGeometry? = hasDisk ? diskGeometry(style, folder: folder, palette: palette) : nil
        let hotDisk: SCNGeometry? = style == .blackHole && hasDisk ? hotHole().disk : nil
        disk.geometry = diskGeometry
        var diskSide: Float = 0
        if style == .blackHole && hasDisk { diskSide = r * GraphShape.diskRadius * 2 }
        if style == .gasGiant && hasDisk { diskSide = bodyRadius * 4.8 }
        let startSpin: Float = random.unit() * Float.pi
        disk.simdEulerAngles = SIMD3<Float>(0, 0, startSpin)
        if diskSide > 0 { disk.simdScale = SIMD3<Float>(diskSide, diskSide, diskSide) }
        disk.renderingOrder = 4
        disk.categoryBitMask = 2
        tilt.addChildNode(disk)

        // the glow in front: lifted towards the camera more than the body's
        // radius, so no part of the body is ever in front of it
        let reachRadius: Float = Self.linkRadius(style, r: r, body: bodyRadius)
        let holder = SCNNode()
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        holder.constraints = [billboard]
        let stretch = SCNNode()
        let lift: Float = reachRadius * GraphShape.ringLift
        stretch.simdPosition = SIMD3<Float>(0, 0, lift)
        stretch.opacity = 0.85
        let ringGeometry: SCNGeometry = ringGeometry(style, folder: folder, palette: palette, look: look)
        let ring = SCNNode(geometry: ringGeometry)
        var ringSide: Float = Self.ringSide(style, r: r, body: bodyRadius)
        if look == .moon { ringSide = bodyRadius * 2.4 }
        ring.simdScale = SIMD3<Float>(ringSide, ringSide, 1)
        ring.renderingOrder = 6
        ring.categoryBitMask = 2
        stretch.addChildNode(ring)
        holder.addChildNode(stretch)
        node.addChildNode(holder)
        // a dark star has no corona
        if case .star(_, let dark) = look, dark { stretch.isHidden = true }

        var haze: [SCNNode] = [holder, disk]
        var moon: SCNNode?
        var beam: SCNNode?
        var tail: SCNNode?
        var extra = SIMD2<Float>(0, 0)
        switch style {
        case .rocky where look == .plain:
            // the graph look's decorative moon; in the Universe every moon
            // on screen is a real note
            let made = SCNNode(geometry: moonGeometry())
            let size: Float = bodyRadius * 0.27
            made.simdScale = SIMD3<Float>(size, size, size)
            made.categoryBitMask = 2
            node.addChildNode(made)
            moon = made
        case .pulsar:
            let made = SCNNode(geometry: plane("pulsarBeam", source: GraphStyleShaders.pulsarBeam,
                                               fallback: GraphStyleArt.streak, tint: nil))
            made.renderingOrder = 6
            made.categoryBitMask = 2
            node.addChildNode(made)
            beam = made
            haze.append(made)
            extra = SIMD2<Float>(r * 0.9, r * 6)
        case .comet:
            // an Oort comet rests with no tail: none is made, so the
            // animator never swings a hidden one
            if case .comet(let active) = look, !active { break }
            let made = SCNNode(geometry: plane("cometTail", source: GraphStyleShaders.cometTail,
                                               fallback: GraphStyleArt.streak, tint: nil))
            made.renderingOrder = 3
            made.categoryBitMask = 2
            node.addChildNode(made)
            tail = made
            haze.append(made)
            extra = SIMD2<Float>(r * 2, r * 7)
        default:
            break
        }

        let rig = GraphStyleRig(style: style, tilt: tilt, base: base, body: body,
                                bodyRadius: bodyRadius, bodyFlat: style == .gasGiant ? 0.94 : 1,
                                bodySpin: Self.bodySpin(style), bodyTurn: bodyTurn,
                                diskLeaf: disk, diskSide: diskSide, ringLeaf: ring, ringSide: ringSide,
                                moon: moon, moonOrbit: bodyRadius * 2.3, beam: beam, extraSize: extra,
                                tail: tail, seed: seed, haze: haze, reach: r)
        rigs.append(rig)

        // each disk turns once every 10 to 20 seconds at rest
        let pace: Float = 0.5 + random.unit() * 0.5
        let spinRate: Float = 0.31 + pace * 0.31
        let swell: Float = style == .sun ? 0.3 : 0
        let gain: Float = style == .blackHole ? 1 : 0.4
        let hotRing: SCNGeometry? = style == .blackHole ? hotHole().ring : nil
        lightNow = .shared
        lightKey = ""
        return GraphStyledParts(node: node, ringStretch: stretch, ringLeaf: ring,
                                ringGeometry: ringGeometry, hotRing: hotRing, diskLeaf: disk,
                                diskGeometry: diskGeometry, hotDisk: hotDisk, radius: reachRadius,
                                spin: startSpin, spinRate: spinRate, swell: swell, stretchGain: gain)
    }

    /// The clocked materials split in two: those shared by many bodies, and
    /// the Universe's copies made for one owner star or one comet, each with
    /// that body's index (GraphSim ticks these less often).
    func splitClocked() -> (shared: [SCNMaterial], owned: [(SCNMaterial, Int)]) {
        var ownerOf: [ObjectIdentifier: Int] = [:]
        for (material, body) in owned { ownerOf[ObjectIdentifier(material)] = body }
        for (material, body) in nearest { ownerOf[ObjectIdentifier(material)] = body }
        var shared: [SCNMaterial] = []
        var mine: [(SCNMaterial, Int)] = []
        for material in clocked {
            if let body = ownerOf[ObjectIdentifier(material)] {
                mine.append((material, body))
            } else {
                shared.append(material)
            }
        }
        return (shared, mine)
    }

    /// Whether a body has its disk: a black hole unless dormant, a gas giant
    /// unless the Universe keeps its ring for a long read.
    private static func hasDisk(_ style: GraphNodeStyle, look: GraphBodyLook) -> Bool {
        switch look {
        case .galaxy(let empty): return !empty && style == .blackHole
        case .planet(let ringed): return style == .gasGiant ? ringed : style == .blackHole
        default: return style == .blackHole || style == .gasGiant
        }
    }

    /// The cache-key ending for a light: materials lit by different owners
    /// are different materials.
    private static func suffix(_ light: GraphLight) -> String {
        switch light {
        case .shared: return ""
        case .key: return "-k"
        case .fixed(let owner): return "-o\(owner)"
        case .nearest(let body): return "-c\(body)"
        }
    }

    /// Registers a new lit material with whatever lights the body being made.
    private func markLit(_ material: SCNMaterial) {
        switch lightNow {
        case .shared:
            if !lit.contains(material) { lit.append(material) }
        case .key:
            break
        case .fixed(let owner):
            owned.append((material, owner))
        case .nearest(let body):
            nearest.append((material, body))
        }
    }

    /// A star's colour by tier: white (today's sun), orange, red; a dark
    /// star's ember.
    static func tierColour(_ tier: Int, dark: Bool) -> UIColor {
        if dark { return UIColor(red: 0.42, green: 0.20, blue: 0.14, alpha: 1) }
        switch tier {
        case 2: return UIColor(red: 1.0, green: 0.74, blue: 0.50, alpha: 1)
        case 3: return UIColor(red: 1.0, green: 0.52, blue: 0.36, alpha: 1)
        default: return UIColor.white
        }
    }

    // MARK: sizes

    /// The body's radius over the note's radius.
    static func bodyScale(_ style: GraphNodeStyle) -> Float {
        switch style {
        case .blackHole: return 1
        case .sun: return 1.1
        case .rocky: return 0.9
        case .gasGiant: return 1.15
        case .pulsar: return 0.3
        case .comet: return 0.3
        }
    }

    /// Where links stop and rings are fitted: the body, but never so small
    /// that a link reaches into a pulsar's or comet's core.
    static func linkRadius(_ style: GraphNodeStyle, r: Float, body: Float) -> Float {
        switch style {
        case .pulsar, .comet: return r * 0.45
        default: return body
        }
    }

    /// The glow plane's side. The shaders place the limb to match: a
    /// quarter of the half side for the sun's corona, two thirds for the
    /// air of a planet, 0.12 of it for the pulsar, 0.1875 for the comet.
    static func ringSide(_ style: GraphNodeStyle, r: Float, body: Float) -> Float {
        switch style {
        case .blackHole: return r * GraphShape.ringPlane
        case .sun: return body * 8
        case .rocky, .gasGiant: return body * 3
        case .pulsar: return r * 5
        case .comet: return r * 3.2
        }
    }

    static func bodySpin(_ style: GraphNodeStyle) -> Float {
        switch style {
        case .blackHole: return 0
        case .sun: return 0.05
        case .rocky: return 0.12
        case .gasGiant: return 0.2
        case .pulsar: return 0
        case .comet: return 0.3
        }
    }

    // MARK: geometry and materials

    private func folderKey(_ folder: UUID?) -> String {
        folder?.uuidString ?? "none"
    }

    private func bodyGeometry(_ style: GraphNodeStyle, palette: Int, look: GraphBodyLook) -> SCNGeometry {
        if look == .moon { return moonGeometry() }
        var tier: Int = 1
        var dark: Bool = false
        if case .star(let t, let d) = look {
            tier = t
            dark = d
        }
        let key: String
        switch style {
        case .rocky, .gasGiant: key = "body-\(style.rawValue)-\(palette)" + lightKey
        case .comet: key = "body-comet" + lightKey
        case .sun: key = "body-sun" + Self.tierKey(tier, dark: dark)
        default: key = "body-\(style.rawValue)"
        }
        if let made = cache[key] { return made }
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = style == .blackHole ? 28 : 36
        let material: SCNMaterial = bodyMaterial(style, palette: palette)
        if style == .sun { material.multiply.contents = Self.tierColour(tier, dark: dark) }
        sphere.materials = [material]
        cache[key] = sphere
        return sphere
    }

    /// "" for today's sun, else the tier's own key.
    private static func tierKey(_ tier: Int, dark: Bool) -> String {
        if dark { return "-dark" }
        return tier > 1 ? "-t\(tier)" : ""
    }

    private func bodyMaterial(_ style: GraphNodeStyle, palette: Int) -> SCNMaterial {
        if style == .blackHole { return GraphLook.hole() }
        let material = Self.opaque(Self.flatColour(style))
        let pick: (String, String) = Self.bodyShader(style)
        let name: String = pick.0
        let source: String = pick.1
        guard support.has(name) else { return material }
        attach(material, source)
        if style == .rocky { tints(material, GraphStyleArt.rockPalette(palette)) }
        if style == .gasGiant { tints(material, GraphStyleArt.gasPalette(palette)) }
        if style == .rocky || style == .gasGiant || style == .comet { markLit(material) }
        return material
    }

    private static func bodyShader(_ style: GraphNodeStyle) -> (String, String) {
        switch style {
        case .sun: return ("sunBody", GraphStyleShaders.sunBody)
        case .rocky: return ("rockBody", GraphStyleShaders.rockBody)
        case .gasGiant: return ("gasBody", GraphStyleShaders.gasBody)
        case .pulsar: return ("pulsarCore", GraphStyleShaders.pulsarCore)
        default: return ("cometNucleus", GraphStyleShaders.cometNucleus)
        }
    }

    private func moonGeometry() -> SCNGeometry {
        let key: String = "moon" + lightKey
        if let made = cache[key] { return made }
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 16
        let material = Self.opaque(UIColor(white: 0.55, alpha: 1))
        if support.has("moonBody") {
            attach(material, GraphStyleShaders.moonBody)
            markLit(material)
        }
        sphere.materials = [material]
        cache[key] = sphere
        return sphere
    }

    private func diskGeometry(_ style: GraphNodeStyle, folder: UUID?, palette: Int) -> SCNGeometry? {
        switch style {
        case .blackHole: return holeLook(folder).disk
        case .gasGiant:
            let cream = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
            let key: String = "gasRing" + lightKey
            let fresh: Bool = cache[key] == nil
            let made: SCNGeometry = plane(key, source: GraphStyleShaders.gasRing,
                                          fallback: GraphStyleArt.band, tint: cream)
            if fresh, support.has("gasRing"), let material = made.firstMaterial { markLit(material) }
            return made
        default: return nil
        }
    }

    private func ringGeometry(_ style: GraphNodeStyle, folder: UUID?, palette: Int,
                              look: GraphBodyLook) -> SCNGeometry {
        if look == .moon { return moonGlow() }
        switch style {
        case .blackHole:
            return holeLook(folder).ring
        case .sun:
            var tier: Int = 1
            var dark: Bool = false
            if case .star(let t, let d) = look {
                tier = t
                dark = d
            }
            return corona(tier: tier, dark: dark)
        case .rocky, .gasGiant:
            let air: SIMD3<Float> = style == .rocky ? SIMD3<Float>(0.38, 0.64, 1.0)
                : GraphStyleArt.gasGlow(palette)
            let key: String = "halo-\(style.rawValue)-\(palette)" + lightKey
            if let made = cache[key] { return made }
            let tint = UIColor(red: CGFloat(air.x), green: CGFloat(air.y), blue: CGFloat(air.z), alpha: 1)
            let material = Self.glow(GraphStyleArt.glow)
            material.multiply.contents = tint
            if support.has("halo") {
                material.multiply.contents = UIColor.white
                attach(material, GraphStyleShaders.halo)
                let v = SCNVector3(x: air.x, y: air.y, z: air.z)
                material.setValue(NSValue(scnVector3: v), forKey: "rpTintA")
                markLit(material)
            }
            let made = Self.unitPlane(material)
            cache[key] = made
            return made
        case .pulsar:
            return plane("pulsarGlow", source: GraphStyleShaders.pulsarGlow,
                         fallback: GraphStyleArt.glow, tint: UIColor(red: 0.6, green: 0.72, blue: 1, alpha: 1))
        case .comet:
            let key: String = "cometComa" + lightKey
            let fresh: Bool = cache[key] == nil
            let made: SCNGeometry = plane(key, source: GraphStyleShaders.cometComa,
                                          fallback: GraphStyleArt.glow,
                                          tint: UIColor(red: 0.45, green: 1, blue: 0.85, alpha: 1))
            if fresh, support.has("cometComa"), let material = made.firstMaterial { markLit(material) }
            return made
        }
    }

    /// A sun's corona in its tier's colour: today's for tier 1.
    private func corona(tier: Int, dark: Bool) -> SCNGeometry {
        let warm = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1)
        let tierKey: String = Self.tierKey(tier, dark: dark)
        let key: String = "sunCorona" + tierKey
        let fresh: Bool = cache[key] == nil
        let made: SCNGeometry = plane(key, source: GraphStyleShaders.sunCorona, fallback: GraphStyleArt.glow,
                                      tint: warm, shader: "sunCorona")
        guard fresh, !tierKey.isEmpty, let material = made.firstMaterial else { return made }
        let colour: UIColor = Self.tierColour(tier, dark: dark)
        material.multiply.contents = support.has("sunCorona") ? colour : Self.mix(warm, colour)
        return made
    }

    /// A moon's faint grey glow (unlit).
    private func moonGlow() -> SCNGeometry {
        if let made = cache["moonGlow"] { return made }
        let material = Self.glow(GraphStyleArt.glow)
        material.multiply.contents = UIColor(white: 0.32, alpha: 1)
        let made = Self.unitPlane(material)
        cache["moonGlow"] = made
        return made
    }

    /// Two colours multiplied.
    private static func mix(_ a: UIColor, _ b: UIColor) -> UIColor {
        let x: SIMD3<Float> = GraphStyleArt.components(a)
        let y: SIMD3<Float> = GraphStyleArt.components(b)
        let m: SIMD3<Float> = x * y
        return UIColor(red: CGFloat(m.x), green: CGFloat(m.y), blue: CGFloat(m.z), alpha: 1)
    }

    /// A shared unit plane with a glow shader (or its baked fallback),
    /// cached as `name`; `shader` is the probe's name for it when the two
    /// differ (a copy per owner or tier).
    private func plane(_ name: String, source: String, fallback: UIImage, tint: UIColor?,
                       shader: String? = nil) -> SCNGeometry {
        if let made = cache[name] { return made }
        let material = Self.glow(fallback)
        if let tint { material.multiply.contents = tint }
        let probe: String = shader ?? Self.probeName(name)
        if support.has(probe) {
            material.multiply.contents = UIColor.white
            attach(material, source)
        }
        let made = Self.unitPlane(material)
        cache[name] = made
        return made
    }

    /// The probe's name for a cached plane: its key without an owner's or
    /// comet's ending.
    private static func probeName(_ key: String) -> String {
        guard let dash = key.firstIndex(of: "-") else { return key }
        return String(key[key.startIndex..<dash])
    }

    /// The black hole's ring and disk for a folder: the elevated shaders,
    /// or the approved older ones (GraphLook) when these did not compile.
    private func holeLook(_ folder: UUID?) -> (ring: SCNGeometry, disk: SCNGeometry) {
        let key: String = "hole-" + folderKey(folder)
        if let ring = cache[key + "-ring"], let disk = cache[key + "-disk"] { return (ring, disk) }
        let tone: UIColor = folder.flatMap { tones[$0] } ?? NoteTone.uiColor(for: folder, in: store)
        let tint: UIColor = GraphLook.tint(tone)
        let pair = holePair(tint: tint)
        cache[key + "-ring"] = pair.ring
        cache[key + "-disk"] = pair.disk
        return pair
    }

    /// The chosen black hole's pair: untinted, so brighter.
    private func hotHole() -> (ring: SCNGeometry, disk: SCNGeometry) {
        if let ring = cache["hot-ring"], let disk = cache["hot-disk"] { return (ring, disk) }
        let pair = holePair(tint: .white)
        cache["hot-ring"] = pair.ring
        cache["hot-disk"] = pair.disk
        return pair
    }

    private func holePair(tint: UIColor) -> (ring: SCNGeometry, disk: SCNGeometry) {
        let ringMaterial: SCNMaterial
        if support.has("bhRing") {
            ringMaterial = Self.glow(GraphArt.ring)
            ringMaterial.multiply.contents = tint
            attach(ringMaterial, GraphStyleShaders.bhRing)
        } else {
            ringMaterial = GraphLook.ring(tint: tint, hot: false, shader: shaders.ring, lively: lively)
            if shaders.ring { clocked.append(ringMaterial) }
        }
        let diskMaterial: SCNMaterial
        if support.has("bhDisk") {
            diskMaterial = Self.glow(GraphArt.disk)
            diskMaterial.multiply.contents = tint
            attach(diskMaterial, GraphStyleShaders.bhDisk)
        } else {
            diskMaterial = GraphLook.disk(tint: tint, hot: false, shader: shaders.disk)
        }
        return (Self.unitPlane(ringMaterial), Self.unitPlane(diskMaterial))
    }

    /// Puts a style shader on a material, sets its arguments, and has
    /// GraphSim tick its clock.
    private func attach(_ material: SCNMaterial, _ source: String) {
        material.shaderModifiers = [.surface: source]
        GraphStyleUniforms.defaults(material)
        material.setValue(NSNumber(value: lively ? 1.0 : 0.0), forKey: "rpMotion")
        material.setValue(NSNumber(value: detail), forKey: "rpDetail")
        clocked.append(material)
    }

    private func tints(_ material: SCNMaterial, _ colours: [SIMD3<Float>]) {
        let names: [String] = ["rpTintA", "rpTintB", "rpTintC", "rpTintD"]
        for (k, c) in colours.prefix(4).enumerated() {
            let v = SCNVector3(x: c.x, y: c.y, z: c.z)
            material.setValue(NSValue(scnVector3: v), forKey: names[k])
        }
    }

    // MARK: the chosen note's orbit, and the folders' wells

    /// The orbit ring round the chosen note (GraphStyleAnimator places it).
    func makeOrbit() -> SCNNode {
        let material = Self.glow(GraphArt.ring)
        material.multiply.contents = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
        if support.has("orbit") {
            material.multiply.contents = UIColor.white
            attach(material, GraphStyleShaders.orbit)
        }
        let holder = SCNNode()
        holder.name = "orbit"
        let leaf = SCNNode(geometry: Self.unitPlane(material))
        let tipped = simd_quatf(angle: 1.15, axis: SIMD3<Float>(1, 0, 0))
        let rolled = simd_quatf(angle: 0.2, axis: SIMD3<Float>(0, 0, 1))
        leaf.simdOrientation = rolled * tipped
        leaf.renderingOrder = 7
        leaf.categoryBitMask = 2
        holder.addChildNode(leaf)
        holder.categoryBitMask = 2
        return holder
    }

    /// A faint gravity well round each top-level folder with three or more
    /// notes, centred on their homes and tinted by the folder: the folders
    /// read as star systems, each in its own dip in space.
    func makeWells(homes: [UUID: SIMD3<Float>], radius: Float) -> [SCNNode] {
        guard support.has("well") else { return [] }
        var groups: [UUID: [SIMD3<Float>]] = [:]
        for note in store.notes {
            guard let root = store.rootFolder(of: note.folderId), let p = homes[note.id] else { continue }
            groups[root, default: []].append(p)
        }
        var wells: [SCNNode] = []
        let order: [UUID] = groups.keys.sorted { $0.uuidString < $1.uuidString }
        for root in order {
            guard let points = groups[root], points.count >= 3 else { continue }
            var centre = SIMD3<Float>(0, 0, 0)
            for p in points { centre += p }
            centre /= Float(points.count)
            var reach: Float = 0
            for p in points { reach = max(reach, simd_distance(p, centre)) }
            let side: Float = (reach + radius * 3) * 2.2
            let colour: UIColor = NoteTone.uiColor(for: root, in: store)
            let node: SCNNode = makeWell(colour: colour, side: side)
            node.simdPosition = centre
            wells.append(node)
        }
        return wells
    }

    /// One faint gravity well of `side`, in `colour`, billboarded. Only
    /// called when the well shader compiled.
    func makeWell(colour: UIColor, side: Float) -> SCNNode {
        let material = Self.glow(GraphStyleArt.glow)
        attach(material, GraphStyleShaders.well)
        let tone: SIMD3<Float> = GraphStyleArt.components(colour)
        let v = SCNVector3(x: tone.x, y: tone.y, z: tone.z)
        material.setValue(NSValue(scnVector3: v), forKey: "rpTintA")
        material.readsFromDepthBuffer = false
        let node = SCNNode(geometry: Self.unitPlane(material))
        node.simdScale = SIMD3<Float>(side, side, 1)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.renderingOrder = -5
        node.categoryBitMask = 2
        node.name = "well"
        return node
    }

    /// Whether the wells can be drawn.
    var hasWells: Bool { support.has("well") }

    // MARK: the links

    /// Every link's material: the style-aware beam when it compiled, the
    /// approved calm beam (GraphShaders.link) when only that did, or the
    /// baked strip. `reach`: how far an end's style reaches along a link.
    static func link(bold: Bool, old: Bool, styled: Bool, lively: Bool, reach: Float) -> SCNMaterial {
        guard styled else { return GraphLook.link(bold: bold, shader: old, lively: lively) }
        let material: SCNMaterial = GraphLook.link(bold: bold, shader: false, lively: lively)
        material.diffuse.intensity = 1
        material.shaderModifiers = [.surface: GraphStyleShaders.link]
        GraphStyleUniforms.defaults(material)
        material.setValue(NSNumber(value: lively ? 1.0 : 0.0), forKey: "rpMotion")
        material.setValue(NSNumber(value: bold ? 1.5 : 1.0), forKey: "rpEnergy")
        material.setValue(NSNumber(value: bold ? 1.0 : 0.0), forKey: "rpSolid")
        material.setValue(NSNumber(value: reach), forKey: "rpReach")
        return material
    }

    // MARK: helpers

    static func unitPlane(_ material: SCNMaterial) -> SCNGeometry {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [material]
        return plane
    }

    /// Additive, unlit, tested against depth but never writing it.
    static func glow(_ image: UIImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        return material
    }

    /// Opaque and unlit (the shaders light it), writing depth so what is
    /// behind is hidden.
    static func opaque(_ colour: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = colour
        material.transparency = 1
        material.blendMode = .replace
        return material
    }

    /// A body's plain colour, for when its shader did not compile.
    static func flatColour(_ style: GraphNodeStyle) -> UIColor {
        switch style {
        case .blackHole: return .black
        case .sun: return UIColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
        case .rocky: return UIColor(red: 0.2, green: 0.38, blue: 0.62, alpha: 1)
        case .gasGiant: return UIColor(red: 0.82, green: 0.66, blue: 0.46, alpha: 1)
        case .pulsar: return UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        case .comet: return UIColor(red: 0.3, green: 0.33, blue: 0.36, alpha: 1)
        }
    }
}

/// The styles' baked pieces: soft glows for fallbacks (and to carry
/// texture coordinates), and the planets' palettes.
nonisolated enum GraphStyleArt {
    /// A soft round glow, white.
    static let glow: UIImage = image(128) { x, y in
        let r2: Float = x * x + y * y
        let fade: Float = max(1 - r2, 0)
        return exp(-r2 * 5) * fade
    }

    /// A soft streak along y, for beams and tails.
    static let streak: UIImage = image(64) { x, y in
        let across: Float = exp(-x * x * 12)
        let along: Float = max(1 - abs(y), 0)
        return across * along
    }

    /// A soft band round the middle, for a ring.
    static let band: UIImage = image(128) { x, y in
        let r: Float = (x * x + y * y).squareRoot()
        let d: Float = (r - 0.72) / 0.18
        return exp(-d * d) * 0.8
    }

    /// An opaque grey image shaded from x and y (-1...1, y up).
    private static func image(_ size: Int, _ shade: (Float, Float) -> Float) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        let half: Float = Float(size) / 2
        for row in 0..<size {
            let y: Float = (half - Float(row) - 0.5) / half
            for col in 0..<size {
                let x: Float = (Float(col) + 0.5 - half) / half
                let value: Float = min(max(shade(x, y), 0), 1)
                let byte = UInt8(value * 255 + 0.5)
                let k: Int = (row * size + col) * 4
                bytes[k] = byte
                bytes[k + 1] = byte
                bytes[k + 2] = byte
                bytes[k + 3] = 255
            }
        }
        let data = Data(bytes)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: size * 4, space: space, bitmapInfo: info,
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }

    /// Sea, shallows, land, high ground: an Earth, a desert world, an ice
    /// world. As they show on screen (the shader takes them to linear).
    static func rockPalette(_ k: Int) -> [SIMD3<Float>] {
        switch k {
        case 1:
            return [SIMD3<Float>(0.18, 0.08, 0.05), SIMD3<Float>(0.35, 0.16, 0.08),
                    SIMD3<Float>(0.62, 0.32, 0.16), SIMD3<Float>(0.8, 0.55, 0.35)]
        case 2:
            return [SIMD3<Float>(0.1, 0.2, 0.35), SIMD3<Float>(0.3, 0.5, 0.65),
                    SIMD3<Float>(0.7, 0.8, 0.88), SIMD3<Float>(0.9, 0.93, 0.97)]
        default:
            return [SIMD3<Float>(0.02, 0.09, 0.26), SIMD3<Float>(0.05, 0.24, 0.42),
                    SIMD3<Float>(0.17, 0.30, 0.11), SIMD3<Float>(0.45, 0.36, 0.22)]
        }
    }

    /// Cream, tan, rust, poles: Jupiter, Saturn, Neptune.
    static func gasPalette(_ k: Int) -> [SIMD3<Float>] {
        switch k {
        case 1:
            return [SIMD3<Float>(0.96, 0.9, 0.72), SIMD3<Float>(0.86, 0.74, 0.5),
                    SIMD3<Float>(0.7, 0.55, 0.34), SIMD3<Float>(0.72, 0.7, 0.6)]
        case 2:
            return [SIMD3<Float>(0.62, 0.8, 0.95), SIMD3<Float>(0.3, 0.52, 0.85),
                    SIMD3<Float>(0.14, 0.28, 0.62), SIMD3<Float>(0.5, 0.62, 0.8)]
        default:
            return [SIMD3<Float>(0.93, 0.85, 0.68), SIMD3<Float>(0.78, 0.56, 0.36),
                    SIMD3<Float>(0.6, 0.33, 0.2), SIMD3<Float>(0.5, 0.56, 0.62)]
        }
    }

    /// The glow round a gas giant, by palette.
    static func gasGlow(_ k: Int) -> SIMD3<Float> {
        switch k {
        case 2: return SIMD3<Float>(0.4, 0.62, 1.0)
        default: return SIMD3<Float>(0.5, 0.4, 0.27)
        }
    }

    /// A colour's components, as they show.
    static func components(_ colour: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard colour.getRed(&r, green: &g, blue: &b, alpha: &a) else { return SIMD3<Float>(1, 1, 1) }
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }
}
