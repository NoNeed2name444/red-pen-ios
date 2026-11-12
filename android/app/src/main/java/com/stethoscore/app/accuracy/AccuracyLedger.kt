package com.stethoscore.app.accuracy

import androidx.compose.runtime.mutableStateMapOf
import com.stethoscore.app.exam.ExamDefaults
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

// Port of iOS Shared/Accuracy/AccuracyLedger.swift: what was found about every
// item, kept by its content hash, and what each finding means. Pure (no
// Android classes, no clock but the `now` a caller may pass), so the whole of
// it is tested on the JVM; AccuracyLedgerFile keeps it on disk, in its own
// file, and AccuracySeen is the process's in-memory view the study screens
// read.
//
// Times are epoch milliseconds (iOS Dates), so every interval below is the
// iOS one in milliseconds.

/**
 * What was found about one item, kept by its content hash: the checker
 * models' votes, the evidence they were shown, how much of it the lecture
 * contains, and the correction they offered. Never the verdict itself - that
 * is worked out from these whenever it is shown, so new model weights re-score
 * everything without a new check.
 */
data class AccuracyRecord(
    val hash: String,
    val votes: List<AccuracyVote> = emptyList(),
    val evidence: List<AccuracyEvidence> = emptyList(),
    val sourceMatch: Double? = null,
    val fix: AccuracySuggestion? = null,
    val checkedAt: Long = System.currentTimeMillis(),
    /** The student reported this item as wrong. */
    val reported: Boolean = false,
    /**
     * The server's claim gate (server/claims.js): what the item says that
     * contradicts its own lecture - "negation", "dose", "frequency",
     * "percentage", "direction" (a sentence turned around: higher for lower,
     * rare for common) - or "gate_failed" when the gate could not tell. Any of
     * them and the item is never Verified, whatever the votes say. Null when
     * the gate found nothing (or the check predates it).
     */
    val claimHolds: List<String>? = null,
    /** The server's source proof (server/proof.js): which of the item's claims an official source states word for word. Null before the check had one. */
    val proof: AccuracyProof? = null,
    /** How many checks in a row came back with the proof cut short: asked again a few times, then left at Check this. */
    val proofTries: Int? = null,
    /**
     * The server's vignette proof check (server/vignette-proof.js), sent only
     * while its vignette route is on; null otherwise, and cleared when a reply
     * comes back without one.
     */
    val vignette: AccuracyVignette? = null,
) {
    fun toJson(): JSONObject = JSONObject().put("hash", hash)
        .put("votes", JSONArray().also { a -> votes.forEach { a.put(it.toJson()) } })
        .put("evidence", JSONArray().also { a -> evidence.forEach { a.put(it.toJson()) } })
        .put("checkedAt", checkedAt).put("reported", reported).also { o ->
            sourceMatch?.let { o.put("sourceMatch", it) }
            fix?.let { o.put("fix", it.toJson()) }
            claimHolds?.let { o.put("claimHolds", AccuracyJson.array(it)) }
            proof?.let { o.put("proof", it.toJson()) }
            proofTries?.let { o.put("proofTries", it) }
            vignette?.let { o.put("vignette", it.toJson()) }
        }

    companion object {
        /** A record saved before a field existed still loads, with the field's default. */
        fun fromJson(o: JSONObject): AccuracyRecord? {
            val hash = AccuracyJson.str(o, "hash") ?: return null
            return AccuracyRecord(
                hash = hash,
                votes = AccuracyJson.objects(o, "votes").orEmpty().mapNotNull { AccuracyVote.fromJson(it) },
                evidence = AccuracyJson.objects(o, "evidence").orEmpty().mapNotNull { AccuracyEvidence.fromJson(it) },
                sourceMatch = AccuracyJson.double(o, "sourceMatch"),
                fix = AccuracySuggestion.fromJson(o.optJSONObject("fix")),
                checkedAt = (o.opt("checkedAt") as? Number)?.toLong() ?: 0L,
                reported = AccuracyJson.bool(o, "reported") ?: false,
                claimHolds = AccuracyJson.strings(o, "claimHolds"),
                proof = o.optJSONObject("proof")?.let { AccuracyProof.fromJson(it) },
                proofTries = AccuracyJson.int(o, "proofTries"),
                vignette = o.optJSONObject("vignette")?.let { AccuracyVignette.fromJson(it) },
            )
        }
    }
}

