import Foundation

/// Examples made from a real lecture, for a personal build that carries one
/// in its Samples folder: the app's own pipeline runs on it at first launch -
/// its diagrams become image occlusion cards, a textbook written from it has
/// the lecture's figures placed on the matching pages, and the lecture itself
/// is kept so the document viewer can be tried.
///
/// The lecture file is never in the repository (it is someone's teaching
/// material); only a build made for its owner carries it.
enum SampleLectures {

    /// Lectures bundled with this build, if any.
    static var bundled: [URL] { AppResources.samples(withExtension: "pdf") }

    @MainActor
    static func seed(into store: Store) async {
        let flag = "sampleLectures.v2"
        guard PersonalBuild.isOn,
              !UserDefaults.standard.bool(forKey: flag), !bundled.isEmpty else { return }
        // marked done first, and on disk: if reading it ever stops the app,
        // the next launch does not try again
        UserDefaults.standard.set(true, forKey: flag)
        UserDefaults.standard.synchronize()
        // the library first: nothing starts until it has been on screen a moment
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard !Task.isCancelled else { return }
        let folder = store.folders.first { $0.name.hasPrefix("Examples") }
            ?? { let made = StudyFolder(name: "Examples - try every mode"); store.folders.append(made); return made }()

        for url in bundled {
            // Reading 45 slides - rendering each, finding its diagrams,
            // reading their labels - is seconds of work per page. All of it
            // happens off the main thread, so the app never stops answering
            // taps while it runs.
            let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: #"^[0-9a-f-]+-"#, with: "", options: .regularExpression)
            guard let made = await Task.detached(priority: .background, operation: { () -> Made? in
                // one page at a time and fewer diagrams: slower, but a phone
                // running Swift Playgrounds has little memory to spare
                guard let read = try? await SourceIngest.read(pdf: url, figureLimit: 24, workers: 1) else { return nil }
                return Made(document: read.document,
                            diagrams: LectureWriterSection.diagramCards(from: read, name: name),
                            figures: LectureWriterSection.figures(from: read),
                            blob: SourceFiles.keep(url, kind: .pdf))
            }).value else { continue }
            let source = ReadSource(name: name, document: made.document, kind: .pdf, fileBlob: made.blob).doc()

            // image occlusion: the lecture's labelled diagrams, as they are found
            let diagrams = made.diagrams
            if !diagrams.cards.isEmpty {
                var cards = StudySet(name: "Example: \(name) - image occlusion", subject: "Surgery", kind: .anki)
                cards.cards = diagrams.cards
                cards.images = diagrams.images
                cards.sources = [source]
                cards.folderId = folder.id
                store.addSet(cards)
            }

            // a textbook with the lecture's own figures placed by topic
            if let pages = textbook[key(for: name)] {
                let figures = made.figures
                let split = BookPages.split(pages).map(\.markdown)
                let placement = BookFigures.assign(figures, to: split)
                let placed = split.enumerated().map { i, page in
                    BookPages.tidyPage(page, fallbackTitle: "Part \(i + 1)",
                                       figures: placement.indices.contains(i) ? placement[i] : [])
                }.joined(separator: "\n\n")
                let kept = BookFigures.compact(placed, images: figures.map(\.imageBase64))
                var book = StudySet(name: "Example: \(name) - textbook", subject: "Surgery", kind: .book)
                book.bookMarkdown = kept.markdown
                book.images = kept.images
                book.sources = [source]
                book.folderId = folder.id
                store.addSet(book)
            }
        }
    }

    /// What the background read hands back to the main thread.
    private struct Made {
        var document: SourceText.Document
        var diagrams: DiagramCards
        var figures: [BookFigure]
        var blob: String?
    }

