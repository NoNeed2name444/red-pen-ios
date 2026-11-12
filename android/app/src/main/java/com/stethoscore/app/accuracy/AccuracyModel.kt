package com.stethoscore.app.accuracy

import com.stethoscore.app.exam.ExamDefaults
import org.json.JSONArray
import org.json.JSONObject
import java.util.regex.Pattern
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min

// Port of iOS Shared/Accuracy/AccuracyModel.swift (the grades, the votes, the
// weights and the model itself) and of AccuracyFix's pure checks from
// Shared/Accuracy/AccuracySchedule.swift (canApply, keyIndex, lines).
//
// Swift's Codable is read here with org.json, field for field: a vote without
// an integer risk makes a whole reply unreadable (as Swift's decode throws);
// a malformed evidence entry, correction, proof or vignette is dropped alone,
// where Swift would refuse the whole reply.

/**
 * Verified / Checked / Check this / Flagged - or not checked yet. Checked (the
 * vignette route, server/vignette-proof.js) sits below Verified: every check
 * passed, but the published rule its proof rests on is not signed off yet.
 * The symbol and tone a grade is drawn with belong to the screen
 * (ui/AccuracyWhySheet.kt), not here.
 */
@Suppress("EnumEntryName")
enum class AccuracyGrade(val title: String) {
    verified("Verified"), checked("Checked"), check("Check this"), flagged("Flagged"), unchecked("Not checked yet");

    /** server/accuracy-model.js TIER_MEANINGS, word for word. */
    val meaning: String? get() = when (this) {
        verified -> "Verified means every fact was matched word for word to an open source, and every step was checked."
        checked -> "Checked means it passed our checks and agreement tests, but it isn't fully proven yet."
        else -> null
    }
}

/** Typed reads of the worker's JSON: a value of the wrong type is absent, as for a field Swift's decodeIfPresent finds null. */
internal object AccuracyJson {
    fun str(o: JSONObject, key: String): String? = o.opt(key) as? String

    fun int(o: JSONObject, key: String): Int? = when (val v = o.opt(key)) {
        is Int -> v
        is Long -> v.toInt()
        is Double -> v.takeIf { it == Math.rint(it) && it >= Int.MIN_VALUE && it <= Int.MAX_VALUE }?.toInt()
        else -> null
    }

    fun double(o: JSONObject, key: String): Double? = (o.opt(key) as? Number)?.toDouble()
    fun bool(o: JSONObject, key: String): Boolean? = o.opt(key) as? Boolean

    fun strings(o: JSONObject, key: String): List<String>? {
        val a = o.opt(key) as? JSONArray ?: return null
        return (0 until a.length()).mapNotNull { a.opt(it) as? String }
    }

    fun objects(o: JSONObject, key: String): List<JSONObject>? {
        val a = o.opt(key) as? JSONArray ?: return null
        return (0 until a.length()).mapNotNull { a.opt(it) as? JSONObject }
    }

    fun array(items: List<String>): JSONArray = JSONArray().also { a -> items.forEach { a.put(it) } }
}

/** A correction the checkers offered: a new key letter, or new wording for the explanation, the answer or the text. */
data class AccuracySuggestion(val field: String, val value: String, val by: List<String>? = null) {
    fun toJson(): JSONObject = JSONObject().put("field", field).put("value", value).also { o -> by?.let { o.put("by", AccuracyJson.array(it)) } }

    companion object {
        fun fromJson(o: JSONObject?): AccuracySuggestion? {
            if (o == null) return null
            val field = AccuracyJson.str(o, "field") ?: return null
            val value = AccuracyJson.str(o, "value") ?: return null
            return AccuracySuggestion(field, value, AccuracyJson.strings(o, "by"))
        }
    }
}

