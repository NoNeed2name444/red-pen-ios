package com.stethoscore.app.data

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

// Writing cases from the student's own material: the instructions every
// writer is given, and reading a writer's JSON back into case files. Port of
// iOS Shared/Cases/CaseWriting.swift.
//
// The instructions ask for what the case file holds and the checks demand
// (CaseChecks): the history written out as a clerking note (the patient is
// never questioned), examination and test steps with their minutes, a few key
// findings (key-features, Page & Bordage 1995), the red flags and the one or
// two that must not be missed, differentials each with the steps for and
// against them (illness scripts, Schmidt & Rikers 2007), the turning step, a
// next step as a single best answer, and three teaching points tied to the lecture.

object CaseWriting {

    /** What to steer one case towards, beyond the lecture. */
    data class Brief(
        /** The diagnosis the case must have ("Another patient like this"). */
        val diagnosis: String? = null,
        /** An earlier presentation to stay away from. */
        val unlike: String? = null,
        /** Where to set it, turned over case by case so a set is not all one ward. */
        val setting: CaseFile.Setting? = null,
        /** Diagnoses already written in this run, not to be repeated. */
        val avoid: List<String> = emptyList(),
    )

    /** Characters of lecture in one on-device prompt: the instructions and a whole case written back share a 4,096-token window. */
    const val onDeviceSourceChars = 2_400

    /** Cases per call: one. A case is long, and a writer asked for several at once thins every one of them. */
    const val perCall = 1

    const val maxCases = 50

    /** The setting for the n-th case of a set: emergency first, then the rest in turn. */
    fun setting(index: Int): CaseFile.Setting {
        val order = listOf(CaseFile.Setting.emergency, CaseFile.Setting.ward, CaseFile.Setting.clinic, CaseFile.Setting.community)
        return order[index % order.size]
    }

    /** The instructions. `json` adds the exact shape to answer in, for the writers with no schema of their own. */
    fun instructions(source: String, subject: String, brief: Brief, options: Int = 5, json: Boolean): String {
        val rules = mutableListOf(
            "You write one practice patient for a medical student, built from the student's own lecture (below). The student reads the admission notes, then works the patient up against a clock: they choose what to examine and which tests to order, each costing minutes, keep a ranked list of up to three working diagnoses, then commit to the diagnosis and the single best next step. Afterwards they see what mattered.",
            "",
            "How to build the patient:",
            "1. Stay inside the lecture. The diagnosis, the findings that point to it and the teaching must be supported by it. Use realistic adult values and current practice. Never invent a dose, a value or a recommendation.",
            "2. Give the patient a made-up full name, an age, a sex (F or M) and a few words about their life. Choose where they are seen: emergency, ward, clinic or community.",
            "3. Write the complaint as the patient would say it, in everyday words, in the first person - no medical terms.",
            "4. Write the history already taken, as a doctor's clerking note: presenting complaint, history of the presenting complaint, past medical history, drugs and allergies, social history. Clinical shorthand is fine. The student reads it; there are no questions to the patient anywhere in the case.",
            "5. Give arrival observations that fit the story: heart rate, systolic and diastolic blood pressure, breathing rate, oxygen saturation and temperature in degrees Celsius.",
            "6. Write 10 to 14 steps (never under 8 or over 20) in two groups only: examine and test - never a question to the patient. Use both groups. Each step has a short label naming the action (\"Feel the abdomen\", \"Listen to the heart\", \"Serum sodium\"), the finding it reveals as a doctor would note it, and its cost in minutes: 2-4 for an examination, 5-10 for a bedside test, 15-60 for a laboratory test or imaging. Keep the deciding findings for the steps: the clerking note should leave the diagnosis open.",
            "7. Mark each step's value: key for the 2 to 5 findings the diagnosis turns on, useful for findings that help, low for actions that add little in this patient. In the note say why the step matters here - or, for a low one, why it adds little here.",
            "8. Mark redFlag on findings that signal danger, and mustNotMiss on the one or two whose omission could kill the patient.",
            "9. Put test values in results as numbers with their units, and give the reference range (low and high) for tests outside routine chemistry.",
            "10. List 3 to 5 differentials, most likely first, the diagnosis among them. For each, the ids of the steps that support it and of those that argue against it; every differential needs at least one supporting step. Add 2 or 3 distractors: plausible diagnoses that are wrong here.",
            "11. turningStep is the id of the key step after which the diagnosis should clearly lead.",
            "12. budget is the minutes allowed: enough for the key steps plus about a third.",
            "13. The next step is a single-best-answer question with exactly $options options of similar length and style, the correct one at answer (counting from 0), and why it is correct.",
            "14. Give three teaching points, one sentence each, and the lecture pages they come from if the lecture shows page numbers.",
        )
        val topic = subject.trimSpaces()
        if (topic.isNotEmpty() && topic != "General") rules += "The subject is $topic."
        brief.setting?.let { rules += "See this patient in: ${it.rawValue}." }
        brief.diagnosis?.takeIf { it.isNotEmpty() }?.let { rules += "The diagnosis must be $it." }
        brief.unlike?.takeIf { it.isNotEmpty() }?.let {
            rules += "Present it differently from this earlier patient, with a different age, setting and leading complaint: $it"
        }
        if (brief.avoid.isNotEmpty()) rules += "Already written, do not repeat these diagnoses: " + brief.avoid.joinToString("; ") + "."
        if (json) {
            rules += ""
            rules += "Answer with JSON only, in exactly this shape:"
            rules += shape
        }
        rules += ""
        rules += "LECTURE:"
        rules += source
        return rules.joinToString("\n")
    }

