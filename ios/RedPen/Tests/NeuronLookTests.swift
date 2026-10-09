// The Neurons theme's look, as far as it is numbers (GraphNeuronStates):
//
// - the palette: bioluminescent green, cyan, pink and amber dyes on a deep
//   blue, every colour on screen's scale; an idea leans to its cell's
//   accent, so two cells already show all four colours; the soma's
//   interior a deep violet brightening to violet at its heart (the owner's
//   close-up);
// - the cell states: six, one for each space style and back again, each its
//   own shader number; the Look menu in the space styles' order; natural
//   states follow biology (a receptor migrates, a drifter engulfs, the
//   rest rest); a pacemaker beats with the pulsar's period;
// - the choice: one state for every note, one per cell winning over it,
//   containers always resting, stored strings read back the same and
//   anything unreadable skipped;
// - the bokeh: always the same discs, on the unit sphere, gold and blue,
//   the big ones fainter;
// - the shaders say the same: the soma and halo read rpState and its
//   codes, the soma's interior is the palette's;
// - the far cells behind it all: always the same, spread over the sky,
//   blue, each turned its own way, the big ones fainter.
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphAnatomy.swift, GraphNeuronImpulses.swift, GraphTheme.swift, GraphSpaceOptics.swift,
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
check("N1 the interior deep violet, the heart a brighter violet",
      NeuronPalette.interior.z > NeuronPalette.interior.x && NeuronPalette.interior.x > NeuronPalette.interior.y
      && NeuronPalette.heart.z > NeuronPalette.heart.x && NeuronPalette.heart.x > NeuronPalette.heart.y
      && NeuronPalette.heart.max() > NeuronPalette.interior.max())
let first: SIMD3<Float> = NeuronPalette.dye(slot: 0)
let firstIdea: SIMD3<Float> = NeuronPalette.dye(slot: 0, idea: true)
let accent: SIMD3<Float> = NeuronPalette.dyes[0].accent
check("N1 an idea leans to its cell's accent",
      simd_distance_f(firstIdea, accent) < simd_distance_f(first, accent) && firstIdea != first)
check("N1 slots wrap round, 5 and 6 a receptor's and a drifter's",
      NeuronPalette.dye(slot: 5) == NeuronPalette.receptor && NeuronPalette.dye(slot: 6) == NeuronPalette.drifter
      && NeuronPalette.dye(slot: 7) == NeuronPalette.dye(slot: 2))
check("N1 a cell's glow leans to the violet, a receptor's and a drifter's keep their own",
      (0..<5).allSatisfy { slot in
          [false, true].allSatisfy { idea in
              let glow: SIMD3<Float> = NeuronPalette.glow(slot: slot, idea: idea)
              return glow.z > glow.y && onScreen(glow) && glow != NeuronPalette.dye(slot: slot, idea: idea)
          }
      }
      && NeuronPalette.glow(slot: 5) == NeuronPalette.receptor && NeuronPalette.glow(slot: 6) == NeuronPalette.drifter)
// cells 0 and 1 with their ideas: all four target colours
let two: [SIMD3<Float>] = [NeuronPalette.dyes[0].main, NeuronPalette.dyes[0].accent,
                           NeuronPalette.dyes[1].main, NeuronPalette.dyes[1].accent]
let hasAll: Bool = two.contains { $0.y > 0.9 && $0.x < 0.5 } && two.contains { $0.z > 0.9 && $0.x < 0.4 }
    && two.contains { $0.x > 0.9 && $0.z > 0.6 } && two.contains { $0.x > 0.9 && $0.z < 0.4 }
check("N1 two cells' dyes and accents give all four colours", hasAll)

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
let resting: [NeuronRole] = [.cell, .part, .home, .vesicle, .granule]
check("N2 natural: a receptor migrates, a drifter engulfs, the rest rest",
      NeuronState.natural(.receptor) == .migrating && NeuronState.natural(.drifter) == .engulfing
      && resting.allSatisfy { NeuronState.natural($0) == .resting })
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
var input = UniverseInput(notes: notes, folders: [UniverseFolder(id: folderA, name: "Examples", parent: nil),
                                                  UniverseFolder(id: folderB, name: "Cardiology", parent: nil)],
                          edges: edges, seedByName: true)
check("N3 a closed cell shows nothing inside",
      GraphNeurons.plan(input).bodies.filter { $0.kind == .note }.count == 2)
