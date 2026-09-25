// The Circuit theme (GraphCircuit): the ideas' hierarchy as a printed
// circuit board - the vault the motherboard, top-level folders processors,
// folders inside them modules on their own sub-boards, pages capacitors (an
// inductor when long), ideas resistors, LEDs and diodes, short one-link
// ideas small surface-mount parts beside their note, bridging ideas bus
// headers, loose notes edge fingers or pads on the board's edges - joined by
// traces routed square to the board with rounded 45° corners
// (GraphLinkRoute).
//
// None of this needs a screen, so it is all checked here: the parts the
// design preview must show, the links' kinds and which way current runs,
// the size ladder over hundreds of random vaults, that no two footprints
// ever overlap and every sub-board is clear of the others, that everything
// lies flat on the board, that the same notes always give the same board,
// the edge cases, scale, and that every routed trace is one smooth piece of
// straights and 45° diagonals.
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphCircuit.swift,
// GraphLinkCurve.swift, GraphNeuronImpulses.swift and GraphTheme.swift
// (Foundation only). The design preview's notes are the same copy
// CosmicHierarchyTests and NeuronHierarchyTests use.
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

/// A tiny random source for the random vaults.
struct Dice: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        return Int(next() % UInt64(n))
    }
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }
}

// MARK: the design preview's store, as GraphPreview.makeStore builds it

struct Draft {
    let title: String
    let page: Bool
    let folder: String?
    let body: String
}

let heartFailureBody: String = """
Heart failure is a syndrome, not a diagnosis: the heart cannot pump enough blood for the body's needs, or manages only at raised filling pressures. It is common, and most admissions are older people with other illnesses too.

Types
- HFrEF: ejection fraction 40% or less.
- HFpEF: ejection fraction 50% or more, with raised filling pressures.
- Mildly reduced: 41 to 49%.

Causes
- Ischaemic heart disease, the commonest; hypertension; valve disease.
- Cardiomyopathy, arrhythmia, alcohol, anaemia, thyroid disease and some drugs.

Symptoms and signs
- Breathlessness on exertion, orthopnoea, waking breathless at night, fatigue.
- Ankle swelling, raised JVP, basal crackles, a third heart sound, a displaced apex.

Investigations
- [[BNP]]: a normal level makes heart failure unlikely.
- Echocardiogram: ejection fraction, valves and wall motion.
- ECG and chest X-ray: cardiomegaly, upper lobe diversion, effusions.
- Bloods: renal function, electrolytes, full blood count, thyroid, iron studies.

Treatment
- [[Loop diuretics]] for congestion: they ease symptoms but do not prolong life.
- [[ACE inhibitors]] (or an ARNI), a beta-blocker, an MRA and an SGLT2 inhibitor lower mortality in HFrEF.
- Start low and titrate; check K+ and renal function after each change.
- An ICD or CRT for selected patients with a low ejection fraction or a wide QRS.

Acute decompensation
- Sit the patient up, give oxygen if hypoxic and IV furosemide, and treat the trigger: ischaemia, arrhythmia, infection or missed tablets.

Follow-up
- Daily weights: a gain of 2 kg in 3 days means fluid.
- A salt and fluid plan, flu and pneumococcal vaccines, cardiac rehabilitation, and advance care planning.
- Review within two weeks of discharge.
"""

