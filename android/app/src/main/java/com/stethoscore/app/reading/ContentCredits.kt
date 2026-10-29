package com.stethoscore.app.reading

import com.stethoscore.app.data.MCQQuestion
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.StudySet
import org.json.JSONObject

// A port of ios/RedPen/Shared/ContentCredits.swift (fed0105): where one set's
// content came from, with the licence and credit line of each part, and every
// licence the app's own content carries, for Settings. The words are iOS's,
// letter for letter (ContentCreditsTest).
//
// Android keeps a question's checked evidence inside the question's own JSON
// (MCQQuestion.rawJson, "differential" → "evidence", as iOS writes it), so it
// is read from there rather than from a typed field.

data class ContentLicence(val name: String, val url: String)

/** Content the app itself brings - not the student's - with its credit. */
data class ContentSource(
    val id: String,
    val name: String,
    /** What the app uses it for, in the student's terms. */
    val use: String,
    val licences: List<ContentLicence>,
    /** The credit line, as the licence or the source asks for it. */
    val attribution: String,
    /** What was changed, which CC BY asks to be said. Null when nothing is copied in. */
    val changes: String?,
    val home: String,
)

/** One public page an accuracy check read (iOS EvidenceRef). */
data class EvidenceRef(val id: String, val source: String, val title: String, val url: String) {
    /** "Europe PMC: Groin hernia repair (Hernia, 2023)". */
    val label: String get() = (if (source.isEmpty()) "" else "$source: ") + title.ifEmpty { url }
}

/** The evidence a question's differential was checked against, as iOS keeps it in the question. */
val MCQQuestion.evidence: List<EvidenceRef> get() = runCatching {
    val list = JSONObject(rawJson).optJSONObject("differential")?.optJSONArray("evidence") ?: return@runCatching emptyList()
    (0 until list.length()).mapNotNull { i ->
        list.optJSONObject(i)?.let { EvidenceRef(it.optString("id"), it.optString("source"), it.optString("title"), it.optString("url")) }
    }
}.getOrDefault(emptyList())

object ContentSources {

    val mit = ContentLicence("MIT licence", "https://opensource.org/license/mit")
    val ccBy4 = ContentLicence("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/legalcode.en")
    val apache2 = ContentLicence("Apache License 2.0", "https://www.apache.org/licenses/LICENSE-2.0")

    // style examples bundled with the iOS app (ExamExemplarData)

    val medqa = ContentSource(
        id = "medqa", name = "MedQA",
        use = "Example questions shown to the question writer, for the style of USMLE-type exams",
        licences = listOf(mit, ccBy4),
        attribution = "MedQA by Jin et al. (2020), github.com/jind11/MedQA, MIT licence; US questions from the GBaker/MedQA-USMLE-4-options mirror on Hugging Face, CC BY 4.0.",
        changes = "A few whole questions per topic, from the training split, with spacing tidied. They are shown to the question writer only as examples of style, not to you.",
        home = "https://github.com/jind11/MedQA")

    val medmcqa = ContentSource(
        id = "medmcqa", name = "MedMCQA",
        use = "Example questions shown to the question writer, for the style of NEET-PG, INI-CET and FMGE",
        licences = listOf(apache2),
        attribution = "MedMCQA by Pal et al. (2022), huggingface.co/datasets/openlifescienceai/medmcqa, Apache License 2.0.",
        changes = "A few whole questions per topic, from the training split, with spacing tidied. They are shown to the question writer only as examples of style, not to you.",
        home = "https://huggingface.co/datasets/openlifescienceai/medmcqa")

    // public sources a check reads (server/evidence.js)

    /** The credit line governance/licences/allowlist.json gives MedlinePlus. */
    const val medlinePlusCredit = "Courtesy of MedlinePlus from the National Library of Medicine"

    val medlinePlus = ContentSource(
        id = "medlineplus", name = "MedlinePlus",
        use = "Health topic summaries an accuracy check reads",
        licences = listOf(ContentLicence("U.S. government work (MedlinePlus's public-domain health topics)",
            "https://medlineplus.gov/about/using/usingcontent/")),
        attribution = "$medlinePlusCredit.",
        changes = null,
        home = "https://medlineplus.gov/")

    val europePMC = ContentSource(
        id = "europepmc", name = "Europe PMC",
        use = "Articles an accuracy check reads; their titles are shown with a link",
        licences = listOf(ContentLicence("Each article under its own licence, shown on its page", "https://europepmc.org/")),
        attribution = "Article search by Europe PMC (europepmc.org). Each article belongs to its authors and publisher.",
        changes = null,
        home = "https://europepmc.org/")

    val openFDA = ContentSource(
        id = "openfda", name = "openFDA",
        use = "Drug labels an accuracy check reads",
        licences = listOf(ContentLicence("CC0 1.0 (public domain)", "https://open.fda.gov/license/")),
        attribution = "Drug label data from openFDA, U.S. Food and Drug Administration. No endorsement by the FDA is implied.",
        changes = null,
        home = "https://open.fda.gov/")

    // imagery the app draws with (assets/earth, iOS Resources/Earth)

    /** The credit line the Earth maps' SOURCES.md gives, word for word. */
    const val nasaEarthCredit = "Earth imagery: NASA Earth Observatory (Blue Marble: Next Generation, Black Marble); clouds: NASA Goddard Space Flight Center; water mask: NASA GPM."

    val nasaEarth = ContentSource(
        id = "nasa-earth", name = "NASA Earth imagery",
        use = "The Earth in the Ideas map's Space theme: its land and seas, clouds, city lights and coastlines",
        licences = listOf(
            ContentLicence("NASA images and media: not subject to U.S. copyright", "https://www.nasa.gov/nasa-brand-center/images-and-media/"),
            ContentLicence("GPM data: freely available, source acknowledged", "https://gpm.nasa.gov/data/policy")),
        attribution = "$nasaEarthCredit No endorsement by NASA is implied.",
        changes = "Resized to 4096 by 2048 and 2048 by 1024 pixels and recompressed; the clouds, lights and water kept as grey maps.",
        home = "https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/")

