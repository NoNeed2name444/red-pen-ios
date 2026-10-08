// The Neurons theme (GraphNeurons): the ideas' folders as living cells.
//
// A top-level folder is a cell on one sheet, a folder inside it a part
// inside the cell, a folder inside that a smaller part inside the part,
// and a note the smallest thing: a page a vesicle, an idea a granule,
// inside the folder that holds it. Insides show only once a folder is
// opened; a note in no folder is a free cell at the edge (a receptor when
// it has links); links are the cells' own processes. None of this needs a
// screen, so it is all checked here: the preview's roles closed and
// opened, every note link carried once, the size ladder and nothing
// meeting while they drift over hundreds of random vaults, that opening
// never moves anything, that the same notes always give the same picture,
// the sheet's order, and the edge cases (no folders, a cycle, ten deep,
// empty folders, many loose notes, 300 notes).
//
// Compiled with GraphUniverse.swift, GraphThemePlan.swift, GraphNeurons.swift,
// GraphAnatomy.swift, GraphNeuronImpulses.swift and GraphTheme.swift
// (Foundation only). The design preview's notes are the same copy
// CosmicHierarchyTests uses.
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
    NeuronRole(rawValue: body.role) ?? .granule
}

func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    let sum: Float = (d * d).sum()
    return sum.squareRoot()
}

func size(_ a: SIMD3<Float>) -> Float {
    (a * a).sum().squareRoot()
}

/// The plan with these folders opened.
func planOpen(_ input: UniverseInput, _ open: [UUID]) -> ThemePlan {
    var copy: UniverseInput = input
    copy.open = open
    return GraphNeurons.plan(copy)
}

/// The plan with every folder opened.
func allOpen(_ input: UniverseInput) -> ThemePlan {
    planOpen(input, input.folders.map(\.id))
}

/// Times to look at drifting things: two minutes, at uneven steps.
let looks: [Double] = (0..<24).map { Double($0) * 5.3 + 0.17 }

/// Each body's insides, by index.
func insides(_ plan: ThemePlan) -> [[Int]] {
    var kids: [[Int]] = [[Int]](repeating: [], count: plan.bodies.count)
    for (k, body) in plan.bodies.enumerated() where body.parent >= 0 && body.parent < plan.bodies.count {
        kids[body.parent].append(k)
    }
    return kids
}

/// Whether body `outer` holds body `inner`, however deep.
func holds(_ plan: ThemePlan, _ outer: Int, _ inner: Int) -> Bool {
    var at: Int = plan.bodies[inner].parent
    var steps: Int = 0
    while at >= 0 && steps <= plan.bodies.count {
        if at == outer { return true }
        at = plan.bodies[at].parent
        steps += 1
    }
    return false
}

/// What breaks the size ladder: a body as big as the room inside what
/// holds it, a note as big as a part beside it, an idea as big as a page
/// beside it, a busier cell smaller than a quieter one, a drifting cell as
/// big as a receptor, or a role that does not fit where it is.
func ladderProblems(_ plan: ThemePlan) -> [String] {
    var problems: [String] = []
    let bodies: [ThemeBody] = plan.bodies
    for (k, body) in bodies.enumerated() {
        let role: NeuronRole = roleOf(body)
        guard body.sphere > 0 && body.sphere.isFinite else {
            problems.append("\(body.title) has no size")
            continue
        }
        switch body.kind {
        case .note:
            if ![NeuronRole.vesicle, .granule, .receptor, .drifter].contains(role) { problems.append("\(body.title) a note as \(role)") }
        case .folder:
            if role != .cell && role != .part { problems.append("\(body.title) a folder as \(role)") }
        case .home:
            if role != .home || body.id != GraphUniverse.homeID { problems.append("\(body.title) a home as \(role)") }
        }
        let free: Bool = role == .cell || role == .home || role.isFree
        if free != (body.parent < 0) { problems.append("\(body.title) as \(role) with parent \(body.parent)") }
        guard body.parent >= 0 else { continue }
        guard body.parent < k else {
            problems.append("\(body.title) before what holds it")
            continue
        }
        let holder: ThemeBody = bodies[body.parent]
        if !roleOf(holder).isContainer { problems.append("\(body.title) inside \(holder.title), a \(roleOf(holder))") }
        if body.sphere >= holder.sphere * Float(GraphNeurons.inner) {
            problems.append("\(body.title) \(body.sphere) as big as the room in \(holder.title) \(holder.sphere)")
        }
        if body.kind != .note && body.depth != holder.depth + 1 { problems.append("\(body.title) at depth \(body.depth)") }
    }
    for inside in insides(plan) where !inside.isEmpty {
        let parts: [Float] = inside.filter { roleOf(bodies[$0]) == .part }.map { bodies[$0].sphere }
        let notes: [Float] = inside.filter { bodies[$0].kind == .note }.map { bodies[$0].sphere }
        let pages: [Float] = inside.filter { roleOf(bodies[$0]) == .vesicle }.map { bodies[$0].sphere }
        let ideas: [Float] = inside.filter { roleOf(bodies[$0]) == .granule }.map { bodies[$0].sphere }
        if let note = notes.max(), let part = parts.min(), note >= part {
            problems.append("a note \(note) as big as a part \(part) in \(bodies[bodies[inside[0]].parent].title)")
        }
        if let idea = ideas.max(), let page = pages.min(), idea >= page {
            problems.append("an idea \(idea) as big as a page \(page) in \(bodies[bodies[inside[0]].parent].title)")
        }
    }
    let tops: [ThemeBody] = bodies.filter { $0.parent < 0 && roleOf($0).isContainer }
    for a in tops {
        for b in tops where a.count > b.count && a.sphere < b.sphere {
            problems.append("\(a.title) (\(a.count) notes) smaller than \(b.title) (\(b.count))")
        }
    }
    let receptors: [Float] = bodies.filter { roleOf($0) == .receptor }.map(\.sphere)
    let drifters: [Float] = bodies.filter { roleOf($0) == .drifter }.map(\.sphere)
    if let drifter = drifters.max(), let receptor = receptors.min(), drifter >= receptor {
        problems.append("a drifting cell \(drifter) as big as a receptor \(receptor)")
    }
    return problems
}

