package com.stethoscore.app.data

import java.util.Locale

// A patient to work up against the clock: who arrives and their history,
// already written as the clerking note, what can be examined and tested (each
// at a cost in minutes), what it all turns out to be, and what to do next.
// The patient is never questioned: the history is read, not asked for. One
// CaseFile is one patient; a Cases set holds a list of them
// (StudySet.caseFiles). Port of iOS Shared/Cases/CaseFile.swift.
//
// The shape follows the key-features approach (Page & Bordage 1995): a few
// findings carry the case, so they are marked `key`, and the ones that would
// kill if missed are marked `mustNotMiss`. The differentials, each with the
// steps for and against it, are the case's illness scripts (Schmidt &
// Rikers 2007).
//
// Read tolerantly (CaseJson): a field a later version adds, or one a writer
// left out, takes its default rather than losing the case.

/** Trims spaces and tabs only, as Swift's `.whitespaces`. */
internal fun String.trimSpaces(): String = trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }

/** One patient case. */
data class CaseFile(
    val id: String = newId(),
    val title: String = "",
    val specialty: String = "",
    val setting: Setting = Setting.ward,
    val patient: Patient = Patient(),
    /** The complaint in the patient's own words. */
    val complaint: String = "",
    /** The written history. */
    val clerking: Clerking = Clerking(),
    val arrival: List<Obs> = emptyList(),
    val budgetMinutes: Int = 20,
    val steps: List<CaseStep> = emptyList(),
    val diagnosis: Diagnosis = Diagnosis(),
    /** The working diagnoses worth weighing, the most likely first; the diagnosis is one of them. */
    val differentials: List<Differential> = emptyList(),
    /** Plausible names that are none of the above, mixed into the list the ladder is picked from. */
    val distractors: List<String> = emptyList(),
    /** The step after which the right diagnosis should lead. */
    val turningStep: String = "",
    val nextStep: NextStep = NextStep(),
    /** Three points to take away. */
    val teaching: List<String> = emptyList(),
    val source: Source = Source(),
    val verification: Verification = Verification.unchecked,
    /** Why a held case is held, in words. */
    val heldBecause: List<String> = emptyList(),
    /** The original object, so fields added by another version survive export. */
    val rawJson: String = "{}",
) {
    /** Where the patient is seen. */
    @Suppress("EnumEntryName")
    enum class Setting(val rawValue: String, val label: String) {
        emergency("emergency", "Emergency"), ward("ward", "Ward"), clinic("clinic", "Clinic"), community("community", "Community");

        companion object {
            /** A setting written loosely by a model: "ED", "A&E", "GP surgery". */
            fun read(text: String): Setting {
                val t = text.lowercase()
                entries.firstOrNull { it.rawValue == t }?.let { return it }
                if (t.contains("emerg") || t.contains("a&e") || t == "ed" || t.contains("casualty")) return emergency
                if (t.contains("clinic") || t.contains("outpatient")) return clinic
                if (t.contains("gp") || t.contains("community") || t.contains("home") || t.contains("practice")) return community
                return ward
            }
        }
    }

    /** Who the patient is, in a line. */
    data class Patient(
        /** A made-up name, for the initials on the patient's card. May be empty. */
        val name: String = "",
        val age: Int = 0,
        /** "F" or "M". */
        val sex: String = "",
        /** A few words about them: "retired teacher, lives alone". */
        val about: String = "",
        val rawJson: String = "{}",
    ) {
        val isFemale: Boolean get() = sex.uppercase().startsWith("F") || sex.lowercase().startsWith("w")

        /** "F" or "M", whatever the writer wrote. */
        val sexLetter: String get() = if (isFemale) "F" else if (sex.isEmpty()) "" else "M"

        /** Two letters for the avatar: the name's, or the sex and age. */
        val initials: String get() {
            val letters = name.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.substring(0, it.offsetByCodePoints(0, 1)).uppercase() }
            if (letters.isNotEmpty()) return letters
            return sexLetter + if (age > 0) age.toString() else ""
        }

        /** "58 F" */
        val ageSex: String get() = listOf(if (age > 0) age.toString() else "", sexLetter).filter { it.isNotEmpty() }.joinToString(" ")

        /** What TalkBack says: "58-year-old woman". */
        val spoken: String get() {
            val who = if (isFemale) "woman" else if (sex.isEmpty()) "patient" else "man"
            return if (age > 0) "$age-year-old $who" else who
        }
    }

    /** The history as a doctor wrote it on admission: read on arrival, never asked for. */
    data class Clerking(
        /** Presenting complaint. */
        val presenting: String = "",
        /** History of the presenting complaint. */
        val history: String = "",
        /** Past medical history. */
        val past: String = "",
        /** Drugs and allergies. */
        val drugs: String = "",
        /** Social history. */
        val social: String = "",
        val rawJson: String = "{}",
    ) {
        data class Part(val label: String, val text: String)

        /** The note's parts in the order a clerking is written, the empty ones left out. */
        val parts: List<Part> get() = listOf(
            "Presenting complaint" to presenting, "History of presenting complaint" to history,
            "Past medical history" to past, "Drugs" to drugs, "Social" to social,
        ).map { Part(it.first, it.second.trim()) }.filter { it.text.isNotEmpty() }

        val isEmpty: Boolean get() = parts.isEmpty()
    }

    /** One observation on arrival. */
    data class Obs(val sign: Sign, val value: Double, /** The diastolic pressure, for BP only. */ val second: Double? = null, val rawJson: String = "{}") {
        @Suppress("EnumEntryName")
        enum class Sign(val rawValue: String, val label: String, val spoken: String, val unit: String) {
            hr("hr", "HR", "Heart rate", "/min"),
            bp("bp", "BP", "Blood pressure", "mmHg"),
            rr("rr", "RR", "Respiratory rate", "/min"),
            spo2("spo2", "SpO₂", "Oxygen saturation", "%"),
            temp("temp", "Temp", "Temperature", "°C"),
            gcs("gcs", "GCS", "Glasgow coma scale", "/15");

            companion object { fun from(raw: String): Sign? = entries.firstOrNull { it.rawValue == raw } }
        }

        /** "128/82", "36.8", "98" */
        val shown: String get() {
            val first = number(value)
            if (sign != Sign.bp || second == null) return first
            return first + "/" + number(second)
        }

        companion object {
            fun number(value: Double): String {
                if (value.isFinite() && value % 1.0 == 0.0) return value.toLong().toString()
                return String.format(Locale.ROOT, "%.1f", value)
            }
        }
    }

    data class Diagnosis(val name: String = "", /** Other names that count as the same answer when typed. */ val accepted: List<String> = emptyList(), val rawJson: String = "{}")

    /** The decision after the diagnosis: one best next step. */
    data class NextStep(val options: List<String> = emptyList(), val key: Int = 0, val why: String = "", val rawJson: String = "{}")

    /** Where the case's teaching comes from in the student's material. */
    data class Source(val lecture: String = "", val pages: String = "", val rawJson: String = "{}") {
        /** "Renal lecture, pp. 12-14" */
        val cited: String get() {
            val pages = this.pages.trimSpaces()
            val where = if (pages.isEmpty()) "" else (if (pages.contains("-") || pages.contains(",") || pages.contains("–")) "pp. " else "p. ") + pages
            return listOf(lecture.trimSpaces(), where).filter { it.isNotEmpty() }.joinToString(", ")
        }
    }

    /** What the verification layer made of the case. */
    @Suppress("EnumEntryName")
    enum class Verification(val rawValue: String) {
        /** Not looked at yet (a case made before checks ran). */
        unchecked("unchecked"),
        /** Through the structure checks and the on-device rules. */
        passed("passed"),
        /** A red flag in the medicine: kept, never shown, until cleared. */
        held("held");

        companion object { fun from(raw: String): Verification = entries.firstOrNull { it.rawValue == raw } ?: unchecked }
    }

    // MARK: what the verification layer reads

    /**
     * What the case asserts as true, for the accuracy engine: the complaint,
     * every finding and result, the diagnosis, the next step and why, and the
     * teaching points. The other options are wrong on purpose, so they are
     * left out, as a question's distractors are.
     */
    val assertedText: String get() {
        val lines = mutableListOf<String>()
        lines += "Patient: " + listOf(patient.spoken, patient.about).filter { it.isNotEmpty() }.joinToString(", ") + "."
        lines += "Complaint: “" + complaint + "”"
        for (part in clerking.parts) lines += part.label + ": " + part.text
        if (arrival.isNotEmpty()) {
            lines += "Arrival observations: " + arrival.joinToString("; ") { "${it.sign.spoken} ${it.shown} ${it.sign.unit}" } + "."
        }
        for (step in steps) {
            var line = step.group.label + " – " + step.label + ": " + step.finding
            if (step.results.isNotEmpty()) line += " (" + step.results.joinToString("; ") { it.said } + ")"
            lines += line
        }
        lines += "Diagnosis: " + diagnosis.name
        if (nextStep.key in nextStep.options.indices) {
            lines += "Next step: " + nextStep.options[nextStep.key] + ". " + nextStep.why
        }
        for (point in teaching) lines += "Teaching: $point"
        return lines.joinToString("\n").trim()
    }
}