/**
 * What server/vignette-proof.js found for a clinical vignette: whether its
 * proof was accepted, and at which tier - "proven" (every rule it used signed
 * off by the owner: may back Verified) or "checked" (at most Checked) - or why
 * it was refused.
 */
data class AccuracyVignette(val ok: Boolean? = null, val tier: String? = null, val why: String? = null, val rules: List<String>? = null) {
    val isProven: Boolean get() = ok == true && tier == "proven"
    val isChecked: Boolean get() = ok == true && tier == "checked"

    fun toJson(): JSONObject = JSONObject().also { o ->
        ok?.let { o.put("ok", it) }
        tier?.let { o.put("tier", it) }
        why?.let { o.put("why", it) }
        rules?.let { o.put("rules", AccuracyJson.array(it)) }
    }

    companion object {
        fun fromJson(o: JSONObject): AccuracyVignette = AccuracyVignette(
            AccuracyJson.bool(o, "ok"), AccuracyJson.str(o, "tier"), AccuracyJson.str(o, "why"), AccuracyJson.strings(o, "rules"))
    }
}

/**
 * What server/proof.js found for one item. Only [isFull] lets an item be
 * Verified: every claim stated word for word by an official source.
 */
data class AccuracyProof(
    val v: Int? = null, val claims: Int? = null, val proven: Int? = null, val why: String? = null, val quotes: List<Quote>? = null,
) {
    data class Quote(val claim: String? = null, val quote: String? = null, val source: String? = null, val title: String? = null, val url: String? = null)

    /** proof.js fullyProven */
    val isFull: Boolean get() = v == version && why == null && (claims ?: 0) > 0 && proven == claims

    /** accuracy.js proofDue, for a proof the device holds */
    val due: Boolean get() = v != version || retried.contains(why ?: "")

    fun toJson(): JSONObject = JSONObject().also { o ->
        v?.let { o.put("v", it) }
        claims?.let { o.put("claims", it) }
        proven?.let { o.put("proven", it) }
        why?.let { o.put("why", it) }
        quotes?.let { list ->
            o.put("quotes", JSONArray().also { a ->
                list.forEach { q ->
                    a.put(JSONObject().also { j ->
                        q.claim?.let { j.put("claim", it) }; q.quote?.let { j.put("quote", it) }; q.source?.let { j.put("source", it) }
                        q.title?.let { j.put("title", it) }; q.url?.let { j.put("url", it) }
                    })
                }
            })
        }
    }

    companion object {
        /** server/proof.js PROOF_VERSION */
        const val version: Int = 2

        /** Proofs cut short rather than failed: proven again on a later check. */
        val retried: Set<String> = setOf("budget", "timeout", "lookup", "error")

        fun fromJson(o: JSONObject): AccuracyProof = AccuracyProof(
            AccuracyJson.int(o, "v"), AccuracyJson.int(o, "claims"), AccuracyJson.int(o, "proven"), AccuracyJson.str(o, "why"),
            AccuracyJson.objects(o, "quotes")?.map { q ->
                Quote(AccuracyJson.str(q, "claim"), AccuracyJson.str(q, "quote"), AccuracyJson.str(q, "source"),
                    AccuracyJson.str(q, "title"), AccuracyJson.str(q, "url"))
            },
        )
    }
}

/**
 * What the server's /accuracy/check answers, as much of it as the device
 * keeps: per item, in the order sent, the votes, evidence, correction and
 * features, and the claim gate's hard findings. Everything is optional, so an
 * older or newer server's reply still decodes.
 */