/// What floats out through its container's membrane, a cell's part out
/// of its nucleus or a note into it, or into a sibling at some time.
/// Measured relative to the container (the drift offsets), so even ten
/// levels deep the floats are fine.
func insideProblems(_ plan: ThemePlan) -> [String] {
    var problems: [String] = []
    for (p, inside) in insides(plan).enumerated() where !inside.isEmpty {
        let holder: ThemeBody = plan.bodies[p]
        let zones: NeuronZones = GraphNeurons.zones(radius: Double(holder.sphere), cell: holder.depth == 0)
        let radii: [Float] = inside.map { plan.bodies[$0].sphere }
        for t in looks where problems.count < 4 {
            let at: [SIMD3<Float>] = inside.map { GraphUniverse.offset(plan.bodies[$0].orbit, time: t) }
            for n in 0..<inside.count {
                let name: String = plan.bodies[inside[n]].title
                let far: Float = size(at[n])
                let part: Bool = plan.bodies[inside[n]].kind != .note
                let room = Float(part ? zones.parts : zones.room)
                if far + radii[n] > room * 1.00001 {
                    problems.append("\(name) out of \(part ? "the nucleus of " : "")\(holder.title) at \(t): \(far + radii[n]) > \(room)")
                }
                if !part && zones.core > 0 && far - radii[n] < Float(zones.core) * 0.99999 {
                    problems.append("\(name) in the nucleus of \(holder.title) at \(t)")
                }
                for m in (n + 1)..<inside.count where distance(at[n], at[m]) < radii[n] + radii[m] {
                    problems.append("\(name) meets \(plan.bodies[inside[m]].title) in \(holder.title) at \(t)")
                }
            }
        }
    }
    return problems
}

/// Cells and free cells that meet at some time (what floats inside a
/// container is insideProblems' to check).
func meetProblems(_ plan: ThemePlan) -> [String] {
    var problems: [String] = []
    let outer: [Int] = plan.bodies.indices.filter { plan.bodies[$0].parent < 0 }
    for t in looks where problems.count < 4 {
        let at: [SIMD3<Float>] = outer.map { plan.position(of: $0, time: t) }
        for n in 0..<outer.count {
            let a: ThemeBody = plan.bodies[outer[n]]
            for m in (n + 1)..<outer.count {
                let b: ThemeBody = plan.bodies[outer[m]]
                if distance(at[n], at[m]) < a.sphere + b.sphere {
                    problems.append("\(a.title) meets \(b.title) at \(t)")
                }
            }
        }
    }
    return problems
}

/// Cells and free cells that leave the whole-map framing at some time.
func envelopeProblems(_ plan: ThemePlan) -> [String] {
    guard let first = plan.envelope.first else { return plan.bodies.isEmpty ? [] : ["no envelope"] }
    var low: SIMD3<Float> = first
    var high: SIMD3<Float> = first
    for p in plan.envelope {
        low = pointwiseMin(low, p)
        high = pointwiseMax(high, p)
    }
    var problems: [String] = []
    for (k, body) in plan.bodies.enumerated() where body.parent < 0 {
        for t in looks {
            let p: SIMD3<Float> = plan.position(of: k, time: t)
            let r: Float = body.sphere
            let inside: Bool = p.x - r >= low.x - 0.001 && p.y - r >= low.y - 0.001 && p.z - r >= low.z - 0.001
                && p.x + r <= high.x + 0.001 && p.y + r <= high.y + 0.001 && p.z + r <= high.z + 0.001
            if !inside {
                problems.append("\(body.title) leaves the framing at \(t)")
                break
            }
        }
    }
    return problems
}

/// The body each note shows as: its own when it shows, else the nearest
/// folder round it that does (with no folders, the home cell).
func shownBodies(_ input: UniverseInput, _ plan: ThemePlan) -> [UUID: Int] {
    var byID: [UUID: Int] = [:]
    for (k, body) in plan.bodies.enumerated() { byID[body.id] = k }
    var parentOf: [UUID: UUID] = [:]
    for folder in input.folders {
        if let p = folder.parent { parentOf[folder.id] = p }
    }
    var out: [UUID: Int] = [:]
    for note in input.notes {
        if let own = byID[note.id] {
            out[note.id] = own
            continue
        }
        if input.folders.isEmpty {
            out[note.id] = byID[GraphUniverse.homeID]
            continue
        }
        var at: UUID? = note.folder
        var steps: Int = 0
        while let folder = at, steps <= input.folders.count + 1 {
            if let k = byID[folder] {
                out[note.id] = k
                break
            }
            at = parentOf[folder]
            steps += 1
        }
    }
    return out
}

struct Way: Hashable {
    let a: UUID
    let b: UUID
}

struct BodyPair: Hashable {
    let low: Int
    let high: Int
}

