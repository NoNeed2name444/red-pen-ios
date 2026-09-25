// The Universe look (GraphUniverse): the ideas' hierarchy as a universe, the
// biggest bodies for the biggest containers.
//
// Top-level folders are black holes, folders stars, pages gas giants, ideas
// rocky planets, short one-link ideas moons, bridging ideas pulsars, loose
// notes comets. None of this needs a screen, so all of it is checked here:
// the roles the design preview must show, the size ladder over hundreds of
// random vaults, that the same notes always give the same picture, that no
// two bodies ever meet, and the edge cases (cycles, deep nesting, empty
// folders, no folders at all, forty loose notes).
//
// Compiled with GraphUniverse.swift alone (the planner imports only
// Foundation). The design preview's notes are copied below; T1 checks the
// roles the planner gives that copy.
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

// MARK: helpers over a plan

func bodyNamed(_ plan: UniversePlan, _ title: String) -> Int? {
    plan.bodies.firstIndex { $0.title == title }
}

func titles(_ plan: UniversePlan, _ role: UniverseRole) -> Set<String> {
    Set(plan.bodies.filter { $0.role == role }.map(\.title))
}

func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.0006) -> Bool {
    abs(a - b) <= tolerance
}

func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    let sum: Float = (d * d).sum()
    return sum.squareRoot()
}

/// The radius two bodies must keep apart: the sphere, or a core's disk.
func keepOut(_ body: UniverseBody, grow: Float) -> Float {
    if body.role == .galaxy && !body.empty { return body.sphere * 2.5 }
    let isNote: Bool = body.count == 0 && body.role != .galaxy && body.role != .star && body.role != .home
    return isNote ? body.sphere * grow : body.sphere
}

