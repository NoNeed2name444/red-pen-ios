import SwiftUI

/// A launch hook for the design preview: pictures of the 3D idea map taken
/// in the simulator by GraphPreviewUITests, for the owner to see before
/// trying the app.
///
/// - `-graphPreview` opens straight into the space, full screen, before any
///   sign-in or terms screen, on a throwaway store of 30 example notes in
///   five folders, joined by links. Nothing the user owns is read or
///   written. It shows the Universe (GraphUniverse): Cardiology and
///   Examples as two galaxies round their black holes; Inguinal and Femoral
///   as stars beside Examples' core, with Anatomy an orange companion star
///   inside Inguinal; pages as gas giants (Heart failure, a long read,
///   ringed), ideas as rocky planets, six short one-link ideas as moons,
///   "Expansile cough impulse" - linking both hernia folders - as Examples'
///   pulsar, and two notes in no folder as comets. A moment (1.5 s) after
///   the space appears the busiest note (Heart failure) is chosen and its
///   name shown - not held as a press, which would stop the orbits - so the
///   picture at rest shows one name on its pill and the Universe still
///   turns.
/// - `-graphPreviewDrag`, as well, has the app pick up the busiest star
///   (Inguinal; the most-linked note in a single look) a second after the
///   space appears, carry it along an arc for two seconds and let go (see
///   GraphSCNView.Coordinator), so a screenshot can catch its system
///   following.
/// - `-graphPreviewFly <folder>` flies in to that folder's system 1.5 s
///   after the space appears, and holds it, instead of choosing a note.
/// - `-graphPreviewLegend` opens "What the bodies mean" a second after the
///   space appears.
/// - `-graphPreviewStyle <name>` (blackHole, sun, rocky, gasGiant, pulsar,
///   comet) shows every note in that one style in today's force layout
///   instead.
/// - `-graphPreviewTheme neurons` shows the Neurons theme (GraphNeurons):
///   Cardiology and Examples as two brain regions, Inguinal and Femoral
///   relays out along Examples' pathway with Anatomy one step further,
///   pages as large neurons, ideas as interneurons, the six short one-link
///   ideas as glia on their neurons, the bridging idea as a commissural
///   neuron and the two loose notes as receptors. `-graphPreviewFly` and
///   `-graphPreviewLegend` work with it too.
/// - `-graphPreviewTheme circuit` shows the Circuit theme (GraphCircuit):
///   Cardiology and Examples as two circuit boards side by side on the
///   bench, each with its chip, power rail along the top and ground rail
///   along the bottom; Inguinal and Femoral as smaller chips on sub-boards
///   on branches of Examples' bus, with Anatomy on Inguinal's; pages as
///   capacitors, ideas as LEDs in branches off the pages they link to, and
///   the two loose notes as gold pads on their boards' left edges.
///   `-graphPreviewFly`, `-graphPreviewDrag` and `-graphPreviewLegend`
///   work with it too.
/// - `-graphPreviewRemove [names]` deletes some folders and notes three
///   seconds in (see `removes`), in any theme, to show them dying.
///
/// The Universe seeds by names here, as the store's ids change every
/// launch. The owner's own look setting is never read or written. The space
/// is exposed to UI tests as the element "graph3D".
enum GraphPreview {
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreview")
    static let drags: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreviewDrag")
    /// The legend is opened a second after appearing.
    static let showsLegend: Bool = isOn && ProcessInfo.processInfo.arguments.contains("-graphPreviewLegend")
    /// The folder to fly in to, asked for with `-graphPreviewFly`.
    static let fly: String? = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-graphPreviewFly"), at + 1 < args.count else { return nil }
        return args[at + 1]
    }()
    /// What `-graphPreviewRemove [titles]` deletes from the preview's store
    /// three seconds after the space appears, so screenshots can catch the
    /// bodies dying (GraphDeath): the folders and notes named in the
    /// comma-separated list that follows, or by default the Femoral and
    /// Anatomy folders (stars; relays; sub-chips) and BNP, Murmurs, Troponin,
    /// Expansile cough impulse and Richter's hernia (a moon, a gas giant, a
    /// rocky planet, the pulsar and a comet; cells; parts). Nil without it.
    static let removes: [String]? = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard isOn, let at = args.firstIndex(of: "-graphPreviewRemove") else { return nil }
        if at + 1 < args.count, !args[at + 1].hasPrefix("-") {
            return args[at + 1].split(separator: ",").map { String($0) }
        }
        return ["Femoral", "Anatomy", "BNP", "Murmurs", "Troponin", "Expansile cough impulse", "Richter's hernia"]
    }()

    /// Deletes what `removes` names: a folder by name (its notes move up),
    /// else a note by title.
    @MainActor
    static func remove(from store: NoteStore) {
        guard let names = removes else { return }
        for name in names {
            if let folder = store.folders.first(where: { $0.name == name }) {
                store.deleteFolder(folder.id)
            } else if let note = store.notes.first(where: { $0.title == name }) {
                store.delete(note.id)
            }
        }
    }

    /// Choose one note shortly after appearing (see GraphSCNView.Coordinator).
    static let chooses: Bool = isOn && !drags && fly == nil && select == nil && hold == nil

    /// `-graphPreviewSelect <title or folder>`: a moment after the map
    /// appears, that body is tapped - chosen, its peek card up. With
    /// `-graphPreviewOpen` too, the card's Open is pressed a moment later.
    static let select: String? = argument("-graphPreviewSelect")
    static let opens: Bool = isOn && ProcessInfo.processInfo.arguments.contains("-graphPreviewOpen")
    /// `-graphPreviewHold <title or folder>`: that body is held still - its
    /// options open beside it.
    static let hold: String? = argument("-graphPreviewHold")
    /// `-graphPreviewLinkLength <0.6...1.8>`: the map planned at that link
    /// length (never the owner's stored one).
    static let linkLength: Double? = argument("-graphPreviewLinkLength").flatMap { Double($0) }

    /// The value after a launch argument, in the design preview.
    private static func argument(_ flag: String) -> String? {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard args.contains("-graphPreview"), let at = args.firstIndex(of: flag), at + 1 < args.count else { return nil }
        return args[at + 1]
    }

    /// The theme asked for with `-graphPreviewTheme <name>` (space,
    /// neurons, circuit); Space without one.
    static let theme: GraphTheme = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-graphPreviewTheme"), at + 1 < args.count else { return .space }
        return GraphTheme.stored(args[at + 1])
    }()

    /// The one style asked for with `-graphPreviewStyle`, if any.
    static let style: GraphNodeStyle? = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-graphPreviewStyle"), at + 1 < args.count else { return nil }
        return GraphNodeStyle(rawValue: args[at + 1])
    }()

    /// The groin hernia examples (Examples, Inguinal with its Anatomy
    /// inside, Femoral), the bridging idea, a Cardiology folder of 14 more
    /// and two ideas in no folder, on a file in the temporary folder.
    @MainActor
    static func makeStore() -> NoteStore {
        let name = "redpen-graph-preview-\(UUID().uuidString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let store = NoteStore(fileURL: url)
        NoteExamples.seed(into: store)
        addAnatomy(to: store)
        addCardiology(to: store)
        addBridgeAndLoose(to: store)
        return store
    }

    /// A subfolder inside a subfolder: Anatomy in Inguinal, holding the
    /// canal's walls, their mnemonic and the cord's coverings.
    @MainActor
    private static func addAnatomy(to store: NoteStore) {
        guard let inguinal = store.folders.first(where: { $0.name == "Inguinal" }) else { return }
        let anatomy = store.createFolder(name: "Anatomy", parentId: inguinal.id)
        let moved: [String] = ["Canal boundaries", "LA/PM mnemonic", "Spermatic cord coverings"]
        for note in store.notes where moved.contains(note.title) {
            store.move(note.id, to: anatomy.id)
        }
    }

    @MainActor
    private static func addCardiology(to store: NoteStore) {
        let folder = store.createFolder(name: "Cardiology")
        func add(_ title: String, _ kind: NoteKind, _ body: String) -> Note {
            store.create(title: title, body: body, kind: kind, folderId: folder.id, at: (x: 0, y: 0))
        }
        // a long read: a ringed gas giant
        let heartFailure = add("Heart failure", .page, """
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
        """)
        _ = add("BNP", .idea, "Raised in [[Heart failure]]; a normal level makes it unlikely.")
        _ = add("Loop diuretics", .idea, "Furosemide for congestion in [[Heart failure]]. Watch [[Hypokalaemia]].")
        _ = add("ACE inhibitors", .idea, "Prognostic in [[Heart failure]]. Cough; check [[Hypokalaemia]] the other way.")
        _ = add("Hypokalaemia", .idea, "Flat T waves, U waves. Risk with [[Loop diuretics]].")
        let acs = add("Acute coronary syndrome", .page, """
        [[STEMI]], [[NSTEMI]] and unstable angina. [[Troponin]] tells them apart.
        """)
        _ = add("STEMI", .idea, "ST elevation: primary PCI. Part of [[Acute coronary syndrome]].")
        _ = add("NSTEMI", .idea, "Raised [[Troponin]] without ST elevation.")
        _ = add("Troponin", .idea, "Rises in 3 hours, peaks at 24. [[Acute coronary syndrome]].")
        let af = add("Atrial fibrillation", .page, """
        Irregularly irregular. Rate or rhythm control; [[CHA2DS2-VASc]] for anticoagulation.
        """)
        _ = add("CHA2DS2-VASc", .idea, "Stroke risk in [[Atrial fibrillation]].")
        let murmurs = add("Murmurs", .page, "Aortic stenosis, mitral regurgitation - and [[Heart failure]] as the end point.")
        // two notes with no links yet
        _ = add("Heart sounds", .idea, "S1 and S2; listen at the apex for S3.")
        _ = add("Syncope", .idea, "Cardiac or not? Exertional syncope needs an echo.")
        store.link(acs.id, heartFailure.id)
        store.link(af.id, heartFailure.id)
        store.link(murmurs.id, af.id)
    }

    /// An idea in Examples linking notes in both its subfolders (the
    /// galaxy's pulsar), and two ideas in no folder (comets).
    @MainActor
    private static func addBridgeAndLoose(to store: NoteStore) {
        guard let examples = store.folders.first(where: { $0.name == "Examples" && $0.parentId == nil }) else { return }
        store.create(title: "Expansile cough impulse", body: """
        Felt over an [[Indirect inguinal hernia]], a [[Direct inguinal hernia]] and a [[Femoral hernia]]. A groin lump with a cough impulse is a hernia until shown otherwise.
        """, kind: .idea, folderId: examples.id, at: (x: 0, y: -300))
        store.create(title: "Richter's hernia", body: """
        Only part of the bowel wall is trapped, so it can strangulate without obstructing. Most often through the femoral ring: see [[Femoral hernia]].
        """, kind: .idea, folderId: nil, at: (x: 300, y: 300))
        store.create(title: "Pericarditis", body: """
        Sharp chest pain, better sitting forward; saddle-shaped ST elevation in many leads and PR depression. Not a [[STEMI]].
        """, kind: .idea, folderId: nil, at: (x: -300, y: 300))
    }
}

/// The whole app, for a `-graphPreview` launch: only the space.
struct GraphPreviewRoot: View {
    @StateObject private var notes: NoteStore = GraphPreview.makeStore()
    /// The library the note editor reads (its cards), empty and in a
    /// temporary file, so Open works in the preview.
    @StateObject private var library: Store = Store(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("redpen-graph-preview-library-\(UUID().uuidString).json"))

    var body: some View {
        Graph3DView(open: { _ in }, openFolder: { _ in })
            .environmentObject(notes)
            .environmentObject(library)
            .background(Color.black)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }
}