/// What is wrong with a plan's processes: every pair of shown bodies with
/// note links between them carries exactly one, sent from the side with
/// more of the links (ties by name), never between a body and what holds
/// it, kind 5 inside one cell and 6 between cells or free ones, with a dye
/// and a width.
func processProblems(_ input: UniverseInput, _ plan: ThemePlan) -> [String] {
    var problems: [String] = []
    let shown: [UUID: Int] = shownBodies(input, plan)
    let notes = Set<UUID>(input.notes.map(\.id))
    var ways = Set<Way>()
    for edge in input.edges where edge.a != edge.b && notes.contains(edge.a) && notes.contains(edge.b) {
        ways.insert(Way(a: edge.a, b: edge.b))
    }
    var up: [BodyPair: Int] = [:]
    var down: [BodyPair: Int] = [:]
    for way in ways {
        guard let x = shown[way.a], let y = shown[way.b] else {
            problems.append("a linked note shows nowhere")
            continue
        }
        if x == y { continue }
        let pair = BodyPair(low: min(x, y), high: max(x, y))
        if x < y { up[pair, default: 0] += 1 } else { down[pair, default: 0] += 1 }
    }
    var seen: [BodyPair: Int] = [:]
    for link in plan.links {
        let n: Int = plan.bodies.count
        guard link.a >= 0, link.b >= 0, link.a < n, link.b < n, link.a != link.b else {
            problems.append("a process with a bad end: \(link.a) \(link.b)")
            continue
        }
        let a: ThemeBody = plan.bodies[link.a]
        let b: ThemeBody = plan.bodies[link.b]
        let pair = BodyPair(low: min(link.a, link.b), high: max(link.a, link.b))
        seen[pair, default: 0] += 1
        let same: Bool = a.region >= 0 && a.region == b.region
        if link.kind != (same ? 5 : 6) { problems.append("\(a.title) - \(b.title): kind \(link.kind)") }
        if link.centre != -1 { problems.append("\(a.title) - \(b.title): centre \(link.centre)") }
        if FiberKind(rawValue: link.tag) == nil { problems.append("\(a.title) - \(b.title): dye \(link.tag)") }
        if !(link.width >= 0.669 && link.width <= 1.751) { problems.append("\(a.title) - \(b.title): width \(link.width)") }
        if holds(plan, link.a, link.b) || holds(plan, link.b, link.a) {
            problems.append("\(a.title) - \(b.title): one holds the other")
        }
        let along: Int = link.a < link.b ? up[pair, default: 0] : down[pair, default: 0]
        let against: Int = link.a < link.b ? down[pair, default: 0] : up[pair, default: 0]
        if along + against == 0 {
            problems.append("\(a.title) - \(b.title) carries no link")
        } else if along < against {
            problems.append("\(a.title) -> \(b.title) runs against \(against) of its \(along + against) links")
        } else if along == against
            && (a.title.lowercased(), a.id.uuidString) > (b.title.lowercased(), b.id.uuidString) {
            problems.append("\(a.title) -> \(b.title): a tie sent from the later name")
        }
    }
    for pair in Set(up.keys).union(down.keys) where seen[pair] != 1 {
        problems.append("\(plan.bodies[pair.low].title) - \(plan.bodies[pair.high].title): \(seen[pair] ?? 0) processes")
    }
    return problems
}

/// Bodies of `small` that `big` (the same vault with more opened) lost or
/// changed: place, size, drift, facing or role.
func movedProblems(_ small: ThemePlan, _ big: ThemePlan) -> [String] {
    var byID: [UUID: ThemeBody] = [:]
    for body in big.bodies { byID[body.id] = body }
    var problems: [String] = []
    for body in small.bodies {
        guard let other = byID[body.id] else {
            problems.append("\(body.title) is gone")
            continue
        }
        if other.home != body.home || other.sphere != body.sphere || other.orbit != body.orbit
            || other.axis != body.axis || other.role != body.role || other.label != body.label {
            problems.append("\(body.title) changed")
        }
    }
    return problems
}

/// The first few problems, for a check's detail.
func few(_ problems: [String]) -> String {
    problems.prefix(3).joined(separator: "; ")
}

// MARK: T1 the design preview, closed and opened

let preview: UniverseInput = previewInput()
let examples: UUID = fixedID(900)
let inguinal: UUID = fixedID(901)
let closed: ThemePlan = GraphNeurons.plan(preview)
check("T1 closed: two cells and two receptors", closed.summary == "2 cells, 2 receptors", closed.summary)
check("T1 closed: the top folders are the cells", titles(closed, .cell) == ["Examples", "Cardiology"],
      "\(titles(closed, .cell))")
check("T1 closed: the linked loose notes are receptors",
      titles(closed, .receptor) == ["Richter's hernia", "Pericarditis"], "\(titles(closed, .receptor))")
check("T1 closed: nothing shows inside a closed cell", closed.bodies.allSatisfy { $0.parent < 0 })
check("T1 the cells are the regions", closed.regions.map { closed.bodies[$0].title } .sorted() == ["Cardiology", "Examples"]
      && closed.regions.allSatisfy { closed.bodies[$0].region == $0 })
let openOne: ThemePlan = planOpen(preview, [examples])
check("T1 Examples opened: its two parts and three notes show",
      openOne.summary == "2 cells, 2 parts, 1 vesicle, 2 granules, 2 receptors", openOne.summary)
check("T1 Examples opened: Inguinal and Femoral are parts", titles(openOne, .part) == ["Inguinal", "Femoral"],
      "\(titles(openOne, .part))")
check("T1 Examples opened: Groin hernia a vesicle, its ideas granules",
      titles(openOne, .vesicle) == ["Groin hernia"]
      && titles(openOne, .granule) == ["Hernia repair", "Expansile cough impulse"],
      "\(titles(openOne, .vesicle)) \(titles(openOne, .granule))")
let examplesBody: Int = bodyNamed(openOne, "Examples") ?? -1
check("T1 Examples opened: all of it inside Examples",
      openOne.bodies.allSatisfy { $0.parent < 0 || $0.parent == examplesBody }
      && openOne.bodies.filter { $0.parent == examplesBody }.count == 5)
