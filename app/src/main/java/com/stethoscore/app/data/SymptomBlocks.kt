package com.stethoscore.app.data

import com.stethoscore.app.quiz.MockRandom

// Ported from ios/RedPen/Shared/Learn/SymptomBlocks.swift. Tested by LearnTest.

/**
 * Symptom-first blocks: "Chest pain block", "Breathless block", "Groin lump
 * block" - questions from every deck that share a presenting complaint,
 * mixed so the student has to tell the lookalikes apart the way the exam
 * asks (ACS from PE, dissection and pericarditis).
 *
 * Tagging is by keyword on the question stem, no model: each presentation
 * has the phrases a stem uses for it, matched on word boundaries, and a
 * phrase with a negation just before it ("denies chest pain", "no shortness
 * of breath") does not count. The lookalikes listed with each are the
 * textbook differential, shown on screen, not used for tagging.
 */
object SymptomBlocks {
    /** [symbol] is the iOS SF Symbol's name; LearnIcons draws it. */
    data class Presentation(
        val id: String,
        /** "Chest pain". */
        val name: String,
        val symbol: String,
        /** Phrases a stem uses for it, lower case. */
        val phrases: List<String>,
        /** The causes the block makes you tell apart. */
        val lookalikes: List<String>,
    ) {
        val blockTitle: String get() = "$name block"
    }