/** One checker model's vote on one item, as the server returns it (iOS AccuracyVote). */
data class AccuracyVote(
    val model: String = "",
    val risk: Int,
    val answer: String? = null,
    /** "supports", "contradicts" or "none" */
    val evidence: String = "none",
    val cites: List<String> = emptyList(),
    val issues: List<String> = emptyList(),
    val fix: AccuracySuggestion? = null,
    /**
     * The checker solved the question without seeing its key or explanation
     * (server/accuracy.js votesStage). Null for a vote that saw them.
     */
    val blind: Boolean? = null,
) {
    fun toJson(): JSONObject = JSONObject().put("model", model).put("risk", risk).put("evidence", evidence)
        .put("cites", AccuracyJson.array(cites)).put("issues", AccuracyJson.array(issues)).also { o ->
            answer?.let { o.put("answer", it) }
            fix?.let { o.put("fix", it.toJson()) }
            blind?.let { o.put("blind", it) }
        }

    companion object {
        /** Anything the server leaves out takes its default; a vote with no integer risk is unreadable (null). */
        fun fromJson(o: JSONObject): AccuracyVote? {
            val risk = AccuracyJson.int(o, "risk") ?: return null
            return AccuracyVote(
                model = AccuracyJson.str(o, "model") ?: "", risk = risk, answer = AccuracyJson.str(o, "answer"),
                evidence = AccuracyJson.str(o, "evidence") ?: "none", cites = AccuracyJson.strings(o, "cites") ?: emptyList(),
                issues = AccuracyJson.strings(o, "issues") ?: emptyList(), fix = AccuracySuggestion.fromJson(o.optJSONObject("fix")),
                blind = AccuracyJson.bool(o, "blind"),
            )
        }
    }
}

/** A source the checkers were shown, to cite in the "why" sheet (iOS AccuracyEvidence). */
data class AccuracyEvidence(val id: String, val source: String, val title: String, val url: String) {
    fun toJson(): JSONObject = JSONObject().put("id", id).put("source", source).put("title", title).put("url", url)

    companion object {
        fun fromJson(o: JSONObject): AccuracyEvidence? = AccuracyEvidence(
            AccuracyJson.str(o, "id") ?: return null, AccuracyJson.str(o, "source") ?: return null,
            AccuracyJson.str(o, "title") ?: return null, AccuracyJson.str(o, "url") ?: return null,
        )
    }
}

/**
 * The weights the app scores with: bundled in [AccuracyModel], replaced by
 * whatever the last training run published (the worker's /accuracy/model).
 */
data class AccuracyWeights(val version: String, val features: List<String>, val weights: List<Double>, val thresholds: Thresholds) {
    data class Thresholds(val verified: Double, val flagged: Double)

    val isValid: Boolean get() = features.size == weights.size && features.all { it in AccuracyModel.features }
        && weights.all { it.isFinite() } && thresholds.flagged < thresholds.verified
        && thresholds.verified <= 1 && thresholds.flagged >= 0

    fun toJson(): JSONObject = JSONObject().put("version", version).put("features", AccuracyJson.array(features))
        .put("weights", JSONArray().also { a -> weights.forEach { a.put(it) } })
        .put("thresholds", JSONObject().put("verified", thresholds.verified).put("flagged", thresholds.flagged))

    companion object {
        fun fromJson(o: JSONObject?): AccuracyWeights? {
            if (o == null) return null
            val version = AccuracyJson.str(o, "version") ?: return null
            val features = AccuracyJson.strings(o, "features") ?: return null
            val array = o.opt("weights") as? JSONArray ?: return null
            val weights = (0 until array.length()).map { (array.opt(it) as? Number)?.toDouble() ?: return null }
            val t = o.optJSONObject("thresholds") ?: return null
            return AccuracyWeights(version, features, weights,
                Thresholds(AccuracyJson.double(t, "verified") ?: return null, AccuracyJson.double(t, "flagged") ?: return null))
        }

        /**
         * The weights in a /accuracy/model reply ({"weights": {...}}), only if they are in the
         * model's shape (iOS AccuracyStore.refreshWeights keeps the old ones otherwise).
         */
        fun fromReply(reply: JSONObject?): AccuracyWeights? = fromJson(reply?.optJSONObject("weights"))?.takeIf { it.isValid }
    }
}