/// NoteExamples (with Anatomy made inside Inguinal and three notes moved
/// into it), the Cardiology folder, the bridging idea and two loose ideas.
let previewDrafts: [Draft] = [
    Draft(title: "Groin hernia", page: true, folder: "Examples", body: """
    Three to know: [[Indirect inguinal hernia]], [[Direct inguinal hernia]] and [[Femoral hernia]].

    - The anatomy first: [[Inguinal canal]]
    - A groin swelling with an expansile impulse on cough is a hernia until shown otherwise.
    - A hernia is a surgical disease - the only treatment is surgery. See [[Hernia repair]].
    """),
    Draft(title: "Inguinal canal", page: true, folder: "Inguinal", body: """
    Develops by the descent of the testis. Runs obliquely from the deep ring to the superficial ring.

    How long is the inguinal canal? | 4 cm, running obliquely
    What does it contain in males? | Spermatic cord; ilio-inguinal nerve
    What does it contain in females? | Round ligament of the uterus; ilio-inguinal nerve

    Walls: [[Canal boundaries]]. Coverings of the cord: [[Spermatic cord coverings]].
    """),
    Draft(title: "Canal boundaries", page: false, folder: "Anatomy", body: """
    - Anterior: external oblique all through, internal oblique laterally
    - Posterior: fascia transversalis all through, internal oblique medially
    - Roof: conjoined muscles (internal oblique and transversus)
    - Floor: inguinal ligament and lacunar ligament

    Remember it with [[LA/PM mnemonic]].
    """),
    Draft(title: "LA/PM mnemonic", page: false, folder: "Anatomy", body: """
    Internal oblique sits in the Anterior wall Laterally, and in the Posterior wall Medially. The rest of [[Canal boundaries]] follows.
    """),
    Draft(title: "Spermatic cord coverings", page: false, folder: "Anatomy", body: """
    Internal spermatic fascia | From transversalis fascia, at the internal ring
    Cremasteric muscle and fascia | From internal oblique
    External spermatic fascia | From external oblique aponeurosis, at the external ring
    """),
    Draft(title: "Indirect inguinal hernia", page: true, folder: "Inguinal", body: """
    - 70% of all hernias; 30% bilateral; males 20 times more often
    - The defect is the stretched deep inguinal ring
    - The sac lies inside the cord and may reach the scrotum
    - Neck of the sac lateral to the [[Inferior epigastric vessels]]
    """),
    Draft(title: "Direct inguinal hernia", page: true, folder: "Inguinal", body: """
    - Through the posterior wall of the canal
    - Adult or elderly, more often bilateral, hemispherical
    - Reduces backwards; complications uncommon
    - Sac medial to the [[Inferior epigastric vessels]]
    """),
    Draft(title: "Inferior epigastric vessels", page: false, folder: "Inguinal", body: """
    The landmark that tells them apart: sac lateral = [[Indirect inguinal hernia]], sac medial = [[Direct inguinal hernia]].
    """),
    Draft(title: "Internal ring test", page: false, folder: "Inguinal", body: """
    Positive (swelling controlled) = oblique, [[Indirect inguinal hernia]]. Negative = direct. The finger invagination test is obsolete.
    """),
    Draft(title: "Femoral hernia", page: true, folder: "Femoral", body: """
    - Parietal peritoneum down through the [[Femoral canal]]
    - More common in women
    - Neck below and lateral to the pubic tubercle
    - Femoral ring: inguinal ligament in front, pectineal ligament behind, femoral vein laterally, lacunar ligament medially

    The great mimic: [[Saphena varix]].
    """),
    Draft(title: "Femoral canal", page: false, folder: "Femoral", body: """
    Medial to the femoral vein (artery lateral to the vein). 1.25 cm long, cone shaped.
    """),
    Draft(title: "Saphena varix", page: false, folder: "Femoral", body: """
    Mimics a [[Femoral hernia]]: disappears completely lying flat, fluid thrill on cough, venous hum - usually with other varicose veins.
    """),
    Draft(title: "Hernia repair", page: false, folder: "Examples", body: """
    - TAPP: transabdominal preperitoneal
    - TEP: totally extraperitoneal
    - Robotic-assisted repair
    """),
    Draft(title: "Heart failure", page: true, folder: "Cardiology", body: heartFailureBody),
    Draft(title: "BNP", page: false, folder: "Cardiology",
          body: "Raised in [[Heart failure]]; a normal level makes it unlikely."),
    Draft(title: "Loop diuretics", page: false, folder: "Cardiology",
          body: "Furosemide for congestion in [[Heart failure]]. Watch [[Hypokalaemia]]."),
    Draft(title: "ACE inhibitors", page: false, folder: "Cardiology",
          body: "Prognostic in [[Heart failure]]. Cough; check [[Hypokalaemia]] the other way."),
    Draft(title: "Hypokalaemia", page: false, folder: "Cardiology",
          body: "Flat T waves, U waves. Risk with [[Loop diuretics]]."),
    Draft(title: "Acute coronary syndrome", page: true, folder: "Cardiology",
          body: "[[STEMI]], [[NSTEMI]] and unstable angina. [[Troponin]] tells them apart."),
    Draft(title: "STEMI", page: false, folder: "Cardiology",
          body: "ST elevation: primary PCI. Part of [[Acute coronary syndrome]]."),
    Draft(title: "NSTEMI", page: false, folder: "Cardiology", body: "Raised [[Troponin]] without ST elevation."),
    Draft(title: "Troponin", page: false, folder: "Cardiology",
          body: "Rises in 3 hours, peaks at 24. [[Acute coronary syndrome]]."),
    Draft(title: "Atrial fibrillation", page: true, folder: "Cardiology",
          body: "Irregularly irregular. Rate or rhythm control; [[CHA2DS2-VASc]] for anticoagulation."),
    Draft(title: "CHA2DS2-VASc", page: false, folder: "Cardiology", body: "Stroke risk in [[Atrial fibrillation]]."),
    Draft(title: "Murmurs", page: true, folder: "Cardiology",
          body: "Aortic stenosis, mitral regurgitation - and [[Heart failure]] as the end point."),
    Draft(title: "Heart sounds", page: false, folder: "Cardiology", body: "S1 and S2; listen at the apex for S3."),
    Draft(title: "Syncope", page: false, folder: "Cardiology", body: "Cardiac or not? Exertional syncope needs an echo."),
    Draft(title: "Expansile cough impulse", page: false, folder: "Examples", body: """
    Felt over an [[Indirect inguinal hernia]], a [[Direct inguinal hernia]] and a [[Femoral hernia]]. A groin lump with a cough impulse is a hernia until shown otherwise.
    """),
    Draft(title: "Richter's hernia", page: false, folder: nil, body: """
    Only part of the bowel wall is trapped, so it can strangulate without obstructing. Most often through the femoral ring: see [[Femoral hernia]].
    """),
    Draft(title: "Pericarditis", page: false, folder: nil, body: """
    Sharp chest pain, better sitting forward; saddle-shaped ST elevation in many leads and PR depression. Not a [[STEMI]].
    """)
]

/// Links made by hand in the preview store.
let previewHandLinks: [(String, String)] = [
    ("Internal ring test", "Direct inguinal hernia"), ("Spermatic cord coverings", "Indirect inguinal hernia"),
    ("Femoral hernia", "Inguinal canal"), ("Acute coronary syndrome", "Heart failure"),
    ("Atrial fibrillation", "Heart failure"), ("Murmurs", "Atrial fibrillation")
]

/// `[[Title]]` in a body, as NoteStore.wikiTitles reads it.
func wikiTitles(_ text: String) -> [String] {
    var titles: [String] = []
    for piece in text.components(separatedBy: "[[").dropFirst() {
        guard let close = piece.range(of: "]]") else { continue }
        let inner: Substring = piece[piece.startIndex..<close.lowerBound]
        if inner.contains("\n") { continue }
        let target: String = inner.split(separator: "|").first.map(String.init) ?? ""
        let title: String = target.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { titles.append(title) }
    }
    return titles
}

