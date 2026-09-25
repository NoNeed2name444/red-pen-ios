// The Circuit theme (GraphCircuit): one small board per collection (each
// top-level folder), each a closed circuit - a power rail along its top, a
// ground rail along its bottom, the folder's chip as controller, sub-folders
// as smaller chips on branches of its bus, pages as capacitors on the bus,
// ideas as LEDs in parallel branches off the page they link to and their
// linked ideas in series after them, every branch ending on the ground rail;
// loose notes as gold pads on a board's edge; links between boards through
// edge connectors and a thin bus - boards in a tidy grid on a dark bench.
//
// None of this needs a screen, so it is all checked here: the design
// preview's boards and parts; that every part lies on a closed path from
// the power rail to ground; that series and parallel follow the hierarchy;
// that current (the ranks) always runs away from the power rail; the same
// notes always give the same boards; no overlaps, flat, boards apart; edge
// cases; 300 notes in under 2 s; the words; and that every routed trace is
// one smooth piece of straights and 45 degree diagonals.
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
    plan.bodies.firstIndex { $0.title == title && $0.kind != .fixture }
}

func roleOf(_ body: ThemeBody) -> CircuitRole {
    CircuitRole(rawValue: body.role) ?? .led
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

/// A body's place on the bench.
func onBoard(_ p: SIMD3<Float>) -> SIMD2<Double> {
    SIMD2<Double>(Double(dot3(p, boardRight)), Double(dot3(p, boardForward)))
}

func footprint(_ body: ThemeBody) -> CircuitRect {
    let f: SIMD2<Double> = roleOf(body).foot * Double(body.sphere)
    return CircuitRect(c: onBoard(body.home), h: f)
}

/// Parts (not wiring) whose footprints overlap.
func footprintOverlaps(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let parts: [Int] = plan.bodies.indices.filter { plan.bodies[$0].kind != .fixture }
    let rects: [CircuitRect] = parts.map { footprint(plan.bodies[$0]) }
    for x in rects.indices {
        for y in (x + 1)..<rects.count where !rects[x].clears(rects[y], gap: 0.0001) {
            if bad.count < 5 { bad.append("\(plan.bodies[parts[x]].title)/\(plan.bodies[parts[y]].title)") }
        }
    }
    return bad
}

/// The board (a top chip's patch) on the bench.
func boardOf(_ plan: ThemePlan, _ i: Int) -> CircuitRect {
    let p: SIMD4<Float> = plan.patches[i]
    let at: SIMD2<Double> = onBoard(plan.bodies[i].home)
    return CircuitRect(c: at + SIMD2<Double>(Double(p.x), Double(p.y)), h: SIMD2<Double>(Double(p.z), Double(p.w)))
}

/// Each body's board (its top chip), by walking up.
func topOf(_ plan: ThemePlan, _ i: Int) -> Int {
    var at: Int = i
    var steps: Int = 0
    while plan.bodies[at].parent >= 0 && steps < plan.bodies.count {
        at = plan.bodies[at].parent
        steps += 1
    }
    return at
}

/// The circuit as a directed graph: the wiring (kinds 5 and 6, sent from
/// a) and the note links that carry current (sent from the higher rank).
func flowGraph(_ plan: ThemePlan) -> [[Int]] {
    var next = [[Int]](repeating: [], count: plan.bodies.count)
    for l in plan.links {
        if l.kind == 5 || l.kind == 6 {
            next[l.a].append(l.b)
        } else if l.kind == 0 {
            let ra: Int = plan.bodies[l.a].rank
            let rb: Int = plan.bodies[l.b].rank
            if ra > rb { next[l.a].append(l.b) } else if rb > ra { next[l.b].append(l.a) }
        }
    }
    return next
}

func reach(_ next: [[Int]], from starts: [Int]) -> Set<Int> {
    var seen = Set<Int>(starts)
    var queue: [Int] = starts
    var head: Int = 0
    while head < queue.count {
        let x: Int = queue[head]
        head += 1
        for y in next[x] where seen.insert(y).inserted { queue.append(y) }
    }
    return seen
}

/// Parts not on a closed path from a power tap to a ground tap.
func openParts(_ plan: ThemePlan) -> [String] {
    let next: [[Int]] = flowGraph(plan)
    var back = [[Int]](repeating: [], count: next.count)
    for (a, list) in next.enumerated() { for b in list { back[b].append(a) } }
    let vcc: [Int] = plan.bodies.indices.filter { plan.bodies[$0].role == CircuitRole.vcc.rawValue }
    let gnd: [Int] = plan.bodies.indices.filter { plan.bodies[$0].role == CircuitRole.ground.rawValue }
    let fromPower: Set<Int> = reach(next, from: vcc)
    let toGround: Set<Int> = reach(back, from: gnd)
    var bad: [String] = []
    for (i, b) in plan.bodies.enumerated() where b.kind != .fixture {
        if !fromPower.contains(i) || !toGround.contains(i) {
            if bad.count < 5 { bad.append(b.title + (fromPower.contains(i) ? " no ground" : " no power")) }
        }
    }
    return bad
}

/// Series and parallel against the hierarchy, from the feeds.
func topologyProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    let feeds: [Int] = plan.feeds
    guard feeds.count == plan.bodies.count else { return ["no feeds"] }
    func note(_ s: String) { if bad.count < 6 { bad.append(s) } }
    for (i, b) in plan.bodies.enumerated() {
        let f: Int = feeds[i]
        let r: CircuitRole = roleOf(b)
        switch r {
        case .processor, .soc:
            if f < 0 || roleOf(plan.bodies[f]) != .vcc { note("\(b.title) not fed from the power rail") }
        case .module:
            // from its parent chip's bus
            guard f >= 0, roleOf(plan.bodies[f]) == .bus, feeds[f] >= 0 else { note("\(b.title) no bus"); continue }
            var up: Int = feeds[f]
            while up >= 0 && roleOf(plan.bodies[up]) == .bus { up = feeds[up] }
            if up != b.parent { note("\(b.title) fed from \(up) not its parent chip \(b.parent)") }
        case .capacitor:
            // on its own folder's bus: fed by a bus tap under its chip
            guard f >= 0, roleOf(plan.bodies[f]) == .bus else { note("\(b.title) not on a bus"); continue }
        case .led:
            guard f >= 0 else { note("\(b.title) unfed"); continue }
            let fr: CircuitRole = roleOf(plan.bodies[f])
            if fr != .capacitor && fr != .led && fr != .bus { note("\(b.title) fed by \(fr)") }
            if fr != .bus && plan.bodies[f].parent != b.parent { note("\(b.title) fed across folders") }
        case .pad:
            if f < 0 || roleOf(plan.bodies[f]) != .vcc { note("\(b.title) pad not on the power rail") }
        default:
            break
        }
    }
    return bad
}

