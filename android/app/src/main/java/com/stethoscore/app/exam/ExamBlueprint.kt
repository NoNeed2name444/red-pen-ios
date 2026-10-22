package com.stethoscore.app.exam

import com.stethoscore.app.coverage.AreaCoverage
import com.stethoscore.app.coverage.CoverageEngine
import com.stethoscore.app.coverage.CoverageStatus
import com.stethoscore.app.coverage.Syllabus
import com.stethoscore.app.coverage.SyllabusArea
import com.stethoscore.app.coverage.SyllabusSubtopic

// A port of ios/RedPen/Shared/Exam/ExamBlueprint.swift: an exam's
// blueprint turned into the coverage map, the readiness estimate, what to
// study next, and the share of a generated set each area gets. Pure Kotlin
// over CoverageEngine (ExamCatalogTest).

/**
 * One area of the plan the app studies to: a blueprint line with its syllabus
 * subtopics, the primary exam's share, and the weight it gets once a second
 * exam is counted in.
 */
data class BlueprintArea(
    val domain: ExamDomain,
    val title: String,
    /** Percent of the primary exam (0 for an area only the second exam has). */
    val percent: Double,
    /** Percent of the combined plan: 70% primary, 30% second exam. */
    val weight: Double,
    val syllabus: SyllabusArea,
) {
    val id: String get() = domain.rawValue
}

/** Where the student stands on one blueprint area. */
data class BlueprintStanding(
    val area: BlueprintArea,
    /** 0-1: covered subtopics count 1, thin ones a half. */
    val coverage: Double,
    val answered: Int,
    val correct: Int,
    /**
     * 0-1: the expected share right on this area's questions on the day - the
     * student's own answers, pulled towards a prior set by coverage while
     * there are few of them.
     */
    val readiness: Double,
    /** Weight x weakness: how much studying this area now is worth. */
    val priority: Double,
) {
    val id: String get() = area.id
}

/** One row of [ExamBlueprint.quotas]. */
data class BlueprintQuota(val area: BlueprintArea, val questions: Int)

object ExamBlueprint {

    /** How much a second exam counts in the combined plan. */
    const val secondaryShare = 0.3

    // Subtopics per domain

    /**
     * The syllabus subtopics each domain is matched with: the coverage
     * engine's shared blocks, the exam-specific areas already written for
     * PLAB, USMLE and MRCS, and a few basic-science blocks of our own.
     */
    fun subtopics(domain: ExamDomain): List<SyllabusSubtopic> = when (domain) {
        ExamDomain.anatomy -> area(Syllabus.mrcs, "Applied surgical anatomy")
        ExamDomain.physiology -> area(Syllabus.mrcs, "Applied physiology")
        ExamDomain.biochemistry -> area(Syllabus.plab, "Clinical biochemistry") + generalPrinciples(listOf(0, 7))
        ExamDomain.pathology -> area(Syllabus.mrcs, "Applied pathology")
        ExamDomain.pharmacology -> Syllabus.pharmacology
        ExamDomain.microbiology -> microbiology
        ExamDomain.immunology -> Syllabus.immunology
        ExamDomain.genetics -> Syllabus.genetics
        ExamDomain.multisystem -> area(Syllabus.usmle, "Multisystem processes and disorders")
        ExamDomain.biostatistics -> Syllabus.epidemiology
        ExamDomain.ethics -> Syllabus.ethics
        ExamDomain.forensic -> forensic
        ExamDomain.community -> area(Syllabus.plab, "Social and population health")
        ExamDomain.cardio -> Syllabus.cardiology
        ExamDomain.resp -> Syllabus.respiratory
        ExamDomain.gi -> Syllabus.gastro
        ExamDomain.endocrine -> Syllabus.endocrine
        ExamDomain.renal -> Syllabus.renal
        ExamDomain.neuro -> Syllabus.neurology
        ExamDomain.msk -> Syllabus.rheumatology
        ExamDomain.heme -> Syllabus.haematology
        ExamDomain.id -> Syllabus.infection
        ExamDomain.derm -> Syllabus.dermatology
        ExamDomain.psychiatry -> Syllabus.mentalHealth
        ExamDomain.peds -> Syllabus.childHealth
        ExamDomain.obstetrics -> Syllabus.obstetrics
        ExamDomain.gynaecology -> Syllabus.gynaecology
        ExamDomain.ent -> Syllabus.ent
        ExamDomain.ophthalmology -> Syllabus.ophthalmology
        ExamDomain.oncology -> Syllabus.oncology
        ExamDomain.surgery -> area(Syllabus.plab, "Surgery")
        ExamDomain.orthopaedics -> orthopaedics
        ExamDomain.anaesthesia -> Syllabus.perioperative
        ExamDomain.radiology -> area(Syllabus.plab, "Clinical imaging")
        ExamDomain.emergency -> area(Syllabus.plab, "Acute and emergency")
        ExamDomain.geriatrics -> Syllabus.olderAdults
        ExamDomain.palliative -> Syllabus.palliative
        ExamDomain.sexualHealth -> Syllabus.sexualHealth
        ExamDomain.omm -> omm
    }