/** Whether the server's vignette check proved the item's vignette, or only checked it (iOS featureValues' tuple). */
data class VignetteFlags(val proven: Boolean, val checked: Boolean)

/**
 * The app's accuracy model: every signal about an item - the checker models'
 * votes, the literature they were shown, the rule checks, how much of the
 * item its lecture contains - into one calibrated P(accurate).
 *
 * The same logistic regression as server/accuracy-model.js, trained on GitHub
 * Actions (server/bench/train-accuracy.mjs); the phone keeps each item's raw
 * features, so new weights re-score the library without a single new check.
 */
object AccuracyModel {

    val features: List<String> = listOf(
        "bias", "rule_severe", "rule_minor", "risk_max", "risk_mean", "flag_frac", "disagree", "voters",
        "key_disagree", "ev_support", "ev_contradict", "ev_count", "source_match", "no_source", "no_models",
        "kind_mcq", "kind_card", "kind_case", "kind_osce", "kind_page",
    )

    // BEGIN DEFAULT WEIGHTS (kept identical to server/accuracy-model.js)
    /** One weight a line, by feature name (the server keeps them as a list in `features` order). */
    const val defaultJSON: String = """
        {"version": "prior-1",
         "weights": {
            "bias": 3.0,
            "rule_severe": -2.5,
            "rule_minor": -0.4,
            "risk_max": -2.5,
            "risk_mean": -1.5,
            "flag_frac": -2.0,
            "disagree": -0.5,
            "voters": 0.3,
            "key_disagree": -2.5,
            "ev_support": 0.8,
            "ev_contradict": -2.5,
            "ev_count": 0.1,
            "source_match": 0.8,
            "no_source": -0.3,
            "no_models": -1.5,
            "kind_mcq": 0,
            "kind_card": 0,
            "kind_case": 0,
            "kind_osce": 0,
            "kind_page": 0
         },
         "thresholds": {"verified": 0.85, "flagged": 0.4}}
        """
    // END DEFAULT WEIGHTS

    val bundled: AccuracyWeights by lazy {
        val prior = runCatching { JSONObject(defaultJSON) }.getOrNull()
        val named = prior?.optJSONObject("weights")
        val thresholds = prior?.optJSONObject("thresholds")
        AccuracyWeights(
            prior?.let { AccuracyJson.str(it, "version") } ?: "prior-1", features,
            features.map { name -> named?.let { AccuracyJson.double(it, name) } ?: 0.0 },
            AccuracyWeights.Thresholds(thresholds?.let { AccuracyJson.double(it, "verified") } ?: 0.85,
                thresholds?.let { AccuracyJson.double(it, "flagged") } ?: 0.4),
        )
    }

    private fun clamp01(x: Double): Double = min(1.0, max(0.0, x))

