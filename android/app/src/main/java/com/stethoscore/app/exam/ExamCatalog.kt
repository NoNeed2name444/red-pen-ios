package com.stethoscore.app.exam

import com.stethoscore.app.quiz.ExamTrack
import com.stethoscore.app.quiz.MockFormat
import com.stethoscore.app.quiz.MockSectionSpec

// A port of ios/RedPen/Shared/Exam/ExamCatalog.swift: the most common
// medical exams, each with its format and blueprint, so the whole app can put
// one first: which topics matter, what to study next, the mock paper and its
// clock.
//
// Every blueprint cites where it comes from. Where the exam publishes ranges
// (USMLE, COMLEX), the weights are the ranges' midpoints, normalised to 100%.
// Where it publishes a content map but no percentages (PLAB / MLA, MCC, AMC,
// SCFHS, the Gulf regulators, NBEMS "indicative" numbers), the weights are OUR
// approximation and `blueprintIsApproximate` says so on screen. Exams change
// their formats: the screen always tells the student to confirm with the exam.
// Pure Kotlin (ExamCatalogTest).

/**
 * A topic area a blueprint is written in. Organ systems for the clinical
 * exams, subjects for the Indian ones, sciences for the basic-science ones -
 * one list, so any two exams can be compared and combined.
 */
@Suppress("EnumEntryName")
enum class ExamDomain(val rawValue: String, val title: String) {
    anatomy("anatomy", "Anatomy"),
    physiology("physiology", "Physiology"),
    biochemistry("biochemistry", "Biochemistry"),
    pathology("pathology", "Pathology"),
    pharmacology("pharmacology", "Pharmacology"),
    microbiology("microbiology", "Microbiology"),
    immunology("immunology", "Immunology"),
    genetics("genetics", "Genetics"),
    multisystem("multisystem", "Multisystem processes"),
    biostatistics("biostatistics", "Biostatistics and epidemiology"),
    ethics("ethics", "Ethics, law and communication"),
    forensic("forensic", "Forensic medicine"),
    community("community", "Community and public health"),
    cardio("cardio", "Cardiovascular"),
    resp("resp", "Respiratory"),
    gi("gi", "Gastrointestinal and liver"),
    endocrine("endocrine", "Endocrine and metabolic"),
    renal("renal", "Renal and urinary"),
    neuro("neuro", "Nervous system"),
    msk("msk", "Musculoskeletal and rheumatology"),
    heme("heme", "Blood and haematology"),
    id("id", "Infectious disease"),
    derm("derm", "Skin"),
    psychiatry("psychiatry", "Psychiatry and behavioural health"),
    peds("peds", "Paediatrics"),
    obstetrics("obstetrics", "Obstetrics"),
    gynaecology("gynaecology", "Gynaecology and breast"),
    ent("ent", "Ear, nose and throat"),
    ophthalmology("ophthalmology", "Ophthalmology"),
    oncology("oncology", "Oncology"),
    surgery("surgery", "General surgery"),
    orthopaedics("orthopaedics", "Orthopaedics"),
    anaesthesia("anaesthesia", "Anaesthesia and perioperative"),
    radiology("radiology", "Radiology"),
    emergency("emergency", "Acute and emergency"),
    geriatrics("geriatrics", "Older adults"),
    palliative("palliative", "Palliative care"),
    sexualHealth("sexualHealth", "Sexual health"),
    omm("omm", "Osteopathic principles (OMM)");