let openTwo: ThemePlan = planOpen(preview, [examples, inguinal])
check("T1 Inguinal opened too: Anatomy and Inguinal's notes show",
      openTwo.summary == "2 cells, 3 parts, 4 vesicles, 4 granules, 2 receptors", openTwo.summary)
check("T1 Anatomy is a part inside Inguinal",
      bodyNamed(openTwo, "Anatomy").map { openTwo.bodies[$0].parent } == bodyNamed(openTwo, "Inguinal")
      && bodyNamed(openTwo, "Anatomy").map { roleOf(openTwo.bodies[$0]) } == .part)
check("T1 a part inside a closed cell stays shut", planOpen(preview, [inguinal]).summary == "2 cells, 2 receptors")
check("T1 the order folders are opened in changes nothing",
      planOpen(preview, [inguinal, examples]).bodies == openTwo.bodies)
let openAll: ThemePlan = allOpen(preview)
check("T1 all opened: every note shows inside its folder",
      openAll.summary == "2 cells, 3 parts, 9 vesicles, 19 granules, 2 receptors", openAll.summary)
var misplaced: [String] = []
for note in preview.notes {
    guard let k = bodyNamed(openAll, note.title) else {
        misplaced.append(note.title + " missing")
        continue
    }
    let body: ThemeBody = openAll.bodies[k]
    let holder: UUID? = body.parent >= 0 ? openAll.bodies[body.parent].id : nil
    if holder != note.folder { misplaced.append(note.title) }
    if roleOf(body) != (note.folder == nil ? .receptor : (note.isPage ? .vesicle : .granule)) {
        misplaced.append(note.title + " as \(roleOf(body))")
    }
}
check("T1 all opened: each note in the folder that holds it, a page a vesicle", misplaced.isEmpty, few(misplaced))
check("T1 each body after what holds it", openAll.bodies.enumerated().allSatisfy { $0.element.parent < $0.offset })
check("T1 a container's framing holds it; a note has none",
      openAll.systems.count == openAll.bodies.count
      && zip(openAll.bodies, openAll.systems).allSatisfy { $0.kind == .note ? $1.isEmpty : $1.count == 6 })
check("T1 the preview's ladder holds, open and closed",
      ladderProblems(closed).isEmpty && ladderProblems(openOne).isEmpty && ladderProblems(openAll).isEmpty,
      few(ladderProblems(closed) + ladderProblems(openOne) + ladderProblems(openAll)))
check("T1 nothing inside meets or leaves its cell", insideProblems(openAll).isEmpty, few(insideProblems(openAll)))
check("T1 no cells meet", meetProblems(openAll).isEmpty, few(meetProblems(openAll)))
check("T1 the framing holds every cell", envelopeProblems(openAll).isEmpty, few(envelopeProblems(openAll)))

// MARK: T2 the links as the cells' processes

check("T2 closed: every link carried once", processProblems(preview, closed).isEmpty,
      few(processProblems(preview, closed)))
check("T2 closed: two processes, each from a receptor into its cell",
      closed.links.count == 2 && closed.links.allSatisfy {
          roleOf(closed.bodies[$0.a]) == .receptor && roleOf(closed.bodies[$0.b]) == .cell && $0.kind == 6
      }, "\(closed.links)")
check("T2 Examples opened: every link carried once", processProblems(preview, openOne).isEmpty,
      few(processProblems(preview, openOne)))
let richter: Int = bodyNamed(openOne, "Richter's hernia") ?? -1
let femoral: Int = bodyNamed(openOne, "Femoral") ?? -1
check("T2 a link into a closed part ends on the part",
      openOne.links.contains { $0.a == richter && $0.b == femoral && $0.kind == 6 })
let groin: Int = bodyNamed(openOne, "Groin hernia") ?? -1
let inguinalPart: Int = bodyNamed(openOne, "Inguinal") ?? -1
check("T2 three links from Groin hernia into Inguinal make one process",
      openOne.links.filter { $0.a == groin && $0.b == inguinalPart }.count == 1
      && openOne.links.first { $0.a == groin && $0.b == inguinalPart }?.width == Float(0.55 + 0.12 * 6))
check("T2 inside a cell kind 5, between cells 6",
      openOne.links.filter { $0.kind == 5 }.count == 6 && openOne.links.filter { $0.kind == 6 }.count == 2,
      "\(openOne.links.map(\.kind))")
check("T2 Inguinal opened: every link carried once", processProblems(preview, openTwo).isEmpty,
      few(processProblems(preview, openTwo)))
check("T2 all opened: every link carried once", processProblems(preview, openAll).isEmpty,
      few(processProblems(preview, openAll)))
check("T2 all opened: links between notes only, no note to a folder",
      openAll.links.allSatisfy { openAll.bodies[$0.a].kind == .note && openAll.bodies[$0.b].kind == .note })
check("T2 plain links are excitatory: strength 4 one way, 5 both ways",
      openAll.links.allSatisfy {
          $0.tag == FiberKind.excitatory.rawValue
              && ($0.width == Float(0.55 + 0.12 * 4) || $0.width == Float(0.55 + 0.12 * 5))
      } && openAll.links.contains { $0.width == Float(0.55 + 0.12 * 5) })
// what a link carries, read from the notes (GraphAnatomy)
let dyeFolders: [UniverseFolder] = [UniverseFolder(id: fixedID(700), name: "Sender", parent: nil),
                                    UniverseFolder(id: fixedID(701), name: "Target", parent: nil)]