    /**
     * The feature values for one item (the same as features() on the server).
     * [sourceProof]: every claim of the item is stated word for word by an
     * official source (AccuracyProof.isFull). [vignette]: only while the
     * server's vignette route is on (its reply carried the item's proof
     * check), whether that proof is proven or only checked; null, the
     * features are what they always were.
     */
    fun featureValues(
        kind: AccuracyKind, rules: List<AccuracyRules.Hit>, votes: List<AccuracyVote>, evidenceCount: Int,
        sourceMatch: Double?, keyLetter: String?, sourceProof: Boolean = false, vignette: VignetteFlags? = null,
    ): Map<String, Double> {
        val risks = votes.map { clamp01((it.risk - 1).toDouble() / 3) }
        val flags = votes.map { it.risk >= 3 }
        val answered = votes.filter { v -> v.answer?.let { it.length == 1 && "ABCDEFGHIJ".contains(it) } == true }
        val n = votes.size.toDouble()
        val flagCount = flags.count { it }.toDouble()
        val f = LinkedHashMap<String, Double>()
        f["bias"] = 1.0
        f["rule_severe"] = min(2, rules.count { it.isSevere }).toDouble()
        f["rule_minor"] = min(3, rules.count { !it.isSevere }).toDouble()
        f["risk_max"] = risks.maxOrNull() ?: 0.0
        f["risk_mean"] = if (risks.isEmpty()) 0.0 else risks.fold(0.0) { a, b -> a + b } / n
        f["flag_frac"] = if (flags.isEmpty()) 0.0 else flagCount / n
        val split = flags.size > 1 && flags.contains(true) && flags.contains(false)
        f["disagree"] = if (split) 1.0 else 0.0
        f["voters"] = min(3, votes.size).toDouble() / 3
        var keyDisagree = 0.0
        if (kind == AccuracyKind.mcq && keyLetter != null && answered.isNotEmpty()) {
            val other = answered.count { it.answer != keyLetter }
            keyDisagree = other.toDouble() / answered.size
        }
        f["key_disagree"] = keyDisagree
        f["ev_support"] = if (votes.isEmpty()) 0.0 else votes.count { it.evidence == "supports" }.toDouble() / n
        f["ev_contradict"] = if (votes.isEmpty()) 0.0 else votes.count { it.evidence == "contradicts" }.toDouble() / n
        f["ev_count"] = min(5, evidenceCount).toDouble() / 5
        f["source_match"] = sourceMatch?.let(::clamp01) ?: 0.0
        f["no_source"] = if (sourceMatch == null) 1.0 else 0.0
        f["source_proof"] = if (sourceProof) 1.0 else 0.0
        f["no_models"] = if (votes.isEmpty()) 1.0 else 0.0
        f["kind_mcq"] = if (kind == AccuracyKind.mcq) 1.0 else 0.0
        f["kind_card"] = if (kind == AccuracyKind.card) 1.0 else 0.0
        f["kind_case"] = if (kind == AccuracyKind.case) 1.0 else 0.0
        f["kind_osce"] = if (kind == AccuracyKind.osce) 1.0 else 0.0
        val pageLike = kind == AccuracyKind.page || kind == AccuracyKind.fact || kind == AccuracyKind.note
        f["kind_page"] = if (pageLike) 1.0 else 0.0
        // not a weighted feature: how many model families the votes that pass
        // the item come from (the verdict needs three), as the server counts it
        f["families"] = votes.filter { it.risk < 3 }.map { familyOf(it.model) }.toSet().size.toDouble()
        // the blind solves of a question, counted by family (features() in
        // server/accuracy-model.js): agreeing with the key, the most agreeing
        // on one other answer, and whether they split
        if (kind == AccuracyKind.mcq && keyLetter != null) {
            val byLetter = LinkedHashMap<String, MutableSet<String>>()
            for (v in answered) if (v.blind == true) v.answer?.let { byLetter.getOrPut(it) { mutableSetOf() }.add(familyOf(v.model)) }
            f["blind_agree"] = (byLetter[keyLetter]?.size ?: 0).toDouble()
            f["blind_against"] = (byLetter.filterKeys { it != keyLetter }.values.maxOfOrNull { it.size } ?: 0).toDouble()
            f["blind_split"] = if (byLetter.size > 1) 1.0 else 0.0
            // every family that solved it blind and reached anything but the key
            f["blind_dissent"] = byLetter.filterKeys { it != keyLetter }.values.flatten().toSet().size.toDouble()
        }
        // the families that flagged it
        f["flag_families"] = votes.filter { it.risk >= 3 }.map { familyOf(it.model) }.toSet().size.toDouble()
        // not weighted: the vignette route's proof, as the server sets it
        if (vignette != null) {
            f["vignette_proof"] = if (vignette.proven) 1.0 else 0.0
            f["vignette_checked"] = if (vignette.checked) 1.0 else 0.0
        }
        return f
    }