func previewInput() -> UniverseInput {
    let folderNames: [(String, String?)] = [
        ("Examples", nil), ("Inguinal", "Examples"), ("Femoral", "Examples"),
        ("Cardiology", nil), ("Anatomy", "Inguinal")
    ]
    var folderID: [String: UUID] = [:]
    for (k, pair) in folderNames.enumerated() { folderID[pair.0] = fixedID(900 + k) }
    var folders: [UniverseFolder] = []
    for pair in folderNames {
        guard let id = folderID[pair.0] else { continue }
        let parent: UUID? = pair.1.flatMap { folderID[$0] }
        folders.append(UniverseFolder(id: id, name: pair.0, parent: parent))
    }
    var byTitle: [String: UUID] = [:]
    var notes: [UniverseNote] = []
    for (k, draft) in previewDrafts.enumerated() {
        let id: UUID = fixedID(k + 1)
        byTitle[draft.title.lowercased()] = id
        let words: Int = GraphUniverse.wordCount(draft.body)
        let folder: UUID? = draft.folder.flatMap { folderID[$0] }
        notes.append(UniverseNote(id: id, title: draft.title, isPage: draft.page, folder: folder,
                                  words: words, created: Double(k)))
    }
    var edges: [UniverseEdge] = []
    for (k, draft) in previewDrafts.enumerated() {
        for title in wikiTitles(draft.body) {
            guard let to = byTitle[title.lowercased()] else { continue }
            edges.append(UniverseEdge(a: fixedID(k + 1), b: to))
        }
    }
    for (a, b) in previewHandLinks {
        guard let x = byTitle[a.lowercased()], let y = byTitle[b.lowercased()] else { continue }
        edges.append(UniverseEdge(a: x, b: y))
    }
    return UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: true)
}

/// A random vault: up to `maxNotes` notes, `maxFolders` folders nested up
/// to depth 6, random links.
func randomVault(_ seed: UInt64, maxNotes: Int, maxFolders: Int, exact: Bool = false) -> UniverseInput {
    var dice = Dice(state: seed)
    let folderCount: Int = dice.below(maxFolders + 1)
    var folders: [UniverseFolder] = []
    var depthOf: [Int] = []
    for k in 0..<folderCount {
        let id: UUID = fixedID(10_000 + k)
        var parent: UUID?
        var d: Int = 0
        if k > 0 && dice.unit() < 0.6 {
            let p: Int = dice.below(k)
            if depthOf[p] < 6 {
                parent = folders[p].id
                d = depthOf[p] + 1
            }
        }
        folders.append(UniverseFolder(id: id, name: "Folder \(k)", parent: parent))
        depthOf.append(d)
    }
    let drawn: Int = dice.below(maxNotes + 1)
    let noteCount: Int = exact ? maxNotes : drawn
    var notes: [UniverseNote] = []
    for k in 0..<noteCount {
        var folder: UUID?
        if !folders.isEmpty && dice.unit() < 0.88 { folder = folders[dice.below(folders.count)].id }
        let words: Int = Int(pow(2.0, dice.unit() * 11))
        let note = UniverseNote(id: fixedID(k + 1), title: "Note \(k)", isPage: dice.unit() < 0.3,
                                folder: folder, words: words, created: Double(k))
        notes.append(note)
    }
    var edges: [UniverseEdge] = []
    let linkCount: Int = noteCount * 13 / 10
    for _ in 0..<linkCount where noteCount > 1 {
        let a: Int = dice.below(noteCount)
        let b: Int = dice.below(noteCount)
        edges.append(UniverseEdge(a: fixedID(a + 1), b: fixedID(b + 1)))
    }
    return UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: false)
}


// MARK: helpers over a plan

func bodyNamed(_ plan: ThemePlan, _ title: String) -> Int? {
    plan.bodies.firstIndex { $0.title == title }
}

func roleOf(_ body: ThemeBody) -> CircuitRole {
    CircuitRole(rawValue: body.role) ?? .resistor
}

func titles(_ plan: ThemePlan, _ role: CircuitRole) -> Set<String> {
    Set(plan.bodies.filter { $0.role == role.rawValue }.map(\.title))
}

func dot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    (a * b).sum()
}

func length3(_ a: SIMD3<Float>) -> Float {
    (a * a).sum().squareRoot()
}

let boardRight: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.right)
let boardForward: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.forward)
let boardNormal: SIMD3<Float> = GraphUniverse.float3(GraphCircuit.normal)

/// A body's place on the board.
func onBoard(_ p: SIMD3<Float>) -> SIMD2<Double> {
    SIMD2<Double>(Double(dot3(p, boardRight)), Double(dot3(p, boardForward)))
}

/// A body's footprint on the board, as the planner keeps it clear.
func footprint(_ body: ThemeBody) -> CircuitRect {
    let role: CircuitRole = roleOf(body)
    var f: SIMD2<Double> = role.foot * Double(body.sphere)
    let vertical: Bool = dot3(body.axis, boardForward) > 0.5
    if vertical && role.isOriented { f = SIMD2<Double>(f.y, f.x) }
    return CircuitRect(c: onBoard(body.home), h: f)
}

/// Pairs of parts whose footprints overlap.
func footprintOverlaps(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let rects: [CircuitRect] = plan.bodies.map(footprint)
    for x in rects.indices {
        for y in (x + 1)..<rects.count where !rects[x].clears(rects[y], gap: 0.0001) {
            if bad.count < 5 { bad.append("\(plan.bodies[x].title)/\(plan.bodies[y].title)") }
        }
    }
    return bad
}

/// A container's sub-board, on the board.
func patchOf(_ plan: ThemePlan, _ i: Int) -> CircuitRect {
    let p: SIMD4<Float> = plan.patches[i]
    let at: SIMD2<Double> = onBoard(plan.bodies[i].home)
    return CircuitRect(c: at + SIMD2<Double>(Double(p.x), Double(p.y)), h: SIMD2<Double>(Double(p.z), Double(p.w)))
}

