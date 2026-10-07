// The themed hierarchy (GraphAnatomy, plan §3d): every folder a cluster -
// a cell in Neurons, a circuit in Circuit - with the same seven parts,
// files and bullets in both themes, read from the app's own data.
//
// Checked here: the vocabulary (seven distinct parts a theme, the file
// names); a small vault's cells (the core note, from-/to- files, sources,
// why it matters, the myelin's share, hand-made links as synapses);
// levels 3 and 4 built only when asked for, every list bounded; links'
// strength and kind (contrast -> inhibitory, hand only -> modulatory),
// both ways; fibres between clusters, wires' resistance, colours and
// thickness; the level-of-detail distances and their hysteresis; the size
// ladder's page floor; the layout's no-overlap; the same structure in both
// themes; the same answer every run; 5,000 notes quickly.
//
// Compiled with GraphUniverse.swift and GraphAnatomy.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// A fixed id from a number, so every run uses the same ones.
func fixedID(_ n: Int) -> UUID {
    let hex: String = String(format: "%012X", n)
    return UUID(uuidString: "00000000-0000-4000-8000-" + hex) ?? UUID()
}

struct Dice: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11 ^ state
    }
}

func note(_ n: Int, _ title: String, page: Bool, folder: Int?, tags: [String] = [], source: String? = nil,
          hand: [Int] = [], written: [Int] = [], body: String = "", created: Double = 0) -> AnatomyNote {
    AnatomyNote(id: fixedID(n), title: title, body: body, isPage: page, folder: folder.map(fixedID), tags: tags,
                source: source, hand: hand.map(fixedID), written: written.map(fixedID),
                created: created == 0 ? Double(n) : created)
}

// MARK: - the sample vault

let cardio: UUID = fixedID(1)
let examples: UUID = fixedID(2)
let femoral: UUID = fixedID(3)
let inguinal: UUID = fixedID(4)
let folders: [UniverseFolder] = [
    UniverseFolder(id: cardio, name: "Cardiology", parent: nil),
    UniverseFolder(id: examples, name: "Examples", parent: nil),
    UniverseFolder(id: femoral, name: "Femoral", parent: examples),
    UniverseFolder(id: inguinal, name: "Inguinal", parent: examples),
]
let hfBody: String = """
Pump fails to meet the body's demand
- Reduced ejection fraction (HFrEF)
- Preserved ejection fraction (HFpEF)
## Why
Common finals topic and a frequent OSCE station
## Example
E.g. 70 M breathless on exertion with ankle swelling
Leads on to [[Acute coronary syndrome]]
"""
let notes: [AnatomyNote] = [
    note(10, "Heart failure", page: true, folder: 1, tags: ["#high-yield"], source: "Question \u{00B7} Cardiology set",
         hand: [11], written: [11], body: hfBody),
    note(11, "Acute coronary syndrome", page: true, folder: 1, tags: ["verified"], source: "Lecture \u{00B7} ACS",
         written: [12, 20], body: "Plaque rupture\nCan become [[STEMI]]\nNot the same as [[Femoral hernia]]"),
    note(12, "STEMI", page: false, folder: 1, hand: [10], body: "ST elevation"),
    note(20, "Femoral hernia", page: true, folder: 3, tags: ["unsure"], written: [21],
         body: "Below and lateral to the pubic tubercle\nSee [[Inguinal hernia]]"),
    note(21, "Inguinal hernia", page: true, folder: 4, tags: ["hy"], written: [20],
         body: "Above and medial\nCompare [[Femoral hernia]] vs direct"),
    note(22, "Hernia overview", page: false, folder: 2, hand: [10], body: "Groin lumps"),
    note(30, "Loose thought", page: false, folder: nil, hand: [10]),
]
let input = AnatomyInput(notes: notes, folders: folders)
let index = AnatomyIndex(input)
func byID(_ n: Int) -> AnatomyNote { notes.first { $0.id == fixedID(n) }! }