/// Current running towards the power rail on any wire or circuit link.
func backwards(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    for l in plan.links where l.kind == 5 {
        let ra: Int = plan.bodies[l.a].rank
        let rb: Int = plan.bodies[l.b].rank
        let cross: Bool = plan.bodies[l.a].role == CircuitRole.connector.rawValue
            || plan.bodies[l.b].role == CircuitRole.connector.rawValue
        if !cross && ra <= rb && bad.count < 4 { bad.append("\(plan.bodies[l.a].title)->\(plan.bodies[l.b].title)") }
    }
    for (b, f) in plan.feeds.enumerated() where f >= 0 && plan.bodies[f].rank != plan.bodies[b].rank + 1 {
        if bad.count < 4 { bad.append("feed rank \(plan.bodies[b].title)") }
    }
    return bad
}

/// Everything flat on the bench, still, inside its own board.
func flatProblems(_ plan: ThemePlan) -> [String] {
    var bad: [String] = []
    for (i, b) in plan.bodies.enumerated() {
        let h: Float = dot3(b.home, boardNormal)
        if abs(h) > 1e-4 && bad.count < 3 { bad.append("\(b.title) at height \(h)") }
        let top: Int = topOf(plan, i)
        let board: CircuitRect = boardOf(plan, top)
        let r: CircuitRect = footprint(b)
        let inside: Bool = r.low.x >= board.low.x - 1e-4 && r.low.y >= board.low.y - 1e-4
            && r.high.x <= board.high.x + 1e-4 && r.high.y <= board.high.y + 1e-4
        if !inside && bad.count < 3 { bad.append("\(b.title) off its board") }
        if length3(plan.position(of: i, time: 30) - b.home) > 1e-4 && bad.count < 3 { bad.append("\(b.title) moves") }
    }
    return bad
}