let dyeNotes: [AnatomyNote] = [
    AnatomyNote(id: fixedID(710), title: "Benign mimic", body: "Unlike [[Strangulation]], it never needs surgery.",
                isPage: false, folder: fixedID(700), tags: [], source: nil, hand: [fixedID(712)],
                written: [fixedID(711)], created: 0),
    AnatomyNote(id: fixedID(711), title: "Strangulation", body: "Ischaemic bowel.", isPage: false,
                folder: fixedID(701), tags: [], source: nil, hand: [], written: [], created: 1),
    AnatomyNote(id: fixedID(712), title: "Obstruction", body: "Colicky pain.", isPage: false,
                folder: fixedID(701), tags: [], source: nil, hand: [], written: [], created: 2)
]
let dyeInput = UniverseInput(
    notes: dyeNotes.map { UniverseNote(id: $0.id, title: $0.title, isPage: false, folder: $0.folder, words: 4,
                                       created: $0.created) },
    folders: dyeFolders, edges: [UniverseEdge(a: fixedID(710), b: fixedID(711)), UniverseEdge(a: fixedID(710), b: fixedID(712))],
    seedByName: true, anatomy: AnatomyInput(notes: dyeNotes, folders: dyeFolders))
let dyeShut: ThemePlan = GraphNeurons.plan(dyeInput)
check("T2 a contrast and a hand link: one process, dyed by the contrast",
      dyeShut.links.count == 1 && dyeShut.links[0].tag == FiberKind.inhibitory.rawValue
      && dyeShut.links[0].width == Float(0.55 + 0.12 * 5), "\(dyeShut.links)")
check("T2 it runs from the cell that sends", dyeShut.links.first.map { dyeShut.bodies[$0.a].title } == "Sender")
let dyeOpen: ThemePlan = allOpen(dyeInput)
let dyeTags: [String: Int] = Dictionary(uniqueKeysWithValues: dyeOpen.links.map { (dyeOpen.bodies[$0.b].title, $0.tag) })
check("T2 opened: the contrast inhibitory, the hand link modulatory",
      dyeTags == ["Strangulation": FiberKind.inhibitory.rawValue, "Obstruction": FiberKind.modulatory.rawValue],
      "\(dyeTags)")
check("T2 opened: every link carried once", processProblems(dyeInput, dyeOpen).isEmpty,
      few(processProblems(dyeInput, dyeOpen)))

// MARK: T3 the ladder and nothing meeting, over random vaults

var ladderSeen: [String] = []
var insideSeen: [String] = []
var meetSeen: [String] = []
var processSeen: [String] = []
var movedSeen: [String] = []
var envelopeSeen: [String] = []
var shownSeen: [String] = []
for seed in 0..<160 {
    let vault: UniverseInput = randomVault(UInt64(seed) &* 7919 &+ 13, maxNotes: 60, maxFolders: 12)
    var dice = Dice(state: UInt64(seed) &+ 99)
    let some: [UUID] = vault.folders.map(\.id).filter { _ in dice.unit() < 0.5 }
    let shut: ThemePlan = GraphNeurons.plan(vault)
    let half: ThemePlan = planOpen(vault, some)
    let full: ThemePlan = allOpen(vault)
    for (name, plan) in [("closed", shut), ("half open", half), ("open", full)] {
        let tag: String = "seed \(seed) \(name): "
        if ladderSeen.count < 3 { ladderSeen += ladderProblems(plan).prefix(1).map { tag + $0 } }
        if insideSeen.count < 3 { insideSeen += insideProblems(plan).prefix(1).map { tag + $0 } }
        if meetSeen.count < 3 { meetSeen += meetProblems(plan).prefix(1).map { tag + $0 } }
        if processSeen.count < 3 { processSeen += processProblems(vault, plan).prefix(1).map { tag + $0 } }
        if envelopeSeen.count < 3 { envelopeSeen += envelopeProblems(plan).prefix(1).map { tag + $0 } }
    }
    if movedSeen.count < 3 {
        movedSeen += (movedProblems(shut, half) + movedProblems(half, full)).prefix(1).map { "seed \(seed): " + $0 }
    }
    let notes: Int = full.bodies.filter { $0.kind == .note }.count
    let folders: Int = full.bodies.filter { $0.kind != .note }.count
    let wantFolders: Int = vault.folders.isEmpty ? (vault.notes.isEmpty ? 0 : 1) : vault.folders.count
    if (notes != vault.notes.count || folders != wantFolders) && shownSeen.count < 3 {
        shownSeen.append("seed \(seed): \(notes) of \(vault.notes.count) notes, \(folders) of \(wantFolders) folders")
    }
}
check("T3 all opened, every note and folder shows", shownSeen.isEmpty, few(shownSeen))
check("T3 the ladder holds in 160 random vaults, closed, half open and open", ladderSeen.isEmpty, few(ladderSeen))
check("T3 nothing leaves its membrane, enters a nucleus or meets a sibling, drifting for two minutes",
      insideSeen.isEmpty, few(insideSeen))
check("T3 no two cells or free cells meet", meetSeen.isEmpty, few(meetSeen))
check("T3 every link carried by exactly one process", processSeen.isEmpty, few(processSeen))
check("T3 opening moves nothing already shown", movedSeen.isEmpty, few(movedSeen))
check("T3 the framing holds every cell", envelopeSeen.isEmpty, few(envelopeSeen))

// MARK: T4 the same notes, the same picture

check("T4 planned twice, the same", allOpen(preview).bodies == openAll.bodies && allOpen(preview).links == openAll.links)
let flippedInput = UniverseInput(notes: preview.notes.reversed(), folders: preview.folders.reversed(),
                                 edges: preview.edges.reversed(), seedByName: true)
