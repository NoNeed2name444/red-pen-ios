import Foundation

/// Symptom-first blocks: "Chest pain block", "Breathless block", "Groin lump
/// block" - questions from every deck that share a presenting complaint,
/// mixed so the student has to tell the lookalikes apart the way the exam
/// asks (ACS from PE, dissection and pericarditis).
///
/// Interleaving helps most when the items are easy to confuse, and in
/// diagnosis that means one presentation with several causes. Training by
/// presentation has improved final diagnoses in multi-centre studies.
///
/// Tagging is by keyword on the question stem, no model: each presentation
/// has the phrases a stem uses for it, matched on word boundaries, and a
/// phrase with a negation just before it ("denies chest pain", "no
/// shortness of breath") does not count. The lookalikes listed with each
/// are the textbook differential, shown on screen, not used for tagging.
///
/// Foundation only.
enum SymptomBlocks {

    struct Presentation: Hashable, Identifiable {
        var id: String
        /// "Chest pain".
        var name: String
        var symbol: String
        /// Phrases a stem uses for it, lower case.
        var phrases: [String]
        /// The causes the block makes you tell apart.
        var lookalikes: [String]

        var blockTitle: String { "\(name) block" }
    }

    /// The presentations, in the order they are listed.
    static let all: [Presentation] = [
        Presentation(id: "chest-pain", name: "Chest pain", symbol: "heart.text.square",
                     phrases: ["chest pain", "chest tightness", "tight chest", "chest discomfort",
                               "retrosternal pain", "central chest", "pleuritic pain", "pleuritic chest",
                               "crushing chest", "pain in the chest", "pain in his chest",
                               "pain in her chest"],
                     lookalikes: ["Acute coronary syndrome", "Pulmonary embolism", "Aortic dissection",
                                  "Pericarditis", "Pneumothorax", "Pneumonia",
                                  "Oesophageal rupture", "Gastro-oesophageal reflux",
                                  "Musculoskeletal pain"]),
        Presentation(id: "breathless", name: "Breathless", symbol: "lungs",
                     phrases: ["short of breath", "shortness of breath", "breathless", "breathlessness",
                               "dyspnoea", "dyspnea", "difficulty breathing", "orthopnoea", "orthopnea",
                               "paroxysmal nocturnal dyspnoea", "paroxysmal nocturnal dyspnea",
                               "exertional dyspnoea", "exertional dyspnea"],
                     lookalikes: ["Asthma", "COPD exacerbation", "Heart failure", "Pulmonary embolism",
                                  "Pneumonia", "Pneumothorax", "Pleural effusion",
                                  "Interstitial lung disease", "Anaemia", "Anaphylaxis"]),
        Presentation(id: "groin-lump", name: "Groin lump", symbol: "circle.dashed",
                     phrases: ["groin lump", "groin swelling", "groin mass", "lump in the groin",
                               "lump in his groin", "lump in her groin", "lump in their groin",
                               "swelling in the groin", "swelling in his groin", "swelling in her groin",
                               "inguinal swelling", "inguinal lump", "inguinal mass", "inguinal bulge",
                               "groin bulge"],
                     lookalikes: ["Indirect inguinal hernia", "Direct inguinal hernia", "Femoral hernia",
                                  "Saphena varix", "Inguinal lymphadenopathy", "Femoral artery aneurysm",
                                  "Undescended or ectopic testis", "Psoas abscess",
                                  "Hydrocele of the cord", "Lipoma"]),
        Presentation(id: "abdominal-pain", name: "Abdominal pain", symbol: "stethoscope",
                     phrases: ["abdominal pain", "epigastric pain", "right upper quadrant pain",
                               "right iliac fossa pain", "left iliac fossa pain", "periumbilical pain",
                               "loin to groin", "flank pain", "lower abdominal pain", "abdominal cramps",
                               "pain in the abdomen", "tummy pain"],
                     lookalikes: ["Appendicitis", "Acute cholecystitis", "Biliary colic", "Acute pancreatitis",
                                  "Diverticulitis", "Bowel obstruction", "Perforated peptic ulcer",
                                  "Ruptured ectopic pregnancy", "Renal colic",
                                  "Ruptured abdominal aortic aneurysm", "Mesenteric ischaemia"]),
        Presentation(id: "headache", name: "Headache", symbol: "brain.head.profile",
                     phrases: ["headache", "headaches", "thunderclap", "head pain"],
                     lookalikes: ["Subarachnoid haemorrhage", "Migraine", "Tension-type headache",
                                  "Cluster headache", "Meningitis", "Giant cell arteritis",
                                  "Idiopathic intracranial hypertension", "Subdural haematoma",
                                  "Medication-overuse headache", "Space-occupying lesion"]),
        Presentation(id: "collapse", name: "Collapse", symbol: "figure.fall",
                     phrases: ["collapsed", "syncope", "syncopal", "fainted", "fainting",
                               "blackout", "blacked out", "loss of consciousness", "passed out",
                               "transient loss of consciousness"],
                     lookalikes: ["Vasovagal syncope", "Orthostatic hypotension", "Arrhythmia",
                                  "Aortic stenosis", "Hypertrophic cardiomyopathy", "Seizure",
                                  "Hypoglycaemia", "Pulmonary embolism", "Situational syncope"]),
        Presentation(id: "jaundice", name: "Jaundice", symbol: "drop.halffull",
                     phrases: ["jaundice", "jaundiced", "yellow sclera", "yellowing of the skin",
                               "yellowing of his", "yellowing of her", "icteric", "scleral icterus"],
                     lookalikes: ["Choledocholithiasis", "Pancreatic cancer", "Ascending cholangitis",
                                  "Viral hepatitis", "Alcohol-related liver disease", "Gilbert syndrome",
                                  "Haemolysis", "Primary biliary cholangitis",
                                  "Primary sclerosing cholangitis", "Drug-induced liver injury"]),
        Presentation(id: "back-pain", name: "Back pain", symbol: "figure.walk",
                     phrases: ["back pain", "low back pain", "lower back pain", "backache", "pain in his back",
                               "pain in her back"],
                     lookalikes: ["Mechanical back pain", "Cauda equina syndrome", "Spinal metastases",
                                  "Ankylosing spondylitis", "Discitis or epidural abscess",
                                  "Osteoporotic vertebral fracture", "Prolapsed disc with sciatica",
                                  "Abdominal aortic aneurysm"]),
        Presentation(id: "confusion", name: "Confusion", symbol: "questionmark.bubble",
                     phrases: ["confusion", "confused", "delirium", "delirious", "disorientated",
                               "disoriented", "acutely confused"],
                     lookalikes: ["Delirium from infection", "Hypoglycaemia", "Hyponatraemia",
                                  "Hypercalcaemia", "Wernicke encephalopathy", "Stroke",
                                  "Subdural haematoma", "Drug toxicity", "Dementia"]),
        Presentation(id: "palpitations", name: "Palpitations", symbol: "waveform.path.ecg",
                     phrases: ["palpitations", "palpitation", "racing heart", "heart racing",
                               "fluttering in", "pounding heart"],
                     lookalikes: ["Atrial fibrillation", "Supraventricular tachycardia",
                                  "Ventricular tachycardia", "Ectopic beats", "Thyrotoxicosis",
                                  "Wolff-Parkinson-White syndrome", "Anxiety", "Anaemia"]),
        Presentation(id: "gi-bleed", name: "GI bleeding", symbol: "drop.fill",
                     phrases: ["rectal bleeding", "bleeding per rectum", "blood in his stool",
                               "blood in her stool", "blood in the stool", "blood in stool",
                               "bright red blood", "melaena", "melena", "haematochezia", "hematochezia",
                               "haematemesis", "hematemesis", "vomiting blood", "coffee-ground",
                               "coffee ground"],
                     lookalikes: ["Peptic ulcer bleed", "Oesophageal varices", "Mallory-Weiss tear",
                                  "Haemorrhoids", "Anal fissure", "Colorectal cancer",
                                  "Diverticular bleed", "Inflammatory bowel disease", "Angiodysplasia"]),
        Presentation(id: "swollen-leg", name: "Swollen leg", symbol: "figure.stand",
                     phrases: ["swollen calf", "calf swelling", "swollen leg", "leg swelling",
                               "swelling of the leg", "swelling of his leg", "swelling of her leg",
                               "swollen left leg", "swollen right leg", "unilateral leg swelling"],
                     lookalikes: ["Deep vein thrombosis", "Cellulitis", "Ruptured Baker's cyst",
                                  "Heart failure", "Lymphoedema", "Venous insufficiency",
                                  "Compartment syndrome"]),
        Presentation(id: "hot-joint", name: "Hot swollen joint", symbol: "figure.flexibility",
                     phrases: ["swollen joint", "hot joint", "hot, swollen", "hot swollen", "swollen knee",
                               "swollen ankle", "painful swollen", "monoarthritis", "acute arthritis"],
                     lookalikes: ["Septic arthritis", "Gout", "Pseudogout", "Reactive arthritis",
                                  "Rheumatoid arthritis flare", "Haemarthrosis", "Cellulitis over a joint"]),
        Presentation(id: "scrotal", name: "Scrotal pain or lump", symbol: "exclamationmark.circle",
                     phrases: ["scrotal pain", "testicular pain", "scrotal swelling", "testicular swelling",
                               "testicular lump", "scrotal lump", "scrotal mass", "testicular mass",
                               "painful testis", "painful testicle"],
                     lookalikes: ["Testicular torsion", "Epididymo-orchitis", "Hydrocele", "Varicocele",
                                  "Testicular cancer", "Epididymal cyst", "Inguinoscrotal hernia",
                                  "Torsion of the appendix testis"]),
        Presentation(id: "vision-loss", name: "Loss of vision", symbol: "eye.slash",
                     phrases: ["loss of vision", "visual loss", "vision loss", "lost vision",
                               "sudden blindness", "blurred vision", "blurring of vision",
                               "curtain coming down", "curtain over"],
                     lookalikes: ["Central retinal artery occlusion", "Central retinal vein occlusion",
                                  "Retinal detachment", "Vitreous haemorrhage", "Giant cell arteritis",
                                  "Acute angle-closure glaucoma", "Optic neuritis", "Amaurosis fugax"]),
    ]

