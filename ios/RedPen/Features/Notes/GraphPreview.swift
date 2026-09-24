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
///
/// The space is exposed to UI tests as the element "graph3D".
enum GraphPreview {
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreview")
    static let drags: Bool = ProcessInfo.processInfo.arguments.contains("-graphPreviewDrag")

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
