import Foundation

// MARK: - The Neurons theme's colours, cell states and bokeh
//
// The owner's Neurons target (docs/design/targets-2026-10-01.md, section 3)
// and the close-up they circled on their board: a glass cell on deep navy,
// far blurred blue networks and gold and blue bokeh behind it; inside the
// soma a solid violet nucleus (the owner asked for a nucleus, not a light,
// at its centre), golden light hugging it; and, as the space's bodies have
// their styles, cells shown in six states - each its own biological
// process, with its own look and movement:
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
    /// The soma's interior, as in the owner's close-up: a deep violet; the
    /// nucleus's chromatin between it and the brighter heart violet, its
    /// nucleolus the violet-magenta (the soma's tint B).
    static let interior = SIMD3<Float>(0.2, 0.07, 0.46)
    static let heart = SIMD3<Float>(0.52, 0.24, 0.98)
    static let nucleus = SIMD3<Float>(0.82, 0.36, 1.0)
    static let nucleolus = SIMD3<Float>(1.0, 0.5, 0.88)
    /// Impulses: amber, in a warm orange halo.
    static let impulse = SIMD3<Float>(1.0, 0.72, 0.30)
    static let impulseHalo = SIMD3<Float>(1.0, 0.58, 0.22)
    /// The fluid behind everything: a dark teal-navy, as the darkest of
    /// the owner's close-up.
    static let deep = SIMD3<Float>(0.02, 0.05, 0.085)

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

    /// The violet a cell's glow leans to, so the light in and round it is
    /// one with its violet nucleus.
    static let glowViolet = SIMD3<Float>(0.78, 0.34, 0.95)

    /// A dye slot's glow: a cell's dye halfway to the violet; a receptor's
    /// and a drifter's keep their own colour.
    static func glow(slot: Int, idea: Bool = false) -> SIMD3<Float> {
        let own: SIMD3<Float> = dye(slot: slot, idea: idea)
        if slot == 5 || slot == 6 { return own }
        return own * 0.5 + glowViolet * 0.5
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

/// The backdrop's bokeh: soft gold and blue discs (the owner's close-up)
/// scattered over the deep navy, most small and bright, a few large and
/// faint - as light out of focus behind a microscope's plane. The same
/// every time.
nonisolated enum NeuronBokeh {
    static let count: Int = 84
    /// The bokeh's colours (sRGB): golds and blues, as in the close-up.
    static let tones: [SIMD3<Float>] = [
        SIMD3<Float>(1.0, 0.74, 0.36),
        SIMD3<Float>(0.3, 0.5, 1.0),
        SIMD3<Float>(1.0, 0.6, 0.25),
        SIMD3<Float>(0.35, 0.8, 1.0),
        SIMD3<Float>(0.6, 0.45, 1.0)
    ]

    static func discs(count n: Int = NeuronBokeh.count) -> [NeuronBokehDisc] {
        var random = UniverseRandom(0xB0E4)
        var out: [NeuronBokehDisc] = []
        out.reserveCapacity(n)
        let tones: [SIMD3<Float>] = NeuronBokeh.tones
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

/// One far, out-of-focus neuron on the Neurons' backdrop (the owner's
/// close-up: blurred blue networks far behind the cell): where it is on
/// the sky (unit), how big (radians), how it is turned (radians), its
/// colour (sRGB) and how bright.
nonisolated struct NeuronFarCell: Sendable, Equatable {
    let direction: SIMD3<Float>
    let size: Float
    let turn: Float
    let colour: SIMD3<Float>
    let strength: Float
}

extension NeuronBokeh {
    static let farCount: Int = 28

    /// The far neurons spread over the whole sky, blue, cyan and violet,
    /// each turned its own way; the big ones fainter, as nearer the
    /// microscope's blur. The same every time.
    static func farCells(count n: Int = NeuronBokeh.farCount) -> [NeuronFarCell] {
        var random = UniverseRandom(0xFA2C)
        var out: [NeuronFarCell] = []
        out.reserveCapacity(n)
        let tones: [SIMD3<Float>] = [
            SIMD3<Float>(0.3, 0.5, 1.0),
            SIMD3<Float>(0.25, 0.75, 1.0),
            SIMD3<Float>(0.5, 0.4, 1.0)
        ]
        for k in 0..<n {
            let d: SIMD3<Float> = GraphUniverse.float3(ThemeLayout.fibonacci(k, n))
            let jitter = SIMD3<Float>(Float(random.signed()), Float(random.signed()), Float(random.signed()))
            let v: SIMD3<Float> = d + jitter * 0.25
            let length: Float = (v * v).sum().squareRoot()
            let dir: SIMD3<Float> = length > 0.0001 ? v / length : d
            let u: Float = Float(random.unit())
            let size: Float = 0.12 + 0.16 * u
            let turn: Float = Float(random.unit()) * 2 * Float.pi
            let strength: Float = (0.5 + 0.5 * Float(random.unit())) * (1 - 0.4 * u)
            out.append(NeuronFarCell(direction: dir, size: size, turn: turn, colour: tones[k % tones.count], strength: strength))
        }
        return out
    }
}