    /**
     * The family a checker model belongs to: two models of one family share
     * their training and so their blind spots - two votes from one family are
     * one witness. server/accuracy-model.js familyOf, pattern for pattern.
     */
    val families: List<Pair<String, String>> = listOf(
        "google" to "gemini|gemma", "openai" to "gpt|openai", "nvidia" to "nemotron|nvidia",
        "meta" to "llama|\\bmeta\\b", "alibaba" to "qwen", "mistral" to "mistral|mixtral", "deepseek" to "deepseek",
        "anthropic" to "claude|anthropic", "baichuan" to "baichuan", "microsoft" to "\\bphi-|microsoft", "apple" to "\\bapple\\b",
    )

    private val familyPatterns: List<Pair<String, Pattern?>> by lazy {
        families.map { (family, pattern) -> family to runCatching { Pattern.compile(pattern, Pattern.UNICODE_CHARACTER_CLASS) }.getOrNull() }
    }

    fun familyOf(model: String): String {
        val m = model.lowercase()
        for ((family, re) in familyPatterns) if (re != null && re.matcher(m).find()) return family
        return m.ifEmpty { "unknown" }
    }

    fun probability(f: Map<String, Double>, weights: AccuracyWeights = bundled): Double {
        var z = 0.0
        for ((i, name) in weights.features.withIndex()) if (i < weights.weights.size) z += (f[name] ?: 0.0) * weights.weights[i]
        z = max(-40.0, min(40.0, z))
        return 1 / (1 + exp(-z))
    }

    // MARK: stricter for the chosen exam's management questions

    /**
     * Lead-ins of a management question - "next best step", "most appropriate
     * treatment" - the same list as server/accuracy-model.js.
     */
    val managementCues: List<String> = listOf(
        "next step", "next best step", "most appropriate management", "most appropriate treatment",
        "most appropriate therapy", "most appropriate pharmacotherapy", "most appropriate initial",
        "most appropriate immediate", "most appropriate next", "most appropriate intervention",
        "most appropriate action", "best management", "best treatment", "initial management",
        "immediate management", "treatment of choice", "drug of choice", "first-line", "first line",
        "should be managed", "should be prescribed",
    )

    fun isManagement(text: String): Boolean {
        val t = text.lowercase()
        return managementCues.any { t.contains(it) }
    }

    /**
     * Cut-offs made stricter by [s] (0-1): Verified moves [s] of the way to
     * 0.99, Flagged up by a tenth of [s] (always 0.05 under Verified).
     */
    fun stricter(t: AccuracyWeights.Thresholds, s: Double): AccuracyWeights.Thresholds {
        val k = min(1.0, max(0.0, s))
        if (k <= 0) return t
        val verified = if (t.verified < 0.99) t.verified + (0.99 - t.verified) * k else t.verified
        val flagged = min(verified - 0.05, t.flagged + 0.1 * k)
        fun round4(x: Double): Double = Math.round(x * 10000).toDouble() / 10000
        return AccuracyWeights.Thresholds(round4(verified), round4(max(0.0, flagged)))
    }

    /**
     * How much stricter to be with this item: the chosen exam's strictness for
     * a management question or card, while that exam's track is still the one
     * chosen; 0 otherwise (and with no [defaults], 0). ExamChoice.choose
     * leaves the strictness and the track it was chosen under in the defaults.
     */
    fun examStrictness(item: AccuracyItem, defaults: ExamDefaults?): Double {
        if (defaults == null) return 0.0
        val s = defaults.double(EXAM_STRICTNESS_KEY)
        if (s <= 0) return 0.0
        val family = defaults.string(EXAM_FAMILY_KEY) ?: return 0.0
        if (family != (defaults.string(EXAM_TRACK_KEY) ?: "general")) return 0.0
        val text = if (item.kind == AccuracyKind.mcq) item.stem else item.text
        return if (isManagement(text)) s else 0.0
    }

    /** Where ExamChoice leaves the chosen exam's strictness (0-1), the track it was chosen under, and the track now. */
    const val EXAM_STRICTNESS_KEY = "exam.accuracyStrictness"
    const val EXAM_FAMILY_KEY = "exam.accuracyFamily"
    const val EXAM_TRACK_KEY = "examTrack"