    companion object {
        fun from(raw: String?): ExamDomain? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * One line of a blueprint: a topic area and its weight. [weight] is as the
 * source gives it (a range's midpoint, questions out of 200...); the exam
 * normalises the whole blueprint to percent.
 */
data class BlueprintShare(
    val domain: ExamDomain,
    val weight: Double,
    /** The exam's own name for the area, when it differs from the domain's. */
    val label: String? = null,
) {
    val title: String get() = label ?: domain.title
}

/** Where the exam is sat, for grouping the picker. */
@Suppress("EnumEntryName")
enum class ExamRegion(val rawValue: String, val title: String) {
    usa("usa", "United States"),
    uk("uk", "United Kingdom"),
    canada("canada", "Canada"),
    australia("australia", "Australia"),
    india("india", "India"),
    gulf("gulf", "Saudi Arabia and the Gulf"),
    egypt("egypt", "Egypt"),
    international("international", "International"),
}

/** The exams sat in one region, for the picker. */
data class ExamRegionGroup(val region: ExamRegion, val exams: List<TargetExam>) {
    val id: String get() = region.rawValue
}

/** The openly licensed bank whose items show this exam's style. */
@Suppress("EnumEntryName")
enum class ExemplarSource(val rawValue: String) {
    /** MedQA's Step 1 items (MIT): long vignettes, mechanism lead-ins. */
    medqaStep1("medqa-step1"),
    /** MedQA's Step 2 and 3 items: long vignettes, diagnosis and management. */
    medqaStep23("medqa-step23"),
    /** MedMCQA (Apache-2.0): AIIMS / NEET-PG one-liners, four options. */
    medmcqa("medmcqa"),
}

/** One row of [TargetExam.shares]. */
data class ExamShare(val domain: ExamDomain, val title: String, val percent: Double)

/** One exam, as the app puts it first. */
data class TargetExam(
    val id: String,
    /** "USMLE Step 2 CK": in the picker and on the dashboard. */
    val name: String,
    /** "Step 2 CK": on a set's badge. */
    val shortName: String,
    val region: ExamRegion,
    /** The existing track whose units, guidelines and OSCE style it shares. */
    val family: ExamTrack,
    /** Options per question: 5 for single-best-of-five, 4 where the exam uses A-D. */
    val options: Int,
    /** A typical stem's length, in words. */
    val stemWords: IntRange,
    /** How this exam asks: its usual lead-ins. */
    val leadIns: String,
    /** Units, drug names, whose guidelines. */
    val conventions: String,
    /** Roughly how many questions are pure recall rather than a clinical case. */
    val recallShare: Double,
    val blueprint: List<BlueprintShare>,
    /** The published document the blueprint follows. */
    val blueprintSource: String,
    /** True when the weights are our estimate rather than the exam's numbers. */
    val blueprintIsApproximate: Boolean,
    /** The written paper as sat: sections, each with its count and clock. */
    val sections: List<MockSectionSpec>,
    /** USMLE-style blocks: the student chooses how many to sit. */
    val sitsBlockwise: Boolean,
    /** Each section is its own paper, sat on its own (MRCP's two papers). */
    val sitsSeparately: Boolean,
    /** How the real exam runs, in a line. */
    val paperNote: String,
    /** A rough pass mark as a fraction, for the readiness estimate only. */
    val passMark: Double,
    val passNote: String,
    /** Marks lost for a wrong answer, when the exam takes them. */
    val negativeMarking: String?,
    val exemplars: ExemplarSource,
    /** 0-1: how much stricter the accuracy engine is on this exam's management questions. */
    val accuracyStrictness: Double,
    /** False when the exam publishes too little to be sure of the format. */
    val formatConfirmed: Boolean,
) {
    /** Seconds per question across the whole paper. */
    val secondsPerQuestion: Int get() {
        val q = sections.sumOf { it.questions }
        val m = sections.sumOf { it.minutes }
        if (q <= 0) return 60
        return Math.round((m * 60).toDouble() / q).toInt()
    }

    val totalWeight: Double get() = blueprint.sumOf { it.weight }

    /** The blueprint in percent, largest first; sums to 100. */
    val shares: List<ExamShare> get() {
        val total = maxOf(totalWeight, 0.0001)
        return blueprint.map { ExamShare(it.domain, it.title, it.weight / total * 100) }
            .sortedWith { a, b -> b.percent.compareTo(a.percent) }
    }

    /** Percent for one domain (0 when the exam does not test it by name). */
    fun percent(domain: ExamDomain): Double {
        val total = maxOf(totalWeight, 0.0001)
        return blueprint.filter { it.domain == domain }.sumOf { it.weight } / total * 100
    }
}

// The catalogue

object ExamCatalog {

    val all: List<TargetExam> get() = listOf(
        step1, step2ck, step3, comlex1, comlex2, plab1, mrcp1, mrcsA, mccqe1, amc,
        neetpg, inicet, fmge, smle, dha, doh, mohap, qchp, omsb, emle, ifom,
    )

    fun exam(id: String?): TargetExam? {
        if (id.isNullOrEmpty()) return null
        return all.firstOrNull { it.id == id }
    }

    /** The catalogue in the picker's order: by region, as listed. */
    val byRegion: List<ExamRegionGroup> get() {
        val list = all
        return ExamRegion.entries.mapNotNull { region ->
            val exams = list.filter { it.region == region }
            if (exams.isEmpty()) null else ExamRegionGroup(region, exams)
        }
    }

    private fun s(domain: ExamDomain, weight: Number, label: String? = null): BlueprintShare =
        BlueprintShare(domain, weight.toDouble(), label)

    private fun blocks(count: Int, questions: Int, minutes: Int, name: String = MockFormat.partWord): List<MockSectionSpec> =
        (1..count).map { MockSectionSpec("$name $it", questions, minutes) }

    val usUnits: String = "US conventional units (mg/dL, °F alongside °C), US generic drug names (acetaminophen, epinephrine) and current US guidelines"
    val ukUnits: String = "SI units (mmol/L), UK drug names (paracetamol, adrenaline) and current NICE / BNF guidance; where UK and US practice differ, the UK answer is correct"
    val intlUnits: String = "SI units, international generic drug names and current international guidelines (WHO and the major specialty societies)"
    val indiaUnits: String = "SI units, and the answers given by the standard Indian postgraduate textbooks"

    // United States

    // USMLE Step 1 Content Outline and Specifications (usmle.org, "Step 1
    // Content Outline", 2024-2026 edition): system ranges, midpoints here.
    // Human development 1-3%; blood, lymphoreticular and immune 9-13%;
    // behavioural health and nervous system / special senses 10-14%;
    // musculoskeletal, skin 6-10%; cardiovascular 6-10%; respiratory and
    // renal 11-15%; gastrointestinal 6-10%; reproductive and endocrine 12-16%;
    // multisystem 8-12%; biostatistics and epidemiology 4-6%; social
    // sciences (communication, ethics) 6-9%. Split within a shared range is
    // ours. Seven 60-minute blocks of up to 40 items; pass/fail since 2022.
    val step1 = TargetExam(
        id = "step1", name = "USMLE Step 1", shortName = "Step 1", region = ExamRegion.usa, family = ExamTrack.usmle,
        options = 5, stemWords = 90..200,
        leadIns = "mechanism, most likely cause, underlying pathophysiology, the drug's mechanism or adverse effect, the expected lab or histology finding",
        conventions = usUnits, recallShare = 0.1,
        blueprint = listOf(s(ExamDomain.genetics, 3, "Human development and genetics"), s(ExamDomain.heme, 7, "Blood and lymphoreticular"), s(ExamDomain.immunology, 4, "Immune system"),
                    s(ExamDomain.psychiatry, 5, "Behavioural health"), s(ExamDomain.neuro, 7, "Nervous system and special senses"),
                    s(ExamDomain.msk, 5), s(ExamDomain.derm, 3), s(ExamDomain.cardio, 8), s(ExamDomain.resp, 6.5), s(ExamDomain.renal, 6.5), s(ExamDomain.gi, 8),
                    s(ExamDomain.endocrine, 7), s(ExamDomain.obstetrics, 3, "Pregnancy"), s(ExamDomain.gynaecology, 4, "Reproductive system and breast"),
                    s(ExamDomain.multisystem, 10, "Multisystem processes and disorders"), s(ExamDomain.biostatistics, 5),
                    s(ExamDomain.ethics, 8, "Social sciences: communication and ethics")),
        blueprintSource = "USMLE Step 1 Content Outline and Specifications (usmle.org): published ranges, midpoints",
        blueprintIsApproximate = false,
        sections = blocks(7, questions = 40, minutes = 60), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "Up to 280 questions in seven 60-minute blocks of up to 40, with break time, in one 8-hour day.",
        passMark = 0.60, passNote = "Pass/fail since January 2022; USMLE does not publish a percent-correct pass mark (about 60% is a common rough guide).",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep1, accuracyStrictness = 0.0, formatConfirmed = true)

    // USMLE Step 2 CK Content Outline (usmle.org): immune 3-5%, blood 4-6%,
    // behavioural 8-10%, nervous 6-10%, skin 4-6%, musculoskeletal 6-10%,
    // cardiovascular 7-11%, respiratory 7-11%, gastrointestinal 7-11%, renal
    // and male reproductive 4-6%, pregnancy 4-6%, female reproductive and
    // breast 4-6%, endocrine 5-9%, multisystem 7-9%, biostatistics 3-5%,
    // social sciences (ethics, patient safety) 10-15%. Midpoints sum to
    // 112.5 and are normalised. Eight 60-minute blocks of up to 40 items.
    val step2ck = TargetExam(
        id = "step2ck", name = "USMLE Step 2 CK", shortName = "Step 2 CK", region = ExamRegion.usa, family = ExamTrack.usmle,
        options = 5, stemWords = 100..220,
        leadIns = "most likely diagnosis, next best step in management, most appropriate pharmacotherapy, most appropriate initial investigation, most likely complication",
        conventions = usUnits, recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.immunology, 4), s(ExamDomain.heme, 5), s(ExamDomain.psychiatry, 9), s(ExamDomain.neuro, 8), s(ExamDomain.derm, 5), s(ExamDomain.msk, 8), s(ExamDomain.cardio, 9),
                    s(ExamDomain.resp, 9), s(ExamDomain.gi, 9), s(ExamDomain.renal, 5, "Renal, urinary and male reproductive"), s(ExamDomain.obstetrics, 5),
                    s(ExamDomain.gynaecology, 5), s(ExamDomain.endocrine, 7), s(ExamDomain.multisystem, 8, "Multisystem processes and disorders"),
                    s(ExamDomain.biostatistics, 4), s(ExamDomain.ethics, 12.5, "Social sciences: ethics, law and patient safety")),
        blueprintSource = "USMLE Step 2 CK Content Outline (usmle.org): published ranges, midpoints normalised",
        blueprintIsApproximate = false,
        sections = blocks(8, questions = 40, minutes = 60), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "Up to 318 questions in eight 60-minute blocks of up to 40, in one 9-hour day.",
        passMark = 0.62, passNote = "A three-digit score; the passing standard is set by USMLE (around 214-218 in recent years). The percent here is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.5, formatConfirmed = true)

    // USMLE Step 3 (usmle.org, Step 3 Content Outline): the same systems as
    // Step 2 CK with more weight on biostatistics / interpreting the
    // literature (5-10%) and on ambulatory management. Our midpoints.
    // Day 1, Foundations of Independent Practice: 232 items in six 60-minute
    // blocks; day 2, Advanced Clinical Medicine: 180 items in six 45-minute
    // blocks, then 13 computer-based case simulations (not mocked here).
    val step3 = TargetExam(
        id = "step3", name = "USMLE Step 3", shortName = "Step 3", region = ExamRegion.usa, family = ExamTrack.usmle,
        options = 5, stemWords = 100..230,
        leadIns = "most appropriate next step, screening and prevention, long-term and ambulatory management, prognosis, interpreting a study's results",
        conventions = usUnits, recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.immunology, 4), s(ExamDomain.heme, 4), s(ExamDomain.psychiatry, 9), s(ExamDomain.neuro, 7), s(ExamDomain.derm, 4), s(ExamDomain.msk, 7), s(ExamDomain.cardio, 10),
                    s(ExamDomain.resp, 9), s(ExamDomain.gi, 8), s(ExamDomain.renal, 5), s(ExamDomain.obstetrics, 5), s(ExamDomain.gynaecology, 5), s(ExamDomain.endocrine, 7),
                    s(ExamDomain.multisystem, 7, "Multisystem processes and disorders"), s(ExamDomain.biostatistics, 8, "Biostatistics and the medical literature"),
                    s(ExamDomain.ethics, 8, "Social sciences: ethics, law and patient safety")),
        blueprintSource = "USMLE Step 3 Content Outline (usmle.org): approximate midpoints",
        blueprintIsApproximate = true,
        sections = blocks(6, questions = 39, minutes = 60, name = "FIP " + MockFormat.partWord.lowercase()) + blocks(6, questions = 30, minutes = 45, name = "ACM " + MockFormat.partWord.lowercase()),
        sitsBlockwise = true, sitsSeparately = false,
        paperNote = "Two days: Foundations of Independent Practice (about 232 questions, six 60-minute blocks), then Advanced Clinical Medicine (180 questions, six 45-minute blocks) and 13 case simulations.",
        passMark = 0.60, passNote = "A three-digit score; the passing standard is set by USMLE (about 200). The percent here is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.6, formatConfirmed = true)

    // COMLEX-USA Level 1 (NBOME, nbome.org "COMLEX-USA Master Blueprint"):
    // NBOME weights competency domains and clinical presentations, not organ
    // systems; Osteopathic Principles and Practice is its own domain. The
    // system split is OUR approximation. Pass/fail since 2022.
    val comlex1 = TargetExam(
        id = "comlex1", name = "COMLEX-USA Level 1", shortName = "COMLEX 1", region = ExamRegion.usa, family = ExamTrack.usmle,
        options = 5, stemWords = 80..200,
        leadIns = "mechanism, most likely cause, the osteopathic structural finding, the most appropriate osteopathic manipulative treatment",
        conventions = usUnits, recallShare = 0.1,
        blueprint = listOf(s(ExamDomain.omm, 12), s(ExamDomain.cardio, 8), s(ExamDomain.resp, 7), s(ExamDomain.gi, 7), s(ExamDomain.renal, 6), s(ExamDomain.neuro, 8), s(ExamDomain.psychiatry, 5),
                    s(ExamDomain.msk, 7), s(ExamDomain.derm, 3), s(ExamDomain.heme, 5), s(ExamDomain.immunology, 4), s(ExamDomain.endocrine, 7), s(ExamDomain.obstetrics, 3),
                    s(ExamDomain.gynaecology, 3), s(ExamDomain.multisystem, 8), s(ExamDomain.biostatistics, 4), s(ExamDomain.ethics, 3)),
        blueprintSource = "NBOME COMLEX-USA Master Blueprint (nbome.org): our system split of its domains",
        blueprintIsApproximate = true,
        sections = blocks(8, questions = 44, minutes = 60, name = "Section"), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "One day, two 4-hour sessions of hour-long sections (about 352 questions); check nbome.org for the current count.",
        passMark = 0.60, passNote = "Pass/fail; NBOME does not publish a percent-correct pass mark.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep1, accuracyStrictness = 0.0, formatConfirmed = true)

    // COMLEX-USA Level 2-CE (NBOME Master Blueprint): as Level 1, our system
    // split, with the clinical disciplines' management emphasis.
    val comlex2 = TargetExam(
        id = "comlex2", name = "COMLEX-USA Level 2-CE", shortName = "COMLEX 2", region = ExamRegion.usa, family = ExamTrack.usmle,
        options = 5, stemWords = 90..220,
        leadIns = "most likely diagnosis, next best step, most appropriate management including osteopathic treatment",
        conventions = usUnits, recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.omm, 12), s(ExamDomain.cardio, 9), s(ExamDomain.resp, 8), s(ExamDomain.gi, 8), s(ExamDomain.renal, 5), s(ExamDomain.neuro, 7), s(ExamDomain.psychiatry, 8),
                    s(ExamDomain.msk, 7), s(ExamDomain.derm, 4), s(ExamDomain.heme, 4), s(ExamDomain.immunology, 2), s(ExamDomain.endocrine, 6), s(ExamDomain.obstetrics, 5),
                    s(ExamDomain.gynaecology, 5), s(ExamDomain.multisystem, 5), s(ExamDomain.emergency, 3), s(ExamDomain.biostatistics, 3), s(ExamDomain.ethics, 4)),
        blueprintSource = "NBOME COMLEX-USA Master Blueprint (nbome.org): our system split of its domains",
        blueprintIsApproximate = true,
        sections = blocks(8, questions = 44, minutes = 60, name = "Section"), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "One day of hour-long sections (about 352 questions); check nbome.org for the current count.",
        passMark = 0.62, passNote = "A three-digit score with a minimum pass set by NBOME. The percent here is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.5, formatConfirmed = true)

    // United Kingdom

    // PLAB 1 (GMC, gmc-uk.org): 180 single-best-answer questions in 3 hours,
    // set against the MLA content map. The GMC publishes the areas of
    // clinical practice but NOT percentages: these weights are ours, leaning
    // on acute care, common presentations and prescribing as the GMC's
    // guidance does.
    val plab1 = TargetExam(
        id = "plab1", name = "PLAB 1 (UKMLA)", shortName = "PLAB 1", region = ExamRegion.uk, family = ExamTrack.plab,
        options = 5, stemWords = 50..120,
        leadIns = "most likely diagnosis, most appropriate initial or immediate management, most appropriate investigation, what should be done next",
        conventions = ukUnits, recallShare = 0.1,
        blueprint = listOf(s(ExamDomain.emergency, 9), s(ExamDomain.cardio, 7), s(ExamDomain.resp, 6), s(ExamDomain.gi, 6), s(ExamDomain.endocrine, 5), s(ExamDomain.renal, 4), s(ExamDomain.neuro, 5),
                    s(ExamDomain.psychiatry, 6, "Mental health"), s(ExamDomain.msk, 4), s(ExamDomain.heme, 3), s(ExamDomain.id, 4), s(ExamDomain.derm, 3), s(ExamDomain.ent, 3),
                    s(ExamDomain.ophthalmology, 3), s(ExamDomain.peds, 6, "Child health"), s(ExamDomain.obstetrics, 4), s(ExamDomain.gynaecology, 4),
                    s(ExamDomain.oncology, 3, "Cancer"), s(ExamDomain.surgery, 5), s(ExamDomain.geriatrics, 2), s(ExamDomain.palliative, 2), s(ExamDomain.sexualHealth, 2),
                    s(ExamDomain.pharmacology, 4, "Clinical pharmacology and prescribing"), s(ExamDomain.ethics, 3, "Professional knowledge and ethics"),
                    s(ExamDomain.community, 2, "Social and population health")),
        blueprintSource = "GMC MLA content map (gmc-uk.org): areas as published, weights ours",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "PLAB 1", questions = 180, minutes = 180)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "180 single-best-answer questions in 3 hours, as the GMC sets it.",
        passMark = 0.63, passNote = "Set for each sitting by standard setting; usually a little over 60%.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.3, formatConfirmed = true)

    // MRCP(UK) Part 1 blueprint (mrcpuk.org), questions out of 200:
    // cardiology 15, haematology and oncology 15, clinical pharmacology 16,
    // clinical sciences 25, dermatology 8, endocrinology 15, gastroenterology
    // 15, geriatrics 4, infectious disease 15, nephrology 15, neurology 15,
    // ophthalmology 4, psychiatry 8, respiratory 15, rheumatology 15. The
    // splits inside "haematology and oncology" and "clinical sciences" are ours.
    val mrcp1 = TargetExam(
        id = "mrcp1", name = "MRCP(UK) Part 1", shortName = "MRCP 1", region = ExamRegion.uk, family = ExamTrack.mrcp,
        options = 5, stemWords = 80..200,
        leadIns = "most likely diagnosis, underlying mechanism, most likely explanation for these results, most appropriate investigation",
        conventions = ukUnits, recallShare = 0.15,
        blueprint = listOf(s(ExamDomain.cardio, 15), s(ExamDomain.heme, 9), s(ExamDomain.oncology, 6), s(ExamDomain.pharmacology, 16, "Clinical pharmacology and toxicology"),
                    s(ExamDomain.immunology, 6), s(ExamDomain.genetics, 4), s(ExamDomain.biostatistics, 5), s(ExamDomain.biochemistry, 5, "Biochemistry and metabolism"),
                    s(ExamDomain.physiology, 5, "Physiology and cell biology"), s(ExamDomain.derm, 8), s(ExamDomain.endocrine, 15), s(ExamDomain.gi, 15), s(ExamDomain.geriatrics, 4),
                    s(ExamDomain.id, 15, "Infectious diseases and GU medicine"), s(ExamDomain.renal, 15, "Nephrology"), s(ExamDomain.neuro, 15), s(ExamDomain.ophthalmology, 4),
                    s(ExamDomain.psychiatry, 8), s(ExamDomain.resp, 15), s(ExamDomain.msk, 15, "Rheumatology")),
        blueprintSource = "MRCP(UK) Part 1 blueprint (mrcpuk.org): questions per specialty out of 200",
        blueprintIsApproximate = false,
        sections = listOf(MockSectionSpec(title = "Paper 1", questions = 100, minutes = 180),
                   MockSectionSpec(title = "Paper 2", questions = 100, minutes = 180)),
        sitsBlockwise = false, sitsSeparately = true,
        paperNote = "Two papers of 100 best-of-five questions, 3 hours each, on one day. Sit one now and the other later.",
        passMark = 0.60, passNote = "Standard-set for each diet; reported as a scaled score. About 60% is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.2, formatConfirmed = true)

    // MRCS Part A (Intercollegiate, intercollegiatemrcsexams.org.uk): Paper 1
    // Applied Basic Sciences, Paper 2 Principles of Surgery-in-General. The
    // colleges publish the syllabus and times, not weights: ours.
    val mrcsA = TargetExam(
        id = "mrcsA", name = "MRCS Part A", shortName = "MRCS A", region = ExamRegion.uk, family = ExamTrack.mrcs,
        options = 5, stemWords = 30..110,
        leadIns = "which structure is most likely injured, the nerve or vessel at risk, the physiological change, the most appropriate perioperative step",
        conventions = ukUnits, recallShare = 0.3,
        blueprint = listOf(s(ExamDomain.anatomy, 30, "Applied surgical anatomy"), s(ExamDomain.physiology, 15, "Applied physiology"),
                    s(ExamDomain.pathology, 15, "Applied pathology"), s(ExamDomain.anaesthesia, 10, "Perioperative care"),
                    s(ExamDomain.emergency, 8, "Trauma"), s(ExamDomain.oncology, 6, "Surgical oncology"), s(ExamDomain.multisystem, 6, "Critical care"),
                    s(ExamDomain.peds, 3, "Paediatric surgery"), s(ExamDomain.surgery, 4, "Surgical technique"), s(ExamDomain.ethics, 3, "Professional practice")),
        blueprintSource = "Intercollegiate MRCS Part A syllabus: areas as published, weights ours",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "Applied Basic Sciences", questions = 180, minutes = 180),
                   MockSectionSpec(title = "Principles of Surgery", questions = 120, minutes = 120)),
        sitsBlockwise = false, sitsSeparately = true,
        paperNote = "Applied Basic Sciences (3 hours) and Principles of Surgery-in-General (2 hours) on one day, at about a question a minute.",
        passMark = 0.70, passNote = "Standard-set each sitting; the colleges publish the mark with the results.",
        negativeMarking = null, exemplars = ExemplarSource.medmcqa, accuracyStrictness = 0.2, formatConfirmed = true)

