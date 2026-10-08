import Foundation

// MARK: - The Neurons theme's colours, cell states and bokeh
//
// The owner's Neurons target (docs/design/targets-2026-10-01.md, section 3):
// bioluminescent green, pink, cyan and amber on deep blue with bokeh; each
// soma translucent and glowing with a purple and magenta interior; and, as
// the space's bodies have their styles, cells shown in six states - each
// its own biological process, with its own look and movement:
//
//   resting    (the rocky planet's mirror) calm, slowly breathing
//   firing     (the sun's)       a burst of spikes: flickering, rays of
//                                calcium waves, a ring spreading at each spike
//   releasing  (the gas giant's) a cloud of transmitter in slow swirling
//                                bands, vesicles drifting out - volume
//                                transmission, spreading as a gas does
//   pacemaker  (the pulsar's)    a steady beat, twice a turn of two sweeping
//                                lobes, a ring wave each beat, its bipolar
//                                dendrites turning
//   migrating  (the comet's)     a leading process with its growth cone, a
//                                trailing one, the nucleus stepping forward
//                                (nucleokinesis)
//   engulfing  (the black hole's) a phagocyte: debris spiralling into a dark
//                                phagosome ringed with light
//
// Natural states follow biology where a role is one of them: a receptor
// (the space's comet) migrates in along its leading process, a drifting
// free cell (a microglial cell) engulfs; everything else rests. The Look
// menu sets one state for every note, or one per cell (NeuronStateChoice),
// as the space's looks do.
//
// Foundation only: tested on Linux (Tests/NeuronLookTests).

nonisolated enum NeuronPalette {
    /// The cells' membrane dyes in turn (sRGB, as on screen): green,
    /// cyan, pink, amber, violet - each with its accent, which the ideas
    /// inside lean towards, so even two cells show all four colours.
    static let dyes: [(main: SIMD3<Float>, accent: SIMD3<Float>)] = [
        (SIMD3<Float>(0.35, 1.0, 0.5), SIMD3<Float>(1.0, 0.74, 0.28)),
        (SIMD3<Float>(0.25, 0.92, 1.0), SIMD3<Float>(1.0, 0.42, 0.78)),
        (SIMD3<Float>(1.0, 0.42, 0.78), SIMD3<Float>(0.25, 0.92, 1.0)),
        (SIMD3<Float>(1.0, 0.74, 0.28), SIMD3<Float>(0.35, 1.0, 0.5)),
        (SIMD3<Float>(0.66, 0.5, 1.0), SIMD3<Float>(0.25, 0.92, 1.0))
    ]
    /// A receptor's gold, a drifting free cell's pale ice.
    static let receptor = SIMD3<Float>(1.0, 0.84, 0.48)
    static let drifter = SIMD3<Float>(0.62, 0.8, 0.98)
    /// The soma's interior: purple, deepening to magenta at its heart; the
    /// nucleus a violet-magenta, its nucleolus brighter.
    static let interior = SIMD3<Float>(0.58, 0.24, 0.98)
    static let heart = SIMD3<Float>(0.98, 0.28, 0.72)
    static let nucleus = SIMD3<Float>(0.82, 0.36, 1.0)
    static let nucleolus = SIMD3<Float>(1.0, 0.5, 0.88)
    /// Impulses: amber, in a magenta-pink halo.
    static let impulse = SIMD3<Float>(1.0, 0.72, 0.30)
    static let impulseHalo = SIMD3<Float>(1.0, 0.32, 0.80)
    /// The fluid behind everything: deep blue.
    static let deep = SIMD3<Float>(0.012, 0.03, 0.09)

    /// How far an idea leans to its cell's accent.
    static let ideaLean: Float = 0.45

    /// A dye slot's membrane colour: 0...4 the cells' (round again past
    /// five), 5 a receptor's, 6 a drifter's; `idea` leans to the accent.
    static func dye(slot: Int, idea: Bool = false) -> SIMD3<Float> {
        if slot == 5 { return receptor }
        if slot == 6 { return drifter }
        let pair = dyes[max(slot, 0) % dyes.count]
        guard idea else { return pair.main }
        return pair.main + (pair.accent - pair.main) * ideaLean
    }
}