    // MARK: the oath check (plan §22 Layer 7: regex first, fail closed)

    /**
     * The fewest model families an item needs, each passing it (a question:
     * each solving it blind and reaching its key), before it can be Verified,
     * and the fewest agreeing on another answer before a question is Flagged.
     * Three, for the owner's 99.999% (1 Oct). server/accuracy-model.js
     * MIN_VERIFY_VOTERS.
     */
    const val minVerifyVoters: Int = 3

    /**
     * How much of an oath item its own lecture must contain to stand for the
     * evidence behind it (OATH_SOURCE_MATCH). No longer enough for Verified:
     * only an official source's own words are (source_proof).
     */
    const val oathSourceMatch: Double = 0.5

    /**
     * A specific dose: an amount in a dose unit beside a route or a frequency,
     * or per kilogram, day or dose; lab values in a case are not doses.
     * server/accuracy-model.js DOSE_PATTERN, character for character.
     */
    const val dosePattern: String = """\b\d+(?:\.\d+)?\s?(?:mg|mcg|µg|μg|micrograms?|milligrams?|g|grams?|units?|iu|ml)\b[^.\n]{0,30}\b(?:iv|po|im|sc|sl|oral|orally|intravenous|intravenously|daily|once|twice|bd|bid|tds|tid|qds|qid|nocte|stat|hourly|weekly|per day|a day|every \d+ ?(?:h|hours?))\b""" +
        """|\b(?:iv|po|im|sc|oral|orally|intravenous|intravenously)\b[^.\n]{0,20}?\b\d+(?:\.\d+)?\s?(?:mg|mcg|µg|μg|g|units?|iu|ml)\b""" +
        """|\b\d+(?:\.\d+)?\s?(?:mg|mcg|µg|μg|g|units?|iu|ml)\s?/\s?(?:kg|day|d|dose|m2|m²)\b"""

    // ICU's caseInsensitive and Unicode word boundaries, as AccuracyRules runs its patterns
    private val doseExpression: Pattern? by lazy {
        runCatching { Pattern.compile(dosePattern, Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE or Pattern.UNICODE_CHARACTER_CLASS) }.getOrNull()
    }

    /** Words that make an item a diagnosis - the same list as server/accuracy-model.js DIAGNOSIS_CUES. */
    val diagnosisCues: List<String> = listOf(
        "most likely diagnosis", "most probable diagnosis", "likely diagnosis is", "the diagnosis is",
        "diagnosis of choice", "is diagnosed with", "is diagnostic of", "confirms the diagnosis", "pathognomonic",
    )

    fun hasDose(text: String): Boolean {
        val expression = doseExpression ?: return true  // fail closed: an unreadable pattern holds every item
        return expression.matcher(text).find()
    }

    fun isDiagnosis(text: String): Boolean {
        val t = text.lowercase()
        return diagnosisCues.any { t.contains(it) }
    }

    /** Does this item give a dose, name a diagnosis or recommend a treatment? Then the oath check holds it to more than the models' word. */
    fun isOath(text: String): Boolean = hasDose(text) || isDiagnosis(text) || isManagement(text)