/// Sub-boards that overlap, and parts outside their own chip's sub-board.
func patchProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    guard plan.patches.count == plan.bodies.count else { return ["patches \(plan.patches.count)"] }
    let chips: [Int] = plan.bodies.indices.filter { roleOf(plan.bodies[$0]).isContainer }
    for x in chips.indices {
        for y in (x + 1)..<chips.count {
            let a: CircuitRect = patchOf(plan, chips[x])
            let b: CircuitRect = patchOf(plan, chips[y])
            if !a.clears(b, gap: 0) && bad.count < 5 {
                bad.append("sub-boards \(plan.bodies[chips[x]].title)/\(plan.bodies[chips[y]].title)")
            }
        }
    }
    for (i, b) in plan.bodies.enumerated() where !roleOf(b).isContainer && b.parent >= 0 {
        var up: Int = b.parent
        while up >= 0 && !roleOf(plan.bodies[up]).isContainer { up = plan.bodies[up].parent }
        guard up >= 0 else { continue }
        let zone: CircuitRect = patchOf(plan, up)
        let r: CircuitRect = footprint(b)
        let inside: Bool = r.low.x >= zone.low.x - 1e-6 && r.low.y >= zone.low.y - 1e-6
            && r.high.x <= zone.high.x + 1e-6 && r.high.y <= zone.high.y + 1e-6
        if !inside && bad.count < 5 { bad.append("\(b.title) outside \(plan.bodies[up].title)'s sub-board") }
        _ = i
    }
    return bad
}

/// The ladder's rules, for any vault.
func ladderProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let bodies: [ThemeBody] = plan.bodies
    let chips: [ThemeBody] = bodies.filter { roleOf($0).isContainer }
    let parts: [ThemeBody] = bodies.filter { !roleOf($0).isContainer }
    let smallestChip: Float = chips.map(\.sphere).min() ?? 99
    let biggestPart: Float = parts.map(\.sphere).max() ?? 0
    if !chips.isEmpty && !parts.isEmpty && smallestChip <= biggestPart {
        bad.append("chip \(smallestChip) <= part \(biggestPart)")
    }
    for (i, b) in bodies.enumerated() {
        if b.parent >= i { bad.append("\(b.title) before its parent") }
        guard roleOf(b) == .module else { continue }
        let up: ThemeBody = bodies[b.parent]
        if !roleOf(up).isContainer { bad.append("\(b.title)'s parent is not a chip") }
        if b.sphere >= up.sphere { bad.append("\(b.title) \(b.sphere) >= parent \(up.sphere)") }
    }
    func sizes(_ roles: [CircuitRole]) -> [Float] {
        bodies.filter { roles.contains(roleOf($0)) }.map(\.sphere)
    }
    let pages: [Float] = sizes([.capacitor, .inductor])
    let ideas: [Float] = sizes([.resistor, .led, .diode])
    let headers: [Float] = sizes([.header])
    let smds: [Float] = sizes([.smd])
    if let p = pages.min(), let q = ideas.max(), p <= q { bad.append("page \(p) <= idea \(q)") }
    if let p = pages.min(), let q = headers.max(), p <= q { bad.append("page \(p) <= header \(q)") }
    if let p = ideas.min(), let q = smds.max(), p <= q { bad.append("idea \(p) <= smd \(q)") }
    for b in bodies where roleOf(b) == .smd {
        if roleOf(bodies[b.parent]).isContainer { bad.append("smd \(b.title) on a chip") }
    }
    return bad
}

/// Everything on the board's plane (height 0) and inside the motherboard.
func flatProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    guard let g = plan.ground else { return ["no motherboard"] }
    for b in plan.bodies {
        let h: Float = dot3(b.home, boardNormal)
        if abs(h) > 1e-4 && bad.count < 3 { bad.append("\(b.title) at height \(h)") }
        let r: CircuitRect = footprint(b)
        let inside: Bool = r.low.x >= Double(g.x) - 1e-4 && r.low.y >= Double(g.y) - 1e-4
            && r.high.x <= Double(g.z) + 1e-4 && r.high.y <= Double(g.w) + 1e-4
        if !inside && bad.count < 3 { bad.append("\(b.title) off the board") }
        for t in [0.0, 30.0, 600.0] where length3(plan.position(of: plan.bodies.firstIndex(of: b) ?? 0, time: t) - b.home) > 1e-4 {
            if bad.count < 3 { bad.append("\(b.title) moves") }
        }
    }
    return bad
}

/// Every body inside the envelope's box.
func envelopeHolds(_ plan: ThemePlan) -> [String] {
    guard !plan.envelope.isEmpty else { return ["no envelope"] }
    var low = SIMD3<Float>(repeating: 1e9)
    var high = SIMD3<Float>(repeating: -1e9)
    for p in plan.envelope {
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }
    var bad: [String] = []
    for b in plan.bodies {
        let p: SIMD3<Float> = b.home
        let r: Float = b.sphere
        let out: Bool = p.x - r < low.x || p.y - r < low.y || p.z - r < low.z
            || p.x + r > high.x || p.y + r > high.y || p.z + r > high.z
        if out && bad.count < 3 { bad.append(b.title) }
    }
    return bad
}

// MARK: T1 the design preview's parts

let preview: ThemePlan = GraphCircuit.plan(previewInput())
check("T1 two processors", titles(preview, .processor) == ["Cardiology", "Examples"], "\(titles(preview, .processor))")
check("T1 three modules", titles(preview, .module) == ["Inguinal", "Femoral", "Anatomy"], "\(titles(preview, .module))")
let expectedCaps: Set<String> = [
    "Groin hernia", "Inguinal canal", "Femoral hernia", "Indirect inguinal hernia",
    "Direct inguinal hernia", "Acute coronary syndrome", "Atrial fibrillation", "Murmurs"
]
check("T1 eight capacitors", titles(preview, .capacitor) == expectedCaps, "\(titles(preview, .capacitor))")
check("T1 the long read is an inductor", titles(preview, .inductor) == ["Heart failure"], "\(titles(preview, .inductor))")
let ledsAndResistors: Set<String> = titles(preview, .led).union(titles(preview, .resistor))
let expectedIdeas: Set<String> = [
    "Inferior epigastric vessels", "Internal ring test", "Canal boundaries",
    "Loop diuretics", "ACE inhibitors", "Hypokalaemia", "NSTEMI", "Troponin", "STEMI", "Heart sounds", "Syncope"
]
check("T1 eleven ideas as resistors and LEDs", ledsAndResistors == expectedIdeas, "\(ledsAndResistors)")
let ledsOK: Bool = preview.bodies.filter { roleOf($0) == .led }.allSatisfy { $0.links >= 2 }
    && preview.bodies.filter { roleOf($0) == .resistor }.allSatisfy { $0.links < 2 }