    /** The JSON the writers without a schema answer in. */
    const val shape: String = """{"cases":[{"title":"short title","specialty":"...","setting":"emergency","patient":{"name":"...","age":58,"sex":"F","about":"..."},"complaint":"...","clerking":{"presenting":"...","history":"...","past":"...","drugs":"...","social":"..."},"vitals":{"hr":96,"sbp":128,"dbp":82,"rr":18,"spo2":97,"temp":37.2},"budget":25,"steps":[{"id":"s1","group":"examine","label":"...","finding":"...","minutes":2,"value":"key","redFlag":false,"mustNotMiss":false,"note":"...","results":[{"name":"Sodium","value":131,"unit":"mmol/L"}]}],"diagnosis":{"name":"...","accepted":["..."]},"differentials":[{"name":"...","accepted":["..."],"for":["s1"],"against":["s4"]}],"distractors":["..."],"turningStep":"s3","nextStep":{"options":["...","...","...","...","..."],"answer":0,"why":"..."},"teaching":["...","...","..."],"pages":"12-14"}]}"""

    /** The user turn that requests it. */
    const val request = "Write the patient now."
    const val requestJSON = "Write the patient now, as JSON only."

    // MARK: reading a writer's answer

    /** Every case in a reply: a "cases" list, or one case on its own. A malformed case costs only itself. */
    fun parse(raw: String, lecture: String = ""): List<CaseFile> {
        val obj = jsonObject(raw) ?: return emptyList()
        val list = objects(obj.opt("cases"))
        val items = when {
            list != null -> list
            obj.has("steps") -> listOf(obj)
            else -> emptyList()
        }
        return items.mapNotNull { read(it, lecture) }
    }

    /** The cases across a cloud job's replies, at most `count`. */
    fun collect(replies: List<String>, count: Int, lecture: String = ""): List<CaseFile> =
        replies.flatMap { parse(it, lecture) }.take(count)

    /** The outermost JSON object in a reply, with any reasoning block, code fence or sentence around it left out. */
    fun jsonObject(raw: String): JSONObject? {
        var text = raw
        while (true) {
            val open = text.indexOf("<think>")
            if (open < 0) break
            val close = text.indexOf("</think>", open + "<think>".length)
            if (close < 0) break
            text = text.removeRange(open, close + "</think>".length)
        }
        val first = text.indexOf('{')
        val last = text.lastIndexOf('}')
        if (first < 0 || last < 0 || first >= last) return null
        return runCatching { JSONTokener(text.substring(first, last + 1)).nextValue() as? JSONObject }.getOrNull()
    }

    /** A JSON array of objects, as Swift's `as? [[String: Any]]`: null when it is not one. */
    private fun objects(any: Any?): List<JSONObject>? {
        val a = any as? JSONArray ?: return null
        val out = (0 until a.length()).map { a.opt(it) }
        if (out.any { it !is JSONObject }) return null
        return out.map { it as JSONObject }
    }

    private fun JSONObject.at(key: String): Any? = if (has(key)) opt(key) else null

    /** One case from its JSON; null when it has no complaint or no steps. */
    fun read(o: JSONObject, lecture: String): CaseFile? {
        val title = string(o.at("title"))
        val patient = (o.at("patient") as? JSONObject)?.let { p ->
            CaseFile.Patient(name = string(p.at("name")), age = number(p.at("age"))?.toInt() ?: 0, sex = string(p.at("sex")), about = string(p.at("about")))
        } ?: CaseFile.Patient()
        val clerking = (o.at("clerking") as? JSONObject)?.let { k ->
            CaseFile.Clerking(
                presenting = string(k.at("presenting") ?: k.at("pc")),
                history = string(k.at("history") ?: k.at("hpc")),
                past = string(k.at("past") ?: k.at("pmh")),
                drugs = string(k.at("drugs") ?: k.at("medications")),
                social = string(k.at("social") ?: k.at("sh")),
            )
        } ?: CaseFile.Clerking()
        val arrival = (o.at("vitals") as? JSONObject)?.let(::vitals) ?: emptyList()
        val steps = (objects(o.at("steps")) ?: emptyList()).mapIndexedNotNull { i, s -> step(s, i) }
        val diagnosis = (o.at("diagnosis") as? JSONObject)?.let { CaseFile.Diagnosis(string(it.at("name")), strings(it.at("accepted"))) }
            ?: CaseFile.Diagnosis(string(o.at("diagnosis")))
        val differentials = (objects(o.at("differentials")) ?: emptyList()).mapNotNull { d ->
            val name = string(d.at("name"))
            if (name.isEmpty()) null
            else Differential(name, strings(d.at("accepted")), strings(d.at("for") ?: d.at("supportedBy")), strings(d.at("against") ?: d.at("againstBy")))
        }
        val nextStep = (o.at("nextStep") as? JSONObject)?.let { n ->
            val options = strings(n.at("options"))
            CaseFile.NextStep(options, keyIndex(n.at("answer") ?: n.at("key"), options), string(n.at("why")))
        } ?: CaseFile.NextStep()
        val complaint = unquoted(string(o.at("complaint")))
        val file = CaseFile(
            title = title.ifEmpty { diagnosis.name },
            specialty = string(o.at("specialty")),
            setting = CaseFile.Setting.read(string(o.at("setting"))),
            patient = patient,
            complaint = complaint,
            clerking = clerking,
            arrival = arrival,
            budgetMinutes = number(o.at("budget") ?: o.at("budgetMinutes"))?.toInt() ?: 20,
            steps = steps,
            diagnosis = diagnosis,
            differentials = differentials,
            distractors = strings(o.at("distractors")),
            turningStep = string(o.at("turningStep")),
            nextStep = nextStep,
            teaching = strings(o.at("teaching")),
            source = CaseFile.Source(lecture, string(o.at("pages"))),
        )
        if (file.complaint.isEmpty() || file.steps.isEmpty()) return null
        return file
    }