    /// Words that, just before a phrase, mean the patient does not have it.
    static let negators: Set<String> = ["no", "denies", "denied", "denying", "without", "nor",
                                        "not", "never", "negative"]

    /// Presentations whose phrases appear, not negated, in `stem`.
    static func presentations(in stem: String) -> [Presentation] {
        let text = stem.lowercased()
        return all.filter { p in p.phrases.contains { mentions($0, in: text) } }
    }

    /// Whether `phrase` appears in `text` (both lower case) as whole words,
    /// at least once without a negation in the four words before it within
    /// the same clause.
    static func mentions(_ phrase: String, in text: String) -> Bool {
        var from = text.startIndex
        while let range = text.range(of: phrase, range: from..<text.endIndex) {
            from = range.upperBound
            let before: Character? = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after: Character? = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            if let b = before, b.isLetter || b.isNumber { continue }
            if let a = after, a.isLetter || a.isNumber { continue }
            if !negated(before: text[text.startIndex..<range.lowerBound]) { return true }
        }
        return false
    }

    /// Whether the clause leading up to a phrase negates it.
    static func negated(before prefix: Substring) -> Bool {
        // only this clause: a full stop, semicolon or "but" starts afresh
        var clause = String(prefix)
        for stop in [".", ";", ":", "?", "!", " but ", " however ", " although "] {
            if let r = clause.range(of: stop, options: .backwards) {
                clause = String(clause[r.upperBound...])
            }
        }
        let words = clause.split { !$0.isLetter }.map(String.init)
        return words.suffix(4).contains { negators.contains($0) }
    }