check("T1 LEDs are the ideas with two or more links", ledsOK && titles(preview, .led).count >= 4,
      "\(titles(preview, .led))")
let expectedSmd: [String: String] = [
    "Hernia repair": "Groin hernia", "LA/PM mnemonic": "Canal boundaries", "Femoral canal": "Femoral hernia",
    "Saphena varix": "Femoral hernia", "BNP": "Heart failure", "CHA2DS2-VASc": "Atrial fibrillation"
]
var foundSmd: [String: String] = [:]
for body in preview.bodies where body.role == CircuitRole.smd.rawValue {
    foundSmd[body.title] = preview.bodies[body.parent].title
}
check("T1 six surface-mount parts beside their notes", foundSmd == expectedSmd, "\(foundSmd)")
check("T1 the bridging idea is a bus header", titles(preview, .header) == ["Expansile cough impulse"],
      "\(titles(preview, .header))")
check("T1 both loose notes are edge fingers", titles(preview, .edgePin) == ["Richter's hernia", "Pericarditis"],
      "\(titles(preview, .edgePin))")
check("T1 Anatomy's idea wired only up into Inguinal is a diode",
      titles(preview, .diode) == ["Spermatic cord coverings"], "\(titles(preview, .diode))")
check("T1 no pads", titles(preview, .pad).isEmpty)
check("T1 summary", preview.summary.hasPrefix("2 processors, 3 modules, 8 capacitors, 1 inductor")
      && preview.summary.hasSuffix("1 diode, 6 surface-mount parts, 1 bus header, 2 edge fingers"), preview.summary)
let anatomy: Int = bodyNamed(preview, "Anatomy") ?? -1
let inguinal: Int = bodyNamed(preview, "Inguinal") ?? -1
let examples: Int = bodyNamed(preview, "Examples") ?? -1
check("T1 Anatomy sits under Inguinal, Inguinal under Examples",
      anatomy >= 0 && preview.bodies[anatomy].parent == inguinal && preview.bodies[inguinal].parent == examples)
check("T1 processors listed", preview.regions.map { preview.bodies[$0].title }.sorted() == ["Cardiology", "Examples"])
check("T1 Anatomy's zone is Examples'", anatomy >= 0 && preview.bodies[anatomy].region == examples)

// MARK: T2 links and current

func link(_ plan: ThemePlan, _ a: String, _ b: String) -> ThemeLink? {
    guard let i = bodyNamed(plan, a), let j = bodyNamed(plan, b) else { return nil }
    return plan.links.first { ($0.a == i && $0.b == j) || ($0.a == j && $0.b == i) }
}

check("T2 a surface-mount part's link is hidden (it is soldered on)", link(preview, "BNP", "Heart failure")?.kind == 3)
check("T2 inside one zone: a signal trace", link(preview, "Loop diuretics", "Hypokalaemia")?.kind == 0)
check("T2 between zones of one processor", link(preview, "Femoral hernia", "Inguinal canal")?.kind == 1)
check("T2 to an edge finger: a bus trace", link(preview, "Pericarditis", "STEMI")?.kind == 2)
let buses: [ThemeLink] = preview.links.filter { $0.kind == 4 }
check("T2 one bus per module", buses.count == 3, "\(buses.count)")
check("T2 each bus runs from a chip to the module under it",
      buses.allSatisfy { preview.bodies[$0.b].parent == $0.a && preview.bodies[$0.a].rank >= preview.bodies[$0.b].rank })
let ledRank: Int = CircuitRole.led.rank
check("T2 LEDs only ever receive", CircuitRole.allCases.filter { $0 != .led && $0 != .pad }.allSatisfy { $0.rank > ledRank })
check("T2 edge fingers feed current in", CircuitRole.edgePin.rank > CircuitRole.capacitor.rank)
check("T2 ranks fit the link coding (0...7)", CircuitRole.allCases.allSatisfy { $0.rank >= 0 && $0.rank <= 7 })
check("T2 every note link kept", preview.links.filter { $0.kind != 4 }.count == 35)

// MARK: T3 the ladder, footprints and sub-boards