/** One thing the student can do: examine or test. (The history is not a step: it is in the clerking note.) */
data class CaseStep(
    val id: String,
    val group: Group,
    val label: String,
    val finding: String,
    val minutes: Int = 2,
    val value: Yield = Yield.useful,
    val redFlag: Boolean = false,
    val mustNotMiss: Boolean = false,
    val results: List<LabResult> = emptyList(),
    /** Why it matters here, or why it adds little: said in the debrief. */
    val note: String = "",
    val rawJson: String = "{}",
) {
    @Suppress("EnumEntryName")
    enum class Group(val rawValue: String, val label: String) {
        examine("examine", "Examine"), test("test", "Test");

        companion object {
            /**
             * A group written loosely by a model: "exam", "investigation". Null
             * for a history question, which a case never has: a writer's step
             * that asks the patient something is dropped (CaseWriting).
             */
            fun read(text: String): Group? {
                val t = text.lowercase().trimSpaces()
                entries.firstOrNull { it.rawValue == t }?.let { return it }
                if (t.startsWith("hist") || t.startsWith("ask") || t.startsWith("q") || t.contains("interview")) return null
                if (t.startsWith("exam") || t.contains("inspect") || t.contains("palp") || t.contains("auscult")) return examine
                return test
            }
        }
    }

    /** How much the step is worth here. */
    @Suppress("EnumEntryName")
    enum class Yield(val rawValue: String) {
        /** One of the findings the case turns on. */
        key("key"),
        /** Worth doing, not decisive. */
        useful("useful"),
        /** Adds little in this patient. */
        low("low");

        companion object {
            fun read(text: String): Yield {
                val t = text.lowercase()
                entries.firstOrNull { it.rawValue == t }?.let { return it }
                if (t.contains("key") || t.contains("high") || t.contains("critical")) return key
                if (t.contains("low") || t.contains("little") || t.contains("none")) return low
                return useful
            }
        }
    }

    /** A test value, shown in the results table. */
    data class LabResult(
        val name: String,
        val value: Double,
        val unit: String = "",
        /** The reference range the writer gave, for tests the accuracy engine's table does not hold (troponin, CRP). Null when not given. */
        val low: Double? = null,
        val high: Double? = null,
        val rawJson: String = "{}",
    ) {
        /** "Potassium 6.8 mmol/L" */
        val said: String get() = listOf(name, CaseFile.Obs.number(value), unit).filter { it.isNotEmpty() }.joinToString(" ")
    }
}

/** A working diagnosis worth weighing, with the steps that argue for and against it. */
data class Differential(
    val name: String,
    val accepted: List<String> = emptyList(),
    val supportedBy: List<String> = emptyList(),
    val againstBy: List<String> = emptyList(),
    val rawJson: String = "{}",
)
