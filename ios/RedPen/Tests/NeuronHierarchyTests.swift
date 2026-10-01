// The Neurons theme (GraphNeurons): the ideas' hierarchy as a nervous
// system, laid out the way a pathway runs from the brain outward.
//
// Top-level folders are brain regions, folders inside them relays down the
// pathway, pages large neurons, ideas interneurons, short one-link ideas
// glia hugging their neuron, bridging ideas commissural neurons, loose notes
// receptors (linked) or microglia (not). None of this needs a screen, so it
// is all checked here: the roles the design preview must show, the size
// ladder over hundreds of random vaults, that the same notes always give the
// same picture, that no two cells ever meet while they drift, that every
// pathway runs outward, the links' kinds, and the edge cases (cycles, deep
// nesting, empty folders, no folders at all, many loose notes).
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphNeuronImpulses.swift and GraphTheme.swift (Foundation only). The design preview's notes are the
// same copy CosmicHierarchyTests uses.
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

func titles(_ plan: ThemePlan, _ role: NeuronRole) -> Set<String> {
    Set(plan.bodies.filter { $0.role == role.rawValue }.map(\.title))
}

func roleOf(_ body: ThemeBody) -> NeuronRole {
    NeuronRole(rawValue: body.role) ?? .interneuron
}

func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    let sum: Float = (d * d).sum()
    return sum.squareRoot()
}

func dot3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    (a * b).sum()
}

/// Whether one of the pair is a glial cell on the other, or both glia on
/// the same neuron: those sit inside each other's reach by design.
func family(_ plan: ThemePlan, _ i: Int, _ j: Int) -> Bool {
    let a: ThemeBody = plan.bodies[i]
    let b: ThemeBody = plan.bodies[j]
    let ga: Bool = roleOf(a) == .glia
    let gb: Bool = roleOf(b) == .glia
    if ga && a.parent == j { return true }
    if gb && b.parent == i { return true }
    return ga && gb && a.parent == b.parent
}

/// Pairs whose solid bodies meet at some time in 0...`upTo` s.
func overlaps(_ plan: ThemePlan, upTo: Double = 120, step: Double = 3) -> [String] {
    var bad: [String] = []
    var t: Double = 0
    let n: Int = plan.bodies.count
    while t <= upTo {
        let at: [SIMD3<Float>] = (0..<n).map { plan.position(of: $0, time: t) }
        for x in 0..<n {
            for y in (x + 1)..<n {
                let limit: Float = plan.bodies[x].sphere + plan.bodies[y].sphere
                let gap: Float = distance(at[x], at[y])
                if gap < limit && bad.count < 5 {
                    bad.append("\(plan.bodies[x].title)/\(plan.bodies[y].title) t=\(t) d=\(gap) < \(limit)")
                }
            }
        }
        t += step
    }
    return bad
}

/// Pairs whose dendrites' reach overlaps at rest (glia and their neuron
/// excepted).
func reachOverlaps(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let n: Int = plan.bodies.count
    for x in 0..<n {
        for y in (x + 1)..<n where !family(plan, x, y) {
            let a: ThemeBody = plan.bodies[x]
            let b: ThemeBody = plan.bodies[y]
            let ra: Float = a.sphere * Float(roleOf(a).reach)
            let rb: Float = b.sphere * Float(roleOf(b).reach)
            let gap: Float = distance(a.home, b.home)
            if gap < ra + rb - 1e-4 && bad.count < 5 {
                bad.append("\(a.title)/\(b.title) d=\(gap) < \(ra + rb)")
            }
        }
    }
    return bad
}