check("T3 preview ladder", ladderProblems(preview).isEmpty, "\(ladderProblems(preview))")
check("T3 preview: no footprints overlap", footprintOverlaps(preview).isEmpty, "\(footprintOverlaps(preview))")
check("T3 preview: sub-boards apart, parts on their own", patchProblems(preview).isEmpty, "\(patchProblems(preview))")
check("T3 preview: flat, still and on the board", flatProblems(preview).isEmpty, "\(flatProblems(preview))")
check("T3 preview: inside the envelope", envelopeHolds(preview).isEmpty, "\(envelopeHolds(preview))")
var ladderBad: [String] = []
var overlapBad: [String] = []
var patchBad: [String] = []
var flatBad: [String] = []
for seed in 1...200 {
    let input: UniverseInput = randomVault(UInt64(seed), maxNotes: 60, maxFolders: 12)
    let plan: ThemePlan = GraphCircuit.plan(input)
    let problems: [String] = ladderProblems(plan)
    if !problems.isEmpty && ladderBad.count < 3 { ladderBad.append("seed \(seed): \(problems)") }
    let o: [String] = footprintOverlaps(plan)
    if !o.isEmpty && overlapBad.count < 3 { overlapBad.append("seed \(seed): \(o)") }
    let p: [String] = patchProblems(plan)
    if !p.isEmpty && patchBad.count < 3 { patchBad.append("seed \(seed): \(p)") }
    let f: [String] = flatProblems(plan) + envelopeHolds(plan)
    if !f.isEmpty && !plan.bodies.isEmpty && flatBad.count < 3 { flatBad.append("seed \(seed): \(f)") }
    let planned: Int = plan.bodies.filter { !roleOf($0).isContainer }.count
    if planned != input.notes.count && ladderBad.count < 3 { ladderBad.append("seed \(seed): lost notes") }
}
check("T3 200 random vaults keep the ladder", ladderBad.isEmpty, "\(ladderBad)")
check("T3 200 random vaults: no footprints overlap", overlapBad.isEmpty, "\(overlapBad)")
check("T3 200 random vaults: sub-boards apart", patchBad.isEmpty, "\(patchBad)")
check("T3 200 random vaults: flat, on the board, in the envelope", flatBad.isEmpty, "\(flatBad)")

// MARK: T4 the same notes, the same board

let again: ThemePlan = GraphCircuit.plan(previewInput())
check("T4 planned twice, identical", again.bodies == preview.bodies && again.links == preview.links
      && again.patches == preview.patches && again.ground == preview.ground)
let base: UniverseInput = previewInput()
let shuffled = UniverseInput(notes: base.notes.reversed(), folders: base.folders.reversed(),
                             edges: base.edges.reversed(), seedByName: true)
check("T4 in any order, identical", GraphCircuit.plan(shuffled).bodies == preview.bodies)

// MARK: T5 the board's shape

var offAxis: [String] = []
for b in preview.bodies where roleOf(b) == .module {
    let d: SIMD2<Double> = onBoard(b.home) - onBoard(preview.bodies[b.parent].home)
    let square: Bool = abs(d.x) < 1e-4 || abs(d.y) < 1e-4 || abs(abs(d.x) - abs(d.y)) < 1e-4
    if !square { offAxis.append(b.title) }
}
check("T5 every module sits square (or at 45°) off its parent chip", offAxis.isEmpty, "\(offAxis)")
var systemsBad: [String] = []
for (i, b) in preview.bodies.enumerated() where roleOf(b).isContainer && preview.systems[i].isEmpty {
    systemsBad.append(b.title)
}
check("T5 every chip has a zone to fly in to", systemsBad.isEmpty, "\(systemsBad)")
let zoneReach: Float = preview.systems[examples].map(length3).max() ?? 0
let anatomyFar: Float = length3(preview.bodies[anatomy].home - preview.bodies[examples].home)
check("T5 a processor's fly-in holds its modules", zoneReach > anatomyFar, "\(zoneReach) vs \(anatomyFar)")
if let g = preview.ground {
    let width: Float = g.z - g.x
    let height: Float = g.w - g.y
    check("T5 the motherboard stands tall, like the phone", height > width * 0.8, "\(width) x \(height)")
    let fingersOnEdge: Bool = preview.bodies.filter { roleOf($0) == .edgePin }.allSatisfy { b in
        abs(footprint(b).low.y - Double(g.y)) < 1e-4
    }
    check("T5 edge fingers sit on the board's bottom edge", fingersOnEdge)
}
let orientedOK: Bool = preview.bodies.filter { roleOf($0).isOriented && roleOf($0) != .smd }.allSatisfy { b in
    let d: SIMD2<Double> = onBoard(b.home) - onBoard(preview.bodies[b.parent].home)
    let vertical: Bool = dot3(b.axis, boardForward) > 0.5
    return vertical ? abs(d.y) >= abs(d.x) - 0.05 : abs(d.x) >= abs(d.y) - 0.05
}
check("T5 resistors and headers point at their chip", orientedOK)

// MARK: T6 edge cases

let top1: UUID = fixedID(5001)
let homeOnly: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: (1...8).map { UniverseNote(id: fixedID($0), title: "N\($0)", isPage: $0 % 3 == 0, folder: nil,
                                      words: 20 * $0, created: 0) },
    folders: [], edges: [UniverseEdge(a: fixedID(1), b: fixedID(2))], seedByName: false))
check("T6 no folders: one system chip first", homeOnly.bodies.first?.role == CircuitRole.soc.rawValue
      && homeOnly.bodies.first?.id == GraphUniverse.homeID)
check("T6 no folders: every note on it", homeOnly.bodies.dropFirst().allSatisfy { $0.parent >= 0 })
check("T6 no folders: summary", homeOnly.summary.hasPrefix("1 system chip"), homeOnly.summary)
check("T6 no folders: no overlaps", footprintOverlaps(homeOnly).isEmpty)

let fa: UUID = fixedID(6001)
let fb: UUID = fixedID(6002)
let cyc: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "x", isPage: false, folder: fa, words: 5, created: 0)],
    folders: [UniverseFolder(id: fa, name: "A", parent: fb), UniverseFolder(id: fb, name: "B", parent: fa)],
    edges: [], seedByName: false))
check("T6 a folder cycle is cut into one processor and one module",
      titles(cyc, .processor).count == 1 && titles(cyc, .module).count == 1, cyc.summary)

var deepFolders: [UniverseFolder] = []
for k in 0..<10 {
    let parent: UUID? = k == 0 ? nil : fixedID(7000 + k - 1)
    deepFolders.append(UniverseFolder(id: fixedID(7000 + k), name: "D\(k)", parent: parent))
}
let deep: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "bottom", isPage: true, folder: fixedID(7009), words: 3000,
                         created: 0)],
    folders: deepFolders, edges: [], seedByName: false))
