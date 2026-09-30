import Foundation

/// A finished example for the idea dump in the personal build, so the list,
/// the board and the space all have something connected to show the first
/// time they are opened.
///
/// The notes are the groin hernia lecture that ships with the personal build
/// (SampleLectures), cut into the kind of pages and one-line ideas a student
/// would actually dump: a hub page, the anatomy, the two inguinal hernias told
/// apart, and the femoral side with its great mimic. They are joined both
/// ways the app joins notes - `[[Title]]` in the text, and a few links made
/// by hand - and laid out on the board as one readable cluster.
///
/// Seeded once: deleting the examples leaves them deleted.
@MainActor
enum NoteExamples {
    static let flag = "examples.ideas.v1"

    static func seedIfNeeded(into store: NoteStore) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        seed(into: store)
    }

    static func seed(into store: NoteStore) {
        let examples = store.createFolder(name: "Examples")
        let inguinal = store.createFolder(name: "Inguinal", parentId: examples.id)
        let femoral = store.createFolder(name: "Femoral", parentId: examples.id)

        func add(_ title: String, _ kind: NoteKind, _ folder: NoteFolder,
                 x: Double, y: Double, _ body: String) -> Note {
            store.create(title: title, body: body, kind: kind, folderId: folder.id, at: (x: x, y: y))
        }

        // the hub everything hangs from
        _ = add("Groin hernia", .page, examples, x: 0, y: 0, """
        Three to know: [[Indirect inguinal hernia]], [[Direct inguinal hernia]] and [[Femoral hernia]].

        - The anatomy first: [[Inguinal canal]]
        - A groin swelling with an expansile impulse on cough is a hernia until shown otherwise.
        - A hernia is a surgical disease - the only treatment is surgery. See [[Hernia repair]].
        """)

        // the anatomy
        let canal = add("Inguinal canal", .page, inguinal, x: -240, y: -150, """
        Develops by the descent of the testis. Runs obliquely from the deep ring to the superficial ring.

        How long is the inguinal canal? | 4 cm, running obliquely
        What does it contain in males? | Spermatic cord; ilio-inguinal nerve
        What does it contain in females? | Round ligament of the uterus; ilio-inguinal nerve

        Walls: [[Canal boundaries]]. Coverings of the cord: [[Spermatic cord coverings]].
        """)
        _ = add("Canal boundaries", .idea, inguinal, x: -470, y: -60, """
        - Anterior: external oblique all through, internal oblique laterally
        - Posterior: fascia transversalis all through, internal oblique medially
        - Roof: conjoined muscles (internal oblique and transversus)
        - Floor: inguinal ligament and lacunar ligament

        Remember it with [[LA/PM mnemonic]].
        """)
        _ = add("LA/PM mnemonic", .idea, inguinal, x: -470, y: -240, """
        Internal oblique sits in the Anterior wall Laterally, and in the Posterior wall Medially. The rest of [[Canal boundaries]] follows.
        """)
        let cord = add("Spermatic cord coverings", .idea, inguinal, x: -240, y: -330, """
        Internal spermatic fascia | From transversalis fascia, at the internal ring
        Cremasteric muscle and fascia | From internal oblique
        External spermatic fascia | From external oblique aponeurosis, at the external ring
        """)

        // the two inguinal hernias, and how to tell them apart
        let indirect = add("Indirect inguinal hernia", .page, inguinal, x: 240, y: -150, """
        - 70% of all hernias; 30% bilateral; males 20 times more often
        - The defect is the stretched deep inguinal ring
        - The sac lies inside the cord and may reach the scrotum
        - Neck of the sac lateral to the [[Inferior epigastric vessels]]
        """)
        let direct = add("Direct inguinal hernia", .page, inguinal, x: 240, y: 60, """
        - Through the posterior wall of the canal
        - Adult or elderly, more often bilateral, hemispherical
        - Reduces backwards; complications uncommon
        - Sac medial to the [[Inferior epigastric vessels]]
        """)
        _ = add("Inferior epigastric vessels", .idea, inguinal, x: 470, y: -60, """
        The landmark that tells them apart: sac lateral = [[Indirect inguinal hernia]], sac medial = [[Direct inguinal hernia]].
        """)
        let ringTest = add("Internal ring test", .idea, inguinal, x: 470, y: 150, """
        Positive (swelling controlled) = oblique, [[Indirect inguinal hernia]]. Negative = direct. The finger invagination test is obsolete.
        """)

        // the femoral side
        let femoralHernia = add("Femoral hernia", .page, femoral, x: -200, y: 200, """
        - Parietal peritoneum down through the [[Femoral canal]]
        - More common in women
        - Neck below and lateral to the pubic tubercle
        - Femoral ring: inguinal ligament in front, pectineal ligament behind, femoral vein laterally, lacunar ligament medially

        The great mimic: [[Saphena varix]].
        """)
        _ = add("Femoral canal", .idea, femoral, x: -430, y: 200, """
        Medial to the femoral vein (artery lateral to the vein). 1.25 cm long, cone shaped.
        """)
        _ = add("Saphena varix", .idea, femoral, x: -200, y: 380, """
        Mimics a [[Femoral hernia]]: disappears completely lying flat, fluid thrill on cough, venous hum - usually with other varicose veins.
        """)
        _ = add("Hernia repair", .idea, examples, x: 40, y: 300, """
        - TAPP: transabdominal preperitoneal
        - TEP: totally extraperitoneal
        - Robotic-assisted repair
        """)

        // links made by hand, where the connection is an idea rather than a
        // name in the text
        store.link(ringTest.id, direct.id)
        store.link(cord.id, indirect.id)
        store.link(femoralHernia.id, canal.id)
    }
}