/// Pairs of non-comet bodies that overlap at some time in 0...600 s.
func overlaps(_ plan: UniversePlan, grow: Float, step: Double = 5) -> [String] {
    var bad: [String] = []
    let kept: [Int] = plan.bodies.indices.filter { i in
        let r: UniverseRole = plan.bodies[i].role
        return r != .comet && r != .oort
    }
    var t: Double = 0
    while t <= 600 {
        let at: [SIMD3<Float>] = kept.map { GraphUniverse.position(of: $0, in: plan, time: t) }
        for x in kept.indices {
            for y in (x + 1)..<kept.count {
                let a: UniverseBody = plan.bodies[kept[x]]
                let b: UniverseBody = plan.bodies[kept[y]]
                // a moon may pass through its own ringed planet's flat ring
                let family: Bool = a.parent == kept[y] || b.parent == kept[x]
                if family && (a.ringed || b.ringed) { continue }
                let limit: Float = keepOut(a, grow: grow) + keepOut(b, grow: grow)
                let gap: Float = distance(at[x], at[y])
                if gap < limit - 1e-4 && bad.count < 5 {
                    bad.append("\(a.title)/\(b.title) t=\(t) d=\(gap) < \(limit)")
                }
            }
        }
        t += step
    }
    return bad
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

// MARK: T1 the design preview's roles

let preview: UniversePlan = GraphUniverse.plan(previewInput())
check("T1 two galaxies", titles(preview, .galaxy) == ["Cardiology", "Examples"], "\(titles(preview, .galaxy))")
check("T1 three stars", titles(preview, .star) == ["Inguinal", "Femoral", "Anatomy"], "\(titles(preview, .star))")
let expectedGas: Set<String> = [
    "Heart failure", "Groin hernia", "Inguinal canal", "Femoral hernia", "Indirect inguinal hernia",
    "Direct inguinal hernia", "Acute coronary syndrome", "Atrial fibrillation", "Murmurs"
]
check("T1 nine gas giants", titles(preview, .gasGiant) == expectedGas, "\(titles(preview, .gasGiant))")
let expectedRocky: Set<String> = [
    "Inferior epigastric vessels", "Internal ring test", "Canal boundaries", "Spermatic cord coverings",
    "Loop diuretics", "ACE inhibitors", "Hypokalaemia", "NSTEMI", "Troponin", "STEMI", "Heart sounds", "Syncope"
]
check("T1 twelve rocky planets", titles(preview, .rocky) == expectedRocky, "\(titles(preview, .rocky))")
let expectedMoons: [String: String] = [
    "Hernia repair": "Groin hernia", "LA/PM mnemonic": "Canal boundaries", "Femoral canal": "Femoral hernia",
    "Saphena varix": "Femoral hernia", "BNP": "Heart failure", "CHA2DS2-VASc": "Atrial fibrillation"
]
var foundMoons: [String: String] = [:]
for body in preview.bodies where body.role == .moon {
    foundMoons[body.title] = preview.bodies[body.parent].title
}
check("T1 six moons round their planets", foundMoons == expectedMoons, "\(foundMoons)")
check("T1 one pulsar", titles(preview, .pulsar) == ["Expansile cough impulse"], "\(titles(preview, .pulsar))")
check("T1 two comets", titles(preview, .comet) == ["Pericarditis", "Richter's hernia"], "\(titles(preview, .comet))")
let ringedTitles: Set<String> = Set(preview.bodies.filter(\.ringed).map(\.title))
check("T1 only Heart failure is ringed", ringedTitles == ["Heart failure"], "\(ringedTitles)")
let sizes: [(String, Float)] = [
    ("Cardiology", 0.459), ("Examples", 0.459), ("Inguinal", 0.332), ("Femoral", 0.320), ("Anatomy", 0.299),
    // gas giants by their real word counts: 272, 63, 50, 44, 43, 29 and under 15
    ("Heart failure", 0.24), ("Inguinal canal", 0.22), ("Groin hernia", 0.21), ("Femoral hernia", 0.21),
    ("Indirect inguinal hernia", 0.21), ("Direct inguinal hernia", 0.20), ("Acute coronary syndrome", 0.19),
    ("Atrial fibrillation", 0.19), ("Murmurs", 0.19), ("Expansile cough impulse", 0.07)
]
var wrongSizes: [String] = []
for (title, size) in sizes {
    let got: Float = bodyNamed(preview, title).map { preview.bodies[$0].sphere } ?? -1
    if !near(got, size) { wrongSizes.append("\(title) \(got) not \(size)") }
}
check("T1 sizes on the ladder", wrongSizes.isEmpty, "\(wrongSizes)")
let tiers: [(String, Int)] = [("Inguinal", 1), ("Femoral", 1), ("Anatomy", 2)]
let gotTiers: [Int] = tiers.map { pair in bodyNamed(preview, pair.0).map { preview.bodies[$0].tier } ?? -1 }
check("T1 star tiers: Inguinal and Femoral yellow-white, Anatomy orange", gotTiers == tiers.map(\.1), "\(gotTiers)")
let labels: [String] = [
    "Examples \u{00B7} 14 notes", "Inguinal \u{00B7} 8 notes", "Anatomy \u{00B7} 3 notes",
    "Femoral \u{00B7} 3 notes", "Cardiology \u{00B7} 14 notes"
]
let shownLabels: Set<String> = Set(preview.bodies.map(\.label))
let missingLabels: [String] = labels.filter { !shownLabels.contains($0) }
check("T1 folder labels with counts", missingLabels.isEmpty, "\(missingLabels)")
let previewSummary: String = "2 galaxies, 3 stars, 21 planets, 6 moons, 1 pulsar, 2 comets"
check("T1 summary", preview.summary == previewSummary, preview.summary)
if let anatomy = bodyNamed(preview, "Anatomy"), let inguinal = bodyNamed(preview, "Inguinal") {
    check("T1 Anatomy stands beside Inguinal", preview.bodies[anatomy].parent == inguinal)
}
let heartWords: Int = GraphUniverse.wordCount(heartFailureBody)
check("T1 Heart failure has 250 words or more", heartWords >= 250, "\(heartWords)")

// MARK: T2 the ladder, over 200 random vaults

var ladderBad: [String] = []
var containmentBad: [String] = []
for k in 0..<200 {
    let plan: UniversePlan = GraphUniverse.plan(randomVault(UInt64(k) &+ 77, maxNotes: 300, maxFolders: 40))
    var lowest: [UniverseRole: Float] = [:]
    var highest: [UniverseRole: Float] = [:]
    for body in plan.bodies {
        var role: UniverseRole = body.role
        if role == .home { role = .star }
        if role == .oort || role == .comet { continue }
        lowest[role] = min(lowest[role] ?? 9, body.sphere)
        highest[role] = max(highest[role] ?? 0, body.sphere)
        // every container holds bodies smaller than itself
        guard body.parent >= 0 else { continue }
        let holder: UniverseBody = plan.bodies[body.parent]
        let ok: Bool = body.sphere < holder.sphere
        if !ok && containmentBad.count < 3 { containmentBad.append("vault \(k): \(body.title) in \(holder.title)") }
    }
    let ladder: [UniverseRole] = [.galaxy, .star, .gasGiant, .rocky, .moon, .pulsar]
    for pair in zip(ladder, ladder.dropFirst()) {
        guard let small = lowest[pair.0], let big = highest[pair.1] else { continue }
        if small <= big && ladderBad.count < 3 { ladderBad.append("vault \(k): \(pair.0) \(small) <= \(pair.1) \(big)") }
    }
}
check("T2 ladder: core > star > gas > rocky > moon > pulsar", ladderBad.isEmpty, "\(ladderBad)")
check("T2 every container is bigger than anything it holds (a star than its own, strictly)", containmentBad.isEmpty,
      "\(containmentBad)")

// MARK: T3 determinism

let again: UniversePlan = GraphUniverse.plan(previewInput())
check("T3 planning twice gives identical bodies", again.bodies == preview.bodies)
let base: UniverseInput = randomVault(4242, maxNotes: 120, maxFolders: 12)
var dice = Dice(state: 99)
let shuffled = UniverseInput(notes: base.notes.shuffled(using: &dice), folders: base.folders.shuffled(using: &dice),
                             edges: base.edges.shuffled(using: &dice).map { UniverseEdge(a: $0.b, b: $0.a) },
                             seedByName: false)
let planA: UniversePlan = GraphUniverse.plan(base)
let planB: UniversePlan = GraphUniverse.plan(shuffled)
check("T3 shuffled input gives the same plan", planA.bodies == planB.bodies && planA.links == planB.links)
check("T3 same shells", planA.shells == planB.shells)

// MARK: T4 no overlap over ten minutes

check("T4 preview: no overlaps", overlaps(preview, grow: 1).isEmpty, "\(overlaps(preview, grow: 1))")
check("T4 preview: none with note spheres x1.5", overlaps(preview, grow: 1.5).isEmpty,
      "\(overlaps(preview, grow: 1.5))")
let bigVault: UniversePlan = GraphUniverse.plan(randomVault(2024, maxNotes: 220, maxFolders: 19))
check("T4 big vault: no overlaps", overlaps(bigVault, grow: 1, step: 10).isEmpty,
      "\(overlaps(bigVault, grow: 1, step: 10))")
check("T4 big vault: none with x1.5", overlaps(bigVault, grow: 1.5, step: 10).isEmpty,
      "\(overlaps(bigVault, grow: 1.5, step: 10))")
var randomOverlaps: [String] = []
for k in 0..<12 {
    let plan: UniversePlan = GraphUniverse.plan(randomVault(UInt64(k) &+ 500, maxNotes: 150, maxFolders: 20))
    randomOverlaps += overlaps(plan, grow: 1, step: 20)
}
check("T4 random vaults: no overlaps", randomOverlaps.isEmpty, "\(randomOverlaps.prefix(3))")

// MARK: T5 the envelope holds everything

func envelopeHolds(_ plan: UniversePlan) -> [String] {
    guard let first = plan.envelope.first else { return [] }
    var lo: SIMD3<Float> = first
    var hi: SIMD3<Float> = first
    for p in plan.envelope {
        lo = pointwiseMin(lo, p)
        hi = pointwiseMax(hi, p)
    }
    var bad: [String] = []
    var t: Double = 0
    while t <= 600 {
        for (i, body) in plan.bodies.enumerated() {
            let p: SIMD3<Float> = GraphUniverse.position(of: i, in: plan, time: t)
            let r: Float = body.sphere + 0.001
            let inside: Bool = all(p .>= lo - r) && all(p .<= hi + r)
            if !inside && bad.count < 3 { bad.append("\(body.title) at t=\(t): \(p) not in \(lo)...\(hi)") }
        }
        t += 10
    }
    return bad
}
check("T5 preview inside its envelope", envelopeHolds(preview).isEmpty, "\(envelopeHolds(preview))")
check("T5 big vault inside its envelope", envelopeHolds(bigVault).isEmpty, "\(envelopeHolds(bigVault))")

// MARK: T6 structure: cycles, missing parents, missing folders

let fa: UUID = fixedID(501)
let fb: UUID = fixedID(502)
let fc: UUID = fixedID(503)
let gone: UUID = fixedID(599)
let cycleInput = UniverseInput(
    notes: [
        UniverseNote(id: fixedID(1), title: "n1", isPage: false, folder: fa, words: 5, created: 1),
        UniverseNote(id: fixedID(2), title: "n2", isPage: true, folder: fb, words: 500, created: 2),
        UniverseNote(id: fixedID(3), title: "n3", isPage: false, folder: gone, words: 5, created: 3),
        UniverseNote(id: fixedID(4), title: "n4", isPage: false, folder: fc, words: 5, created: 4)
    ],
    folders: [
        UniverseFolder(id: fa, name: "A", parent: fb), UniverseFolder(id: fb, name: "B", parent: fa),
        UniverseFolder(id: fc, name: "C", parent: gone)
    ],
    edges: [], seedByName: false)
let cyclePlan: UniversePlan = GraphUniverse.plan(cycleInput)
func roleOf(_ plan: UniversePlan, _ title: String) -> UniverseRole? {
    bodyNamed(plan, title).map { plan.bodies[$0].role }
}
check("T6 a two-folder cycle is cut at the smaller uuid", roleOf(cyclePlan, "A") == .galaxy
      && roleOf(cyclePlan, "B") == .star, "A \(String(describing: roleOf(cyclePlan, "A")))")
check("T6 a folder with a missing parent is top level", roleOf(cyclePlan, "C") == .galaxy)
check("T6 a note in a missing folder is a comet", roleOf(cyclePlan, "n3") == .comet)
check("T6 notes in the cycle stay planets", roleOf(cyclePlan, "n1") == .rocky && roleOf(cyclePlan, "n2") == .gasGiant)
check("T6 bodies come after their parents",
      cyclePlan.bodies.indices.allSatisfy { cyclePlan.bodies[$0].parent < $0 })

// MARK: T7 no folders at all

var flatNotes: [UniverseNote] = []
var flatEdges: [UniverseEdge] = []
for k in 0..<20 {
    let note = UniverseNote(id: fixedID(k + 1), title: "Idea \(k)", isPage: k % 3 == 0, folder: nil,
                            words: 10 + 7 * k, created: Double(k))
    flatNotes.append(note)
}
for k in stride(from: 0, to: 18, by: 3) { flatEdges.append(UniverseEdge(a: fixedID(k + 1), b: fixedID(k + 2))) }
let flat: UniversePlan = GraphUniverse.plan(UniverseInput(notes: flatNotes, folders: [], edges: flatEdges,
                                                          seedByName: false))
let homes: [UniverseBody] = flat.bodies.filter { $0.role == .home }
check("T7 one home star", homes.count == 1 && homes.first?.id == GraphUniverse.homeID)
check("T7 its label", homes.first?.label == "Ideas \u{00B7} 20 notes", homes.first?.label ?? "")
check("T7 no comets or pulsars", !flat.bodies.contains { [.comet, .oort, .pulsar, .galaxy].contains($0.role) })
let orbitsHome: Bool = flat.bodies.dropFirst().allSatisfy { body in
    body.parent == 0 || (body.role == .moon && flat.bodies[body.parent].parent == 0)
}
check("T7 every note orbits it or its planets", orbitsHome)
check("T7 summary", flat.summary.hasPrefix("1 star, "), flat.summary)

// MARK: T8 comets

var looseNotes: [UniverseNote] = []
for k in 0..<40 {
    let note = UniverseNote(id: fixedID(k + 1), title: String(format: "Loose %02d", k), isPage: false,
                            folder: nil, words: 20, created: Double(k))
    looseNotes.append(note)
}
let lone: UUID = fixedID(700)
looseNotes.append(UniverseNote(id: fixedID(99), title: "x", isPage: true, folder: lone, words: 300, created: 99))
let cometPlan: UniversePlan = GraphUniverse.plan(UniverseInput(
    notes: looseNotes, folders: [UniverseFolder(id: lone, name: "F", parent: nil)], edges: [], seedByName: false))
let active: [UniverseBody] = cometPlan.bodies.filter { $0.role == .comet }
let resting: [UniverseBody] = cometPlan.bodies.filter { $0.role == .oort }
check("T8 twelve active comets", active.count == 12, "\(active.count)")
check("T8 twenty-eight in the Oort cloud", resting.count == 28, "\(resting.count)")
let newest: Set<String> = Set((28..<40).map { String(format: "Loose %02d", $0) })
check("T8 the newest fly", Set(active.map(\.title)) == newest)
check("T8 summary", cometPlan.summary == "1 galaxy, 1 planet, 40 comets", cometPlan.summary)

// MARK: T9 moons

var moonBad: [String] = []
for k in 0..<60 {
    let input: UniverseInput = randomVault(UInt64(k) &+ 3000, maxNotes: 200, maxFolders: 15)
    let plan: UniversePlan = GraphUniverse.plan(input)
    var words: [UUID: Int] = [:]
    var folderOf: [UUID: UUID?] = [:]
    for note in input.notes {
        words[note.id] = note.words
        folderOf[note.id] = note.folder
    }
    var perPlanet: [Int: Int] = [:]
    for body in plan.bodies where body.role == .moon {
        let planet: UniverseBody = plan.bodies[body.parent]
        perPlanet[body.parent, default: 0] += 1
        let short: Bool = (words[body.id] ?? 99) < 60
        let sameFolder: Bool = folderOf[body.id] == folderOf[planet.id]
        let strong: Bool = planet.role == .gasGiant || (planet.role == .rocky && planet.links >= 2)
        if !(short && body.links == 1 && sameFolder && strong) && moonBad.count < 3 {
            moonBad.append("\(body.title) round \(planet.title)")
        }
    }
    for (p, n) in perPlanet {
        let cap: Int = plan.bodies[p].role == .gasGiant ? 4 : 2
        if n > cap && moonBad.count < 3 { moonBad.append("\(plan.bodies[p].title) has \(n) moons") }
    }
}
check("T9 moons: short, one link, same folder, a strong planet, capped", moonBad.isEmpty, "\(moonBad)")

// MARK: T10 pulsars

var pulsarBad: [String] = []
for k in 0..<60 {
    let input: UniverseInput = randomVault(UInt64(k) &+ 5000, maxNotes: 200, maxFolders: 15)
    let plan: UniversePlan = GraphUniverse.plan(input)
    var galaxies: [Int: Int] = [:]
    var pageOf: [UUID: Bool] = [:]
    for note in input.notes { pageOf[note.id] = note.isPage }
    for body in plan.bodies where body.role == .pulsar {
        galaxies[body.galaxy, default: 0] += 1
        if pageOf[body.id] == true { pulsarBad.append("a page is a pulsar") }
    }
    if galaxies.values.contains(where: { $0 > 1 }) { pulsarBad.append("vault \(k): two pulsars in a galaxy") }
}
check("T10 at most one pulsar per galaxy, ideas only", pulsarBad.isEmpty, "\(pulsarBad.prefix(3))")
// thresholds: two other folders and three cross links
let g1: UUID = fixedID(801)
let s1: UUID = fixedID(802)
let s2: UUID = fixedID(803)
let s3: UUID = fixedID(804)
func bridge(_ targets: [UUID?], page: Bool = false) -> UniversePlan {
    var notes: [UniverseNote] = [UniverseNote(id: fixedID(1), title: "Bridge", isPage: page, folder: g1, words: 20,
                                              created: 0)]
    var edges: [UniverseEdge] = []
    for (k, folder) in targets.enumerated() {
        let id: UUID = fixedID(k + 10)
        notes.append(UniverseNote(id: id, title: "T\(k)", isPage: true, folder: folder, words: 100, created: 1))
        edges.append(UniverseEdge(a: fixedID(1), b: id))
    }
    let folders: [UniverseFolder] = [
        UniverseFolder(id: g1, name: "G", parent: nil), UniverseFolder(id: s1, name: "S1", parent: g1),
        UniverseFolder(id: s2, name: "S2", parent: g1), UniverseFolder(id: s3, name: "S3", parent: nil)
    ]
    return GraphUniverse.plan(UniverseInput(notes: notes, folders: folders, edges: edges, seedByName: false))
}
check("T10 two folders, three links: a pulsar", roleOf(bridge([s1, s2, s2]), "Bridge") == .pulsar)
check("T10 one other folder: a planet", roleOf(bridge([s1, s1, s1]), "Bridge") == .rocky)
check("T10 two cross links: a planet", roleOf(bridge([s1, s2]), "Bridge") != .pulsar)
check("T10 loose notes do not count", roleOf(bridge([s1, nil, nil]), "Bridge") != .pulsar)
check("T10 another galaxy counts", roleOf(bridge([s1, s3, s3]), "Bridge") == .pulsar)
check("T10 a bridging page stays a gas giant", roleOf(bridge([s1, s2, s2], page: true), "Bridge") == .gasGiant)

// MARK: T11 orbits

var rateBad: [String] = []
for plan in [preview, bigVault] {
    var byOwner: [Int: [(Float, Float)]] = [:]
    for body in plan.bodies where body.shell >= 0 {
        if case .circle(let r, _, _, _, let rate) = body.orbit { byOwner[body.parent, default: []].append((r, rate)) }
    }
    for (_, list) in byOwner {
        let sorted: [(Float, Float)] = list.sorted { $0.0 < $1.0 }
        for pair in zip(sorted, sorted.dropFirst()) where pair.1.1 > pair.0.1 + 1e-6 {
            rateBad.append("r \(pair.0.0) rate \(pair.0.1) then r \(pair.1.0) rate \(pair.1.1)")
        }
    }
}
check("T11 rates fall with radius", rateBad.isEmpty, "\(rateBad.prefix(3))")
let kepler: GraphOrbit = .kepler(a: 4, e: 0.45, u: SIMD3<Float>(1, 0, 0), v: SIMD3<Float>(0, 1, 0), phase: 0,
                                 rate: 0.02)
let peri: Float = distance(GraphUniverse.offset(kepler, time: 0), SIMD3<Float>(0, 0, 0))
check("T11 a comet at phase 0 is a(1 - e) out", near(peri, 4 * 0.55, 1e-4), "\(peri)")
var ringBad: [String] = []
for plan in [preview, bigVault] {
    for body in plan.bodies where body.role == .moon {
        let planet: UniverseBody = plan.bodies[body.parent]
        guard case .circle(let am, _, _, _, _) = body.orbit else { continue }
        let k: Float = planet.ringed ? 2.5 : 1.8
        let clearance: Float = am - body.sphere - k * planet.sphere
        if clearance < 0.03 - 1e-4 { ringBad.append("\(body.title): \(clearance)") }
    }
}
check("T11 moon rings clear their planet by 0.03", ringBad.isEmpty, "\(ringBad.prefix(3))")
var still: Bool = true
for (i, body) in preview.bodies.enumerated() where [.galaxy, .star, .home].contains(body.role) {
    let p0: SIMD3<Float> = GraphUniverse.position(of: i, in: preview, time: 0)
    let p1: SIMD3<Float> = GraphUniverse.position(of: i, in: preview, time: 321)
    if distance(p0, p1) > 1e-5 || distance(p0, body.home) > 1e-4 { still = false }
}
check("T11 stars and cores never move", still)
var homesMatch: Bool = true
for (i, body) in preview.bodies.enumerated() {
    let p: SIMD3<Float> = GraphUniverse.position(of: i, in: preview, time: 0)
    if distance(p, body.home) > 1e-3 { homesMatch = false }
}
check("T11 each body's home is where it is at time 0", homesMatch)

// MARK: T12 performance

let huge: UniverseInput = randomVault(31337, maxNotes: 1000, maxFolders: 120)
var hugeNotes: [UniverseNote] = huge.notes
var hugeDice = Dice(state: 5)
while hugeNotes.count < 1000 {
    let k: Int = hugeNotes.count
    let folder: UUID? = huge.folders.isEmpty ? nil : huge.folders[hugeDice.below(huge.folders.count)].id
    hugeNotes.append(UniverseNote(id: fixedID(k + 1), title: "Note \(k)", isPage: k % 4 == 0, folder: folder,
                                  words: 40 + k % 700, created: Double(k)))
}
var hugeFolders: [UniverseFolder] = huge.folders
while hugeFolders.count < 120 {
    let k: Int = hugeFolders.count
    let parent: UUID? = k % 3 == 0 ? nil : hugeFolders[k / 2].id
    hugeFolders.append(UniverseFolder(id: fixedID(20_000 + k), name: "Extra \(k)", parent: parent))
}
let hugeInput = UniverseInput(notes: hugeNotes, folders: hugeFolders, edges: huge.edges, seedByName: false)
let started: Date = Date()
let hugePlan: UniversePlan = GraphUniverse.plan(hugeInput)
let took: Double = Date().timeIntervalSince(started) * 1000
check("T12 1000 notes and 120 folders plan in under 300 ms", took < 300, "\(Int(took)) ms")
print("     planned in \(Int(took)) ms")
check("T12 every note has a body", hugePlan.bodies.count == 1120, "\(hugePlan.bodies.count)")

// MARK: T13 words and levels

check("T13 words", GraphUniverse.wordCount("  a b\n\nc ") == 3)
check("T13 no words", GraphUniverse.wordCount(" \t\r\n") == 0)
let levelCases: [(Int, Int)] = [(0, 0), (14, 0), (15, 1), (249, 4), (250, 5), (2000, 8), (99_999, 8)]
let wrongLevels: [Int] = levelCases.filter { GraphUniverse.level(words: $0.0) != $0.1 }.map(\.0)
check("T13 levels: 0, 14 -> 0; 15 -> 1; 249 -> 4; 250 -> 5; 2000 and more -> 8", wrongLevels.isEmpty,
      "\(wrongLevels)")

// MARK: T14 link kinds

func linkKind(_ plan: UniversePlan, _ a: String, _ b: String) -> UniverseLink? {
    guard let i = bodyNamed(plan, a), let j = bodyNamed(plan, b) else { return nil }
    return plan.links.first { ($0.a == i && $0.b == j) || ($0.a == j && $0.b == i) }
}
check("T14 a moon and its planet: hidden", linkKind(preview, "BNP", "Heart failure")?.kind == 3)
check("T14 same folder: straight", linkKind(preview, "Loop diuretics", "Hypokalaemia")?.kind == 0)
let sameGalaxy: UniverseLink? = linkKind(preview, "Femoral hernia", "Inguinal canal")
let examplesCore: Int = bodyNamed(preview, "Examples") ?? -9
check("T14 same galaxy: arched round its core", sameGalaxy?.kind == 1 && sameGalaxy?.centre == examplesCore)
let toComet: UniverseLink? = linkKind(preview, "Pericarditis", "STEMI")
check("T14 to a loose note: far", toComet?.kind == 2 && toComet?.centre == -1)
check("T14 every link joins two bodies", preview.links.allSatisfy { $0.a >= 0 && $0.b >= 0 && $0.a != $0.b })

// MARK: the owner's cases: deep nesting, empty and one-note folders, 300 notes

var chain: [UniverseFolder] = []
var chainNotes: [UniverseNote] = []
for k in 0..<7 {
    let parent: UUID? = k == 0 ? nil : chain[k - 1].id
    chain.append(UniverseFolder(id: fixedID(600 + k), name: "Deep \(k)", parent: parent))
    chainNotes.append(UniverseNote(id: fixedID(k + 1), title: "d\(k)", isPage: false, folder: chain[k].id,
                                   words: 20, created: Double(k)))
}
let deep: UniversePlan = GraphUniverse.plan(UniverseInput(notes: chainNotes, folders: chain, edges: [],
                                                          seedByName: false))
let deepTiers: [Int] = (0..<7).compactMap { k in bodyNamed(deep, "Deep \(k)").map { deep.bodies[$0].tier } }
check("deep nesting: tiers 0, 1, 2, then red dwarfs", deepTiers == [0, 1, 2, 3, 3, 3, 3], "\(deepTiers)")
let deepSizes: [Float] = (0..<7).compactMap { k in bodyNamed(deep, "Deep \(k)").map { deep.bodies[$0].sphere } }
let shrinking: Bool = zip(deepSizes, deepSizes.dropFirst()).allSatisfy { $0.1 < $0.0 }
let aboveGas: Bool = deepSizes.allSatisfy { $0 > 0.26 }
check("deep nesting: always smaller than the parent, never down to a gas giant", shrinking && aboveGas,
      "\(deepSizes)")
let floors: [Double] = (1..<8).map { GraphUniverse.starFloor($0) }
let fallingFloors: Bool = zip(floors, floors.dropFirst()).allSatisfy { $0.1 < $0.0 } && floors.allSatisfy { $0 > 0.26 }
check("the star floor falls with depth and stays above 0.26", fallingFloors, "\(floors)")
check("deep nesting: nothing flattened", deep.bodies.filter { $0.role == .star }.count == 6)
check("deep nesting: no overlaps", overlaps(deep, grow: 1).isEmpty, "\(overlaps(deep, grow: 1))")

let top1: UUID = fixedID(650)
let sub1: UUID = fixedID(651)
let emptyTop: UUID = fixedID(652)
let emptySub: UUID = fixedID(653)
let emptyDeeper: UUID = fixedID(654)
let sparse: UniversePlan = GraphUniverse.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "Only", isPage: false, folder: sub1, words: 8, created: 0)],
    folders: [
        UniverseFolder(id: top1, name: "Top", parent: nil), UniverseFolder(id: sub1, name: "One", parent: top1),
        UniverseFolder(id: emptyTop, name: "Nothing", parent: nil),
        UniverseFolder(id: emptySub, name: "Hollow", parent: top1),
        UniverseFolder(id: emptyDeeper, name: "Hollower", parent: emptySub)
    ],
    edges: [], seedByName: false))