check("T6 ten deep: the ladder holds", ladderProblems(deep).isEmpty, "\(ladderProblems(deep))")
check("T6 ten deep: no overlaps", footprintOverlaps(deep).isEmpty && patchProblems(deep).isEmpty,
      "\(footprintOverlaps(deep)) \(patchProblems(deep))")

let emptyPlan: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: [], folders: [UniverseFolder(id: top1, name: "Empty", parent: nil)], edges: [], seedByName: false))
check("T6 an empty folder is a small processor", emptyPlan.bodies.count == 1
      && emptyPlan.bodies.first?.sphere == 0.40 && emptyPlan.ground != nil)
check("T6 nothing at all plans nothing", GraphCircuit.plan(UniverseInput(notes: [], folders: [], edges: [],
                                                                      seedByName: false)).bodies.isEmpty)

var looseNotes: [UniverseNote] = [UniverseNote(id: fixedID(1), title: "anchor", isPage: true, folder: top1,
                                               words: 100, created: 0)]
var looseEdges: [UniverseEdge] = []
for k in 2...41 {
    looseNotes.append(UniverseNote(id: fixedID(k), title: "L\(k)", isPage: false, folder: nil, words: 10,
                                   created: Double(k)))
    if k % 2 == 0 { looseEdges.append(UniverseEdge(a: fixedID(1), b: fixedID(k))) }
}
let loosePlan: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: looseNotes, folders: [UniverseFolder(id: top1, name: "Top", parent: nil)], edges: looseEdges,
    seedByName: false))
check("T6 forty loose: twenty edge fingers and twenty pads",
      titles(loosePlan, .edgePin).count == 20 && titles(loosePlan, .pad).count == 20, loosePlan.summary)
check("T6 forty loose: none overlap", footprintOverlaps(loosePlan).isEmpty, "\(footprintOverlaps(loosePlan))")
check("T6 forty loose: all on the board", flatProblems(loosePlan).isEmpty, "\(flatProblems(loosePlan))")
let anchorY: Double = onBoard(loosePlan.bodies[0].home).y
check("T6 edge fingers below the chips, pads above",
      loosePlan.bodies.filter { roleOf($0) == .edgePin }.allSatisfy { onBoard($0.home).y < anchorY }
      && loosePlan.bodies.filter { roleOf($0) == .pad }.allSatisfy { onBoard($0.home).y > anchorY })

// a diode: an idea whose links all run into one other folder
let fx: UUID = fixedID(8001)
let fy: UUID = fixedID(8002)
let diodePlan: ThemePlan = GraphCircuit.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "valve", isPage: false, folder: fx, words: 80, created: 0),
            UniverseNote(id: fixedID(2), title: "far page", isPage: true, folder: fy, words: 80, created: 1),
            UniverseNote(id: fixedID(3), title: "far idea", isPage: false, folder: fy, words: 80, created: 2)],
    folders: [UniverseFolder(id: fx, name: "X", parent: nil), UniverseFolder(id: fy, name: "Y", parent: nil)],
    edges: [UniverseEdge(a: fixedID(1), b: fixedID(2)), UniverseEdge(a: fixedID(1), b: fixedID(3)),
            UniverseEdge(a: fixedID(3), b: fixedID(2))],
    seedByName: false))
check("T6 an idea wired only into one other folder is a diode", titles(diodePlan, .diode) == ["valve"],
      diodePlan.summary)

// MARK: T7 scale

let started: Date = Date()
let big: ThemePlan = GraphCircuit.plan(randomVault(300, maxNotes: 300, maxFolders: 30, exact: true))
let took: Double = Date().timeIntervalSince(started)
check("T7 300 notes: every note planned", big.bodies.filter { !roleOf($0).isContainer }.count == 300)
check("T7 300 notes: planned in under 2 s", took < 2, "\(took) s")
check("T7 300 notes: the ladder holds", ladderProblems(big).isEmpty, "\(ladderProblems(big))")
check("T7 300 notes: no overlaps", footprintOverlaps(big).isEmpty && patchProblems(big).isEmpty,
      "\(footprintOverlaps(big)) \(patchProblems(big))")
check("T7 300 notes: on the board, in the envelope", flatProblems(big).isEmpty && envelopeHolds(big).isEmpty)
var crowdFolder: [UniverseNote] = []
for k in 1...300 {
    crowdFolder.append(UniverseNote(id: fixedID(k), title: "C\(k)", isPage: k % 4 == 0, folder: top1,
                                    words: 30 * (k % 40), created: Double(k)))
}
let crowdStart: Date = Date()
let crowd: ThemePlan = GraphCircuit.plan(UniverseInput(notes: crowdFolder,
                                                       folders: [UniverseFolder(id: top1, name: "One", parent: nil)],
                                                       edges: [], seedByName: false))
let crowdTook: Double = Date().timeIntervalSince(crowdStart)
check("T7 300 notes in one folder: under 2 s, no overlaps", crowdTook < 2 && footprintOverlaps(crowd).isEmpty,
      "\(crowdTook) s")

// MARK: T8 the theme choice

check("T8 Circuit is offered", GraphTheme.circuit.isReady && GraphTheme.offered.contains(.circuit))
check("T8 Circuit is kept", GraphTheme.stored("circuit") == .circuit)
check("T8 the menu's order: Space, Neurons, Circuit", GraphTheme.offered == [.space, .neurons, .circuit])
check("T8 the Circuit's own words", GraphTheme.circuit.legendTitle == "What the parts mean"
      && GraphTheme.circuit.cardText.contains("processors"))

// MARK: T9 routed traces

let board = GraphLinkBoard(right: boardRight, forward: boardForward, normal: boardNormal)

/// A route's samples, as the ribbon writer takes them.
func samples(_ route: GraphLinkRoute, _ n: Int, grow: Float = 1) -> [SIMD3<Float>] {
    var path = GraphLinkPath(start: SIMD3<Float>(0, 0, 0), end: SIMD3<Float>(0, 0, 0))
    path.route = route
    path.grow = grow
    var points: [SIMD3<Float>] = []
    var lengths: [Float] = []
    GraphLinkCurve.sample(path, count: n, points: &points, lengths: &lengths)
    return Array(points.prefix(n + 1))
}