let flipped: ThemePlan = allOpen(flippedInput)
check("T4 the order notes come in changes nothing", flipped.bodies == openAll.bodies && flipped.links == openAll.links)
check("T4 opening Examples moves nothing shown", movedProblems(closed, openOne).isEmpty, few(movedProblems(closed, openOne)))
check("T4 opening Inguinal moves nothing shown", movedProblems(openOne, openTwo).isEmpty,
      few(movedProblems(openOne, openTwo)))
check("T4 opening everything moves nothing shown", movedProblems(openTwo, openAll).isEmpty,
      few(movedProblems(openTwo, openAll)))
check("T4 closing hides only what was inside",
      Set(closed.bodies.map(\.id)) == Set(openAll.bodies.filter { $0.parent < 0 }.map(\.id)))
check("T4 opening keeps the framing", closed.envelope == openAll.envelope)
let unlinkedInput = UniverseInput(notes: preview.notes, folders: preview.folders, edges: [], seedByName: true)
let unlinked: ThemePlan = allOpen(unlinkedInput)
check("T4 without links: no processes, the loose notes drift free",
      unlinked.links.isEmpty && titles(unlinked, .drifter) == ["Richter's hernia", "Pericarditis"]
      && titles(unlinked, .receptor).isEmpty, unlinked.summary)

// MARK: T5 the sheet: senders first, each cell facing the one it sends to

/// Three top folders whose names run against the flow: Zeta's notes link
/// to Mid's, Mid's to Alpha's.
func flowInput() -> UniverseInput {
    let names: [String] = ["Zeta", "Mid", "Alpha"]
    var folders: [UniverseFolder] = []
    var notes: [UniverseNote] = []
    for (f, name) in names.enumerated() {
        folders.append(UniverseFolder(id: fixedID(600 + f), name: name, parent: nil))
        for k in 0..<3 {
            notes.append(UniverseNote(id: fixedID(610 + f * 10 + k), title: "\(name) note \(k)", isPage: k == 0,
                                      folder: fixedID(600 + f), words: 80, created: Double(f * 10 + k)))
        }
    }
    var edges: [UniverseEdge] = []
    for k in 0..<3 {
        edges.append(UniverseEdge(a: fixedID(610 + k), b: fixedID(620 + k)))
        edges.append(UniverseEdge(a: fixedID(620 + k), b: fixedID(630 + k)))
    }
    return UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: true)
}

let flow: ThemePlan = GraphNeurons.plan(flowInput())
if let zeta = bodyNamed(flow, "Zeta"), let mid = bodyNamed(flow, "Mid"), let alpha = bodyNamed(flow, "Alpha") {
    let z: ThemeBody = flow.bodies[zeta]
    let m: ThemeBody = flow.bodies[mid]
    let a: ThemeBody = flow.bodies[alpha]
    check("T5 the sender first: Zeta left of Mid on the top row, Alpha below",
          z.home.x < m.home.x && z.home.y > a.home.y && m.home.y > a.home.y, "\(z.home) \(m.home) \(a.home)")
    let toMid: SIMD3<Float> = (m.home - z.home) / distance(m.home, z.home)
    let toAlpha: SIMD3<Float> = (a.home - m.home) / distance(a.home, m.home)
    check("T5 Zeta faces Mid and Mid faces Alpha",
          (z.axis * toMid).sum() > 0.95 && (m.axis * toAlpha).sum() > 0.95, "\(z.axis) \(m.axis)")
    check("T5 Alpha, sending nowhere, faces down the sheet", a.axis == SIMD3<Float>(0, -1, 0), "\(a.axis)")
    let biggest: Float = [z.sphere, m.sphere, a.sphere].max() ?? 0
    check("T5 the sheet is flat, facing the camera",
          [z, m, a].allSatisfy { abs($0.home.z) <= 0.3 * biggest + 0.02 }, "\([z.home.z, m.home.z, a.home.z])")
    check("T5 the processes run with the flow",
          Set(flow.links.map { "\(flow.bodies[$0.a].title)>\(flow.bodies[$0.b].title)" }) == ["Zeta>Mid", "Mid>Alpha"]
          && flow.links.allSatisfy { $0.kind == 6 }, "\(flow.links)")
} else {
    check("T5 the three cells", false, flow.summary)
}
check("T5 nothing meets", meetProblems(flow).isEmpty, few(meetProblems(flow)))

// MARK: T6 edge cases

// no folders: one home cell holds every note, always open
let homeNotes: [UniverseNote] = [
    UniverseNote(id: fixedID(801), title: "Murmur grading", isPage: true, folder: nil, words: 300, created: 0),
    UniverseNote(id: fixedID(802), title: "Splitting S2", isPage: false, folder: nil, words: 40, created: 1),
    UniverseNote(id: fixedID(803), title: "Opening snap", isPage: false, folder: nil, words: 20, created: 2)
]
let homeInput = UniverseInput(notes: homeNotes, folders: [],
                              edges: [UniverseEdge(a: fixedID(801), b: fixedID(802)),
                                      UniverseEdge(a: fixedID(802), b: fixedID(803))], seedByName: true)
let homePlan: ThemePlan = GraphNeurons.plan(homeInput)
check("T6 no folders: one home cell first, holding every note",
      homePlan.bodies.first?.id == GraphUniverse.homeID && homePlan.bodies.first?.role == NeuronRole.home.rawValue
      && homePlan.bodies.count == 4 && homePlan.bodies.dropFirst().allSatisfy { $0.parent == 0 }
      && homePlan.regions == [0], homePlan.summary)
check("T6 no folders: the summary", homePlan.summary == "1 cell, 1 vesicle, 2 granules", homePlan.summary)
check("T6 no folders: links inside the cell, each carried",
      homePlan.links.count == 2 && homePlan.links.allSatisfy { $0.kind == 5 }
      && processProblems(homeInput, homePlan).isEmpty, few(processProblems(homeInput, homePlan)))