/// The plan's rules that hold for any vault.
func ladderProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let bodies: [ThemeBody] = plan.bodies
    let containers: [ThemeBody] = bodies.filter { roleOf($0).isContainer }
    let notes: [ThemeBody] = bodies.filter { !roleOf($0).isContainer }
    let smallestContainer: Float = containers.map(\.sphere).min() ?? 99
    let biggestNote: Float = notes.map(\.sphere).max() ?? 0
    if !containers.isEmpty && !notes.isEmpty && smallestContainer <= biggestNote {
        bad.append("container \(smallestContainer) <= note \(biggestNote)")
    }
    for (i, b) in bodies.enumerated() {
        if b.parent >= i { bad.append("\(b.title) before its parent") }
        guard roleOf(b) == .relay else { continue }
        let up: ThemeBody = bodies[b.parent]
        if !roleOf(up).isContainer { bad.append("\(b.title)'s parent is not a container") }
        if b.sphere >= up.sphere { bad.append("\(b.title) \(b.sphere) >= parent \(up.sphere)") }
    }
    let pyramids: [Float] = bodies.filter { roleOf($0) == .pyramidal }.map(\.sphere)
    let inters: [Float] = bodies.filter { roleOf($0) == .interneuron }.map(\.sphere)
    let glia: [Float] = bodies.filter { roleOf($0) == .glia }.map(\.sphere)
    let bridges: [Float] = bodies.filter { roleOf($0) == .commissural }.map(\.sphere)
    if let p = pyramids.min(), let q = inters.max(), p <= q { bad.append("page \(p) <= idea \(q)") }
    if let p = pyramids.min(), let q = bridges.max(), p <= q { bad.append("page \(p) <= commissural \(q)") }
    if let p = inters.min(), let q = glia.max(), p <= q { bad.append("idea \(p) <= glia \(q)") }
    for b in bodies where roleOf(b) == .glia {
        let host: ThemeBody = bodies[b.parent]
        if roleOf(host).isContainer { bad.append("glia \(b.title) on a container") }
    }
    return bad
}

/// Every body stays inside the envelope's box, at any time.
func envelopeHolds(_ plan: ThemePlan) -> [String] {
    guard !plan.envelope.isEmpty else { return ["no envelope"] }
    var low = SIMD3<Float>(repeating: 1e9)
    var high = SIMD3<Float>(repeating: -1e9)
    for p in plan.envelope {
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }
    var bad: [String] = []
    for t in stride(from: 0.0, through: 60.0, by: 5.0) {
        for i in plan.bodies.indices {
            let p: SIMD3<Float> = plan.position(of: i, time: t)
            let r: Float = plan.bodies[i].sphere
            let out: Bool = p.x - r < low.x || p.y - r < low.y || p.z - r < low.z
                || p.x + r > high.x || p.y + r > high.y || p.z + r > high.z
            if out && bad.count < 3 { bad.append("\(plan.bodies[i].title) at t=\(t)") }
        }
    }
    return bad
}

// MARK: T1 the design preview's cells

let preview: ThemePlan = GraphNeurons.plan(previewInput())
check("T1 two regions", titles(preview, .region) == ["Cardiology", "Examples"], "\(titles(preview, .region))")
check("T1 three relays", titles(preview, .relay) == ["Inguinal", "Femoral", "Anatomy"], "\(titles(preview, .relay))")
let expectedPyramids: Set<String> = [
    "Heart failure", "Groin hernia", "Inguinal canal", "Femoral hernia", "Indirect inguinal hernia",
    "Direct inguinal hernia", "Acute coronary syndrome", "Atrial fibrillation", "Murmurs"
]
check("T1 nine large neurons", titles(preview, .pyramidal) == expectedPyramids, "\(titles(preview, .pyramidal))")
let expectedInter: Set<String> = [
    "Inferior epigastric vessels", "Internal ring test", "Canal boundaries", "Spermatic cord coverings",
    "Loop diuretics", "ACE inhibitors", "Hypokalaemia", "NSTEMI", "Troponin", "STEMI", "Heart sounds", "Syncope"
]
check("T1 twelve interneurons", titles(preview, .interneuron) == expectedInter, "\(titles(preview, .interneuron))")
let expectedGlia: [String: String] = [
    "Hernia repair": "Groin hernia", "LA/PM mnemonic": "Canal boundaries", "Femoral canal": "Femoral hernia",
    "Saphena varix": "Femoral hernia", "BNP": "Heart failure", "CHA2DS2-VASc": "Atrial fibrillation"
]
var foundGlia: [String: String] = [:]
for body in preview.bodies where body.role == NeuronRole.glia.rawValue {
    foundGlia[body.title] = preview.bodies[body.parent].title
}
check("T1 six glia on their neurons", foundGlia == expectedGlia, "\(foundGlia)")
check("T1 the bridging idea is commissural", titles(preview, .commissural) == ["Expansile cough impulse"],
      "\(titles(preview, .commissural))")