data class AccuracyCheckReply(
    val items: List<Item>? = null,
    val limit: String? = null,
    val message: String? = null,
    /** true when no checker answered: nothing was checked (the server gave the allowance back) and the app should wait before the next batch */
    val busy: Boolean? = null,
) {
    data class Finding(val code: String? = null)
    data class Claims(val hard: List<Finding>? = null, val partial: Boolean? = null)
    data class Item(
        val id: String? = null,
        val votes: List<AccuracyVote>? = null,
        val evidence: List<AccuracyEvidence>? = null,
        val fix: AccuracySuggestion? = null,
        val features: Map<String, Double>? = null,
        val reason: String? = null,
        val claims: Claims? = null,
        val proof: AccuracyProof? = null,
        val vignette: AccuracyVignette? = null,
    )

    companion object {
        /** The gate's code for "it failed on this item": held at Check this, and the item is asked about again later (its votes come from the cache). */
        const val gateFailed: String = "gate_failed"

        /** The reply as Swift's JSONDecoder reads it; null when it is not an object or a vote has no integer risk. */
        fun parse(json: JSONObject?): AccuracyCheckReply? {
            if (json == null) return null
            var unreadable = false
            val items = (json.opt("items") as? JSONArray)?.let { array ->
                // items are read by position, so one that is not an object makes the reply unreadable
                (0 until array.length()).map { i ->
                    val o = array.opt(i) as? JSONObject
                    if (o == null) { unreadable = true; return@map Item() }
                    val votes = AccuracyJson.objects(o, "votes")?.let { list ->
                        list.mapNotNull { v -> AccuracyVote.fromJson(v).also { if (it == null) unreadable = true } }
                    }
                    val features = o.optJSONObject("features")?.let { f ->
                        f.keys().asSequence().mapNotNull { k -> AccuracyJson.double(f, k)?.let { k to it } }.toMap()
                    }
                    val claims = o.optJSONObject("claims")?.let { c ->
                        Claims(AccuracyJson.objects(c, "hard")?.map { Finding(AccuracyJson.str(it, "code")) }, AccuracyJson.bool(c, "partial"))
                    }
                    Item(
                        id = AccuracyJson.str(o, "id"), votes = votes,
                        evidence = AccuracyJson.objects(o, "evidence")?.mapNotNull { AccuracyEvidence.fromJson(it) },
                        fix = AccuracySuggestion.fromJson(o.optJSONObject("fix")), features = features,
                        reason = AccuracyJson.str(o, "reason"), claims = claims,
                        proof = o.optJSONObject("proof")?.let { AccuracyProof.fromJson(it) },
                        vignette = o.optJSONObject("vignette")?.let { AccuracyVignette.fromJson(it) },
                    )
                }
            }
            if (unreadable) return null
            return AccuracyCheckReply(items, AccuracyJson.str(json, "limit"), AccuracyJson.str(json, "message"), AccuracyJson.bool(json, "busy"))
        }
    }
}

/** One item's standing, ready to show. */
data class AccuracyAssessment(
    val grade: AccuracyGrade,
    val probability: Double,
    val rules: List<AccuracyRules.Hit>,
    val record: AccuracyRecord?,
    val features: Map<String, Double> = emptyMap(),
    /** It gives a dose, names a diagnosis or recommends a treatment. */
    val oath: Boolean = false,
) {
    /**
     * Which rules, which of the claim gate's findings and which models raised a
     * concern, and what no official source states yet, in words.
     */
    val reasons: List<String> get() {
        val out = mutableListOf<String>()
        rules.forEach { out += it.detail }
        for (code in record?.claimHolds.orEmpty()) out += holdReason(code)
        for (v in record?.votes.orEmpty()) if (v.risk >= 3) {
            val issue = v.issues.firstOrNull() ?: "Judged it likely to mislead (risk ${v.risk} of 4)."
            out += v.model + ": " + issue
        }
        val meaning = grade.meaning
        if (grade == AccuracyGrade.checked && meaning != null) {
            out += meaning
        } else if (record != null && record.votes.isNotEmpty() && grade != AccuracyGrade.verified) {
            out += proofReasons(record.proof, oath)
        }
        return out
    }

    companion object {
        /** server/accuracy-model.js reasonsFor and describe, word for word. */
        fun proofReasons(proof: AccuracyProof?, oath: Boolean): List<String> {
            val out = mutableListOf<String>()
            // its key stated word for word, and another option a source may state too
            val other = proof?.why == "distractor" || proof?.why == "options"
            if (proof?.isFull != true && !other) {
                out += if (oath) "A dose, diagnosis or treatment no official source states word for word yet."
                else "No official source states it word for word yet."
            }
            when (proof?.why) {
                "lookup", "timeout", "error" -> out += "An official source could not be read this time; it will be checked again."
                "budget" -> out += "Its official sources were too long to read in this batch; it will be checked again on its own."
                "distractor" -> out += "An official source may also state another of its options."
                "options" -> out += "One of its other options could not be read for certain."
            }
            return out
        }

        fun holdReason(code: String): String = when (code) {
            "negation" -> "Says the opposite of its own lecture."
            "dose" -> "Gives a different dose from its own lecture."
            "frequency" -> "Gives a different dosing frequency from its own lecture."
            "percentage" -> "Gives a different percentage from its own lecture."
            "direction" -> "Says the other way from its own lecture."
            AccuracyCheckReply.gateFailed -> "Couldn't be compared with its lecture yet; it will be checked again."
            // the server's provenance holds (server/provenance.js): where its
            // source came from and whether that chain can be trusted
            "retracted" -> "A source it rests on was retracted or is under an expression of concern."
            "conflict" -> "Only its sponsor's own source says this in its favour; it needs an independent source."
            "dabt" -> "It doesn't copy its source faithfully: a number, unit, frequency, population or \"not\" differs, or a dose is written unsafely."
            "shadh" -> "A stronger source was read against it."
            "tafarrud" -> "Only one source supports it, and that source isn't strong enough on its own."
            "naskh" -> "A published rule its proof rests on has been replaced by a newer one."
            else -> "Differs from its own lecture."
        }
    }
}