check("T6 no folders: the ladder holds, nothing meets", ladderProblems(homePlan).isEmpty
      && insideProblems(homePlan).isEmpty, few(ladderProblems(homePlan) + insideProblems(homePlan)))

// a cycle, A inside B inside A, is cut: nothing lost
let cycleInput = UniverseInput(
    notes: [UniverseNote(id: fixedID(811), title: "In A", isPage: false, folder: fixedID(821), words: 30, created: 0),
            UniverseNote(id: fixedID(812), title: "In B", isPage: false, folder: fixedID(822), words: 30, created: 1)],
    folders: [UniverseFolder(id: fixedID(821), name: "A", parent: fixedID(822)),
              UniverseFolder(id: fixedID(822), name: "B", parent: fixedID(821))],
    edges: [UniverseEdge(a: fixedID(811), b: fixedID(812))], seedByName: true)
let cycleShut: ThemePlan = GraphNeurons.plan(cycleInput)
let cycleOpen: ThemePlan = allOpen(cycleInput)
check("T6 a cycle: one cell, one part inside it, both notes",
      cycleShut.summary == "1 cell" && cycleOpen.summary == "1 cell, 1 part, 2 granules", cycleOpen.summary)
check("T6 a cycle: the ladder holds, nothing meets, every link carried",
      ladderProblems(cycleOpen).isEmpty && insideProblems(cycleOpen).isEmpty
      && processProblems(cycleInput, cycleOpen).isEmpty && processProblems(cycleInput, cycleShut).isEmpty,
      few(ladderProblems(cycleOpen) + insideProblems(cycleOpen) + processProblems(cycleInput, cycleOpen)))

// ten folders deep, one note in each, linked down the chain
var deepFolders: [UniverseFolder] = []
var deepNotes: [UniverseNote] = []
for k in 0..<10 {
    deepFolders.append(UniverseFolder(id: fixedID(830 + k), name: "D\(k)", parent: k == 0 ? nil : fixedID(829 + k)))
    deepNotes.append(UniverseNote(id: fixedID(850 + k), title: "Deep note \(k)", isPage: k % 2 == 0,
                                  folder: fixedID(830 + k), words: 120, created: Double(k)))
}
let deepInput = UniverseInput(notes: deepNotes, folders: deepFolders,
                              edges: (0..<9).map { UniverseEdge(a: fixedID(850 + $0), b: fixedID(851 + $0)) },
                              seedByName: true)
let deep: ThemePlan = allOpen(deepInput)
check("T6 ten deep: one cell, nine parts each inside the last, ten notes",
      titles(deep, .cell) == ["D0"] && titles(deep, .part).count == 9 && deep.bodies.count == 20, deep.summary)
let smallest: Float = deep.bodies.map(\.sphere).min() ?? 0
check("T6 ten deep: the smallest still has a size", smallest > 0 && smallest.isFinite, "\(smallest)")
check("T6 ten deep: the ladder holds, nothing leaves its membrane",
      ladderProblems(deep).isEmpty && insideProblems(deep).isEmpty, few(ladderProblems(deep) + insideProblems(deep)))
check("T6 ten deep: every link carried", processProblems(deepInput, deep).isEmpty,
      few(processProblems(deepInput, deep)))
let deepFirst: ThemePlan = planOpen(deepInput, [fixedID(830)])
check("T6 ten deep, only the cell opened: it, its part and its note",
      deepFirst.bodies.count == 3 && deepFirst.summary == "1 cell, 1 part, 1 vesicle", deepFirst.summary)
check("T6 ten deep: a part opened inside a closed cell shows nothing more",
      planOpen(deepInput, [fixedID(831)]).bodies.count == 1)

// empty folders: a bare cell, a bare part
let emptyInput = UniverseInput(
    notes: [UniverseNote(id: fixedID(871), title: "Lonely fact", isPage: false, folder: fixedID(861), words: 10,
                         created: 0)],
    folders: [UniverseFolder(id: fixedID(860), name: "Empty", parent: nil),
              UniverseFolder(id: fixedID(861), name: "Full", parent: nil),
              UniverseFolder(id: fixedID(862), name: "Hollow", parent: fixedID(861))],
    edges: [], seedByName: true)
let emptyOpen: ThemePlan = allOpen(emptyInput)
if let bare = bodyNamed(emptyOpen, "Empty"), let hollow = bodyNamed(emptyOpen, "Hollow") {
    check("T6 an empty folder: the smallest cell, nothing inside it when opened",
          emptyOpen.bodies[bare].sphere == Float(GraphNeurons.cellSphere(count: 0))
          && !emptyOpen.bodies.contains { $0.parent == bare }, "\(emptyOpen.bodies[bare].sphere)")
    check("T6 an empty part: inside its cell, nothing inside it",
          emptyOpen.bodies[hollow].role == NeuronRole.part.rawValue && !emptyOpen.bodies.contains { $0.parent == hollow })
} else {
    check("T6 empty folders show", false, emptyOpen.summary)
}
check("T6 empty folders: the ladder holds", ladderProblems(emptyOpen).isEmpty && insideProblems(emptyOpen).isEmpty,
      few(ladderProblems(emptyOpen) + insideProblems(emptyOpen)))
let nothing: ThemePlan = GraphNeurons.plan(UniverseInput(notes: [], folders: [], edges: [], seedByName: true))
check("T6 nothing: an empty plan", nothing.bodies.isEmpty && nothing.links.isEmpty && nothing.summary.isEmpty)
let bareInput = UniverseInput(notes: [], folders: emptyInput.folders, edges: [], seedByName: true)
check("T6 folders and no notes: cells and parts only",
      GraphNeurons.plan(bareInput).summary == "2 cells" && allOpen(bareInput).summary == "2 cells, 1 part",
      allOpen(bareInput).summary)