/// A cell's state: one biological process each, mirroring one space style.
nonisolated enum NeuronState: String, CaseIterable, Sendable, Identifiable {
    case resting
    case firing
    case releasing
    case pacemaker
    case migrating
    case engulfing

    var id: String { rawValue }

    /// The shaders' number for it (rpState).
    var code: Int {
        switch self {
        case .resting: return 0
        case .firing: return 1
        case .releasing: return 2
        case .pacemaker: return 3
        case .migrating: return 4
        case .engulfing: return 5
        }
    }

    /// The space style it mirrors.
    var style: GraphNodeStyle {
        switch self {
        case .resting: return .rocky
        case .firing: return .sun
        case .releasing: return .gasGiant
        case .pacemaker: return .pulsar
        case .migrating: return .comet
        case .engulfing: return .blackHole
        }
    }

    /// The state that mirrors a space style.
    static func of(_ style: GraphNodeStyle) -> NeuronState {
        switch style {
        case .rocky: return .resting
        case .sun: return .firing
        case .gasGiant: return .releasing
        case .pulsar: return .pacemaker
        case .comet: return .migrating
        case .blackHole: return .engulfing
        }
    }

    var title: String {
        switch self {
        case .resting: return "Resting"
        case .firing: return "Firing"
        case .releasing: return "Releasing"
        case .pacemaker: return "Pacemaker"
        case .migrating: return "Migrating"
        case .engulfing: return "Engulfing"
        }
    }

    /// What it shows, in a line (the legend and VoiceOver).
    var process: String {
        switch self {
        case .resting: return "at rest, slowly breathing"
        case .firing: return "a burst of spikes, calcium waves spreading"
        case .releasing: return "a cloud of transmitter drifting out"
        case .pacemaker: return "a steady beat, its lobes sweeping round"
        case .migrating: return "crawling on, its growth cone leading"
        case .engulfing: return "drawing debris into a dark phagosome"
        }
    }

    /// The Look menu's symbol: the mirrored style's.
    var symbol: String {
        switch self {
        case .resting: return "globe.europe.africa.fill"
        case .firing: return "sun.max.fill"
        case .releasing: return "circle.lefthalf.filled"
        case .pacemaker: return "dot.radiowaves.left.and.right"
        case .migrating: return "sparkle"
        case .engulfing: return "circle.circle.fill"
        }
    }

    /// The Look menu's order: the space styles' (GraphNodeStyle.menuOrder).
    static var menuOrder: [NeuronState] {
        GraphNodeStyle.menuOrder.map { NeuronState.of($0) }
    }

    /// A role's state when nothing is chosen: biology's, where a role is
    /// one - a receptor migrating in, a drifter (a microglial cell)
    /// engulfing - and rest everywhere else.
    static func natural(_ role: NeuronRole) -> NeuronState {
        switch role {
        case .receptor: return .migrating
        case .drifter: return .engulfing
        default: return .resting
        }
    }

    /// How long a pacemaker takes to turn once: the pulsar's period, so the
    /// two beat alike (twice a turn).
    static var beatPeriod: Float { SpaceOptics.pulsarPeriod }
}

/// What the owner chose in the Look menu for the Neurons: one state for
/// every note (or natural), and one per cell (top-level folder), which
/// wins for the notes inside it. Containers - cells and their parts -
/// keep their own look. Stored as two strings, as the space's looks are.
nonisolated struct NeuronStateChoice: Sendable, Equatable {
    /// "natural", or a state's raw value.
    var main: String = NeuronStateChoice.naturalValue
    var folders: [UUID: NeuronState] = [:]

    static let natural = NeuronStateChoice()
    static let key: String = "vignette.neurons.cellState"
    static let foldersKey: String = "vignette.neurons.cellStateFolders"
    static let naturalValue: String = "natural"

    init(main: String = NeuronStateChoice.naturalValue, folders: [UUID: NeuronState] = [:]) {
        self.main = main
        self.folders = folders
    }

    /// From the stored strings.
    init(main: String, folderRaw: String) {
        self.main = main
        self.folders = Self.parse(folderRaw)
    }

    /// "uuid=state;uuid=state" to a map; anything unreadable is skipped.
    static func parse(_ raw: String) -> [UUID: NeuronState] {
        var found: [UUID: NeuronState] = [:]
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: "=")
            guard pieces.count == 2, let id = UUID(uuidString: String(pieces[0])),
                  let state = NeuronState(rawValue: String(pieces[1])) else { continue }
            found[id] = state
        }
        return found
    }

    static func encode(_ map: [UUID: NeuronState]) -> String {
        let keys: [UUID] = map.keys.sorted { $0.uuidString < $1.uuidString }
        var parts: [String] = []
        for id in keys {
            guard let state = map[id] else { continue }
            parts.append(id.uuidString + "=" + state.rawValue)
        }
        return parts.joined(separator: ";")
    }

    /// Whether anything is chosen (the Look button shows it).
    var isCustom: Bool {
        main != Self.naturalValue || !folders.isEmpty
    }

    /// The state body `i` of `plan` shows: its cell's state, else the one
    /// for all, else its role's natural state; a container rests.
    func state(of i: Int, in plan: ThemePlan) -> NeuronState {
        guard i >= 0, i < plan.bodies.count else { return .resting }
        let body: ThemeBody = plan.bodies[i]
        guard body.kind == .note else { return .resting }
        if body.region >= 0, body.region < plan.bodies.count, let chosen = folders[plan.bodies[body.region].id] {
            return chosen
        }
        if let all = NeuronState(rawValue: main) { return all }
        return NeuronState.natural(NeuronRole(rawValue: body.role) ?? .granule)
    }
}