/**
 * Counts of each grade in a set. [checked] counts every item the models have
 * looked at; [passed] counts the Checked grade alone.
 */
data class AccuracySummary(
    var verified: Int = 0, var passed: Int = 0, var check: Int = 0, var flagged: Int = 0, var unchecked: Int = 0,
) {
    val total: Int get() = verified + passed + check + flagged + unchecked
    val checked: Int get() = verified + passed + check + flagged

    fun add(grade: AccuracyGrade) {
        when (grade) {
            AccuracyGrade.verified -> verified += 1
            AccuracyGrade.checked -> passed += 1
            AccuracyGrade.check -> check += 1
            AccuracyGrade.flagged -> flagged += 1
            AccuracyGrade.unchecked -> unchecked += 1
        }
    }

    /** "12 verified · 2 to check · 1 flagged", or null before anything is checked. */
    val line: String? get() {
        if (!(checked > 0 || flagged > 0)) return null
        val parts = mutableListOf<String>()
        if (verified > 0) parts += "$verified verified"
        if (passed > 0) parts += "$passed checked, not fully proven"
        if (check > 0) parts += "$check to check"
        if (flagged > 0) parts += "$flagged flagged"
        if (unchecked > 0) parts += "$unchecked not yet checked"
        return parts.joinToString(" · ")
    }

    /** The badge for the whole set: flagged if anything is, verified only when everything is, checked when everything is at least that. */
    val grade: AccuracyGrade get() = when {
        flagged > 0 -> AccuracyGrade.flagged
        check > 0 -> AccuracyGrade.check
        passed > 0 && unchecked == 0 -> AccuracyGrade.checked
        verified > 0 && unchecked == 0 -> AccuracyGrade.verified
        else -> AccuracyGrade.unchecked
    }
}

/**
 * Every record on this device, and what each means. Pure, so the whole of it
 * is tested on the JVM; [AccuracyLedgerFile] keeps it on disk. Not thread
 * safe: the one store that owns a ledger serialises its use.
 */