func boardDir(_ v: SIMD3<Float>) -> SIMD2<Float> {
    SIMD2<Float>(dot3(v, boardRight), dot3(v, boardForward))
}

func angle(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    let la: Float = (a * a).sum().squareRoot()
    let lb: Float = (b * b).sum().squareRoot()
    guard la > 1e-6, lb > 1e-6 else { return 0 }
    let c: Float = min(max((a * b).sum() / (la * lb), -1), 1)
    return acos(c) * 180 / Float.pi
}

var routeBad: [String] = []
var dice = Dice(state: 77)
var worstTurn40: Float = 0
var worstTurn20: Float = 0
for k in 0..<400 {
    let ax: Float = Float(dice.unit() * 8 - 4)
    let ay: Float = Float(dice.unit() * 8 - 4)
    let bx: Float = Float(dice.unit() * 8 - 4)
    let by: Float = Float(dice.unit() * 8 - 4)
    let a3: SIMD3<Float> = boardRight * ax + boardForward * ay
    let b3: SIMD3<Float> = boardRight * bx + boardForward * by
    let trimA: Float = Float(0.1 + dice.unit() * 0.5)
    let trimB: Float = Float(0.1 + dice.unit() * 0.5)
    let route = GraphLinkRoute(from: a3, to: b3, board: board, trimA: trimA, trimB: trimB, seed: k)
    let fine: [SIMD3<Float>] = samples(route, 400)
    // flat on the board, just above it
    for p in fine where abs(dot3(p, boardNormal) - board.lift) > 1e-4 {
        if routeBad.count < 4 { routeBad.append("route \(k) off the board") }
        break
    }
    // only straights along the board's axes and 45° diagonals, away from
    // the corners: each fine step's heading is a multiple of 45° or turning
    var headings: [Float] = []
    for j in 1..<fine.count {
        let d: SIMD2<Float> = boardDir(fine[j] - fine[j - 1])
        guard (d * d).sum() > 1e-10 else { continue }
        let deg: Float = atan2(d.y, d.x) * 180 / Float.pi
        headings.append(deg)
    }
    let straight: Int = headings.filter { h in
        let m: Float = (h / 45).rounded() * 45
        return abs(h - m) < 0.05
    }.count
    if Float(straight) < Float(headings.count) * 0.6 && route.to - route.from > 2 && routeBad.count < 4 {
        routeBad.append("route \(k): only \(straight) of \(headings.count) steps square or 45°")
    }
    // continuous: no jump between neighbouring fine samples
    let whole: Float = route.total
    for j in 1..<fine.count where length3(fine[j] - fine[j - 1]) > whole * 0.05 + 0.02 {
        if routeBad.count < 4 { routeBad.append("route \(k) jumps") }
        break
    }
    // trimmed clear of its ends
    let first: SIMD2<Float> = boardDir(fine[0]) - boardDir(a3)
    let last: SIMD2<Float> = boardDir(fine[fine.count - 1]) - boardDir(b3)
    let firstGap: Float = (first * first).sum().squareRoot()
    let lastGap: Float = (last * last).sum().squareRoot()
    if route.total > (trimA + trimB) * 2.3 && (firstGap < trimA * 0.5 || lastGap < trimB * 0.5) && routeBad.count < 4 {
        routeBad.append("route \(k) not trimmed: \(firstGap) \(lastGap)")
    }
    // smooth at the Graphics budget's sample counts: no sharp turn
    for (n, worst) in [(40, 0), (20, 1)] {
        let pts: [SIMD3<Float>] = samples(route, n)
        var turn: Float = 0
        for j in 1..<(pts.count - 1) {
            turn = max(turn, angle(boardDir(pts[j] - pts[j - 1]), boardDir(pts[j + 1] - pts[j])))
        }
        if route.total > 0.8 {
            if worst == 0 { worstTurn40 = max(worstTurn40, turn) } else { worstTurn20 = max(worstTurn20, turn) }
        }
    }
    // grown part: a prefix of the same path
    let half: [SIMD3<Float>] = samples(route, 40, grow: 0.5)
    if !half.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) && routeBad.count < 4 {
        routeBad.append("route \(k) half-grown not finite")
    }
}
check("T9 400 traces: flat, square or 45°, continuous, trimmed", routeBad.isEmpty, "\(routeBad)")
check("T9 at 40 points every corner is round (no turn over 25°)", worstTurn40 <= 25, "\(worstTurn40)°")
check("T9 at 20 points no turn over 45° (never a kink sharper than the corner)", worstTurn20 <= 45,
      "\(worstTurn20)°")
let same = GraphLinkRoute(from: boardRight, to: boardRight, board: board, trimA: 0.2, trimB: 0.2, seed: 3)
check("T9 a trace with both ends together is finite",
      samples(same, 20).allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
let straightRoute = GraphLinkRoute(from: SIMD3<Float>(0, 0, 0), to: boardRight * 5, board: board, trimA: 0,
                                   trimB: 0, seed: 1)
check("T9 a trace along one axis runs nearly straight", abs(straightRoute.total - 5) < 0.3, "\(straightRoute.total)")
let tallA: SIMD3<Float> = boardNormal * 0.4
let raised = GraphLinkRoute(from: tallA, to: boardRight * 3, board: board, trimA: 0, trimB: 0, seed: 2)
let raisedPts: [SIMD3<Float>] = samples(raised, 20)
check("T9 a lifted end eases down to the board",
      abs(dot3(raisedPts[0], boardNormal) - 0.4 - board.lift) < 1e-3
      && abs(dot3(raisedPts[20], boardNormal) - board.lift) < 1e-3)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