// forty loose notes round one cell: twenty linked into it, twenty not
var looseNotes: [UniverseNote] = []
var looseEdges: [UniverseEdge] = []
for k in 0..<4 {
    looseNotes.append(UniverseNote(id: fixedID(880 + k), title: "Hub note \(k)", isPage: false, folder: fixedID(879),
                                   words: 50, created: Double(k)))
}
for k in 0..<40 {
    looseNotes.append(UniverseNote(id: fixedID(1100 + k), title: "Loose \(k)", isPage: k % 5 == 0, folder: nil,
                                   words: 30, created: Double(10 + k)))
    if k < 20 { looseEdges.append(UniverseEdge(a: fixedID(1100 + k), b: fixedID(880 + k % 4))) }
}
let looseInput = UniverseInput(notes: looseNotes, folders: [UniverseFolder(id: fixedID(879), name: "Hub", parent: nil)],
                               edges: looseEdges, seedByName: true)
let loosePlan: ThemePlan = GraphNeurons.plan(looseInput)
check("T6 forty loose: twenty receptors, twenty free cells",
      loosePlan.summary == "1 cell, 20 receptors, 20 free cells", loosePlan.summary)
check("T6 forty loose: no two meet", meetProblems(loosePlan).isEmpty, few(meetProblems(loosePlan)))
check("T6 forty loose: the framing holds them", envelopeProblems(loosePlan).isEmpty, few(envelopeProblems(loosePlan)))
if let hub = bodyNamed(loosePlan, "Hub") {
    let hubBody: ThemeBody = loosePlan.bodies[hub]
    let turned: [String] = loosePlan.bodies.filter { roleOf($0) == .receptor }.compactMap { body in
        let to: SIMD3<Float> = (hubBody.home - body.home) / distance(hubBody.home, body.home)
        return (body.axis * to).sum() > 0.9 ? nil : body.title
    }
    check("T6 forty loose: each receptor faces the cell it sends to", turned.isEmpty, "\(turned)")
    let crowding: [String] = loosePlan.bodies.filter { roleOf($0).isFree }.compactMap { body in
        distance(hubBody.home, body.home) >= hubBody.sphere * Float(GraphNeurons.reach) + body.sphere ? nil : body.title
    }
    check("T6 forty loose: all clear of the cell's processes", crowding.isEmpty, "\(crowding)")
    check("T6 forty loose: every process runs from a receptor into the cell",
          loosePlan.links.count == 20 && loosePlan.links.allSatisfy {
              roleOf(loosePlan.bodies[$0.a]) == .receptor && $0.b == hub && $0.kind == 6
          }, "\(loosePlan.links.count)")
} else {
    check("T6 forty loose: the hub cell", false, loosePlan.summary)
}
let looseOpen: ThemePlan = allOpen(looseInput)
check("T6 forty loose, opened: every link carried, nothing meets",
      processProblems(looseInput, looseOpen).isEmpty && meetProblems(looseOpen).isEmpty
      && insideProblems(looseOpen).isEmpty, few(processProblems(looseInput, looseOpen) + meetProblems(looseOpen)))

// MARK: T7 scale

let started: Date = Date()
let bigInput: UniverseInput = randomVault(4242, maxNotes: 300, maxFolders: 40, exact: true)
let big: ThemePlan = allOpen(bigInput)
let took: Double = Date().timeIntervalSince(started)
check("T7 300 notes, all opened: every note planned", big.bodies.filter { $0.kind == .note }.count == 300, big.summary)
check("T7 300 notes: planned in under 2 s", took < 2, "\(took) s")
print("     planned in \(Int(took * 1000)) ms")
check("T7 300 notes: the ladder holds", ladderProblems(big).isEmpty, few(ladderProblems(big)))
check("T7 300 notes: nothing leaves its membrane or meets", insideProblems(big).isEmpty && meetProblems(big).isEmpty,
      few(insideProblems(big) + meetProblems(big)))
check("T7 300 notes: every link carried once", processProblems(bigInput, big).isEmpty,
      few(processProblems(bigInput, big)))
check("T7 300 notes: the framing holds", envelopeProblems(big).isEmpty, few(envelopeProblems(big)))
var crowdNotes: [UniverseNote] = []
for k in 0..<200 {
    crowdNotes.append(UniverseNote(id: fixedID(2000 + k), title: "Crowd \(k)", isPage: k % 3 == 0,
                                   folder: fixedID(1999), words: 20 + k * 7, created: Double(k)))
}
let crowdInput = UniverseInput(notes: crowdNotes,
                               folders: [UniverseFolder(id: fixedID(1999), name: "Crowded", parent: nil)],
                               edges: [], seedByName: true)
let crowd: ThemePlan = allOpen(crowdInput)
check("T7 two hundred notes in one cell: all inside, none meeting",
      crowd.bodies.count == 201 && insideProblems(crowd).isEmpty && ladderProblems(crowd).isEmpty,
      few(insideProblems(crowd) + ladderProblems(crowd)))
// MARK: T8 the theme choice

check("T8 Space is the default", GraphTheme.stored(nil) == .space && GraphTheme.stored("nonsense") == .space)
check("T8 Neurons is kept", GraphTheme.stored("neurons") == .neurons)
check("T8 a removed theme falls back: a stored Circuit opens in Space", GraphTheme.stored("circuit") == .space)
check("T8 the menu offers only ready themes", GraphTheme.offered.allSatisfy { $0.isReady }
      && GraphTheme.offered.first == .space)
check("T8 the themes' words are their own",
      Set(GraphTheme.allCases.map(\.legendTitle)).count == GraphTheme.allCases.count
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