// Both cells opened, so the notes inside them are planned too.
input.open = [folderA, folderB]
let plan: ThemePlan = GraphNeurons.plan(input)
let noteIndices: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind == .note }
let containers: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind != .note }
let regionA: Int = plan.bodies.firstIndex { $0.id == folderA } ?? -1

let natural = NeuronStateChoice.natural
check("N3 natural: each note its role's state",
      noteIndices.allSatisfy { i in
          natural.state(of: i, in: plan) == NeuronState.natural(NeuronRole(rawValue: plan.bodies[i].role) ?? .granule)
      })
let allFiring = NeuronStateChoice(main: NeuronState.firing.rawValue)
check("N3 one state for every note", !noteIndices.isEmpty
      && noteIndices.allSatisfy { allFiring.state(of: $0, in: plan) == .firing })
check("N3 containers always rest", !containers.isEmpty
      && containers.allSatisfy { allFiring.state(of: $0, in: plan) == .resting })
let mixed = NeuronStateChoice(main: NeuronState.firing.rawValue, folders: [folderA: .engulfing])
let inA: [Int] = noteIndices.filter { plan.bodies[$0].region == regionA }
let outA: [Int] = noteIndices.filter { plan.bodies[$0].region != regionA }
check("N3 a cell's state wins for the notes inside", regionA >= 0 && !inA.isEmpty
      && inA.allSatisfy { mixed.state(of: $0, in: plan) == .engulfing }
      && outA.allSatisfy { mixed.state(of: $0, in: plan) == .firing },
      "A \(regionA) in \(inA.map { mixed.state(of: $0, in: plan).rawValue }) out \(outA.map { mixed.state(of: $0, in: plan).rawValue })")
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
let golds: Int = discs.filter { $0.colour.x > 0.9 && $0.colour.z < 0.45 }.count
let blues: Int = discs.filter { $0.colour.z > 0.9 && $0.colour.x < 0.65 }.count
check("N4 gold and blue, nothing else", golds > 0 && blues > 0 && golds + blues == discs.count)
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
      NeuronShaders.soma.contains("float3(0.2, 0.07, 0.46)") && NeuronShaders.soma.contains("float3(0.52, 0.24, 0.98)")
      && NeuronPalette.interior == SIMD3<Float>(0.2, 0.07, 0.46) && NeuronPalette.heart == SIMD3<Float>(0.52, 0.24, 0.98))
check("N5 an opened nucleus is drawn as big as the layout keeps it for the parts",
      NeuronShaders.soma.contains("mix(0.36 + 0.25 * rpNucleus, \(GraphNeurons.openNucleus), rpOpen)"))
check("N5 the pacemaker's beat is the pulsar's period in both",
      NeuronShaders.soma.contains("rp_t / 1.5") && NeuronShaders.halo.contains("rp_t / 1.5")
      && SpaceOptics.pulsarPeriod == 1.5)

// MARK: N6 the far cells behind it all

let far: [NeuronFarCell] = NeuronBokeh.farCells()
check("N6 the same every time", far == NeuronBokeh.farCells() && far.count == NeuronBokeh.farCount)
check("N6 on the unit sphere", far.allSatisfy { abs((($0.direction * $0.direction).sum()).squareRoot() - 1) < 0.001 })
check("N6 on screen's scale, never full strength",
      far.allSatisfy { onScreen($0.colour) && $0.strength > 0 && $0.strength < 1 && $0.size > 0.1 && $0.size < 0.3 })
check("N6 blue, the strongest channel", far.allSatisfy { $0.colour.z >= $0.colour.x && $0.colour.z >= $0.colour.y })
let bigFar: [NeuronFarCell] = far.filter { $0.size > 0.24 }
let smallFar: [NeuronFarCell] = far.filter { $0.size < 0.18 }
let meanBigFar: Float = bigFar.map(\.strength).reduce(0, +) / Float(max(bigFar.count, 1))
let meanSmallFar: Float = smallFar.map(\.strength).reduce(0, +) / Float(max(smallFar.count, 1))
check("N6 the big ones fainter", !bigFar.isEmpty && !smallFar.isEmpty && meanBigFar < meanSmallFar)
var farOctants = Set<Int>()
for c in far {
    farOctants.insert((c.direction.x > 0 ? 1 : 0) + (c.direction.y > 0 ? 2 : 0) + (c.direction.z > 0 ? 4 : 0))
}
check("N6 spread over the sky", farOctants.count >= 6)
check("N6 each turned its own way", Set(far.map { Int($0.turn * 100) }).count >= far.count - 1
      && far.allSatisfy { $0.turn >= 0 && $0.turn < 2 * Float.pi })

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