    /** The presentations, in the order they are listed. */
    val all: List<Presentation> = listOf(
        Presentation("chest-pain", "Chest pain", "heart.text.square",
            listOf("chest pain", "chest tightness", "tight chest", "chest discomfort", "retrosternal pain", "central chest", "pleuritic pain", "pleuritic chest", "crushing chest", "pain in the chest", "pain in his chest", "pain in her chest"),
            listOf("Acute coronary syndrome", "Pulmonary embolism", "Aortic dissection", "Pericarditis", "Pneumothorax", "Pneumonia", "Oesophageal rupture", "Gastro-oesophageal reflux", "Musculoskeletal pain")),
        Presentation("breathless", "Breathless", "lungs",
            listOf("short of breath", "shortness of breath", "breathless", "breathlessness", "dyspnoea", "dyspnea", "difficulty breathing", "orthopnoea", "orthopnea", "paroxysmal nocturnal dyspnoea", "paroxysmal nocturnal dyspnea", "exertional dyspnoea", "exertional dyspnea"),
            listOf("Asthma", "COPD exacerbation", "Heart failure", "Pulmonary embolism", "Pneumonia", "Pneumothorax", "Pleural effusion", "Interstitial lung disease", "Anaemia", "Anaphylaxis")),
        Presentation("groin-lump", "Groin lump", "circle.dashed",
            listOf("groin lump", "groin swelling", "groin mass", "lump in the groin", "lump in his groin", "lump in her groin", "lump in their groin", "swelling in the groin", "swelling in his groin", "swelling in her groin", "inguinal swelling", "inguinal lump", "inguinal mass", "inguinal bulge", "groin bulge"),
            listOf("Indirect inguinal hernia", "Direct inguinal hernia", "Femoral hernia", "Saphena varix", "Inguinal lymphadenopathy", "Femoral artery aneurysm", "Undescended or ectopic testis", "Psoas abscess", "Hydrocele of the cord", "Lipoma")),
        Presentation("abdominal-pain", "Abdominal pain", "stethoscope",
            listOf("abdominal pain", "epigastric pain", "right upper quadrant pain", "right iliac fossa pain", "left iliac fossa pain", "periumbilical pain", "loin to groin", "flank pain", "lower abdominal pain", "abdominal cramps", "pain in the abdomen", "tummy pain"),
            listOf("Appendicitis", "Acute cholecystitis", "Biliary colic", "Acute pancreatitis", "Diverticulitis", "Bowel obstruction", "Perforated peptic ulcer", "Ruptured ectopic pregnancy", "Renal colic", "Ruptured abdominal aortic aneurysm", "Mesenteric ischaemia")),
        Presentation("headache", "Headache", "brain.head.profile",
            listOf("headache", "headaches", "thunderclap", "head pain"),
            listOf("Subarachnoid haemorrhage", "Migraine", "Tension-type headache", "Cluster headache", "Meningitis", "Giant cell arteritis", "Idiopathic intracranial hypertension", "Subdural haematoma", "Medication-overuse headache", "Space-occupying lesion")),
        Presentation("collapse", "Collapse", "figure.fall",
            listOf("collapsed", "syncope", "syncopal", "fainted", "fainting", "blackout", "blacked out", "loss of consciousness", "passed out", "transient loss of consciousness"),
            listOf("Vasovagal syncope", "Orthostatic hypotension", "Arrhythmia", "Aortic stenosis", "Hypertrophic cardiomyopathy", "Seizure", "Hypoglycaemia", "Pulmonary embolism", "Situational syncope")),
        Presentation("jaundice", "Jaundice", "drop.halffull",
            listOf("jaundice", "jaundiced", "yellow sclera", "yellowing of the skin", "yellowing of his", "yellowing of her", "icteric", "scleral icterus"),
            listOf("Choledocholithiasis", "Pancreatic cancer", "Ascending cholangitis", "Viral hepatitis", "Alcohol-related liver disease", "Gilbert syndrome", "Haemolysis", "Primary biliary cholangitis", "Primary sclerosing cholangitis", "Drug-induced liver injury")),
        Presentation("back-pain", "Back pain", "figure.walk",
            listOf("back pain", "low back pain", "lower back pain", "backache", "pain in his back", "pain in her back"),
            listOf("Mechanical back pain", "Cauda equina syndrome", "Spinal metastases", "Ankylosing spondylitis", "Discitis or epidural abscess", "Osteoporotic vertebral fracture", "Prolapsed disc with sciatica", "Abdominal aortic aneurysm")),
        Presentation("confusion", "Confusion", "questionmark.bubble",
            listOf("confusion", "confused", "delirium", "delirious", "disorientated", "disoriented", "acutely confused"),
            listOf("Delirium from infection", "Hypoglycaemia", "Hyponatraemia", "Hypercalcaemia", "Wernicke encephalopathy", "Stroke", "Subdural haematoma", "Drug toxicity", "Dementia")),
        Presentation("palpitations", "Palpitations", "waveform.path.ecg",
            listOf("palpitations", "palpitation", "racing heart", "heart racing", "fluttering in", "pounding heart"),
            listOf("Atrial fibrillation", "Supraventricular tachycardia", "Ventricular tachycardia", "Ectopic beats", "Thyrotoxicosis", "Wolff-Parkinson-White syndrome", "Anxiety", "Anaemia")),
        Presentation("gi-bleed", "GI bleeding", "drop.fill",
            listOf("rectal bleeding", "bleeding per rectum", "blood in his stool", "blood in her stool", "blood in the stool", "blood in stool", "bright red blood", "melaena", "melena", "haematochezia", "hematochezia", "haematemesis", "hematemesis", "vomiting blood", "coffee-ground", "coffee ground"),
            listOf("Peptic ulcer bleed", "Oesophageal varices", "Mallory-Weiss tear", "Haemorrhoids", "Anal fissure", "Colorectal cancer", "Diverticular bleed", "Inflammatory bowel disease", "Angiodysplasia")),
        Presentation("swollen-leg", "Swollen leg", "figure.stand",
            listOf("swollen calf", "calf swelling", "swollen leg", "leg swelling", "swelling of the leg", "swelling of his leg", "swelling of her leg", "swollen left leg", "swollen right leg", "unilateral leg swelling"),
            listOf("Deep vein thrombosis", "Cellulitis", "Ruptured Baker's cyst", "Heart failure", "Lymphoedema", "Venous insufficiency", "Compartment syndrome")),
        Presentation("hot-joint", "Hot swollen joint", "figure.flexibility",
            listOf("swollen joint", "hot joint", "hot, swollen", "hot swollen", "swollen knee", "swollen ankle", "painful swollen", "monoarthritis", "acute arthritis"),
            listOf("Septic arthritis", "Gout", "Pseudogout", "Reactive arthritis", "Rheumatoid arthritis flare", "Haemarthrosis", "Cellulitis over a joint")),
        Presentation("scrotal", "Scrotal pain or lump", "exclamationmark.circle",
            listOf("scrotal pain", "testicular pain", "scrotal swelling", "testicular swelling", "testicular lump", "scrotal lump", "scrotal mass", "testicular mass", "painful testis", "painful testicle"),
            listOf("Testicular torsion", "Epididymo-orchitis", "Hydrocele", "Varicocele", "Testicular cancer", "Epididymal cyst", "Inguinoscrotal hernia", "Torsion of the appendix testis")),
        Presentation("vision-loss", "Loss of vision", "eye.slash",
            listOf("loss of vision", "visual loss", "vision loss", "lost vision", "sudden blindness", "blurred vision", "blurring of vision", "curtain coming down", "curtain over"),
            listOf("Central retinal artery occlusion", "Central retinal vein occlusion", "Retinal detachment", "Vitreous haemorrhage", "Giant cell arteritis", "Acute angle-closure glaucoma", "Optic neuritis", "Amaurosis fugax")),
    )

    /** Words that, just before a phrase, mean the patient does not have it. */
    val negators: Set<String> = setOf("no", "denies", "denied", "denying", "without", "nor", "not", "never", "negative")