// MARK: - the vocabulary

for theme in AnatomyTheme.allCases {
    let names: [String] = AnatomySlot.allCases.map { $0.part(theme) }
    check("seven distinct parts (\(theme))", Set(names).count == 7 && names.count == 7, "\(names)")
}
check("neuron parts are the §3d list",
      Set(AnatomySlot.allCases.map { $0.part(.neuron) })
        == ["soma", "dendrites", "axon", "nucleus", "mitochondria", "myelin", "synapse"])
check("circuit parts are the §3d list",
      Set(AnatomySlot.allCases.map { $0.part(.circuit) })
        == ["source", "load", "conductors", "resistors", "capacitors", "switches", "ground"])
let kinds: [AnatomyFileKind] = [.idea, .detail, .examples, .from("Heart failure"), .to("STEMI"), .source, .why,
                                .confidence, .link("ACS")]
check("neuron file names", kinds.map { $0.name(.neuron) } == [
    "idea.md", "detail.md", "examples.md", "from-heart-failure.md", "to-stemi.md", "source.md", "why.md",
    "confidence.md", "link-acs.md"], "\(kinds.map { $0.name(.neuron) })")
check("circuit file names", kinds.map { $0.name(.circuit) } == [
    "outcome.md", "detail.md", "application.md", "heart-failure.md", "path-stemi.md", "baseline.md", "voltage.md",
    "limits.md", "if-acs.md"], "\(kinds.map { $0.name(.circuit) })")
check("slug", GraphAnatomy.slug("Heart failure (HFrEF)") == "heart-failure-hfref"
      && GraphAnatomy.slug("  ") == "untitled" && GraphAnatomy.slug(String(repeating: "a", count: 80)).count <= 32)