check("T1 both loose notes are receptors", titles(preview, .receptor) == ["Richter's hernia", "Pericarditis"],
      "\(titles(preview, .receptor))")
check("T1 no microglia", titles(preview, .microglia).isEmpty)
let expectedSummary: String = "2 regions, 3 relays, 9 neurons, 12 interneurons, 6 glia, 1 commissural neuron, 2 receptors"
check("T1 summary", preview.summary == expectedSummary, preview.summary)
let anatomy: Int = bodyNamed(preview, "Anatomy") ?? -1
let inguinal: Int = bodyNamed(preview, "Inguinal") ?? -1
let examples: Int = bodyNamed(preview, "Examples") ?? -1
check("T1 Anatomy relays from Inguinal, Inguinal from Examples",
      anatomy >= 0 && preview.bodies[anatomy].parent == inguinal && preview.bodies[inguinal].parent == examples)
check("T1 regions listed", preview.regions.map { preview.bodies[$0].title }.sorted() == ["Cardiology", "Examples"])
check("T1 a region is its own region", preview.bodies[examples].region == examples)
check("T1 Anatomy's region is Examples", anatomy >= 0 && preview.bodies[anatomy].region == examples)

// MARK: T2 links

func link(_ plan: ThemePlan, _ a: String, _ b: String) -> ThemeLink? {
    guard let i = bodyNamed(plan, a), let j = bodyNamed(plan, b) else { return nil }
    return plan.links.first { ($0.a == i && $0.b == j) || ($0.a == j && $0.b == i) }
}

check("T2 a glial cell's link is hidden", link(preview, "BNP", "Heart failure")?.kind == 3)
check("T2 inside one cluster: local", link(preview, "Loop diuretics", "Hypokalaemia")?.kind == 0)
let projection: ThemeLink? = link(preview, "Femoral hernia", "Inguinal canal")
check("T2 between clusters of one region: a projection round the region",
      projection?.kind == 1 && projection?.centre == examples, "\(String(describing: projection))")
check("T2 to a loose note: a far tract", link(preview, "Pericarditis", "STEMI")?.kind == 2)
let pathways: [ThemeLink] = preview.links.filter { $0.kind == 4 }
check("T2 one pathway per relay", pathways.count == 3, "\(pathways.count)")
let pathwayDown: Bool = pathways.allSatisfy { preview.bodies[$0.b].parent == $0.a }
check("T2 each pathway runs from a container to the one inside it", pathwayDown)
let sendsDown: Bool = pathways.allSatisfy { preview.bodies[$0.a].rank >= preview.bodies[$0.b].rank }
check("T2 impulses run down the pathway", sendsDown)
let receptor: Int = bodyNamed(preview, "Richter's hernia") ?? -1
let femoral: Int = bodyNamed(preview, "Femoral hernia") ?? -1
check("T2 a receptor sends inward", receptor >= 0 && femoral >= 0
      && preview.bodies[receptor].rank > preview.bodies[femoral].rank)
let noteLinks: Int = preview.links.filter { $0.kind != 4 }.count
check("T2 every note link kept", noteLinks == 35, "\(noteLinks)")

// MARK: T3 the ladder, overlaps and the envelope