    // Canada and Australia

    // MCCQE Part I (Medical Council of Canada, mcc.ca blueprint): weighted
    // by dimensions of care and physician activities, not disciplines; the
    // discipline split here is OURS. 210 MCQs plus clinical decision-making
    // cases (the cases are not mocked here).
    val mccqe1 = TargetExam(
        id = "mccqe1", name = "MCCQE Part I", shortName = "MCCQE I", region = ExamRegion.canada, family = ExamTrack.general,
        options = 5, stemWords = 60..150,
        leadIns = "most likely diagnosis, most appropriate next step, most appropriate management, counselling and prevention",
        conventions = "SI units, Canadian drug names and current Canadian guidelines", recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.cardio, 4), s(ExamDomain.resp, 4), s(ExamDomain.gi, 4), s(ExamDomain.endocrine, 3), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 3), s(ExamDomain.heme, 2), s(ExamDomain.id, 3),
                    s(ExamDomain.msk, 2), s(ExamDomain.derm, 1), s(ExamDomain.emergency, 3), s(ExamDomain.surgery, 12), s(ExamDomain.peds, 12), s(ExamDomain.obstetrics, 6), s(ExamDomain.gynaecology, 6),
                    s(ExamDomain.psychiatry, 12), s(ExamDomain.community, 10, "Population health"), s(ExamDomain.ethics, 8, "Ethical, legal and organisational")),
        blueprintSource = "MCC blueprint (mcc.ca): our discipline split",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "Multiple-choice", questions = 210, minutes = 240)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "One day: 210 multiple-choice questions, then clinical decision-making cases (not included here).",
        passMark = 0.60, passNote = "A scaled score with a pass score set by the MCC. The percent here is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.4, formatConfirmed = true)

    // AMC CAT MCQ (Australian Medical Council, amc.org.au): 150 items (120
    // scored) in 3.5 hours across adult health (medicine, surgery), women's
    // health, child health, mental health and population health. The
    // proportions are ours.
    val amc = TargetExam(
        id = "amc", name = "AMC CAT MCQ", shortName = "AMC", region = ExamRegion.australia, family = ExamTrack.general,
        options = 5, stemWords = 60..150,
        leadIns = "most likely diagnosis, most appropriate next step, most appropriate management",
        conventions = "SI units, Australian drug names and current Australian guidelines (Therapeutic Guidelines, RACGP)", recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.cardio, 5), s(ExamDomain.resp, 4), s(ExamDomain.gi, 4), s(ExamDomain.endocrine, 4), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 4), s(ExamDomain.heme, 2), s(ExamDomain.id, 3),
                    s(ExamDomain.msk, 2), s(ExamDomain.derm, 2), s(ExamDomain.emergency, 2), s(ExamDomain.surgery, 15, "Adult health: surgery"), s(ExamDomain.obstetrics, 7.5),
                    s(ExamDomain.gynaecology, 7.5), s(ExamDomain.peds, 12.5, "Child health"), s(ExamDomain.psychiatry, 12.5, "Mental health"),
                    s(ExamDomain.community, 5, "Population health"), s(ExamDomain.ethics, 5)),
        blueprintSource = "AMC MCQ examination specifications (amc.org.au): areas as published, proportions ours",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "CAT MCQ", questions = 150, minutes = 210)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "150 questions (120 scored) in 3.5 hours, computer-adaptive.",
        passMark = 0.60, passNote = "A scaled score (pass 250 on a 0-500 scale). The percent here is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.3, formatConfirmed = true)

    // India

    // NEET-PG (NBEMS, natboard.edu.in information bulletin): 200 MCQs in
    // 3.5 hours, four options, +4 / -1. The bulletin's subject distribution
    // is "indicative"; ours, out of 200: anatomy 10, physiology 10,
    // biochemistry 10, pathology 14, pharmacology 14, microbiology 13,
    // forensic 6, PSM 16, medicine 25 (split by system), surgery 25, OBG 17,
    // paediatrics 8, ENT 6, ophthalmology 6, orthopaedics 6, anaesthesia 3,
    // radiology 3, dermatology 4, psychiatry 4.
    val neetBlueprint: List<BlueprintShare> = listOf(
        s(ExamDomain.anatomy, 10), s(ExamDomain.physiology, 10), s(ExamDomain.biochemistry, 10), s(ExamDomain.pathology, 14), s(ExamDomain.pharmacology, 14),
        s(ExamDomain.microbiology, 13), s(ExamDomain.forensic, 6), s(ExamDomain.community, 16, "Social and preventive medicine"),
        s(ExamDomain.cardio, 4), s(ExamDomain.resp, 3), s(ExamDomain.gi, 3), s(ExamDomain.endocrine, 3), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 3), s(ExamDomain.heme, 3), s(ExamDomain.id, 3),
        s(ExamDomain.surgery, 25), s(ExamDomain.obstetrics, 9), s(ExamDomain.gynaecology, 8), s(ExamDomain.peds, 8), s(ExamDomain.ent, 6), s(ExamDomain.ophthalmology, 6),
        s(ExamDomain.orthopaedics, 6), s(ExamDomain.anaesthesia, 3), s(ExamDomain.radiology, 3), s(ExamDomain.derm, 4), s(ExamDomain.psychiatry, 4))

    val neetpg = TargetExam(
        id = "neetpg", name = "NEET-PG", shortName = "NEET-PG", region = ExamRegion.india, family = ExamTrack.general,
        options = 4, stemWords = 8..60,
        leadIns = "direct one-line recall (\"drug of choice for...\", \"most common site of...\", \"all of the following are true EXCEPT\"), short clinical one-liners, investigation of choice",
        conventions = indiaUnits, recallShare = 0.6,
        blueprint = neetBlueprint,
        blueprintSource = "NBEMS NEET-PG information bulletin (natboard.edu.in): indicative subject distribution, approximate",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "NEET-PG", questions = 200, minutes = 210)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "200 four-option questions in 3.5 hours; +4 for right, -1 for wrong.",
        passMark = 0.50, passNote = "Qualifying is by percentile (50th for the general category), not a fixed percent.",
        negativeMarking = "-1 of +4 for a wrong answer", exemplars = ExemplarSource.medmcqa, accuracyStrictness = 0.1, formatConfirmed = true)

    // INI-CET (AIIMS New Delhi, aiimsexams.ac.in): 200 MCQs in 3 hours, four
    // options, -1/3 for a wrong answer. AIIMS publishes no subject
    // distribution: NEET-PG's is used, approximate.
    val inicet = TargetExam(
        id = "inicet", name = "INI-CET", shortName = "INI-CET", region = ExamRegion.india, family = ExamTrack.general,
        options = 4, stemWords = 10..80,
        leadIns = "short clinical one-liners and direct recall, drug of choice, investigation of choice, next step",
        conventions = indiaUnits, recallShare = 0.5,
        blueprint = neetBlueprint,
        blueprintSource = "No published distribution: NEET-PG's, approximate",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "INI-CET", questions = 200, minutes = 180)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "200 four-option questions in 3 hours; a third of a mark off for a wrong answer.",
        passMark = 0.50, passNote = "Qualifying is by percentile (50th for the general category).",
        negativeMarking = "-1/3 for a wrong answer", exemplars = ExemplarSource.medmcqa, accuracyStrictness = 0.1, formatConfirmed = true)

    // FMGE (NBEMS information bulletin): 300 MCQs in two parts of 150, 150
    // minutes each, four options, no negative marking, pass 150/300. Subject
    // distribution out of 300 as the bulletin gives it (medicine split by
    // system by us); it adds to 295, normalised.
    val fmge = TargetExam(
        id = "fmge", name = "FMGE", shortName = "FMGE", region = ExamRegion.india, family = ExamTrack.general,
        options = 4, stemWords = 8..50,
        leadIns = "direct one-line recall, drug of choice, most common cause, investigation of choice",
        conventions = indiaUnits, recallShare = 0.6,
        blueprint = listOf(s(ExamDomain.anatomy, 17), s(ExamDomain.physiology, 17), s(ExamDomain.biochemistry, 17), s(ExamDomain.pathology, 13), s(ExamDomain.microbiology, 13),
                    s(ExamDomain.pharmacology, 13), s(ExamDomain.forensic, 10), s(ExamDomain.community, 30, "Community medicine"),
                    s(ExamDomain.cardio, 5), s(ExamDomain.resp, 4), s(ExamDomain.gi, 4), s(ExamDomain.endocrine, 4), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 4), s(ExamDomain.heme, 3), s(ExamDomain.id, 6),
                    s(ExamDomain.psychiatry, 5), s(ExamDomain.derm, 5), s(ExamDomain.surgery, 32), s(ExamDomain.orthopaedics, 5), s(ExamDomain.anaesthesia, 5), s(ExamDomain.radiology, 5),
                    s(ExamDomain.peds, 15), s(ExamDomain.ophthalmology, 15), s(ExamDomain.ent, 15), s(ExamDomain.obstetrics, 15), s(ExamDomain.gynaecology, 15)),
        blueprintSource = "NBEMS FMGE information bulletin (natboard.edu.in): subject-wise questions, approximate",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "Part A", questions = 150, minutes = 150),
                   MockSectionSpec(title = "Part B", questions = 150, minutes = 150)),
        sitsBlockwise = false, sitsSeparately = true,
        paperNote = "300 four-option questions in two parts of 150 minutes each, on one day. No negative marking.",
        passMark = 0.50, passNote = "150 out of 300 to pass.",
        negativeMarking = null, exemplars = ExemplarSource.medmcqa, accuracyStrictness = 0.1, formatConfirmed = true)

    // Saudi Arabia and the Gulf

    // SMLE (Saudi Commission for Health Specialties, scfhs.org.sa, sat at
    // Prometric): the SCFHS blueprint weights medicine, surgery, paediatrics
    // and obstetrics & gynaecology, with basic sciences applied within them.
    // The split and the paper here are approximate - check the current SCFHS
    // candidate guide.
    val smle = TargetExam(
        id = "smle", name = "SMLE (Saudi Medical Licensing Exam)", shortName = "SMLE", region = ExamRegion.gulf, family = ExamTrack.general,
        options = 4, stemWords = 30..100,
        leadIns = "most likely diagnosis, most appropriate next step, most appropriate management, best initial investigation",
        conventions = intlUnits, recallShare = 0.2,
        blueprint = listOf(s(ExamDomain.cardio, 5), s(ExamDomain.resp, 4), s(ExamDomain.gi, 4), s(ExamDomain.endocrine, 4), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 3), s(ExamDomain.heme, 2), s(ExamDomain.id, 3),
                    s(ExamDomain.psychiatry, 2), s(ExamDomain.surgery, 12), s(ExamDomain.orthopaedics, 3), s(ExamDomain.ent, 2), s(ExamDomain.ophthalmology, 2), s(ExamDomain.emergency, 5),
                    s(ExamDomain.peds, 20), s(ExamDomain.obstetrics, 10), s(ExamDomain.gynaecology, 10), s(ExamDomain.ethics, 5, "Ethics and professionalism")),
        blueprintSource = "SCFHS SMLE blueprint (scfhs.org.sa): disciplines as published, split approximate",
        blueprintIsApproximate = true,
        sections = blocks(4, questions = 75, minutes = 90, name = "Section"), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "About 300 four-option questions in timed sections at a Prometric centre; check the current SCFHS guide.",
        passMark = 0.60, passNote = "A scaled score with a pass mark set by SCFHS. About 60% is a rough guide.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.2, formatConfirmed = false)

    // The Gulf regulators' general-practitioner licensing exams (Prometric):
    // no public blueprint gives percentages; this is OUR general-practice
    // weighting, the same for each.
    val gulfBlueprint: List<BlueprintShare> = listOf(
        s(ExamDomain.cardio, 6), s(ExamDomain.resp, 5), s(ExamDomain.gi, 5), s(ExamDomain.endocrine, 5), s(ExamDomain.renal, 3), s(ExamDomain.neuro, 4), s(ExamDomain.heme, 2), s(ExamDomain.id, 5),
        s(ExamDomain.surgery, 12), s(ExamDomain.emergency, 8), s(ExamDomain.peds, 13), s(ExamDomain.obstetrics, 7), s(ExamDomain.gynaecology, 6), s(ExamDomain.psychiatry, 5),
        s(ExamDomain.derm, 3), s(ExamDomain.ent, 2), s(ExamDomain.ophthalmology, 2), s(ExamDomain.orthopaedics, 3), s(ExamDomain.ethics, 2), s(ExamDomain.community, 2))

    private fun gulf(id: String, name: String, short: String, body: String): TargetExam =
        TargetExam(
            id = id, name = name, shortName = short, region = ExamRegion.gulf, family = ExamTrack.general,
            options = 4, stemWords = 30..100,
            leadIns = "most likely diagnosis, most appropriate next step, most appropriate management",
            conventions = intlUnits, recallShare = 0.2,
            blueprint = gulfBlueprint,
            blueprintSource = "$body: no published percentages; our general-practice weighting",
            blueprintIsApproximate = true,
            sections = listOf(MockSectionSpec(title = short, questions = 150, minutes = 180)), sitsBlockwise = false, sitsSeparately = false,
            paperNote = "A Prometric computer-based exam, typically 100-150 four-option questions in 2.5-3 hours depending on the licence category; check with $body.",
            passMark = 0.60, passNote = "Commonly reported as 60%; set by $body.",
            negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.2, formatConfirmed = false)

    val dha: TargetExam = gulf("dha", "DHA licensing exam (Dubai)", "DHA", "the Dubai Health Authority")
    val doh: TargetExam = gulf("doh", "DOH licensing exam (Abu Dhabi, formerly HAAD)", "DOH", "the Department of Health Abu Dhabi")
    val mohap: TargetExam = gulf("mohap", "MOHAP licensing exam (UAE)", "MOHAP", "the UAE Ministry of Health and Prevention")
    val qchp: TargetExam = gulf("qchp", "QCHP / DHP licensing exam (Qatar)", "QCHP", "Qatar's Department of Healthcare Professions")
    val omsb: TargetExam = gulf("omsb", "OMSB licensing exam (Oman)", "OMSB", "the Oman Medical Specialty Board")

    // Egypt

    // The Egyptian Medical Licensing Exam for new graduates (announced by the
    // Supreme Council of Universities / Ministry of Health): its full format
    // and blueprint are not published in detail. This is a general clinical
    // single-best-answer blueprint, four options, marked unconfirmed.
    // (The Egyptian Fellowship's written exams are specialty by specialty
    // with no public blueprint, so they are not listed.)
    val emle = TargetExam(
        id = "emle", name = "Egyptian Medical Licensing Exam", shortName = "Egypt MLE", region = ExamRegion.egypt, family = ExamTrack.general,
        options = 4, stemWords = 20..90,
        leadIns = "most likely diagnosis, most appropriate next step, most appropriate management, direct recall",
        conventions = "SI units, international generic drug names, and current guidelines as taught in Egyptian faculties of medicine", recallShare = 0.3,
        blueprint = listOf(s(ExamDomain.cardio, 6), s(ExamDomain.resp, 5), s(ExamDomain.gi, 5), s(ExamDomain.endocrine, 5), s(ExamDomain.renal, 4), s(ExamDomain.neuro, 4), s(ExamDomain.heme, 3), s(ExamDomain.id, 5),
                    s(ExamDomain.surgery, 14), s(ExamDomain.emergency, 5), s(ExamDomain.peds, 13), s(ExamDomain.obstetrics, 8), s(ExamDomain.gynaecology, 7), s(ExamDomain.psychiatry, 3),
                    s(ExamDomain.pharmacology, 5), s(ExamDomain.community, 5, "Community medicine"), s(ExamDomain.ethics, 3)),
        blueprintSource = "Not published in detail: a general clinical blueprint, ours",
        blueprintIsApproximate = true,
        sections = listOf(MockSectionSpec(title = "Paper", questions = 100, minutes = 120)), sitsBlockwise = false, sitsSeparately = false,
        paperNote = "The format is not fully published: practise at about a question every 70 seconds and check the official announcements.",
        passMark = 0.60, passNote = "Not published; 60% is a placeholder.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.2, formatConfirmed = false)

    // International

    // IFOM Clinical Science Examination (NBME, nbme.org): 160 items in four
    // sections; content medicine 30-40%, surgery 15-20%, paediatrics
    // 15-20%, obstetrics and gynaecology 10-15%, psychiatry 10-15% (our
    // reading of NBME's outline; midpoints, medicine split by system).
    val ifom = TargetExam(
        id = "ifom", name = "IFOM Clinical Science (NBME)", shortName = "IFOM", region = ExamRegion.international, family = ExamTrack.general,
        options = 5, stemWords = 90..200,
        leadIns = "most likely diagnosis, next best step in management, most appropriate pharmacotherapy",
        conventions = "SI units with conventional units alongside, and current international guidelines", recallShare = 0.05,
        blueprint = listOf(s(ExamDomain.cardio, 6), s(ExamDomain.resp, 5), s(ExamDomain.gi, 5), s(ExamDomain.endocrine, 4), s(ExamDomain.renal, 4), s(ExamDomain.neuro, 4), s(ExamDomain.heme, 3), s(ExamDomain.id, 4),
                    s(ExamDomain.surgery, 17.5), s(ExamDomain.peds, 17.5), s(ExamDomain.obstetrics, 6.5), s(ExamDomain.gynaecology, 6), s(ExamDomain.psychiatry, 12.5)),
        blueprintSource = "NBME IFOM Clinical Science content outline (nbme.org): midpoints, approximate",
        blueprintIsApproximate = true,
        sections = blocks(4, questions = 40, minutes = 65, name = "Section"), sitsBlockwise = true, sitsSeparately = false,
        paperNote = "160 questions in four sections, about 4.5 hours in all.",
        passMark = 0.60, passNote = "Scaled scores; the pass standard is set by whoever uses the exam.",
        negativeMarking = null, exemplars = ExemplarSource.medqaStep23, accuracyStrictness = 0.4, formatConfirmed = true)
}
