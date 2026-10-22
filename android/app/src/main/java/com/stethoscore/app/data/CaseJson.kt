package com.stethoscore.app.data

import org.json.JSONObject

/**
 * A case file as a library stores it, read tolerantly as iOS's CaseFile
 * decoder reads it: a missing or unreadable field takes its default, a loose
 * setting, group or yield is read as the nearest ("A&E", "exam", "KEY"), and
 * the original object is kept so fields from another version survive export.
 * Written in iOS's shape: enums as their raw values, a step's results and note
 * and a case's heldBecause left out when empty.
 */
object CaseJson {
    private fun JSONObject.str(key: String, fallback: String = ""): String = (opt(key) as? String) ?: fallback
    private fun JSONObject.int(key: String, fallback: Int): Int = (opt(key) as? Number)?.let { n ->
        val d = n.toDouble(); if (d % 1.0 == 0.0) d.toInt() else null
    } ?: fallback
    private fun JSONObject.dbl(key: String): Double? = (opt(key) as? Number)?.toDouble()?.takeIf { it.isFinite() }
    private fun JSONObject.list(key: String): List<String> = optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.opt(it) as? String } } ?: emptyList()

    fun read(o: JSONObject): CaseFile {
        val p = o.optJSONObject("patient") ?: JSONObject()
        val c = o.optJSONObject("clerking") ?: JSONObject()
        val d = o.optJSONObject("diagnosis") ?: JSONObject()
        val n = o.optJSONObject("nextStep") ?: JSONObject()
        val s = o.optJSONObject("source") ?: JSONObject()
        return CaseFile(
            id = o.str("id").ifEmpty { newId() },
            title = o.str("title"),
            specialty = o.str("specialty"),
            setting = CaseFile.Setting.read(o.str("setting", "ward")),
            patient = CaseFile.Patient(p.str("name"), p.int("age", 0), p.str("sex"), p.str("about"), p.toString()),
            complaint = o.str("complaint"),
            clerking = CaseFile.Clerking(c.str("presenting"), c.str("history"), c.str("past"), c.str("drugs"), c.str("social"), c.toString()),
            arrival = o.objects("arrival") { obs(it) }.filterNotNull(),
            budgetMinutes = o.int("budgetMinutes", 20),
            steps = o.objects("steps", ::step),
            diagnosis = CaseFile.Diagnosis(d.str("name"), d.list("accepted"), d.toString()),
            differentials = o.objects("differentials") { Differential(it.str("name"), it.list("accepted"), it.list("supportedBy"), it.list("againstBy"), it.toString()) },
            distractors = o.list("distractors"),
            turningStep = o.str("turningStep"),
            nextStep = CaseFile.NextStep(n.list("options"), n.int("key", 0), n.str("why"), n.toString()),
            teaching = o.list("teaching"),
            source = CaseFile.Source(s.str("lecture"), s.str("pages"), s.toString()),
            verification = CaseFile.Verification.from(o.str("verification")),
            heldBecause = o.list("heldBecause"),
            rawJson = o.toString(),
        )
    }

    private fun obs(o: JSONObject): CaseFile.Obs? {
        val sign = CaseFile.Obs.Sign.from(o.str("sign")) ?: return null
        val value = o.dbl("value") ?: return null
        return CaseFile.Obs(sign, value, o.dbl("second"), o.toString())
    }

    private fun step(o: JSONObject): CaseStep = CaseStep(
        id = o.str("id").ifEmpty { newId() },
        group = CaseStep.Group.read(o.str("group")) ?: CaseStep.Group.examine,
        label = o.str("label"),
        finding = o.str("finding"),
        minutes = o.int("minutes", 2),
        value = CaseStep.Yield.read(o.str("value")),
        redFlag = (o.opt("redFlag") as? Boolean) ?: false,
        mustNotMiss = (o.opt("mustNotMiss") as? Boolean) ?: false,
        results = o.objects("results") { r ->
            val value = r.dbl("value")
            if (value == null) null else CaseStep.LabResult(r.str("name"), value, r.str("unit"), r.dbl("low"), r.dbl("high"), r.toString())
        }.filterNotNull(),
        note = o.str("note"),
        rawJson = o.toString(),
    )

    fun write(c: CaseFile): JSONObject = raw(c.rawJson)
        .put("id", c.id).put("title", c.title).put("specialty", c.specialty).put("setting", c.setting.rawValue)
        .put("patient", raw(c.patient.rawJson).put("name", c.patient.name).put("age", c.patient.age).put("sex", c.patient.sex).put("about", c.patient.about))
        .put("complaint", c.complaint)
        .put("clerking", raw(c.clerking.rawJson).put("presenting", c.clerking.presenting).put("history", c.clerking.history).put("past", c.clerking.past).put("drugs", c.clerking.drugs).put("social", c.clerking.social))
        .put("arrival", jsonArray(c.arrival.map { o -> raw(o.rawJson).put("sign", o.sign.rawValue).put("value", o.value).also { j -> if (o.second != null) j.put("second", o.second) else j.remove("second") } }))
        .put("budgetMinutes", c.budgetMinutes)
        .put("steps", jsonArray(c.steps.map(::writeStep)))
        .put("diagnosis", raw(c.diagnosis.rawJson).put("name", c.diagnosis.name).put("accepted", jsonArray(c.diagnosis.accepted)))
        .put("differentials", jsonArray(c.differentials.map { raw(it.rawJson).put("name", it.name).put("accepted", jsonArray(it.accepted)).put("supportedBy", jsonArray(it.supportedBy)).put("againstBy", jsonArray(it.againstBy)) }))
        .put("distractors", jsonArray(c.distractors))
        .put("turningStep", c.turningStep)
        .put("nextStep", raw(c.nextStep.rawJson).put("options", jsonArray(c.nextStep.options)).put("key", c.nextStep.key).put("why", c.nextStep.why))
        .put("teaching", jsonArray(c.teaching))
        .put("source", raw(c.source.rawJson).put("lecture", c.source.lecture).put("pages", c.source.pages))
        .put("verification", c.verification.rawValue)
        .also { if (c.heldBecause.isNotEmpty()) it.put("heldBecause", jsonArray(c.heldBecause)) else it.remove("heldBecause") }

    private fun writeStep(s: CaseStep): JSONObject = raw(s.rawJson)
        .put("id", s.id).put("group", s.group.rawValue).put("label", s.label).put("finding", s.finding)
        .put("minutes", s.minutes).put("value", s.value.rawValue).put("redFlag", s.redFlag).put("mustNotMiss", s.mustNotMiss)
        .also { j ->
            if (s.results.isNotEmpty()) j.put("results", jsonArray(s.results.map { r ->
                raw(r.rawJson).put("name", r.name).put("value", r.value).put("unit", r.unit)
                    .also { o -> if (r.low != null) o.put("low", r.low) else o.remove("low"); if (r.high != null) o.put("high", r.high) else o.remove("high") }
            })) else j.remove("results")
            if (s.note.isNotEmpty()) j.put("note", s.note) else j.remove("note")
        }
}