    // MARK: blocks

    /// One question as the blocks need it.
    struct Item: Hashable {
        var id: UUID
        var stem: String
        /// The correct option's text, for telling the causes apart.
        var answer: String
    }

    /// A presentation and the questions tagged with it.
    struct Block: Hashable, Identifiable {
        var presentation: Presentation
        var ids: [UUID]
        /// Distinct correct answers among them.
        var causes: Int
        var id: String { presentation.id }
    }

    /// A block is offered with at least this many questions...
    static let minimumQuestions = 6
    /// ...across at least this many different answers.
    static let minimumCauses = 3

    /// Every presentation with enough questions to make a block, biggest
    /// first. With `includeThin`, thinner ones too (for a "coming soon" list).
    static func blocks(_ items: [Item], includeThin: Bool = false) -> [Block] {
        var tagged: [String: [Item]] = [:]
        for item in items {
            for p in presentations(in: item.stem) { tagged[p.id, default: []].append(item) }
        }
        var out: [Block] = []
        for p in all {
            let list = tagged[p.id] ?? []
            guard !list.isEmpty else { continue }
            let causes = Set(list.map { normalised($0.answer) }).count
            let enough = list.count >= minimumQuestions && causes >= minimumCauses
            guard enough || includeThin else { continue }
            out.append(Block(presentation: p, ids: list.map(\.id), causes: causes))
        }
        return out.sorted { a, b in
            if a.ids.count != b.ids.count { return a.ids.count > b.ids.count }
            return a.presentation.name < b.presentation.name
        }
    }