    /**
     * Verified needs three model families passing the item with no concern
     * raised and no sensor firing, and every item needs an official source
     * stating it word for word - proof, not the models' agreement. Flagged
     * needs proof from two directions; rules alone flag an item only before
     * any model has looked. Everything else is Check this.
     * server/accuracy-model.js verdict, rule for rule. [oath] is kept for
     * the signature: as on iOS, it no longer changes the grade (only a proof
     * does). [vignetteRoute]: the server's vignette route is on - an
     * owner-signed vignette proof stands where a source proof would, and one
     * only checked gives at most Checked, every other condition still met.
     */
    @Suppress("UNUSED_PARAMETER")
    fun grade(p: Double, f: Map<String, Double>, weights: AccuracyWeights = bundled, oath: Boolean = false, vignetteRoute: Boolean = false): AccuracyGrade {
        val severe = (f["rule_severe"] ?: 0.0) > 0
        if ((f["no_models"] ?: 1.0) > 0) return if (severe) AccuracyGrade.flagged else AccuracyGrade.unchecked
        val need = minVerifyVoters.toDouble()
        val question = (f["kind_mcq"] ?: 0.0) == 1.0
        // three families solving it blind agree on one other answer and none
        // reaches the key: the key is wrong
        if (question && (f["blind_against"] ?: 0.0) >= need && (f["blind_agree"] ?: 0.0) == 0.0) return AccuracyGrade.flagged
        // a severe safety rule that the models also judge likely wrong
        if (severe && p < weights.thresholds.flagged) return AccuracyGrade.flagged
        // every voter, from three families, judged it wrong
        if (!question && (f["flag_families"] ?: 0.0) >= need && (f["flag_frac"] ?: 0.0) == 1.0 && p < weights.thresholds.flagged) return AccuracyGrade.flagged
        val voters = Math.round((f["voters"] ?: 0.0) * 3).toInt()
        // every item needs an official source stating it word for word (the
        // owner: "they need to be PROVEN 99.999% right", 7 Oct)
        val backed = (f["source_proof"] ?: 0.0) == 1.0 || (vignetteRoute && (f["vignette_proof"] ?: 0.0) == 1.0)
        val independent = (f["families"] ?: 0.0) >= need
        // no voter raised a concern or read the literature against it, and
        // no sensor fired, however mildly
        val unanimous = (f["flag_frac"] ?: 0.0) == 0.0 && (f["ev_contradict"] ?: 0.0) == 0.0
        val clean = !severe && (f["rule_minor"] ?: 0.0) == 0.0
        // a question is Verified only when three independent blind solves
        // reach its key and no family solving it blind went elsewhere
        val solved = !question || ((f["blind_agree"] ?: 0.0) >= need && (f["blind_dissent"] ?: 0.0) == 0.0)
        if (p >= weights.thresholds.verified && clean && voters >= minVerifyVoters && backed && independent && unanimous && solved) return AccuracyGrade.verified
        // Checked: everything Verified needs, but its proof rests on a rule
        // the owner has not signed off yet
        if (vignetteRoute && (f["vignette_checked"] ?: 0.0) == 1.0 && p >= weights.thresholds.verified && clean
            && voters >= minVerifyVoters && independent && unanimous && solved) return AccuracyGrade.checked
        return AccuracyGrade.check
    }
}

/**
 * A checker's correction, applied to the item it is about: whether it can be
 * applied with one tap (iOS AccuracyFix.canApply, keyIndex and lines). The
 * edits themselves (apply, applyEverywhere) rewrite a set and belong with the
 * screen that saves it.
 */
object AccuracyFix {

    /** Whether this suggestion can be applied to this kind of item with one tap. */
    fun canApply(s: AccuracySuggestion, item: AccuracyItem): Boolean = when (item.kind to s.field) {
        AccuracyKind.mcq to "key" -> keyIndex(s.value, item.options.size) != null
        AccuracyKind.mcq to "explanation", AccuracyKind.card to "explanation", AccuracyKind.card to "answer" -> true
        AccuracyKind.osce to "text", AccuracyKind.osce to "answer" -> lines(s.value).size >= 2
        else -> false
    }

    fun keyIndex(value: String, count: Int): Int? {
        val trimmed = value.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }.uppercase()
        if (trimmed.isEmpty() || trimmed.codePointCount(0, trimmed.length) != 1) return null
        val i = trimmed.codePointAt(0) - 65
        return if (i in 0 until count) i else null
    }

    fun lines(value: String): List<String> =
        value.split('\n', ';').map { part -> part.trim { it == ' ' || it == '-' || it == '•' || it == '\t' } }.filter { it.isNotEmpty() }
}