let oneNote: UniverseBody? = bodyNamed(sparse, "One").map { sparse.bodies[$0] }
check("a one-note folder: a star with one planet", oneNote?.role == .star && oneNote?.label == "One \u{00B7} 1 note")
let only: UniverseBody? = bodyNamed(sparse, "Only").map { sparse.bodies[$0] }
check("its note orbits it", only.map { sparse.bodies[$0.parent].title } == "One")
let dormant: UniverseBody? = bodyNamed(sparse, "Nothing").map { sparse.bodies[$0] }
check("an empty top folder: a dormant black hole", dormant?.role == .galaxy && dormant?.empty == true
      && near(dormant?.sphere ?? 0, 0.40) && dormant?.label == "Nothing \u{00B7} empty")
let dark: UniverseBody? = bodyNamed(sparse, "Hollow").map { sparse.bodies[$0] }
check("an empty subfolder: a dark star", dark?.role == .star && dark?.empty == true && near(dark?.sphere ?? 0, 0.278))
let darker: UniverseBody? = bodyNamed(sparse, "Hollower").map { sparse.bodies[$0] }
check("an empty folder in it: a smaller dark star", darker?.empty == true && (darker?.sphere ?? 1) < (dark?.sphere ?? 0),
      "\(darker?.sphere ?? -1) vs \(dark?.sphere ?? -1)")