check("tag keys", GraphAnatomy.tagKey("#High_Yield") == "highyield" && GraphAnatomy.tagKey("must-know") == "mustknow")
check("bullets strip markers and headings",
      GraphAnatomy.bullets("# Title\n- one\n* two\n1. three\n12) four\n- [x] five\n\n> six [[A|shown]] **b**")
        == ["one", "two", "three", "four", "five", "six shown b"],
      "\(GraphAnatomy.bullets("# Title\n- one\n* two\n1. three\n12) four\n- [x] five\n\n> six [[A|shown]] **b**"))")

// MARK: - links

let hfACS: AnatomyLink? = GraphAnatomy.link(byID(10), byID(11))
check("hand + written link", hfACS?.strength == 7 && hfACS?.kind == .excitatory && hfACS?.hand == true
      && hfACS?.written == true && hfACS?.twoWay == false, "\(String(describing: hfACS))")
let contrast: AnatomyLink? = GraphAnatomy.link(byID(11), byID(20))
check("a mention read as a contrast is inhibitory", contrast?.kind == .inhibitory && contrast?.strength == 4,
      "\(String(describing: contrast))")
let handOnly: AnatomyLink? = GraphAnatomy.link(byID(12), byID(10))
check("a link drawn only by hand is modulatory", handOnly?.kind == .modulatory && handOnly?.hand == true
      && handOnly?.written == false, "\(String(describing: handOnly))")
let both: AnatomyLink? = GraphAnatomy.link(byID(20), byID(21))
check("both ways: twoWay and +2", both?.twoWay == true && both?.strength == 6 && both?.kind == .excitatory,
      "\(String(describing: both))")
check("\"vs\" is a contrast", GraphAnatomy.link(byID(21), byID(20))?.kind == .inhibitory)
check("no link, no fibre", GraphAnatomy.link(byID(12), byID(20)) == nil && GraphAnatomy.link(byID(10), byID(10)) == nil)
let full1 = AnatomyNote(id: fixedID(901), title: "A", body: "[[B]]", isPage: true, folder: nil, tags: ["x"],
                        source: "S", hand: [fixedID(902)], written: [fixedID(902)], created: 1)
let full2 = AnatomyNote(id: fixedID(902), title: "B", body: "[[A]]", isPage: true, folder: nil, tags: ["X"],
                        source: "S", hand: [fixedID(901)], written: [fixedID(901)], created: 2)
check("strength clamps at 10", GraphAnatomy.link(full1, full2)?.strength == 10)
check("contrast cues", GraphAnatomy.isContrast("Unlike [[X]]") && GraphAnatomy.isContrast("contraindicated in [[X]]")
      && !GraphAnatomy.isContrast("Leads to [[X]]") && !GraphAnatomy.isContrast("Know [[X]]"))
check("mention needs the whole title", GraphAnatomy.mention(of: "STEMI", in: "a [[STEMI-like]] b") == nil
      && GraphAnatomy.mention(of: "STEMI", in: "x\nsee [[stemi|it]]") == "see [[stemi|it]]")

// MARK: - a cell, level by level

let c2: AnatomyCell! = GraphAnatomy.cell(cardio, in: index, levels: 2)
let c3: AnatomyCell! = GraphAnatomy.cell(cardio, in: index, levels: 3)
let c4: AnatomyCell! = GraphAnatomy.cell(cardio, in: index, levels: 4)
check("cells built", c2 != nil && c3 != nil && c4 != nil)
check("the cluster's notes", c4.notes == 3 && c4.name == "Cardiology")
check("core: the most linked, longest page", c4.core == fixedID(10), "\(String(describing: c4.core))")
check("seven parts in slot order", c4.parts.map(\.slot) == AnatomySlot.allCases)
check("level 2 builds no files", c2.parts.allSatisfy { $0.files.isEmpty } && c2.levels == 2)
check("level 2 still counts them", c2.parts.map(\.fileCount) == c4.parts.map(\.fileCount),
      "\(c2.parts.map(\.fileCount)) vs \(c4.parts.map(\.fileCount))")
check("level 3 builds files, no bullets", c3.parts.contains { !$0.files.isEmpty }
      && c3.parts.allSatisfy { $0.files.allSatisfy { $0.bullets.isEmpty && $0.more == $0.bulletCount } })
check("level 4 builds bullets", c4.parts.contains { $0.files.contains { !$0.bullets.isEmpty } })
check("levels clamp to 2...4", GraphAnatomy.cell(cardio, in: index, levels: 9)?.levels == 4
      && GraphAnatomy.cell(cardio, in: index, levels: 0)?.levels == 2)

func part(_ cell: AnatomyCell, _ slot: AnatomySlot) -> AnatomyPart { cell.parts[slot.rawValue] }
let soma: AnatomyPart = part(c4, .core)
check("soma: idea, detail, examples", soma.files.map(\.kind) == [.idea, .detail, .examples])
check("idea is the first line", soma.files.first?.bullets.first?.text == "Pump fails to meet the body's demand",
      "\(soma.files.first?.bullets ?? [])")
check("examples from the Example heading",
      soma.files[2].bullets.first?.text.hasPrefix("E.g. 70 M") == true, "\(soma.files[2].bullets)")
check("detail has the list lines", soma.files[1].bullets.contains { $0.text == "Reduced ejection fraction (HFrEF)" })
let dendrites: AnatomyPart = part(c4, .incoming)
check("dendrites: one file per note linking in from outside",
      dendrites.files.map { $0.kind.name(.neuron) } == ["from-hernia-overview.md", "from-loose-thought.md"],
      "\(dendrites.files.map { $0.kind.name(.neuron) })")
check("a note in no folder is outside every cluster", dendrites.files.last?.concept == fixedID(30))
let axon: AnatomyPart = part(c4, .outgoing)
check("axon: one file per note linked to outside", axon.files.map { $0.kind.name(.neuron) } == ["to-femoral-hernia.md"]
      && axon.files.first?.concept == fixedID(20) && axon.files.first?.strength == 4)
check("axon bullet is the mention's line", axon.files.first?.bullets.first?.text == "Not the same as Femoral hernia",
      "\(axon.files.first?.bullets ?? [])")
check("circuit names the same file path-", axon.files.first?.kind.name(.circuit) == "path-femoral-hernia.md")
let nucleus: AnatomyPart = part(c4, .reference)
let sourceTexts: [String] = nucleus.files.first?.bullets.map(\.text) ?? []
check("nucleus: sources and written here", sourceTexts.count == 3 && sourceTexts.contains("Written here (1)")
      && sourceTexts.contains("Lecture \u{00B7} ACS (1)"), "\(sourceTexts)")
check("nucleus measure: share saved from a source", abs(nucleus.measure - 2.0 / 3.0) < 1e-9)
let mito: AnatomyPart = part(c4, .energy)
check("mitochondria: why lines", mito.files.first?.bullets.first?.text.hasPrefix("Common finals topic") == true,
      "\(mito.files.first?.bullets ?? [])")
check("mitochondria measure: high-yield share", abs(mito.measure - 1.0 / 3.0) < 1e-9)
let myelin: AnatomyPart = part(c4, .confidence)
check("myelin measure: verified 1, sourced 0.5", abs(myelin.measure - 0.5) < 1e-9, "\(myelin.measure)")
check("myelin lists verified first", myelin.files.first?.bullets.first?.text.contains("Acute coronary syndrome") == true
      && myelin.files.first?.bullets.last?.text.contains("STEMI") == true)
let synapse: AnatomyPart = part(c4, .links)
check("synapse: one file per hand-made link", synapse.fileCount == 4, "\(synapse.files.map { $0.kind.name(.neuron) })")
check("synapse strongest first", synapse.files.first?.strength == 7
      && zip(synapse.files, synapse.files.dropFirst()).allSatisfy { $0.strength >= $1.strength })
check("synapse names the outside end", synapse.files.contains { $0.kind == .link("Hernia overview") })
check("labels", synapse.label(.neuron) == "synapse \u{00B7} 4" && synapse.label(.circuit) == "switches \u{00B7} 4")
check("unknown folder: no cell", GraphAnatomy.cell(fixedID(999), in: index, levels: 4) == nil)

let ex: AnatomyCell! = GraphAnatomy.cell(examples, in: index, levels: 3)
check("a cluster holds its sub-folders' notes", ex.notes == 3, "\(String(describing: ex?.notes))")
check("links inside the cluster are not dendrites", part(ex, .incoming).files.map(\.concept) == [fixedID(11)],
      "\(part(ex, .incoming).files.map(\.kind))")
let emptyFolder: UUID = fixedID(5)
let withEmpty = AnatomyIndex(AnatomyInput(notes: notes, folders: folders + [
    UniverseFolder(id: emptyFolder, name: "Empty", parent: nil)]))
let empty: AnatomyCell! = GraphAnatomy.cell(emptyFolder, in: withEmpty, levels: 4)
check("an empty cluster: no core, seven quiet parts", empty.core == nil && empty.parts.count == 7
      && empty.parts.allSatisfy { $0.measure == 0 })

// MARK: - bounds

var crowd: [AnatomyNote] = [note(100, "Hub", page: true, folder: 1,
                                 body: (1...12).map { "line \($0) " + String(repeating: "x", count: 90) }.joined(separator: "\n"))]
for k in 0..<20 { crowd.append(note(200 + k, "Out \(k)", page: false, folder: 2, written: [100], body: "see [[Hub]]")) }
let crowdIndex = AnatomyIndex(AnatomyInput(notes: crowd, folders: folders))
let hub: AnatomyCell! = GraphAnatomy.cell(cardio, in: crowdIndex, levels: 4)
let hubIn: AnatomyPart = part(hub, .incoming)
check("files bounded, the rest counted", hubIn.fileCount == 20 && hubIn.files.count == GraphAnatomy.maxFiles
      && hubIn.more == 20 - GraphAnatomy.maxFiles, "\(hubIn.fileCount) \(hubIn.files.count) \(hubIn.more)")
let detail: AnatomyFile = part(hub, .core).files[1]
check("bullets bounded, the rest counted", detail.bulletCount == 11 && detail.bullets.count == GraphAnatomy.maxBullets
      && detail.more == 11 - GraphAnatomy.maxBullets, "\(detail.bulletCount) \(detail.bullets.count) \(detail.more)")
check("bullets clipped", hub.parts.allSatisfy { $0.files.allSatisfy { $0.bullets.allSatisfy {
    $0.text.count <= GraphAnatomy.bulletLength } } })

// MARK: - fibres and wires

let fibers: [AnatomyFiber] = GraphAnatomy.fibers(index)
check("one fibre between the two regions", fibers.count == 1, "\(fibers)")
if let f = fibers.first {
    check("fibre: both ways, two links", f.twoWay && f.links == 2, "\(f)")
    check("fibre strength: mean 4 + log2(2)", f.strength == 5, "\(f.strength)")
    check("fibre kind by weighted majority (tie -> inhibitory)", f.kind == .inhibitory, "\(f.kind)")
    check("half by hand is analog", !f.digital)
    check("fibre from Cardiology (alphabetical on a tie)", f.from == cardio && f.to == examples)
    check("evidence", f.evidence.count == 2 && f.evidence.contains("Acute coronary syndrome \u{2192} Femoral hernia"),
          "\(f.evidence)")
}
check("links inside one region make no fibre", !fibers.contains { $0.from == $0.to })
for s in 1...10 {
    let f = AnatomyFiber(from: cardio, to: examples, strength: s, kind: .excitatory, twoWay: false, links: 1,
                         digital: false, evidence: [])
    check("resistance = 11 - strength (\(s))", f.resistance == 11 - s && (1...10).contains(f.resistance))
}
let thick: [Double] = (1...10).map {
    AnatomyFiber(from: cardio, to: examples, strength: $0, kind: .excitatory, twoWay: false, links: 1, digital: false,
                 evidence: []).thickness(.neuron, unit: 1)
}
let wire: [Double] = (1...10).map {
    AnatomyFiber(from: cardio, to: examples, strength: $0, kind: .excitatory, twoWay: false, links: 1, digital: false,
                 evidence: []).thickness(.circuit, unit: 1)
}
check("fibre thickness grows with strength", zip(thick, thick.dropFirst()).allSatisfy { $0 < $1 } && thick.last == 1)
check("wire thickness falls with resistance", zip(wire, wire.dropFirst()).allSatisfy { $0 < $1 } && wire.last == 1
      && (wire.first ?? 0) > 0)
func fiber(_ kind: FiberKind, digital: Bool) -> AnatomyFiber {
    AnatomyFiber(from: cardio, to: examples, strength: 5, kind: kind, twoWay: false, links: 1, digital: digital, evidence: [])
}
let green = fiber(.excitatory, digital: false).colour(.neuron)
let red = fiber(.inhibitory, digital: false).colour(.neuron)
let yellow = fiber(.modulatory, digital: false).colour(.neuron)
check("excitatory green", green.g > green.r && green.g > green.b)
check("inhibitory red", red.r > red.g && red.r > red.b)
check("modulatory yellow", yellow.r > 0.8 && yellow.g > 0.7 && yellow.b < 0.4)
let orange = fiber(.excitatory, digital: true).colour(.circuit)
let blue = fiber(.excitatory, digital: false).colour(.circuit)
check("digital orange, analog blue", orange.r > orange.g && orange.g > orange.b && blue.b > blue.r && blue.b > blue.g)

// MARK: - level of detail and sizes

check("far: the cell only", AnatomyDetail.levels(distance: 100, unit: 1) == 2)
check("nearer: files", AnatomyDetail.levels(distance: 6, unit: 1) == 3)
check("close: bullets", AnatomyDetail.levels(distance: 3, unit: 1) == 4)
check("scales with the cell", AnatomyDetail.levels(distance: 30, unit: 10) == 4)
check("hysteresis holds files at the edge", AnatomyDetail.levels(distance: 9.5, unit: 1, current: 3) == 3
      && AnatomyDetail.levels(distance: 9.5, unit: 1, current: 2) == 2)
check("hysteresis holds bullets at the edge", AnatomyDetail.levels(distance: 4.7, unit: 1, current: 4) == 4
      && AnatomyDetail.levels(distance: 4.7, unit: 1, current: 3) == 3)
check("leaves beyond the band", AnatomyDetail.levels(distance: 10, unit: 1, current: 4) == 2)
for (cell, page) in [(0.5, 0.14), (0.4, 0.228), (2.0, 0.1), (0.1, 0.14)] {
    let s: [Double] = (1...4).map { AnatomySizes.sphere(level: $0, cell: cell, page: page) }
    check("sizes never below a page (\(cell), \(page))", s.allSatisfy { $0 >= page })
    check("sizes step down (\(cell), \(page))", zip(s, s.dropFirst()).allSatisfy { $0 >= $1 })
}

// MARK: - layout

func overlaps(_ places: [AnatomyPlace], cell: Double) -> [String] {
    var out: [String] = []
    for (i, p) in places.enumerated() {
        if GraphAnatomy.length(p.centre) < cell + p.sphere - 1e-9 { out.append("\(p.label) in the cell") }
        for q in places[(i + 1)...] where GraphAnatomy.length(p.centre - q.centre) < p.sphere + q.sphere - 1e-9 {
            out.append("\(p.label) / \(q.label)")
        }
    }
    return out
}
for theme in AnatomyTheme.allCases {
    for cell in [c2!, c3!, c4!, hub!] {
        let places = GraphAnatomy.layout(cell, cellSphere: 0.5, page: 0.14, theme: theme)
        let bad = overlaps(places, cell: 0.5)
        check("no overlaps (\(theme), level \(cell.levels), \(cell.notes) notes)", bad.isEmpty, "\(bad.prefix(4))")
        let want: Int = cell.parts.count + cell.parts.reduce(0) { $0 + $1.files.count
            + $1.files.reduce(0) { $0 + $1.bullets.count } }
        check("one place a built piece (\(theme), level \(cell.levels))", places.count == want, "\(places.count) vs \(want)")
        check("parents come first", places.enumerated().allSatisfy { $0.element.parent < $0.offset })
        check("no place below a page", places.allSatisfy { $0.sphere >= 0.14 })
    }
}
let pn = GraphAnatomy.layout(c4, cellSphere: 0.5, page: 0.14, theme: .neuron)
let pc = GraphAnatomy.layout(c4, cellSphere: 0.5, page: 0.14, theme: .circuit)
check("the same shape in both themes", pn.map(\.centre) == pc.map(\.centre) && pn.map(\.sphere) == pc.map(\.sphere))
check("only the names differ", pn.map(\.label) != pc.map(\.label)
      && pn.first?.label == "soma \u{00B7} 3" && pc.first?.label == "load \u{00B7} 3",
      "\(pn.first?.label ?? "") / \(pc.first?.label ?? "")")
let spread = GraphAnatomy.layout(c4, cellSphere: 0.5, page: 0.14, theme: .neuron, spread: 1.6)
check("link length spreads the parts", GraphAnatomy.length(spread[0].centre) > GraphAnatomy.length(pn[0].centre))

// MARK: - determinism and odd input

check("the same cell every time", GraphAnatomy.cell(cardio, in: AnatomyIndex(input), levels: 4) == c4)
check("the same fibres every time", GraphAnatomy.fibers(AnatomyIndex(input)) == fibers)
let loop = AnatomyIndex(AnatomyInput(notes: notes, folders: [
    UniverseFolder(id: fixedID(1), name: "A", parent: fixedID(2)),
    UniverseFolder(id: fixedID(2), name: "B", parent: fixedID(1))]))
check("a folder loop ends", GraphAnatomy.cell(fixedID(1), in: loop, levels: 4) != nil)
let dangling = AnatomyIndex(AnatomyInput(notes: [note(1000, "Lost", page: true, folder: 1, hand: [99999],
                                                      written: [99998])], folders: folders))
check("links to missing notes are dropped", dangling.outgoing[0].isEmpty
      && GraphAnatomy.cell(cardio, in: dangling, levels: 4)?.parts[AnatomySlot.links.rawValue].fileCount == 0)

// MARK: - a big vault

var dice = Dice(state: 42)
var bigFolders: [UniverseFolder] = []
for f in 0..<60 {
    let parent: UUID? = f < 12 ? nil : fixedID(10_000 + Int.random(in: 0..<f, using: &dice))
    bigFolders.append(UniverseFolder(id: fixedID(10_000 + f), name: "Folder \(f)", parent: parent))
}
var big: [AnatomyNote] = []
for n in 0..<5_000 {
    let hand: [Int] = (0..<Int.random(in: 0...2, using: &dice)).map { _ in 20_000 + Int.random(in: 0..<5_000, using: &dice) }
    let written: [Int] = (0..<Int.random(in: 0...3, using: &dice)).map { _ in 20_000 + Int.random(in: 0..<5_000, using: &dice) }
    let body: String = written.map { "- see [[Note \($0 - 20_000)]]" + (Bool.random(using: &dice) ? " not this" : "") }
        .joined(separator: "\n") + "\nAn idea\nA detail"
    big.append(note(20_000 + n, "Note \(n)", page: n % 5 == 0, folder: 10_000 + Int.random(in: 0..<60, using: &dice),
                    tags: n % 7 == 0 ? ["hy"] : [], source: n % 3 == 0 ? "Set \(n % 11)" : nil,
                    hand: hand, written: written, body: body))
}
/// This process's own CPU time, in seconds. The big vault is timed by it, not
/// by the wall clock: preflight runs eight suites at once on a four-core
/// machine, and time spent waiting for a core is not the work's cost.
func cpuSeconds() -> Double {
    var now = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &now)
    return Double(now.tv_sec) + Double(now.tv_nsec) / 1e9
}
let started: Double = cpuSeconds()
let bigIndex = AnatomyIndex(AnatomyInput(notes: big, folders: bigFolders))
let bigFibers = GraphAnatomy.fibers(bigIndex)
var bigCells: [AnatomyCell] = []
for f in bigFolders.prefix(12) {
    if let cell = GraphAnatomy.cell(f.id, in: bigIndex, levels: 4) { bigCells.append(cell) }
}
let took: Double = cpuSeconds() - started
print("5,000 notes: index, \(bigFibers.count) fibres and 12 cells at level 4 in \(String(format: "%.3f", took)) s of CPU")
check("5,000 notes in under 2 s", took < 2, "\(took)")
check("every big cell bounded", bigCells.allSatisfy { $0.parts.allSatisfy {
    $0.files.count <= GraphAnatomy.maxFiles && $0.files.allSatisfy { $0.bullets.count <= GraphAnatomy.maxBullets } } })
check("big fibres in range", !bigFibers.isEmpty && bigFibers.allSatisfy { (1...10).contains($0.strength) })
check("top-level cells hold every foldered note", bigCells.reduce(0) { $0 + $1.notes } == big.count,
      "\(bigCells.reduce(0) { $0 + $1.notes })")
let bigPlaces = GraphAnatomy.layout(bigCells[0], cellSphere: 0.5, page: 0.14, theme: .circuit)
check("a big cell lays out clear", overlaps(bigPlaces, cell: 0.5).isEmpty)

print(failures.isEmpty ? "\nAll anatomy checks passed." : "\n\(failures.count) failed: \(failures)")
exit(failures.isEmpty ? 0 : 1)