class AccuracyLedger(
    val records: MutableMap<String, AccuracyRecord> = LinkedHashMap(),
    /** Items whose check came back with no vote, and when: tried again after a while rather than on every pass. */
    val failed: MutableMap<String, Long> = LinkedHashMap(),
) {

    /** This item's standing from what this ledger holds about it. */
    fun assess(item: AccuracyItem, weights: AccuracyWeights = AccuracyModel.bundled, defaults: ExamDefaults? = null): AccuracyAssessment =
        assess(item, records[item.contentHash], weights, defaults)

    fun summary(items: List<AccuracyItem>, weights: AccuracyWeights = AccuracyModel.bundled, defaults: ExamDefaults? = null): AccuracySummary {
        val s = AccuracySummary()
        for (item in items) s.add(assess(item, weights, defaults).grade)
        return s
    }

    /**
     * Checked already: a model voted on exactly this content, and the claim
     * gate did not fail on it (an item it failed on is asked about again). A
     * question checked before it was solved blind (1 Oct) is asked about again:
     * votes that saw the key cannot verify it now. So is a check that reached
     * fewer than three model families (the free models had run out), once a
     * day has passed. server/accuracy.js staleSignals. And so is one whose
     * source proof was cut short or predates it, after a few hours and up to
     * [proofTries] times: the server proves it again from its cache, without
     * new votes.
     */
    fun isChecked(hash: String, question: Boolean = false, now: Long = System.currentTimeMillis()): Boolean {
        val record = records[hash] ?: return false
        if (record.votes.isEmpty()) return false
        if ((record.proof?.due ?: true) && (record.proofTries ?: 0) < proofTries && now - record.checkedAt > proofRetry) return false
        if (question && record.votes.count { it.blind == true } < 2) return false
        val counted = record.votes.filter { !question || it.blind == true }
        val families = counted.map { AccuracyModel.familyOf(it.model) }.toSet().size
        if (families < AccuracyModel.minVerifyVoters && now - record.checkedAt > DAY) return false
        return !(record.claimHolds ?: emptyList()).contains(AccuracyCheckReply.gateFailed)
    }

    /** Worth trying again: never failed, or failed more than [after] ago. */
    fun mayRetry(hash: String, now: Long = System.currentTimeMillis(), after: Long = 6 * HOUR): Boolean {
        val failedAt = failed[hash] ?: return true
        return now - failedAt > after
    }

    /**
     * A vote from a check made elsewhere - the server's batch check - added to
     * the item's record.
     * [holds]: the claim gate's hard findings from that check, which replace
     * any earlier ones (the server works them out afresh for every reply); null
     * from a check that has no gate, leaving them as they were.
     * [proof]: that check's source proof, which replaces any earlier one; one
     * cut short counts a try (see [isChecked]).
     */
    fun add(
        votes: List<AccuracyVote>, hash: String, evidence: List<AccuracyEvidence> = emptyList(), sourceMatch: Double? = null,
        fix: AccuracySuggestion? = null, holds: List<String>? = null, proof: AccuracyProof? = null,
        vignette: AccuracyVignette? = null, now: Long = System.currentTimeMillis(),
    ) {
        var record = records[hash] ?: AccuracyRecord(hash = hash)
        val merged = record.votes.toMutableList()
        for (v in votes) {
            merged.removeAll { it.model == v.model }
            merged.add(v)
        }
        record = record.copy(votes = merged)
        if (evidence.isNotEmpty()) record = record.copy(evidence = evidence)
        if (sourceMatch != null) record = record.copy(sourceMatch = sourceMatch)
        if (fix != null) record = record.copy(fix = fix)
        if (holds != null) record = record.copy(claimHolds = holds.ifEmpty { null })
        if (proof != null) {
            if (proof.due && !(record.proof?.isFull ?: false)) {
                record = record.copy(proof = proof, proofTries = (record.proofTries ?: 0) + 1)
            } else if (!proof.due) {
                record = record.copy(proof = proof, proofTries = null)
            }
        }
        // the vignette route's check comes with every reply while it is on:
        // one without it (the route off, or no packet) clears the last
        record = record.copy(vignette = vignette, checkedAt = now)
        records[hash] = record
        if (votes.isNotEmpty()) failed.remove(hash)
    }

    /**
     * The server's answer to a batch, item by item in the order sent: the votes
     * and the claim gate's findings kept; an item with no vote marked failed
     * (tried again later) unless the day's checks ran out; an item the gate
     * failed on kept, held at Check this, and tried again later too.
     */
    fun record(reply: AccuracyCheckReply?, hashes: List<String>, now: Long = System.currentTimeMillis()) {
        val replied = reply?.items.orEmpty()
        for ((n, hash) in hashes.withIndex()) {
            val got = replied.getOrNull(n)
            val votes = got?.votes
            if (got == null || votes.isNullOrEmpty()) {
                if (reply?.limit != "day") failed[hash] = now
                continue
            }
            val noSource = (got.features?.get("no_source") ?: 1.0) > 0
            val match = if (noSource) null else got.features?.get("source_match")
            val holds = (got.claims?.hard ?: emptyList()).map { it.code ?: AccuracyCheckReply.gateFailed }
            add(votes, hash, got.evidence ?: emptyList(), match, got.fix, holds, got.proof, got.vignette, now)
            // a server without the proof: asked a few times more, not for ever
            if (got.proof == null) records[hash]?.let { kept -> records[hash] = kept.copy(proofTries = (kept.proofTries ?: 0) + 1) }
            if (holds.contains(AccuracyCheckReply.gateFailed)) failed[hash] = now
        }
    }

    fun markReported(hash: String) {
        val record = records[hash] ?: AccuracyRecord(hash = hash)
        records[hash] = record.copy(reported = true)
    }

    /** Only the records some item still has: an edited or deleted item's old record would otherwise stay for ever. */
    fun prune(keeping: Set<String>) {
        records.keys.retainAll(keeping)
        failed.keys.retainAll(keeping)
    }

    fun copy(): AccuracyLedger = AccuracyLedger(LinkedHashMap(records), LinkedHashMap(failed))

    fun toJson(): JSONObject = JSONObject().put("v", 1)
        .put("records", JSONObject().also { o -> records.forEach { (hash, record) -> o.put(hash, record.toJson()) } })
        .put("failed", JSONObject().also { o -> failed.forEach { (hash, at) -> o.put(hash, at) } })

    companion object {
        /** How many times a cut-short source proof is asked for again, and how long after the last check. */
        const val proofTries: Int = 4
        const val HOUR: Long = 3_600_000L
        const val DAY: Long = 24 * HOUR
        const val proofRetry: Long = 6 * HOUR

        /**
         * One item's standing from the record held about it (null: nothing
         * found yet). [defaults] is where the chosen exam's strictness is kept
         * (ExamChoice); null, no exam makes the cut-offs stricter.
         */
        fun assess(item: AccuracyItem, record: AccuracyRecord?, weights: AccuracyWeights = AccuracyModel.bundled, defaults: ExamDefaults? = null): AccuracyAssessment {
            val rules = AccuracyRules.hits(item)
            val key = if (item.kind == AccuracyKind.mcq && item.key in item.options.indices) AccuracyItem.letter(item.key) else null
            val match = record?.sourceMatch ?: AccuracyRules.sourceMatch(item)
            val f = AccuracyModel.featureValues(item.kind, rules, record?.votes.orEmpty(), record?.evidence?.size ?: 0, match, key,
                sourceProof = record?.proof?.isFull == true,
                vignette = record?.vignette?.let { VignetteFlags(proven = it.isProven, checked = it.isChecked) })
            val p = AccuracyModel.probability(f, weights)
            // the chosen exam's management questions need more to be Verified
            var cutoffs = weights
            val strict = AccuracyModel.examStrictness(item, defaults)
            if (strict > 0) cutoffs = cutoffs.copy(thresholds = AccuracyModel.stricter(weights.thresholds, strict))
            // the oath check: a dose, a diagnosis or a treatment needs evidence behind it
            val oath = AccuracyModel.isOath(item.checkedText)
            // the vignette route is on when the server's reply carried its check
            var grade = AccuracyModel.grade(p, f, cutoffs, oath, vignetteRoute = record?.vignette != null)
            val passed = grade == AccuracyGrade.verified || grade == AccuracyGrade.checked
            // the student said it is wrong: never shown as Verified (or Checked) to them again
            if (record?.reported == true && passed) grade = AccuracyGrade.check
            // it contradicts its own lecture (or the claim gate could not tell),
            // or a provenance hold: never Verified or Checked on the votes alone
            if (!(record?.claimHolds ?: emptyList()).isEmpty() && passed) grade = AccuracyGrade.check
            return AccuracyAssessment(grade, p, rules, record, f, oath)
        }

        /** A ledger as [toJson] wrote it. A record that cannot be read is left out; everything else loads. */
        fun fromJson(o: JSONObject): AccuracyLedger {
            val ledger = AccuracyLedger()
            o.optJSONObject("records")?.let { all ->
                for (key in all.keys()) all.optJSONObject(key)?.let { AccuracyRecord.fromJson(it) }?.let { ledger.records[key] = it }
            }
            o.optJSONObject("failed")?.let { all ->
                for (key in all.keys()) (all.opt(key) as? Number)?.let { ledger.failed[key] = it.toLong() }
            }
            return ledger
        }
    }
}