check("empty folders do not shine", !sparse.lights.contains { sparse.bodies[$0].empty })

let loosePlan: UniversePlan = GraphUniverse.plan(UniverseInput(
    notes: [
        UniverseNote(id: fixedID(1), title: "Filed", isPage: true, folder: top1, words: 80, created: 0),
        UniverseNote(id: fixedID(2), title: "Root note", isPage: false, folder: nil, words: 8, created: 1)
    ],
    folders: [UniverseFolder(id: top1, name: "Top", parent: nil)],
    edges: [UniverseEdge(a: fixedID(1), b: fixedID(2))], seedByName: false))
let rootNote: UniverseBody? = bodyNamed(loosePlan, "Root note").map { loosePlan.bodies[$0] }
check("a note in no folder is a comet with no parent", rootNote?.role == .comet && rootNote?.parent == -1)
check("it lights from the nearest star", rootNote?.light == -2)

let scale: UniversePlan = GraphUniverse.plan(randomVault(300, maxNotes: 300, maxFolders: 30, exact: true))
let notesPlanned: Int = scale.bodies.filter { $0.count == 0 && ![.galaxy, .star, .home].contains($0.role) }.count
check("300-note scale: every note planned", notesPlanned == 300, "\(notesPlanned) notes")
check("300-note scale: no overlaps", overlaps(scale, grow: 1, step: 20).isEmpty, "\(overlaps(scale, grow: 1, step: 20))")
check("300-note scale: inside the envelope", envelopeHolds(scale).isEmpty, "\(envelopeHolds(scale))")

let longName: String = String(repeating: "Cardiothoracic ", count: 3)
let named: UniversePlan = GraphUniverse.plan(UniverseInput(
    notes: [UniverseNote(id: fixedID(1), title: "", isPage: false, folder: top1, words: 3, created: 0)],
    folders: [UniverseFolder(id: top1, name: longName, parent: nil)], edges: [], seedByName: false))
let cut: String = String(longName.prefix(20)) + "\u{2026} \u{00B7} 1 note"
check("a long folder name is cut but the count shows", named.bodies.first?.label == cut, named.bodies.first?.label ?? "")
check("an empty title shows Untitled", named.bodies.last?.label == "Untitled")

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
