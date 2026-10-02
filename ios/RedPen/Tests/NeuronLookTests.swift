// The Neurons theme's look, as far as it is numbers (GraphNeuronStates):
//
// - the palette: bioluminescent green, cyan, pink and amber dyes on a deep
//   blue, every colour on screen's scale; an idea's cell leans to its
//   region's accent, so two regions already show all four colours; the
//   soma's interior purple deepening to magenta;
// - the cell states: six, one for each space style and back again, each its
//   own shader number; the Look menu in the space styles' order; natural
//   states follow biology (a commissural cell beats, a receptor migrates,
//   a microglial cell engulfs, the rest rest); a pacemaker beats with the
//   pulsar's period;
// - the choice: one state for every note, one per region winning over it,
//   containers always resting, stored strings read back the same and
//   anything unreadable skipped;
// - the bokeh: always the same discs, on the unit sphere, in the
//   palette's colours, the big ones fainter;
// - the shaders say the same: the soma and halo read rpState and its
//   codes, the soma's interior is the palette's.
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphNeuronImpulses.swift, GraphTheme.swift, GraphSpaceOptics.swift,
// GraphNeuronStates.swift, GraphShaderKit.swift, GraphSpaceShaders.swift and
// GraphNeuronShaders.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func fixedID(_ n: Int) -> UUID {
    let hex: String = String(format: "%012X", n)
    return UUID(uuidString: "00000000-0000-4000-8000-" + hex) ?? UUID()
}

func onScreen(_ c: SIMD3<Float>) -> Bool { c.min() >= 0 && c.max() <= 1 }

// MARK: N1 the palette

let mains: [SIMD3<Float>] = NeuronPalette.dyes.map { $0.main }
check("N1 every dye and accent on screen's scale",
      NeuronPalette.dyes.allSatisfy { onScreen($0.main) && onScreen($0.accent) })
// green, cyan, pink, amber by their channels
let green: Bool = mains.contains { $0.y > 0.9 && $0.x < 0.5 && $0.z < 0.6 }
let cyan: Bool = mains.contains { $0.y > 0.85 && $0.z > 0.9 && $0.x < 0.4 }
let pink: Bool = mains.contains { $0.x > 0.9 && $0.z > 0.6 && $0.y < 0.5 }
let amber: Bool = mains.contains { $0.x > 0.9 && $0.y > 0.6 && $0.z < 0.4 }
check("N1 green, cyan, pink and amber dyes", green && cyan && pink && amber)
let deep: SIMD3<Float> = NeuronPalette.deep
check("N1 the fluid deep blue: dark, blue the strongest", deep.z > deep.y && deep.y > deep.x && deep.max() < 0.12)
check("N1 the interior purple, the heart magenta",
      NeuronPalette.interior.z > NeuronPalette.interior.x && NeuronPalette.heart.x > NeuronPalette.heart.z
      && NeuronPalette.heart.z > NeuronPalette.heart.y)
let first: SIMD3<Float> = NeuronPalette.dye(slot: 0)
let firstIdea: SIMD3<Float> = NeuronPalette.dye(slot: 0, idea: true)
let accent: SIMD3<Float> = NeuronPalette.dyes[0].accent
check("N1 an idea's cell leans to its region's accent",
      simd_distance_f(firstIdea, accent) < simd_distance_f(first, accent) && firstIdea != first)
check("N1 slots wrap round, 5 and 6 a receptor's and a microglial cell's",
      NeuronPalette.dye(slot: 5) == NeuronPalette.receptor && NeuronPalette.dye(slot: 6) == NeuronPalette.microglia
      && NeuronPalette.dye(slot: 7) == NeuronPalette.dye(slot: 2))
// regions 0 and 1 with their ideas: all four target colours
let two: [SIMD3<Float>] = [NeuronPalette.dyes[0].main, NeuronPalette.dyes[0].accent,
                           NeuronPalette.dyes[1].main, NeuronPalette.dyes[1].accent]
let hasAll: Bool = two.contains { $0.y > 0.9 && $0.x < 0.5 } && two.contains { $0.z > 0.9 && $0.x < 0.4 }
    && two.contains { $0.x > 0.9 && $0.z > 0.6 } && two.contains { $0.x > 0.9 && $0.z < 0.4 }
check("N1 two regions' dyes and accents give all four colours", hasAll)

func simd_distance_f(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    return (d * d).sum().squareRoot()
}

// MARK: N2 the states

check("N2 six states, six codes 0...5",
      NeuronState.allCases.count == 6 && Set(NeuronState.allCases.map(\.code)) == Set(0...5))
check("N2 each mirrors one space style and back",
      NeuronState.allCases.allSatisfy { NeuronState.of($0.style) == $0 }
      && Set(NeuronState.allCases.map { $0.style.code }).count == 6)
check("N2 the menu in the space styles' order",
      NeuronState.menuOrder.map { $0.style } == GraphNodeStyle.menuOrder)
check("N2 each its own title, process and symbol",
      Set(NeuronState.allCases.map(\.title)).count == 6 && Set(NeuronState.allCases.map(\.process)).count == 6
      && Set(NeuronState.allCases.map(\.symbol)).count == 6)
check("N2 natural: commissural beats, a receptor migrates, microglia engulf, the rest rest",
      NeuronState.natural(.commissural) == .pacemaker && NeuronState.natural(.receptor) == .migrating
      && NeuronState.natural(.microglia) == .engulfing && NeuronState.natural(.pyramidal) == .resting
      && NeuronState.natural(.interneuron) == .resting && NeuronState.natural(.glia) == .resting)
check("N2 a pacemaker beats with the pulsar's period", NeuronState.beatPeriod == SpaceOptics.pulsarPeriod)