    private static func key(for name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// Textbooks written from the lecture's own text, nothing added.
    static let textbook: [String: String] = [
        "groinhernia": """
        ## The inguinal canal

        ### Development and course

        - The inguinal canal develops by the **descent of the testis**.
        - It is **4 cm long** and runs obliquely: from posterior to anterior, from above downwards, and from lateral to medial.
        - It extends from the **deep inguinal ring** to the **superficial inguinal ring**.
        - **Contents:** the spermatic cord in males, the round ligament of the uterus in females, and the **ilio-inguinal nerve** in both.

        ### Layers

        - Skin
        - Superficial fascia, in two layers: the superficial fatty layer (**Camper's**) and the deep membranous layer (**Scarpa's**)
        - Deep fascia: **absent**
        - The three muscles
        - Transversalis fascia

        ### Boundaries

        | Wall | Formed by |
        |---|---|
        | Anterior | External oblique all through, and internal oblique **laterally** |
        | Posterior | Fascia transversalis all through, and internal oblique **medially** |
        | Roof | Conjoined muscles: internal oblique and transversus |
        | Floor | Inguinal ligament and lacunar ligament |

        > **Mnemonic:** **LA / PM** - internal oblique is in the anterior wall **L**aterally (**A**nterior) and the posterior wall **M**edially (**P**osterior).

        ### Spermatic cord

        | Covering | Derived from |
        |---|---|
        | Internal spermatic fascia | Transversalis fascia, at the internal ring |
        | Cremasteric muscle and fascia | Internal oblique |
        | External spermatic fascia | External oblique aponeurosis, at the external ring |

        - **Contents:** vas deferens and its artery; the processus vaginalis (remnant); testicular artery and **pampiniform plexus** of veins; the genital branch of the genitofemoral nerve and autonomic nerves.

        ## Inguinal hernia

        ### Types

        - **Congenital:** usually appears in infancy and young age.
        - **Indirect:** passes from the deep inguinal ring through the canal to the superficial ring.
        - **Direct:** passes through the **posterior wall** of the inguinal canal.

        ### Indirect inguinal hernia

        - **70%** of all hernias; **30% bilateral**; males 20 times more often than females.
        - The defect is the stretched **deep inguinal ring**.
        - The sac lies inside the cord, anterolateral to the vas and vessels, leaves through the external ring and may reach the scrotum.
        - The **neck of the sac is lateral to the inferior epigastric vessels**.
        - Contents are usually small intestine, omentum, or both.

        > **Exam tip:** The inferior epigastric vessels tell the two apart - the sac is **lateral** to them in an indirect hernia and **medial** in a direct one.

        ### Clinical features

        1. A swelling
        2. At the anatomical site of a hernia
        3. With an **expansile impulse on cough**

        ```flow
        Groin swelling with an expansile impulse on cough
        Internal ring test
        If positive → oblique (indirect) inguinal hernia
        If negative → direct inguinal hernia
        ```

        The finger invagination test is obsolete.

        ### Oblique versus direct

        | Feature | Oblique (indirect) | Direct |
        |---|---|---|
        | Age | Any | Adult or elderly |
        | Side | Uni- or bilateral | More commonly bilateral |
        | Shape | Oblong | Hemispherical |
        | Descent | Downwards, forwards and medially | Forwards |
        | Reduction | Upwards, backwards, laterally | Backwards |
        | Complications | More common | Uncommon |
        | Internal ring test | Positive | Negative |
        | Inferior epigastric artery | Sac lateral to it | Sac medial to it |

        ### Treatment

        > **Key point:** A hernia is a surgical disease - **the only treatment is surgery**.

        ## Femoral hernia

        ### What it is

        - A protrusion of parietal peritoneum down through the **femoral canal**.
        - **More common in women** than in men.
        - The neck of the sac lies **below and lateral to the pubic tubercle**, at the femoral ring: the inguinal ligament in front, the pectineal ligament behind, the **femoral vein laterally**, and the sharp edge of the **lacunar ligament medially**.

        ### The femoral canal

        - Medial to the femoral vein (the femoral artery is lateral to the vein).
        - **1.25 cm** (half an inch) long and cone shaped.

        ### Differential diagnosis

        - Inguinal hernia
        - **Saphena varix**
        - Enlarged femoral lymph node
        - Lipoma
        - Femoral aneurysm
        - Psoas abscess - often a fluctuating swelling
        - Distended psoas bursa - diminishes when the hip is flexed; hip osteoarthritis is present
        - Rupture of adductor longus with haematoma

        > **Red flag:** A **saphena varix** mimics a femoral hernia: it disappears completely when the patient lies flat, gives a fluid thrill on cough, and a venous hum can be heard with a stethoscope, usually with other varicose veins.

        ## Hernia repair

        - **TAPP:** transabdominal preperitoneal repair
        - **TEP:** totally extraperitoneal repair
        - Robotic-assisted inguinal hernia repair
        """,
    ]
}