check("T3 preview ladder", ladderProblems(preview).isEmpty, "\(ladderProblems(preview))")
check("T3 preview: no cells meet as they drift", overlaps(preview).isEmpty, "\(overlaps(preview))")
check("T3 preview: dendrites clear at rest", reachOverlaps(preview).isEmpty, "\(reachOverlaps(preview))")
check("T3 preview: inside the envelope", envelopeHolds(preview).isEmpty, "\(envelopeHolds(preview))")
var ladderBad: [String] = []
var reachBad: [String] = []
var meetBad: [String] = []
for seed in 1...200 {
    let input: UniverseInput = randomVault(UInt64(seed), maxNotes: 60, maxFolders: 12)
    let plan: ThemePlan = GraphNeurons.plan(input)
    let problems: [String] = ladderProblems(plan)
    if !problems.isEmpty && ladderBad.count < 3 { ladderBad.append("seed \(seed): \(problems)") }
    let reach: [String] = reachOverlaps(plan)
    if !reach.isEmpty && reachBad.count < 3 { reachBad.append("seed \(seed): \(reach)") }
    if seed % 10 == 0 {
        let meet: [String] = overlaps(plan, upTo: 60, step: 6)
        if !meet.isEmpty && meetBad.count < 3 { meetBad.append("seed \(seed): \(meet)") }
    }
    let planned: Int = plan.bodies.filter { !roleOf($0).isContainer }.count
    if planned != input.notes.count && ladderBad.count < 3 { ladderBad.append("seed \(seed): lost notes") }
}
check("T3 200 random vaults keep the ladder", ladderBad.isEmpty, "\(ladderBad)")
check("T3 200 random vaults: dendrites clear at rest", reachBad.isEmpty, "\(reachBad)")
check("T3 20 random vaults: no cells meet as they drift", meetBad.isEmpty, "\(meetBad)")

// MARK: T4 the same notes, the same picture

let again: ThemePlan = GraphNeurons.plan(previewInput())
check("T4 planned twice, identical", again.bodies == preview.bodies && again.links == preview.links)
let base: UniverseInput = previewInput()
let shuffled = UniverseInput(notes: base.notes.reversed(), folders: base.folders.reversed(),
                             edges: base.edges.reversed(), seedByName: true)
let reordered: ThemePlan = GraphNeurons.plan(shuffled)
check("T4 in any order, identical", reordered.bodies == preview.bodies)

// MARK: T5 the pathway runs outward

var inward: [String] = []
for (i, b) in preview.bodies.enumerated() where roleOf(b) == .relay {
    let up: ThemeBody = preview.bodies[b.parent]
    let out: Float = dot3(b.home - up.home, up.axis)
    if out <= 0 { inward.append(b.title) }
    _ = i
}
check("T5 every relay stands out along its parent's pathway", inward.isEmpty, "\(inward)")
var systemsBad: [String] = []
for (i, b) in preview.bodies.enumerated() where roleOf(b).isContainer {
    let points: [SIMD3<Float>] = preview.systems[i]
    if points.isEmpty { systemsBad.append(b.title) }
}
check("T5 every container has a system to fly in to", systemsBad.isEmpty, "\(systemsBad)")
let flyExamples: [SIMD3<Float>] = preview.systems[examples]
let anatomyFar: Float = distance(preview.bodies[anatomy].home, preview.bodies[examples].home)
let reachExamples: Float = flyExamples.map { ($0 * $0).sum().squareRoot() }.max() ?? 0
check("T5 a region's fly-in holds its whole pathway", reachExamples > anatomyFar, "\(reachExamples) vs \(anatomyFar)")

// MARK: T6 edge cases

let top1: UUID = fixedID(5001)
let homeOnly: ThemePlan = GraphNeurons.plan(UniverseInput(
    notes: (1...8).map { UniverseNote(id: fixedID($0), title: "N\($0)", isPage: $0 % 3 == 0, folder: nil,
                                      words: 20 * $0, created: 0) },
    folders: [], edges: [UniverseEdge(a: fixedID(1), b: fixedID(2))], seedByName: false))