/**
 * The ledger's own file (iOS accuracy-ledger.json): under the app's filesDir,
 * not in the study store, written whole through a temporary file so a crash
 * leaves the old one. A missing or unreadable file is an empty ledger.
 */
class AccuracyLedgerFile(val file: File) {

    fun load(): AccuracyLedger = runCatching { AccuracyLedger.fromJson(JSONObject(file.readText(Charsets.UTF_8))) }.getOrDefault(AccuracyLedger())

    /** Whether it was written. */
    @Synchronized fun save(ledger: AccuracyLedger): Boolean = runCatching {
        file.parentFile?.mkdirs()
        val temporary = File(file.parentFile, file.name + ".tmp")
        temporary.writeText(ledger.toJson().toString(), Charsets.UTF_8)
        try {
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        true
    }.getOrDefault(false)

    companion object {
        const val NAME = "accuracy-ledger.json"

        /** The ledger's file in the app's private files directory (Context.filesDir). */
        fun inDirectory(filesDir: File): AccuracyLedgerFile = AccuracyLedgerFile(File(filesDir, NAME))
    }
}

/**
 * What the checks said while the app runs, by the item's content hash (iOS
 * AccuracyStore's ledger, not kept on disk): the view Check accuracy's sheet
 * reads and writes.
 */
internal object AccuracySeen {
    val records = mutableStateMapOf<String, AccuracyRecord>()
}