// MARK: N3 the choice

let folderA: UUID = fixedID(900)
let folderB: UUID = fixedID(901)
var notes: [UniverseNote] = []
for k in 0..<12 {
    let folder: UUID? = k < 5 ? folderA : (k < 10 ? folderB : nil)
    notes.append(UniverseNote(id: fixedID(k + 1), title: "Note \(k)", isPage: k % 3 == 0, folder: folder,
                              words: 50 + k * 40, created: Double(k)))
}
var edges: [UniverseEdge] = []
for k in 0..<11 { edges.append(UniverseEdge(a: fixedID(k + 1), b: fixedID(((k * 5) % 12) + 1))) }
let input = UniverseInput(notes: notes, folders: [UniverseFolder(id: folderA, name: "Examples", parent: nil),
                                                  UniverseFolder(id: folderB, name: "Cardiology", parent: nil)],
                          edges: edges, seedByName: true)
let plan: ThemePlan = GraphNeurons.plan(input)
let noteIndices: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind == .note }
let containers: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind != .note }
let regionA: Int = plan.bodies.firstIndex { $0.id == folderA } ?? -1

let natural = NeuronStateChoice.natural
check("N3 natural: each note its role's state",
      noteIndices.allSatisfy { i in
          natural.state(of: i, in: plan) == NeuronState.natural(NeuronRole(rawValue: plan.bodies[i].role) ?? .interneuron)
      })
let allFiring = NeuronStateChoice(main: NeuronState.firing.rawValue)
check("N3 one state for every note", !noteIndices.isEmpty
      && noteIndices.allSatisfy { allFiring.state(of: $0, in: plan) == .firing })
check("N3 containers always rest", !containers.isEmpty
      && containers.allSatisfy { allFiring.state(of: $0, in: plan) == .resting })
let mixed = NeuronStateChoice(main: NeuronState.firing.rawValue, folders: [folderA: .engulfing])
let inA: [Int] = noteIndices.filter { plan.bodies[$0].region == regionA }
let outA: [Int] = noteIndices.filter { plan.bodies[$0].region != regionA }
check("N3 a region's state wins for its cells", regionA >= 0 && !inA.isEmpty
      && inA.allSatisfy { mixed.state(of: $0, in: plan) == .engulfing }
      && outA.allSatisfy { mixed.state(of: $0, in: plan) == .firing })
check("N3 out of range: resting", mixed.state(of: -1, in: plan) == .resting
      && mixed.state(of: plan.bodies.count, in: plan) == .resting)
let raw: String = NeuronStateChoice.encode([folderA: .engulfing, folderB: .pacemaker])
let back = NeuronStateChoice(main: "migrating", folderRaw: raw)
check("N3 stored strings read back", back.folders == [folderA: .engulfing, folderB: .pacemaker]
      && back.main == "migrating" && back.isCustom)
check("N3 the stored form is stable", raw == NeuronStateChoice.encode([folderB: .pacemaker, folderA: .engulfing]))
check("N3 anything unreadable skipped",
      NeuronStateChoice.parse("junk;" + folderA.uuidString + "=nonsense;x=y;" + folderB.uuidString + "=firing")
      == [folderB: .firing])
check("N3 natural is not custom", !NeuronStateChoice.natural.isCustom
      && NeuronStateChoice(main: "natural", folderRaw: "").isCustom == false)

// MARK: N4 the bokeh

let discs: [NeuronBokehDisc] = NeuronBokeh.discs()
check("N4 the same every time", discs == NeuronBokeh.discs() && discs.count == NeuronBokeh.count)
check("N4 on the unit sphere", discs.allSatisfy { abs((($0.direction * $0.direction).sum()).squareRoot() - 1) < 0.001 })
check("N4 the palette's colours, on screen's scale", discs.allSatisfy { onScreen($0.colour) && $0.strength > 0 })
let big: [NeuronBokehDisc] = discs.filter { $0.size > 0.08 }
let small: [NeuronBokehDisc] = discs.filter { $0.size < 0.03 }
let meanBig: Float = big.map(\.strength).reduce(0, +) / Float(max(big.count, 1))
let meanSmall: Float = small.map(\.strength).reduce(0, +) / Float(max(small.count, 1))
check("N4 most small, the big ones fainter", small.count > big.count && !big.isEmpty && meanBig < meanSmall)
// spread over the sky: every octant has a disc
var octants = Set<Int>()
for d in discs {
    octants.insert((d.direction.x > 0 ? 1 : 0) + (d.direction.y > 0 ? 2 : 0) + (d.direction.z > 0 ? 4 : 0))
}
check("N4 spread all round", octants.count == 8)

// MARK: N5 the shaders say the same

check("N5 the soma and halo read the state", NeuronShaders.soma.contains("float rpState;")
      && NeuronShaders.halo.contains("float rpState;"))
check("N5 the halo draws every state's process",
      (1...5).allSatisfy { NeuronShaders.halo.contains("rpState > \(Double($0) - 0.5)") })
check("N5 the soma's interior is the palette's",
      NeuronShaders.soma.contains("float3(0.58, 0.24, 0.98)") && NeuronShaders.soma.contains("float3(0.98, 0.28, 0.72)")
      && NeuronPalette.interior == SIMD3<Float>(0.58, 0.24, 0.98) && NeuronPalette.heart == SIMD3<Float>(0.98, 0.28, 0.72))
check("N5 the pacemaker's beat is the pulsar's period in both",
      NeuronShaders.soma.contains("rp_t / 1.5") && NeuronShaders.halo.contains("rp_t / 1.5")
      && SpaceOptics.pulsarPeriod == 1.5)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