/// Boards that overlap or touch.
func boardsTouching(_ plan: ThemePlan) -> [String] {
    let tops: [Int] = plan.regions
    var bad: [String] = []
    for x in tops.indices {
        for y in (x + 1)..<tops.count where !boardOf(plan, tops[x]).clears(boardOf(plan, tops[y]), gap: 0.3) {
            bad.append("\(plan.bodies[tops[x]].title)/\(plan.bodies[tops[y]].title)")
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

func whole(_ plan: ThemePlan) -> [String] {
    openParts(plan) + topologyProblems(plan) + backwards(plan) + footprintOverlaps(plan) + flatProblems(plan)
        + boardsTouching(plan)
}

// MARK: T1 the design preview's boards

let preview: ThemePlan = GraphCircuit.plan(previewInput())
let chips: Set<String> = titles(preview, .processor)
check("T1 one board per collection: Cardiology and Examples", chips == ["Cardiology", "Examples"]
      && preview.regions.count == 2, "\(chips)")
check("T1 sub-folders are smaller chips", titles(preview, .module) == ["Inguinal", "Femoral", "Anatomy"])
check("T1 pages are capacitors", titles(preview, .capacitor).contains("Heart failure")
      && titles(preview, .capacitor).contains("Groin hernia"))
check("T1 ideas are LEDs", titles(preview, .led).contains("BNP") && titles(preview, .led).contains("LA/PM mnemonic"))
check("T1 loose notes are gold pads", titles(preview, .pad).count == 2)
let used: Set<Int> = Set(preview.bodies.map(\.role))
check("T1 only chips, capacitors, LEDs and pads (and wiring)",
      used.isSubset(of: Set(CircuitRole.allCases.map(\.rawValue))))
check("T1 the summary counts boards", preview.summary.hasPrefix("2 boards"), preview.summary)
let tags: [String] = preview.bodies.filter { roleOf($0).isContainer }.map {
    GraphCircuit.modelTag(count: $0.count, depth: $0.depth)
}
check("T1 model tags are the app's own", tags.allSatisfy { $0.hasPrefix("S") }
      && !tags.contains { $0.contains("Apple") || $0.contains("A20") || $0.contains("M5") || $0.contains("M4") },
      "\(tags)")
check("T1 the controller's tag outranks its sub-chips'",
      GraphCircuit.modelTag(count: 30, depth: 0).hasPrefix("S-") && !GraphCircuit.modelTag(count: 5, depth: 1).contains("-"))

// MARK: T2 closed circuits

check("T2 every part on a closed path from power to ground", openParts(preview).isEmpty, "\(openParts(preview))")
check("T2 series and parallel follow the hierarchy", topologyProblems(preview).isEmpty, "\(topologyProblems(preview))")
check("T2 current runs away from the power rail", backwards(preview).isEmpty, "\(backwards(preview))")
if let hf = bodyNamed(preview, "Heart failure"), let bnp = bodyNamed(preview, "BNP") {
    check("T2 an idea hangs off the page it links to", preview.feeds[bnp] == hf || preview.feeds[preview.feeds[bnp]] == hf,
          "\(preview.feeds[bnp])")
}
// two collections linked twice: two buses between their edge connectors
let pairInput = UniverseInput(notes: [
    UniverseNote(id: fixedID(800), title: "P1", isPage: true, folder: fixedID(810), words: 50, created: 0),
    UniverseNote(id: fixedID(801), title: "I1", isPage: false, folder: fixedID(810), words: 20, created: 1),
    UniverseNote(id: fixedID(802), title: "P2", isPage: true, folder: fixedID(811), words: 50, created: 2),
    UniverseNote(id: fixedID(803), title: "I2", isPage: false, folder: fixedID(811), words: 20, created: 3)],
    folders: [UniverseFolder(id: fixedID(810), name: "One", parent: nil),
              UniverseFolder(id: fixedID(811), name: "Two", parent: nil)],
    edges: [UniverseEdge(a: fixedID(800), b: fixedID(802)), UniverseEdge(a: fixedID(801), b: fixedID(803)),
            UniverseEdge(a: fixedID(800), b: fixedID(801))], seedByName: false)
let pairPlan: ThemePlan = GraphCircuit.plan(pairInput)
let crossing: [ThemeLink] = pairPlan.links.filter { $0.kind == 6 }
check("T2 links between boards run as buses between edge connectors", crossing.count == 2 && crossing.allSatisfy {
    roleOf(pairPlan.bodies[$0.a]) == .connector && roleOf(pairPlan.bodies[$0.b]) == .connector
        && topOf(pairPlan, $0.a) != topOf(pairPlan, $0.b)
} && whole(pairPlan).isEmpty, "\(crossing) \(whole(pairPlan))")
let pairHidden: [ThemeLink] = pairPlan.links.filter { $0.kind == 3 }
check("T2 each is hidden as itself", pairHidden.count == 2 && pairHidden.allSatisfy {
    topOf(pairPlan, $0.a) != topOf(pairPlan, $0.b)
})
let hidden: [ThemeLink] = preview.links.filter { $0.kind == 3 }
let inside: [ThemeLink] = preview.links.filter { $0.kind == 0 }
check("T2 links inside a board are its traces", inside.allSatisfy { topOf(preview, $0.a) == topOf(preview, $0.b) })
check("T2 every note link kept", inside.count + hidden.count == 35, "\(inside.count + hidden.count)")

// MARK: T3 layout

check("T3 no parts overlap", footprintOverlaps(preview).isEmpty, "\(footprintOverlaps(preview))")
check("T3 flat, still, each on its own board", flatProblems(preview).isEmpty, "\(flatProblems(preview))")
check("T3 boards apart on the bench", boardsTouching(preview).isEmpty, "\(boardsTouching(preview))")
check("T3 the envelope holds everything", envelopeHolds(preview).isEmpty, "\(envelopeHolds(preview))")
var railsOK: Bool = true
for t in preview.regions {
    let mine: [ThemeBar] = preview.bars.filter { $0.owner == t }
    let power: [ThemeBar] = mine.filter { $0.kind == 0 }
    let ground: [ThemeBar] = mine.filter { $0.kind == 1 }
    guard power.count == 1, let top = power.first, let low = ground.min(by: { $0.y < $1.y }) else {
        railsOK = false
        continue
    }
    let board: CircuitRect = boardOf(preview, t)
    let at: SIMD2<Double> = onBoard(preview.bodies[t].home)
    if Double(top.y) + at.y < board.high.y - 0.4 || Double(low.y) + at.y > board.low.y + 0.4 { railsOK = false }
}
check("T3 power rail along each board's top, ground along its bottom", railsOK)
let taps: [Int] = preview.bodies.indices.filter { preview.bodies[$0].role == CircuitRole.ground.rawValue }
var tapsOnRails: Bool = true
for g in taps {
    let t: Int = topOf(preview, g)
    let y: Double = onBoard(preview.bodies[g].home).y - onBoard(preview.bodies[t].home).y
    let onRail: Bool = preview.bars.contains { $0.owner == t && $0.kind == 1 && abs(Double($0.y) - y) < 1e-4 }
    if !onRail { tapsOnRails = false }
}
check("T3 every ground tap sits on a ground rail", tapsOnRails && !taps.isEmpty)
var sizesOK: Bool = true
for (i, b) in preview.bodies.enumerated() where roleOf(b) == .module {
    if b.sphere >= preview.bodies[b.parent].sphere { sizesOK = false }
    _ = i
}
let pages: [Float] = preview.bodies.filter { roleOf($0) == .capacitor }.map(\.sphere)
let ideas: [Float] = preview.bodies.filter { roleOf($0) == .led }.map(\.sphere)
let chipsMin: Float = preview.bodies.filter { roleOf($0).isContainer }.map(\.sphere).min() ?? 0
check("T3 sizes: chips > pages > ideas, sub-chips under their chip", sizesOK
      && (pages.min() ?? 1) > (ideas.max() ?? 0) && chipsMin > (pages.max() ?? 0))

// MARK: T4 the same notes, the same boards

let again: ThemePlan = GraphCircuit.plan(previewInput())
let shuffledInput: UniverseInput = {
    let i: UniverseInput = previewInput()
    return UniverseInput(notes: i.notes.reversed(), folders: i.folders.reversed(), edges: i.edges.reversed(),
                         seedByName: true)
}()
let shuffled: ThemePlan = GraphCircuit.plan(shuffledInput)
check("T4 deterministic", again.bodies == preview.bodies && again.links == preview.links && again.bars == preview.bars)
check("T4 input order does not matter", shuffled.bodies == preview.bodies && shuffled.links == preview.links)
let fixtureIDs: [UUID] = preview.bodies.filter { $0.kind == .fixture }.map(\.id)
check("T4 wiring ids are stable and unique", Set(fixtureIDs).count == fixtureIDs.count
      && fixtureIDs == again.bodies.filter { $0.kind == .fixture }.map(\.id))

// MARK: T5 random vaults

var vaultBad: [String] = []
for seed in 0..<120 {
    let input: UniverseInput = randomVault(UInt64(seed) &* 7919 &+ 3, maxNotes: 60, maxFolders: 9)
    let plan: ThemePlan = GraphCircuit.plan(input)
    let problems: [String] = whole(plan)
    if !problems.isEmpty && vaultBad.count < 4 { vaultBad.append("vault \(seed): \(problems)") }
    let noteBodies: Int = plan.bodies.filter { $0.kind == .note }.count
    if noteBodies != Set(input.notes.map(\.id)).count && vaultBad.count < 4 { vaultBad.append("vault \(seed) lost notes") }
}
check("T5 120 random vaults: closed, in order, apart, flat", vaultBad.isEmpty, "\(vaultBad)")

// MARK: T6 edge cases

check("T6 nothing: no boards", GraphCircuit.plan(UniverseInput(notes: [], folders: [], edges: [],
                                                                seedByName: false)).bodies.isEmpty)
let onlyNotes: ThemePlan = GraphCircuit.plan(UniverseInput(notes: (0..<7).map {
    UniverseNote(id: fixedID(500 + $0), title: "N\($0)", isPage: $0 == 0, folder: nil, words: 30, created: 0)
}, folders: [], edges: [UniverseEdge(a: fixedID(501), b: fixedID(502))], seedByName: false))
check("T6 no folders: one board, one chip holds every note", onlyNotes.regions.count == 1
      && titles(onlyNotes, .soc).count == 1 && whole(onlyNotes).isEmpty, "\(whole(onlyNotes))")
let emptyFolders: ThemePlan = GraphCircuit.plan(UniverseInput(notes: [UniverseNote(id: fixedID(600), title: "Loose",
    isPage: false, folder: nil, words: 5, created: 0)], folders: [UniverseFolder(id: fixedID(601), name: "A",
    parent: nil), UniverseFolder(id: fixedID(602), name: "B", parent: fixedID(601))], edges: [], seedByName: false))
check("T6 empty folders still close their loops; a loose note is a pad", whole(emptyFolders).isEmpty
      && titles(emptyFolders, .pad) == ["Loose"], "\(whole(emptyFolders))")
let cycle: ThemePlan = GraphCircuit.plan(UniverseInput(notes: [], folders: [
    UniverseFolder(id: fixedID(700), name: "X", parent: fixedID(701)),
    UniverseFolder(id: fixedID(701), name: "Y", parent: fixedID(700))], edges: [], seedByName: false))
check("T6 a folder cycle is cut", cycle.regions.count == 1 && whole(cycle).isEmpty)

// MARK: T7 scale

let top1: UUID = fixedID(20_000)
var crowdFolder: [UniverseNote] = []
var crowdEdges: [UniverseEdge] = []
for k in 0..<300 {
    crowdFolder.append(UniverseNote(id: fixedID(30_000 + k), title: "Crowd \(k)", isPage: k % 5 == 0,
                                    folder: top1, words: 40 + k, created: Double(k)))
    if k % 3 == 1 { crowdEdges.append(UniverseEdge(a: fixedID(30_000 + k), b: fixedID(30_000 + k - 1))) }
}
let crowdStart: Date = Date()
let crowd: ThemePlan = GraphCircuit.plan(UniverseInput(notes: crowdFolder,
                                                       folders: [UniverseFolder(id: top1, name: "One", parent: nil)],
                                                       edges: crowdEdges, seedByName: false))
let crowdTook: Double = Date().timeIntervalSince(crowdStart)
check("T7 300 notes in one folder: under 2 s", crowdTook < 2, "\(crowdTook) s")
check("T7 ... closed, apart, flat", whole(crowd).isEmpty, "\(whole(crowd))")
let crowdBoard: CircuitRect = boardOf(crowd, crowd.regions[0])
check("T7 ... wrapped into tiers, not one long row", crowdBoard.h.x < crowdBoard.h.y * 4, "\(crowdBoard.h)")
let many: UniverseInput = randomVault(99, maxNotes: 300, maxFolders: 12, exact: true)
let manyStart: Date = Date()
let manyPlan: ThemePlan = GraphCircuit.plan(many)
let manyTook: Double = Date().timeIntervalSince(manyStart)
check("T7 300 notes in 12 folders: under 2 s, whole", manyTook < 2 && whole(manyPlan).isEmpty,
      "\(manyTook) s \(whole(manyPlan))")

// MARK: T8 the theme choice

check("T8 Circuit is offered", GraphTheme.circuit.isReady && GraphTheme.offered.contains(.circuit))
check("T8 Circuit is kept", GraphTheme.stored("circuit") == .circuit)
check("T8 the menu's order: Space, Neurons, Circuit", GraphTheme.offered == [.space, .neurons, .circuit])
check("T8 the Circuit's own words teach how to add", GraphTheme.circuit.legendTitle == "How your circuits are built"
      && GraphTheme.circuit.cardSteps.count == 3
      && GraphTheme.circuit.cardSteps.contains { $0.contains("New folder") })
check("T8 every theme's card teaches three ways to add", GraphTheme.allCases.allSatisfy { $0.cardSteps.count == 3 })

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