    // the app's type (res/font, iOS Resources/Fonts)

    val ofl = ContentLicence("SIL Open Font License 1.1", "https://openfontlicense.org/open-font-license-official-text/")

    val fonts = ContentSource(
        id = "fonts", name = "Nunito and Baloo Bhaijaan 2",
        use = "The app's font: Nunito, and Baloo Bhaijaan 2 for Arabic",
        licences = listOf(ofl),
        attribution = "Nunito, copyright 2014 The Nunito Project Authors (github.com/googlefonts/nunito). Baloo Bhaijaan 2, copyright 2019 The Baloo 2 Project Authors (github.com/EkType/Baloo2). Both under the SIL Open Font License 1.1, whose full text comes with the app.",
        changes = "The font files are renamed and otherwise unchanged.",
        home = "https://github.com/googlefonts/nunito")

    /** Every source of content the app brings, for Settings. */
    val all: List<ContentSource> = listOf(medqa, medmcqa, medlinePlus, europePMC, openFDA, nasaEarth, fonts)

    /** The bank behind an exam's style examples (ExemplarSource's raw value). */
    fun styleBank(raw: String): ContentSource? = when {
        raw.startsWith("medqa") -> medqa
        raw == "medmcqa" -> medmcqa
        else -> null
    }

    /** The source an EvidenceRef came from, by the name the lookup gives it. */
    fun evidence(name: String): ContentSource? {
        val n = name.lowercase()
        return when {
            n.contains("medlineplus") -> medlinePlus
            n.contains("europe pmc") -> europePMC
            n.contains("openfda") || n.contains("fda") -> openFDA
            else -> null
        }
    }
}

/** One set's credits: what it was made from, and whose content it carries. */
data class SetCredits(
    val lectures: List<Lecture> = emptyList(),
    /** Lectures that questions or cards cite but that are not kept with the set. */
    val citedElsewhere: List<String> = emptyList(),
    /** The exam's style bank, when the set was written for an exam. */
    val style: ContentSource? = null,
    val examName: String? = null,
    val evidence: List<CheckedSource> = emptyList(),
    /** Evidence from a source this version does not know the licence of. */
    val otherEvidence: List<EvidenceRef> = emptyList(),
) {
    /** One lecture the set was made from. */
    data class Lecture(val source: SourceDoc, val cited: Int) {
        val id: String get() = source.id

        /** "PDF · 32 pages · 4 read from pictures". */
        val detail: String get() {
            val kind = source.sourceKind
            val parts = mutableListOf(kind.label)
            val noun = kind.pageNoun.lowercase()
            parts += "${source.pageCount} $noun${if (source.pageCount == 1) "" else "s"}"
            if (source.recognisedPages > 0) parts += "${source.recognisedPages} read from pictures"
            return parts.joinToString(" · ")
        }
    }

    /** A public source the set's checks read, and the pages of it they read. */
    data class CheckedSource(val source: ContentSource, val refs: List<EvidenceRef>) {
        val id: String get() = source.id
    }

    /** Nothing recorded at all: typed in, imported, or made before any of this was kept. */
    val isEmpty: Boolean get() =
        lectures.isEmpty() && citedElsewhere.isEmpty() && style == null && evidence.isEmpty() && otherEvidence.isEmpty()

    companion object {
        /** The set's credits; [exam] is the set's exam as its name and the raw value of its style bank. */
        fun make(set: StudySet, exam: Pair<String, String>?): SetCredits {
            // the lectures, with how many questions cite each
            val citations = (set.questions.mapNotNull { it.source } + set.cards.mapNotNull { it.source })
                .filter { it.isNotEmpty() }.toMutableList()
            val lectures = mutableListOf<Lecture>()
            for (source in set.sources) {
                val mine = citations.filter { cites(it, source.name) }
                citations.removeAll { cites(it, source.name) }
                lectures += Lecture(source, mine.size)
            }
            val seen = mutableSetOf<String>()
            val elsewhere = citations.map(::lectureName).filter { it.isNotEmpty() && seen.add(it) }

            val bank = exam?.let { ContentSources.styleBank(it.second) }

            // every evidence item once, grouped by source in the catalogue's order
            val refs = mutableListOf<EvidenceRef>()
            val keys = mutableSetOf<String>()
            for (question in set.questions) {
                for (ref in question.evidence) if (keys.add(ref.url + "|" + ref.title)) refs += ref
            }
            val checked = ContentSources.all.mapNotNull { source ->
                val theirs = refs.filter { ContentSources.evidence(it.source)?.id == source.id }
                if (theirs.isEmpty()) null else CheckedSource(source, theirs)
            }
            return SetCredits(
                lectures = lectures,
                citedElsewhere = elsewhere,
                style = bank,
                examName = if (bank != null) exam?.first else null,
                evidence = checked,
                otherEvidence = refs.filter { ContentSources.evidence(it.source) == null },
            )
        }

        /** Whether a citation ("Lupus, p. 14") names this lecture. */
        fun cites(citation: String, name: String): Boolean {
            val cited = lectureName(citation)
            return if (cited.isEmpty()) name.isEmpty() else cited == name
        }

        /** The lecture's name out of a citation: everything before ", p. ". */
        fun lectureName(citation: String): String {
            val at = citation.lastIndexOf(", p. ")
            if (at >= 0) return citation.substring(0, at)
            return if (citation.startsWith("p. ")) "" else citation
        }
    }
}