    /** One step; null when it is unreadable or asks the patient something (a history group): a case never questions its patient. */
    fun step(s: JSONObject, index: Int): CaseStep? {
        val label = string(s.at("label"))
        val finding = string(s.at("finding"))
        if (label.isEmpty() || finding.isEmpty()) return null
        val group = CaseStep.Group.read(string(s.at("group"))) ?: return null
        val results = (objects(s.at("results")) ?: emptyList()).mapNotNull { r ->
            val name = string(r.at("name"))
            val value = number(r.at("value"))
            if (name.isEmpty() || value == null) return@mapNotNull null
            val low = number(r.at("low")); val high = number(r.at("high"))
            val ranged = (low ?: 0.0) < (high ?: 0.0)
            CaseStep.LabResult(name, value, string(r.at("unit")), if (ranged) low else null, if (ranged) high else null)
        }
        val id = string(s.at("id"))
        return CaseStep(
            id = id.ifEmpty { "s${index + 1}" }, group = group, label = label, finding = finding,
            minutes = number(s.at("minutes"))?.toInt() ?: 2,
            value = CaseStep.Yield.read(string(s.at("value"))),
            redFlag = flag(s.at("redFlag")), mustNotMiss = flag(s.at("mustNotMiss")),
            results = results, note = string(s.at("note")),
        )
    }

    /** The arrival observations, in the chart's order. */
    fun vitals(v: JSONObject): List<CaseFile.Obs> {
        val out = mutableListOf<CaseFile.Obs>()
        number(v.at("hr"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.hr, it) }
        number(v.at("sbp"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.bp, it, number(v.at("dbp"))) }
        number(v.at("rr"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.rr, it) }
        number(v.at("spo2"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.spo2, it) }
        number(v.at("temp"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.temp, it) }
        number(v.at("gcs"))?.let { out += CaseFile.Obs(CaseFile.Obs.Sign.gcs, it) }
        return out
    }

    // MARK: small readers, tolerant of how a model writes

    fun string(any: Any?): String {
        if (any is String) return any.trim()
        number(any)?.let { return CaseFile.Obs.number(it) }
        return ""
    }

    fun strings(any: Any?): List<String> {
        if (any is JSONArray) return (0 until any.length()).map { string(any.opt(it)) }.filter { it.isNotEmpty() }
        val one = string(any)
        return if (one.isEmpty()) emptyList() else listOf(one)
    }

    fun number(any: Any?): Double? = when (any) {
        is Boolean -> if (any) 1.0 else 0.0
        is Number -> any.toDouble()
        is String -> any.trimSpaces().filter { it in "0123456789.-" }.toDoubleOrNull()
        else -> null
    }

    fun flag(any: Any?): Boolean {
        if (any is Boolean) return any
        number(any)?.let { return it != 0.0 }
        return string(any).lowercase() in setOf("true", "yes", "1")
    }

    /** The answer as an index, written 2, "2", "C" or as the option's words. */
    fun keyIndex(any: Any?, options: List<String>): Int {
        if (any !is String) number(any)?.toInt()?.let { if (it in options.indices) return it }
        val s = string(any)
        s.toIntOrNull()?.let { if (it in options.indices) return it }
        if (s.length == 1) {
            val i = s.uppercase()[0].code - 65
            if (i in options.indices) return i
        }
        return options.indexOfFirst { CaseNames.same(it, s) }.takeIf { it >= 0 } ?: 0
    }

    /** The complaint without the quotation marks a writer may have added; the screen adds its own. */
    fun unquoted(text: String): String = text.trim { it.isWhitespace() || it in "\"'“”‘’" }
}
