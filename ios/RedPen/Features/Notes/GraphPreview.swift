import SwiftUI

/// A launch hook for the design preview: pictures of the 3D idea map taken
/// in the simulator by GraphPreviewUITests, for the owner to see before
/// trying the app.
///
/// - `-graphPreview` opens straight into the space, full screen, before any
///   sign-in or terms screen, on a throwaway store of about 25 example notes
///   in four folders, joined by links. Nothing the user owns is read or
///   written.
/// - `-graphPreviewDrag`, as well, has the app pick up the most-linked note
///   a second after the space appears, carry it along an arc for two
///   seconds and let go (see GraphSCNView.Coordinator), so a screenshot can
///   catch the moving look.
/// - `-graphPreview` alone has the app choose the most-linked note a moment
///   (1.5 s) after the space appears, as one tap would, so the picture at
///   rest shows one name on its solid pill.
///
/// - The notes take the "Star systems" look (GraphStyleChoice): the
///   most-linked note a black hole, each folder's hub a sun, pages gas
///   giants, ideas rocky planets, the newest note a pulsar and the two
///   unlinked notes comets - so one picture shows every style. The owner's
///   own look setting is never read or written.
/// - `-graphPreviewStyle <name>` (blackHole, sun, rocky, gasGiant, pulsar,
///   comet) shows every note in that one style instead.
///
/// The space is exposed to UI tests as the element "graph3D".
enum GraphPreview {
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreview")
    static let drags: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreviewDrag")
    /// Choose one note shortly after appearing (see GraphSCNView.Coordinator).
    static let chooses: Bool = isOn && !drags

    /// The one style asked for with `-graphPreviewStyle`, if any.
    static let style: GraphNodeStyle? = {
        let args: [String] = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-graphPreviewStyle"), at + 1 < args.count else { return nil }
        return GraphNodeStyle(rawValue: args[at + 1])
    }()

    /// The groin hernia examples (13 notes: Examples, Inguinal, Femoral) and
    /// a Cardiology folder of 12 more, on a file in the temporary folder.
    @MainActor
    static func makeStore() -> NoteStore {
        let name = "redpen-graph-preview-\(UUID().uuidString).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let store = NoteStore(fileURL: url)
        NoteExamples.seed(into: store)
        addCardiology(to: store)
        return store
    }

    @MainActor
    private static func addCardiology(to store: NoteStore) {
        let folder = store.createFolder(name: "Cardiology")
        func add(_ title: String, _ kind: NoteKind, _ body: String) -> Note {
            store.create(title: title, body: body, kind: kind, folderId: folder.id, at: (x: 0, y: 0))
        }
        let heartFailure = add("Heart failure", .page, """
        Reduced or preserved ejection fraction. See [[BNP]], [[Loop diuretics]] and [[ACE inhibitors]].
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
        // two notes with no links yet: they wander as comets
        _ = add("Heart sounds", .idea, "S1 and S2; listen at the apex for S3.")
        _ = add("Syncope", .idea, "Cardiac or not? Exertional syncope needs an echo.")
        store.link(acs.id, heartFailure.id)
        store.link(af.id, heartFailure.id)
        store.link(murmurs.id, af.id)
    }
}

/// The whole app, for a `-graphPreview` launch: only the space.
struct GraphPreviewRoot: View {
    @StateObject private var notes: NoteStore = GraphPreview.makeStore()

    var body: some View {
        Graph3DView(open: { _ in })
            .environmentObject(notes)
            .background(Color.black)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }
}