check("T6 no folders: one brainstem first", homeOnly.bodies.first?.role == NeuronRole.brainstem.rawValue
      && homeOnly.bodies.first?.id == GraphUniverse.homeID)
check("T6 no folders: every note in it", homeOnly.bodies.dropFirst().allSatisfy { $0.parent >= 0 })
check("T6 no folders: summary", homeOnly.summary.hasPrefix("1 brainstem"), homeOnly.summary)

// a cycle: A in B, B in A
let fa: UUID = fixedID(6001)
let fb: UUID = fixedID(6002)
let cyc: ThemePlan = GraphNeurons.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "x", isPage: false, folder: fa, words: 5, created: 0)],
    folders: [UniverseFolder(id: fa, name: "A", parent: fb), UniverseFolder(id: fb, name: "B", parent: fa)],
    edges: [], seedByName: false))
check("T6 a folder cycle is cut into one region and one relay",
      titles(cyc, .region).count == 1 && titles(cyc, .relay).count == 1, cyc.summary)

// ten deep, one note at the bottom
var deepFolders: [UniverseFolder] = []
for k in 0..<10 {
    let parent: UUID? = k == 0 ? nil : fixedID(7000 + k - 1)
    deepFolders.append(UniverseFolder(id: fixedID(7000 + k), name: "D\(k)", parent: parent))
}
let deep: ThemePlan = GraphNeurons.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "bottom", isPage: true, folder: fixedID(7009), words: 3000,
                         created: 0)],
    folders: deepFolders, edges: [], seedByName: false))
check("T6 ten deep: the ladder holds", ladderProblems(deep).isEmpty, "\(ladderProblems(deep))")
check("T6 ten deep: no overlaps", overlaps(deep, upTo: 30, step: 5).isEmpty, "\(overlaps(deep, upTo: 30, step: 5))")
check("T6 ten deep: every relay stands out along its pathway",
      deep.bodies.filter { roleOf($0) == .relay }.allSatisfy { b in
          dot3(b.home - deep.bodies[b.parent].home, deep.bodies[b.parent].axis) > 0 })

let emptyPlan: ThemePlan = GraphNeurons.plan(UniverseInput(
    notes: [], folders: [UniverseFolder(id: top1, name: "Empty", parent: nil)], edges: [], seedByName: false))
check("T6 an empty folder is a small region", emptyPlan.bodies.count == 1
      && emptyPlan.bodies.first?.sphere == 0.40)
check("T6 nothing at all plans nothing", GraphNeurons.plan(UniverseInput(notes: [], folders: [], edges: [],
                                                                      seedByName: false)).bodies.isEmpty)

var looseNotes: [UniverseNote] = [UniverseNote(id: fixedID(1), title: "anchor", isPage: true, folder: top1,
                                               words: 100, created: 0)]
var looseEdges: [UniverseEdge] = []
for k in 2...41 {
    looseNotes.append(UniverseNote(id: fixedID(k), title: "L\(k)", isPage: false, folder: nil, words: 10,
                                   created: Double(k)))
    if k % 2 == 0 { looseEdges.append(UniverseEdge(a: fixedID(1), b: fixedID(k))) }
}
let loosePlan: ThemePlan = GraphNeurons.plan(UniverseInput(
    notes: looseNotes, folders: [UniverseFolder(id: top1, name: "Top", parent: nil)], edges: looseEdges,
    seedByName: false))
check("T6 forty loose: twenty receptors and twenty microglia",
      titles(loosePlan, .receptor).count == 20 && titles(loosePlan, .microglia).count == 20, loosePlan.summary)
check("T6 forty loose: none meet", overlaps(loosePlan, upTo: 60, step: 4).isEmpty,
      "\(overlaps(loosePlan, upTo: 60, step: 4))")