    /** Presentations whose phrases appear, not negated, in [stem]. */
    fun presentations(stem: String): List<Presentation> {
        val text = stem.lowercase()
        return all.filter { p -> p.phrases.any { mentions(it, text) } }
    }

    /**
     * Whether [phrase] appears in [text] (both lower case) as whole words, at
     * least once without a negation in the four words before it within the
     * same clause.
     */
    fun mentions(phrase: String, text: String): Boolean {
        var from = 0
        while (true) {
            val start = text.indexOf(phrase, from)
            if (start < 0) return false
            val end = start + phrase.length
            from = end
            val before = if (start > 0) text[start - 1] else null
            val after = if (end < text.length) text[end] else null
            if (before != null && before.isLetterOrDigit()) continue
            if (after != null && after.isLetterOrDigit()) continue
            if (!negated(text.substring(0, start))) return true
        }
    }

    /** Whether the clause leading up to a phrase negates it. */
    fun negated(prefix: String): Boolean {
        // only this clause: a full stop, semicolon or "but" starts afresh
        var clause = prefix
        for (stop in listOf(".", ";", ":", "?", "!", " but ", " however ", " although ")) {
            val r = clause.lastIndexOf(stop)
            if (r >= 0) clause = clause.substring(r + stop.length)
        }
        val words = clause.split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        return words.takeLast(4).any { it in negators }
    }

    // MARK: blocks

    /** One question as the blocks need it. [answer]: the correct option's text. */
    data class Item(val id: String, val stem: String, val answer: String)

    /** A presentation and the questions tagged with it. [causes]: distinct correct answers among them. */
    data class Block(val presentation: Presentation, val ids: List<String>, val causes: Int) {
        val id: String get() = presentation.id
    }

    /** A block is offered with at least this many questions... */
    const val minimumQuestions = 6
    /** ...across at least this many different answers. */
    const val minimumCauses = 3

    /** Every presentation with enough questions to make a block, biggest first. With [includeThin], thinner ones too. */
    fun blocks(items: List<Item>, includeThin: Boolean = false): List<Block> {
        val tagged = HashMap<String, MutableList<Item>>()
        for (item in items) for (p in presentations(item.stem)) tagged.getOrPut(p.id) { mutableListOf() }.add(item)
        val out = mutableListOf<Block>()
        for (p in all) {
            val list = tagged[p.id] ?: continue
            if (list.isEmpty()) continue
            val causes = list.map { normalised(it.answer) }.toSet().size
            val enough = list.size >= minimumQuestions && causes >= minimumCauses
            if (!enough && !includeThin) continue
            out.add(Block(p, list.map { it.id }, causes))
        }
        return out.sortedWith(compareByDescending<Block> { it.ids.size }.thenBy { it.presentation.name })
    }

    /**
     * The order to ask them in: round the different answers in turn, so two
     * questions with the same answer rarely come one after the other.
     */
    fun interleaved(items: List<Item>, rng: MockRandom = MockRandom.system()): List<Item> {
        val grouped = LinkedHashMap<String, MutableList<Item>>()
        for (item in rng.shuffled(items)) grouped.getOrPut(normalised(item.answer)) { mutableListOf() }.add(item)
        val groups = rng.shuffled(grouped.values.toList()).sortedByDescending { it.size }
        val out = mutableListOf<Item>()
        var index = 0
        while (out.size < items.size) {
            var took = false
            for (g in groups) if (index < g.size) {
                out.add(g[index])
                took = true
            }
            if (!took) break
            index += 1
        }
        return out
    }

    /** Answer text reduced for comparing: lower case, letters and digits. */
    fun normalised(s: String): String = s.lowercase().filter { it.isLetterOrDigit() }

    // MARK: after the block

    /** One mix-up: what was picked, and what it was. */
    data class Confusion(val picked: String, val actual: String, val count: Int) {
        val id: String get() = picked + "→" + actual
    }

    /** One question's options and right answer, as the mix-ups need them. */
    data class Options(val options: List<String>, val correct: Int)

    /** The mix-ups in a block, most frequent first: for each wrong answer among [events], the option picked against the right one. */
    fun confusions(questions: Map<String, Options>, events: List<AnswerEvent>): List<Confusion> {
        val counts = HashMap<String, Confusion>()
        for (e in events) {
            if (e.correct) continue
            val q = questions[e.questionId] ?: continue
            val pick = e.picked ?: continue
            if (pick !in q.options.indices || q.correct !in q.options.indices) continue
            val key = q.options[pick] + "→" + q.options[q.correct]
            val row = counts[key] ?: Confusion(q.options[pick], q.options[q.correct], 0)
            counts[key] = row.copy(count = row.count + 1)
        }
        return counts.values.sortedWith(compareByDescending<Confusion> { it.count }.thenBy { it.id })
    }
}