    private fun area(list: List<SyllabusArea>, name: String): List<SyllabusSubtopic> =
        list.firstOrNull { it.name == name }?.subtopics ?: emptyList()

    /** Some of USMLE's "General principles" subtopics, by position. */
    private fun generalPrinciples(picks: List<Int>): List<SyllabusSubtopic> {
        val all = area(Syllabus.usmle, "General principles")
        return picks.mapNotNull { all.getOrNull(it) }
    }

    private fun t(name: String, keywords: String): SyllabusSubtopic = Syllabus.t(name, keywords)

    val microbiology: List<SyllabusSubtopic> = listOf(
        t("Bacteriology", "gram positive, gram negative, staphylococcus, streptococcus, clostridium, mycobacterium, bacterial toxin, exotoxin, endotoxin"),
        t("Virology", "virus, viral, dna virus, rna virus, herpes, influenza, retrovirus, hepatitis virus"),
        t("Mycology", "fungus, fungal, candida, aspergillus, cryptococcus, dermatophyte"),
        t("Parasitology", "parasite, protozoa, helminth, malaria, plasmodium, giardia, entamoeba, tapeworm"),
        t("Sterilisation and laboratory diagnosis", "sterilisation, disinfection, culture medium, gram stain, pcr, serology"),
    )

    val forensic: List<SyllabusSubtopic> = listOf(
        t("Thanatology", "rigor mortis, livor mortis, post mortem, postmortem, autopsy, time since death"),
        t("Injuries and wounds", "abrasion, contusion, laceration, incised wound, firearm, gunshot"),
        t("Toxicology", "poisoning, toxicology, organophosphate, arsenic, snake bite, antidote"),
        t("Asphyxia", "hanging, strangulation, drowning, asphyxia"),
        t("Medical law", "medicolegal, dying declaration, inquest, consent, negligence, ipc"),
    )

    val orthopaedics: List<SyllabusSubtopic> = listOf(
        t("Fractures", "fracture, colles, scaphoid, supracondylar, neck of femur, open fracture"),
        t("Dislocations and nerve injuries", "dislocation, shoulder dislocation, hip dislocation, nerve injury, wrist drop, foot drop"),
        t("Bone infection and tumours", "osteomyelitis, osteosarcoma, ewing, giant cell tumour, bone tumour"),
        t("Paediatric orthopaedics", "developmental dysplasia, perthes, slipped capital femoral epiphysis, clubfoot"),
        t("Spine and joints", "prolapsed disc, spondylolisthesis, osteoarthritis, compartment syndrome"),
    )

    val omm: List<SyllabusSubtopic> = listOf(
        t("Somatic dysfunction and diagnosis", "somatic dysfunction, tart, tissue texture, restriction, asymmetry"),
        t("Techniques", "counterstrain, muscle energy, hvla, high velocity, myofascial release, osteopathic manipulative"),
        t("Viscerosomatic and Chapman reflexes", "viscerosomatic, chapman point, somatovisceral"),
        t("Spinal and rib mechanics", "fryette, rib dysfunction, sacral torsion, vertebral motion"),
    )

    // The plan

    /**
     * The areas to study to, the primary exam's first by share, then any the
     * second exam adds. Each area appears once, however many blueprint lines
     * share its domain.
     */
    fun plan(primary: TargetExam, secondary: TargetExam? = null): List<BlueprintArea> {
        val second = if (secondary?.id == primary.id) null else secondary
        val own = if (second == null) 1.0 else 1 - secondaryShare
        val out = ArrayList<BlueprintArea>()
        val seen = HashSet<ExamDomain>()
        // names are how the coverage map matches areas, so none repeats
        val titles = HashSet<String>()
        fun add(domain: ExamDomain, label: String, percent: Double, weight: Double) {
            val title = if (titles.add(label)) label else domain.title
            titles.add(title)
            out.add(BlueprintArea(domain, title, percent, weight, SyllabusArea(title, subtopics(domain))))
        }
        for (row in primary.shares) {
            if (!seen.add(row.domain)) continue
            val p = primary.percent(row.domain)
            val extra = second?.let { it.percent(row.domain) * secondaryShare } ?: 0.0
            add(row.domain, row.title, p, p * own + extra)
        }
        if (second != null) {
            for (row in second.shares) {
                if (!seen.add(row.domain)) continue
                add(row.domain, row.title, 0.0, second.percent(row.domain) * secondaryShare)
            }
        }
        return out
    }