let brainEdge: Float = loosePlan.bodies.filter { $0.parent != -1 || roleOf($0).isContainer }
    .map { ($0.home * $0.home).sum().squareRoot() }.max() ?? 0
let looseNear: Float = loosePlan.bodies.filter { roleOf($0) == .receptor || roleOf($0) == .microglia }
    .map { ($0.home * $0.home).sum().squareRoot() }.min() ?? 0
check("T6 loose cells float at the periphery", looseNear > brainEdge * 0.8, "\(looseNear) vs \(brainEdge)")

// MARK: T7 scale

let started: Date = Date()
let big: ThemePlan = GraphNeurons.plan(randomVault(300, maxNotes: 300, maxFolders: 30, exact: true))
let took: Double = Date().timeIntervalSince(started)
let bigNotes: Int = big.bodies.filter { !roleOf($0).isContainer }.count
check("T7 300 notes: every note planned", bigNotes == 300, "\(bigNotes)")
check("T7 300 notes: planned in under 2 s", took < 2, "\(took) s")
check("T7 300 notes: the ladder holds", ladderProblems(big).isEmpty, "\(ladderProblems(big))")
check("T7 300 notes: no overlaps", overlaps(big, upTo: 40, step: 10).isEmpty, "\(overlaps(big, upTo: 40, step: 10))")
check("T7 300 notes: inside the envelope", envelopeHolds(big).isEmpty, "\(envelopeHolds(big))")

// MARK: T8 the theme choice

check("T8 Space is the default", GraphTheme.stored(nil) == .space && GraphTheme.stored("nonsense") == .space)
check("T8 Neurons is kept", GraphTheme.stored("neurons") == .neurons)
check("T8 a theme not ready yet falls back", GraphTheme.stored("circuit") == (GraphTheme.circuit.isReady ? .circuit : .space))
check("T8 the menu offers only ready themes", GraphTheme.offered.allSatisfy { $0.isReady }
      && GraphTheme.offered.first == .space)
check("T8 the themes' words are their own", Set(GraphTheme.allCases.map(\.legendTitle)).count == 3
      && GraphTheme.neurons.title == "Neurons" && GraphTheme.stored("space") == .space)

// MARK: T9 drifting

let still: GraphOrbit = .drift(base: SIMD3<Float>(1, 2, 3), amp: 0, phase: 1, rate: 1)
check("T9 no wobble without amplitude", GraphUniverse.offset(still, time: 123) == SIMD3<Float>(1, 2, 3))
let wob: GraphOrbit = .drift(base: SIMD3<Float>(0, 0, 0), amp: 0.05, phase: 0.3, rate: 0.4)
var widest: Float = 0
var moved: Bool = false
var last: SIMD3<Float> = GraphUniverse.offset(wob, time: 0)
for k in 1...400 {
    let p: SIMD3<Float> = GraphUniverse.offset(wob, time: Double(k) * 0.25)
    widest = max(widest, (p * p).sum().squareRoot())
    if distance(p, last) > 0.001 { moved = true }
    last = p
}
check("T9 a drift stays within its amplitude", widest <= 0.05 * 1.6, "\(widest)")
check("T9 a drift moves", moved)
let late: SIMD3<Float> = GraphUniverse.offset(wob, time: 2_999.5)
check("T9 a drift is fine after 50 minutes", late.x.isFinite && (late * late).sum() < 0.01)


// MARK: T10 impulses at random times

let rhythms: [NeuronImpulse.Rhythm] = (0..<64).map { NeuronImpulse.rhythm(seed: $0) }
check("T10 slots 0.9 to 2.4 s, travel 0.45 to 0.95 s",
      rhythms.allSatisfy { $0.slot >= 0.9 && $0.slot <= 2.4 && $0.travel >= 0.45 && $0.travel <= 0.95 })