/// One out-of-focus glow on the Neurons' backdrop: where it is on the sky
/// (unit), how big (radians), its colour (sRGB) and how bright.
nonisolated struct NeuronBokehDisc: Sendable, Equatable {
    let direction: SIMD3<Float>
    let size: Float
    let colour: SIMD3<Float>
    let strength: Float
}

/// The backdrop's bokeh: soft discs of the palette's colours scattered over
/// the deep blue, most small and bright, a few large and faint - as light
/// out of focus behind a microscope's plane. The same every time.
nonisolated enum NeuronBokeh {
    static let count: Int = 84

    static func discs(count n: Int = NeuronBokeh.count) -> [NeuronBokehDisc] {
        var random = UniverseRandom(0xB0E4)
        var out: [NeuronBokehDisc] = []
        out.reserveCapacity(n)
        let tones: [SIMD3<Float>] = NeuronPalette.dyes.prefix(4).map { $0.main }
            + [SIMD3<Float>(0.3, 0.45, 1.0)]
        for k in 0..<n {
            let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, n))
            let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
            let v: SIMD3<Float> = d + jitter * 0.22
            let length: Float = (v * v).sum().squareRoot()
            let dir: SIMD3<Float> = length > 0.0001 ? v / length : d
            let u: Float = Float(random.unit())
            let size: Float = 0.018 + 0.1 * u * u
            // big ones fainter, as a defocused light spreads thinner
            let strength: Float = (0.35 + 0.65 * Float(random.unit())) * (1 - 0.6 * (size - 0.018) / 0.1)
            let colour: SIMD3<Float> = tones[k % tones.count]
            out.append(NeuronBokehDisc(direction: dir, size: size, colour: colour, strength: strength))
        }
        return out
    }
}

/// One out-of-focus orb floating in the fluid round the map (the owner's
/// board: heavy bokeh in front of the cells and behind them): where, from
/// the map's middle, in map reaches; how wide, likewise; its colour (sRGB)
/// and how bright.
nonisolated struct NeuronOrb: Sendable, Equatable {
    let at: SIMD3<Float>
    let size: Float
    let colour: SIMD3<Float>
    let strength: Float
}

extension NeuronBokeh {
    static let orbCount: Int = 28
    /// The nearest an orb comes towards the camera, in map reaches: it
    /// never sits on the lens.
    static let orbFront: Float = 0.9

    /// Orbs all round the map, a shell from 0.7 to 1.4 of its reach, half
    /// of them nearer the camera than the map's middle; most small, the
    /// big ones fainter. The same every time.
    static func orbs(count n: Int = NeuronBokeh.orbCount) -> [NeuronOrb] {
        var random = UniverseRandom(0x0B5)
        var out: [NeuronOrb] = []
        out.reserveCapacity(n)
        let tones: [SIMD3<Float>] = NeuronPalette.dyes.prefix(4).map { $0.main }
            + [SIMD3<Float>(0.3, 0.45, 1.0)]
        for k in 0..<n {
            let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, n))
            let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
            let v: SIMD3<Float> = d + jitter * 0.3
            let length: Float = (v * v).sum().squareRoot()
            let dir: SIMD3<Float> = length > 0.0001 ? v / length : d
            var at: SIMD3<Float> = dir * (0.7 + 0.7 * Float(random.unit()))
            at.z = min(at.z, orbFront)
            let u: Float = Float(random.unit())
            let size: Float = 0.05 + 0.12 * u * u * u
            let strength: Float = (0.16 + 0.2 * Float(random.unit())) * (1 - 0.5 * (size - 0.05) / 0.12)
            out.append(NeuronOrb(at: at, size: size, colour: tones[(k * 3) % tones.count], strength: strength))
        }
        return out
    }
}