    /** The coverage map's areas for the plan. */
    fun syllabus(plan: List<BlueprintArea>): List<SyllabusArea> = plan.map { it.syllabus }

    // Standing, readiness, priority

    /** A prior for an area's share right, from how well the library covers it: 35% with nothing, 65% when all of it is covered. */
    fun prior(coverage: Double): Double = 0.35 + 0.3 * minOf(1.0, maxOf(0.0, coverage))

    /** How many answers the prior is worth. */
    const val priorAnswers = 8.0

    fun coverage(area: AreaCoverage): Double {
        if (area.subtopics.isEmpty()) return 0.0
        val points = area.subtopics.sumOf {
            when (it.status) {
                CoverageStatus.covered -> 1.0
                CoverageStatus.thin -> 0.5
                CoverageStatus.notCovered -> 0.0
            }
        }
        return points / area.subtopics.size
    }

    /** Each plan area's standing, from the coverage engine's assessment of the same areas (matched by name). */
    fun standings(plan: List<BlueprintArea>, assessed: List<AreaCoverage>): List<BlueprintStanding> {
        val byName = HashMap<String, AreaCoverage>()
        for (a in assessed) byName[a.area.name] = a
        return plan.map { area ->
            val found = byName[area.title]
            val cov = found?.let { coverage(it) } ?: 0.0
            val answered = found?.subtopics?.sumOf { it.answered } ?: 0
            val correct = found?.subtopics?.sumOf { it.correct } ?: 0
            val ready = (correct + prior(cov) * priorAnswers) / (answered + priorAnswers)
            val weakness = 1 - (0.5 * cov + 0.5 * ready)
            BlueprintStanding(area, cov, answered, correct, ready, area.weight * weakness)
        }
    }

    /** The expected share right on the primary exam: each area's readiness weighted by its share. */
    fun predictedScore(standings: List<BlueprintStanding>): Double {
        val total = standings.sumOf { it.area.percent }
        if (total <= 0) return 0.0
        return standings.sumOf { it.readiness * it.area.percent } / total
    }

    /** Blueprint coverage: the primary exam's shares, weighted by coverage. */
    fun weightedCoverage(standings: List<BlueprintStanding>): Double {
        val total = standings.sumOf { it.area.percent }
        if (total <= 0) return 0.0
        return standings.sumOf { it.coverage * it.area.percent } / total
    }

    /** What to study next: the areas worth most now, first. */
    fun studyNext(standings: List<BlueprintStanding>, limit: Int = 3): List<BlueprintStanding> =
        standings.sortedWith { a, b ->
            if (a.priority != b.priority) b.priority.compareTo(a.priority) else a.area.title.compareTo(b.area.title)
        }.take(maxOf(0, limit))

    // A generated set's topics

    /** How [count] questions divide across the plan: by weight, largest remainder, heaviest first; areas that get none are left out. */
    fun quotas(count: Int, plan: List<BlueprintArea>): List<BlueprintQuota> {
        if (count <= 0) return emptyList()
        val total = plan.sumOf { it.weight }
        if (total <= 0) return emptyList()
        val exact = plan.map { count.toDouble() * it.weight / total }
        val given = exact.map { Math.floor(it).toInt() }.toMutableList()
        var left = count - given.sum()
        val order = plan.indices.sortedWith { i, j ->
            val a = exact[i] - given[i]
            val b = exact[j] - given[j]
            if (a != b) b.compareTo(a) else plan[j].weight.compareTo(plan[i].weight)
        }
        var k = 0
        while (left > 0 && order.isNotEmpty()) {
            given[order[k % order.size]] += 1
            left -= 1
            k += 1
        }
        val rows = plan.indices.mapNotNull { if (given[it] > 0) BlueprintQuota(plan[it], given[it]) else null }
        return rows.sortedWith { a, b ->
            if (a.questions != b.questions) b.questions.compareTo(a.questions) else b.area.weight.compareTo(a.area.weight)
        }
    }

    // What a piece of text is about

    private val keywordIndex: List<Pair<ExamDomain, List<CoverageEngine.Keyword>>> by lazy {
        ExamDomain.entries.map { d -> d to subtopics(d).flatMap { it.keywords }.map { CoverageEngine.Keyword(it) } }
    }

    /** The domain a question, card or topic line is most about, among [within] when given; null when no keyword matches. */
    fun domain(text: String, within: Set<ExamDomain>? = null): ExamDomain? {
        val item = CoverageEngine.item(text, practice = true)
        if (item.words.isEmpty()) return null
        var best: ExamDomain? = null
        var bestScore = 0
        for ((d, keys) in keywordIndex) {
            if (within != null && d !in within) continue
            val score = keys.count { it.matches(item) }
            if (score > bestScore) {
                best = d
                bestScore = score
            }
        }
        return best
    }
}