check("T10 links keep their own rhythm", Set(rhythms.map(\.slot)).count > 40)
var refractory: [String] = []
var fired: Int = 0
var span: Float = 0
for seed in 0..<200 {
    let times: [Float] = NeuronImpulse.firings(seed: seed, from: 0, to: 600, rate: 0.6)
    let r: NeuronImpulse.Rhythm = NeuronImpulse.rhythm(seed: seed)
    fired += times.count
    span += 600 / r.slot
    for k in 1..<max(times.count, 1) where times[k] - times[k - 1] < 0.5 * r.slot - 0.001 {
        if refractory.count < 3 { refractory.append("seed \(seed): \(times[k - 1]) then \(times[k])") }
    }
}
check("T10 never two firings within half a slot (refractory)", refractory.isEmpty, "\(refractory)")
let share: Float = Float(fired) / span
check("T10 about the budget's share of slots fire", share > 0.5 && share < 0.7, "\(share)")
check("T10 rate 0 never fires", NeuronImpulse.firings(seed: 3, from: 0, to: 600, rate: 0).isEmpty
      && NeuronImpulse.arrivals(seed: 3, from: 0, to: 600, rate: 0, bursts: 1).isEmpty)
let starts: [Float] = (0..<40).compactMap { NeuronImpulse.firings(seed: $0, from: 0, to: 30, rate: 0.6).first }
check("T10 links do not fire in step", Set(starts.map { ($0 * 100).rounded() }).count > 30, "\(starts.count)")
// every firing lands one travel time later, seen frame by frame at 60 a second
var missed: [String] = []
for seed in [1, 7, 99, 512] {
    let r: NeuronImpulse.Rhythm = NeuronImpulse.rhythm(seed: seed)
    var landed: [Float] = []
    var t: Float = 5
    let frame: Float = 1.0 / 60.0
    while t + frame <= 61 {
        landed += NeuronImpulse.arrivals(seed: seed, from: t, to: t + frame, rate: 0.6, bursts: 0)
        t += frame
    }
    let due: [Float] = NeuronImpulse.firings(seed: seed, from: 0, to: 61, rate: 0.6).map { $0 + r.travel }
        .filter { $0 > 5.01 && $0 < t - 0.01 }
    for d in due where !landed.contains(where: { abs($0 - d) < 0.002 }) {
        if missed.count < 3 { missed.append("seed \(seed) due \(d)") }
    }
    if landed.count > due.count + 1 && missed.count < 3 { missed.append("seed \(seed): \(landed.count) for \(due.count)") }
}
check("T10 each impulse arrives once, a travel time after it fires", missed.isEmpty, "\(missed)")
var burstSeen: Bool = false
for seed in 0..<100 where !burstSeen {
    let landed: [Float] = NeuronImpulse.arrivals(seed: seed, from: 0, to: 3000, rate: 1, bursts: 0.2)
    let sorted: [Float] = landed.sorted()
    for k in 1..<max(sorted.count, 1) where abs(sorted[k] - sorted[k - 1] - NeuronImpulse.burstGap) < 0.001 {
        burstSeen = true
    }
}
check("T10 bursts arrive 0.12 s apart", burstSeen)
var agree: Bool = true
for seed in 0..<50 {
    var t: Float = 0
    while t < 30 {
        let many: Bool = !NeuronImpulse.arrivals(seed: seed, from: t, to: t + 0.05, rate: 0.6, bursts: 0.2).isEmpty
        if many != NeuronImpulse.lands(seed: seed, from: t, to: t + 0.05, rate: 0.6, bursts: 0.2) { agree = false }
        t += 0.05
    }
}
check("T10 the per-frame check agrees with the full list", agree)
check("T10 the rhythm follows the whole seed", NeuronImpulse.hash(5) == NeuronImpulse.hash(5)
      && NeuronImpulse.rhythm(seed: 1024 + 5) != NeuronImpulse.rhythm(seed: 5))

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