    /// The order to ask them in: round the different answers in turn, so two
    /// questions with the same answer rarely come one after the other.
    static func interleaved<R: RandomNumberGenerator>(_ items: [Item], using rng: inout R) -> [Item] {
        var groups = Dictionary(grouping: items.shuffled(using: &rng), by: { normalised($0.answer) })
            .values.map { $0 }
        groups.shuffle(using: &rng)
        groups.sort { $0.count > $1.count }
        var out: [Item] = []
        var index = 0
        while out.count < items.count {
            var took = false
            for g in groups.indices where index < groups[g].count {
                out.append(groups[g][index])
                took = true
            }
            if !took { break }
            index += 1
        }
        return out
    }

    static func interleaved(_ items: [Item]) -> [Item] {
        var rng = SystemRandomNumberGenerator()
        return interleaved(items, using: &rng)
    }

    /// Answer text reduced for comparing: lower case, letters and digits.
    static func normalised(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    // MARK: after the block

    /// One mix-up: what was picked, and what it was.
    struct Confusion: Hashable, Identifiable {
        var picked: String
        var actual: String
        var count: Int
        var id: String { picked + "\u{2192}" + actual }
    }

    /// The mix-ups in a block, most frequent first: for each wrong answer
    /// among `events`, the option picked against the right one.
    static func confusions(questions: [UUID: (options: [String], correct: Int)],
                           events: [AnswerEvent]) -> [Confusion] {
        var counts: [String: Confusion] = [:]
        for e in events where !e.correct {
            guard let q = questions[e.questionId], let pick = e.picked,
                  q.options.indices.contains(pick), q.options.indices.contains(q.correct) else { continue }
            let key = q.options[pick] + "\u{2192}" + q.options[q.correct]
            var row = counts[key] ?? Confusion(picked: q.options[pick], actual: q.options[q.correct], count: 0)
            row.count += 1
            counts[key] = row
        }
        return counts.values.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.id < b.id
        }
    }
}
