package com.stethoscore.app.quiz

// A port of ios/RedPen/Shared/PatientChart.swift.
//
// A question's stem read as a patient's chart (docs/design/targets-2026-10-01.md
// §1, "A question as a patient chart"): who the patient is, their vital
// signs, their results with high and low marked, the story, and the
// question asked. Only what the stem says is shown - nothing is inferred -
// and a stem with no observations in it stays plain text.
//
// High and low for results come from AccuracyRules' reference ranges, the
// table the accuracy check uses, so the chart and the check never disagree
// about what is abnormal; a result that table does not know is shown
// without a flag rather than guessed at. Plain Kotlin, so PatientChartTest
// runs it on the JVM.
data class PatientChart(
    /** "34 y", "Male", "Pregnant", "3 wk" */
    val chips: List<String> = emptyList(),
    val vitals: List<Vital> = emptyList(),
    val labs: List<Lab> = emptyList(),
    /** The stem without its question and without the sentences that only list what the grid and the table already show. */
    val story: String = "",
    /** The question asked, set in bold under the chart; empty when the stem has no question sentence of its own. */
    val question: String = "",
) {
    enum class Flag(val rawValue: String) { high("H"), low("L") }

    data class Vital(val label: String, val value: String, val flag: Flag? = null)

    data class Lab(val name: String, val value: String, val unit: String, val flag: Flag? = null)

    /** Whether there is anything to chart. */
    val hasObservations: Boolean get() = vitals.isNotEmpty() || labs.isNotEmpty()

    /** What was read in one sentence, with the UTF-16 ranges [start, end) it came from. */
    data class Found(val vitals: List<Vital> = emptyList(), val labs: List<Lab> = emptyList(), val spans: List<IntRange> = emptyList())

    companion object {
        // MARK: reading a stem

        fun read(stem: String): PatientChart {
            val text = normalised(stem)
            val chips = chips(text)
            val sentences = AccuracyRules.sentences(text)
            val asked = questionIndex(sentences)
            val vitals = mutableListOf<Vital>()
            val labs = mutableListOf<Lab>()
            val kept = mutableListOf<String>()
            for ((i, sentence) in sentences.withIndex()) {
                val found = observations(sentence)
                vitals += found.vitals
                labs += found.labs
                if (i == asked) continue
                // a sentence that only lists what the chart shows is not repeated
                if (found.vitals.isEmpty() && found.labs.isEmpty() || !onlyObservations(sentence, found.spans)) {
                    kept += sentence
                }
            }
            // one reading of each sign: the first the stem gives
            val seen = HashSet<String>()
            val firstVitals = vitals.filter { seen.add(it.label) }
            val question = if (asked != null) sentences[asked] else ""
            var story = kept.joinToString(" ")
            if (story.isEmpty() && question.isEmpty()) story = stem
            return PatientChart(chips, firstVitals, labs, story, question)
        }

        /** Stems arrive with every kind of degree sign and micro. */
        fun normalised(s: String): String =
            s.replace("μ", "µ").replace("º", "°").replace("˚", "°").replace(" ", " ")

        /** The last sentence that asks something. */
        fun questionIndex(sentences: List<String>): Int? {
            val asks = sentences.indexOfLast { it.contains("?") }
            if (asks >= 0) return asks
            val lead = """^(?:which|what|the most (?:likely|appropriate)|the next|the best)\b"""
            val i = sentences.indexOfLast { AccuracyRules.matches(lead, it.lowercase()) }
            return if (i >= 0) i else null
        }

        // MARK: who the patient is

        private val numberWords: Map<String, String> = mapOf(
            "a" to "1", "an" to "1", "one" to "1", "two" to "2", "three" to "3", "four" to "4", "five" to "5",
            "six" to "6", "seven" to "7", "eight" to "8", "nine" to "9", "ten" to "10", "twelve" to "12",
        )

        private val spanUnits: Map<String, String> = mapOf(
            "hour" to "h", "hours" to "h", "day" to "d", "days" to "d", "week" to "wk", "weeks" to "wk",
            "month" to "mo", "months" to "mo", "year" to "y", "years" to "y",
        )

        fun chips(text: String): List<String> {
            val t = text.lowercase()
            val out = mutableListOf<String>()
            val years = AccuracyRules.find("""\b(\d{1,3})[\s-]*(?:year|yr)s?[\s-]*old\b""", t).firstOrNull()?.groups?.get(1)
            val months = AccuracyRules.find("""\b(\d{1,2})[\s-]*months?[\s-]*old\b""", t).firstOrNull()?.groups?.get(1)
            val days = AccuracyRules.find("""\b(\d{1,2})[\s-]*(?:day|week)s?[\s-]*old\b""", t).firstOrNull()?.groups?.get(1)
            if (years != null) {
                out += "$years y"
            } else if (months != null) {
                out += "$months mo"
            } else if (days != null) {
                out += days + (if (t.contains("week")) " wk" else " d") + " old"
            } else if (AccuracyRules.matches("""\b(?:newborn|neonate)\b""", t)) {
                out += "Newborn"
            }
            val male = """\b(?:man|male|boy|gentleman|father|he)\b"""
            val female = """\b(?:woman|female|girl|lady|mother|she)\b"""
            if (AccuracyRules.matches(male, t) && !AccuracyRules.matches(female, t)) {
                out += "Male"
            } else if (AccuracyRules.matches(female, t) && !AccuracyRules.matches(male, t)) {
                out += "Female"
            }
            if (AccuracyRules.matches("""\bpregnan(?:t|cy)\b""", t) && !AccuracyRules.matches("""\bnot pregnant\b""", t)) {
                out += "Pregnant"
            }
            val duration = """\b(?:for|over)\s+(?:the\s+(?:last|past)\s+)?(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|twelve)\s+(hours?|days?|weeks?|months?|years?)\b"""
            val m = AccuracyRules.find(duration, t).firstOrNull()
            val n = m?.groups?.get(1)
            val unit = m?.groups?.get(2)
            val short = unit?.let { spanUnits[it] }
            if (n != null && short != null) out += (numberWords[n] ?: n) + " " + short
            return out
        }

        // MARK: vital signs and results

        /**
         * The vital signs, with the thresholds an adult's chart would flag:
         * BP 140/90 and over high, systolic under 90 low; pulse over 100 or
         * under 60; breathing over 20 or under 12; temperature 38.0 °C and over,
         * under 35.0; saturation under 94%.
         */
        private val vitalPatterns: List<Pair<String, String>> = listOf(
            "BP" to """\b(?:bp|blood pressure)\b[^0-9.;]{0,14}?(\d{2,3})\s*/\s*(\d{2,3})(?:\s*mm\s?hg)?""",
            "HR" to """\b(?:hr|heart rate|pulse(?: rate)?)\b[^0-9.;/]{0,14}?(\d{2,3})(?:\s*(?:/\s*min(?:ute)?|bpm|beats?(?:\s*(?:per|/|a)\s*min(?:ute)?)?|per\s+min(?:ute)?))?""",
            "RR" to """\b(?:rr|resp(?:iratory)?\.?\s*rate|respirations?)\b[^0-9.;/]{0,14}?(\d{1,2})(?:\s*(?:/\s*min(?:ute)?|breaths?(?:\s*(?:per|/|a)\s*min(?:ute)?)?|per\s+min(?:ute)?))?""",
            "Temp" to """(?:\btemp(?:erature)?\b[^0-9.;]{0,14}?)?(\d{2,3}(?:\.\d)?)\s*(?:°\s*|degrees?\s+)(c|f)(?:elsius|ahrenheit)?\b""",
            "SpO2" to """\b(?:spo2|sp02|sao2|o2\s*sat(?:uration)?s?|oxygen\s+sat(?:uration)?s?|sats?|saturat(?:ing|es|ion))\b[^0-9.;]{0,16}?(\d{2,3})\s*%""",
        )

        private val units: String = listOf(
            """mmol/l""", """µmol/l""", """umol/l""", """nmol/l""", """pmol/l""", """g/l""", """g/dl""", """mg/dl""", """mg/l""",
            """µg/l""", """ug/l""", """ng/ml""", """ng/l""", """pg/ml""", """iu/l""", """u/l""", """miu/l""", """mu/l""",
            """mmol/mol""", """meq/l""", """mm/h(?:r|our)?""", """fl""", """pg""", """mg/mmol""", """kpa""", """mm\s?hg""",
            """(?:x|×)\s?10\s?(?:\^\s?)?(?:9|⁹)\s?/\s?l""", """(?:x|×)\s?10\s?(?:\^\s?)?(?:12|¹²)\s?/\s?l""",
            """%""", """sec(?:onds)?""", """s""",
        ).joinToString("|")

        private val labPattern: String =
            """(?:^|[\s,;:(])([a-z][a-z0-9\-+]*(?:\s+[a-z][a-z0-9\-+]*){0,3}?)\s*(?:level|concentration|count)?\s*(?:of|:|=|is|was|at)?\s*(\d+(?:\.\d+)?)\s*(""" + units + """)(?![a-z0-9])"""

        /** Words that lead into a result but are not its name. */
        private val leadIns: Set<String> = setOf(
            "serum", "plasma", "blood", "his", "her", "their", "the", "a", "an", "and", "with", "shows", "showed",
            "show", "reveal", "reveals", "revealed", "results", "result", "investigations", "labs", "bloods",
            "tests", "test", "include", "including", "of", "is", "was", "were", "are", "on", "her", "level",
            "levels", "random", "fasting", "total",
        )

        /** Names that are vital signs, not results. */
        private val vitalNames: Set<String> = setOf(
            "bp", "hr", "rr", "pulse", "temp", "temperature", "spo2", "sp02", "sao2", "sats", "sat", "saturation",
            "saturations", "o2", "oxygen", "heart", "rate", "respiratory", "pressure",
        )

        private fun overlaps(a: IntRange, b: IntRange): Boolean = maxOf(a.first, b.first) <= minOf(a.last, b.last)

        fun observations(sentence: String): Found {
            val vitals = mutableListOf<Vital>()
            val labs = mutableListOf<Lab>()
            val spans = mutableListOf<IntRange>()
            for ((label, pattern) in vitalPatterns) {
                for (m in AccuracyRules.find(pattern, sentence, caseless = true)) {
                    val vital = vital(label, m.groups) ?: continue
                    vitals += vital
                    spans += m.start until m.end
                }
            }
            for (m in AccuracyRules.find(labPattern, sentence, caseless = true)) {
                val range = m.start until m.end
                if (spans.any { !it.isEmpty() && !range.isEmpty() && overlaps(it, range) }) continue
                val rawName = m.groups[1] ?: continue
                val value = m.groups[2] ?: continue
                val unit = m.groups[3] ?: continue
                val words = rawName.split(" ").filter { it.isNotEmpty() }.toMutableList()
                while (words.isNotEmpty() && words.first().lowercase() in leadIns) words.removeAt(0)
                if (words.isEmpty() || words.size > 3 || words.any { it.lowercase() in vitalNames }) continue
                val name = words.joinToString(" ")
                // a bare "s" or "%" after a lone word is too easily something else
                if (unit.lowercase() == "s" && name.codePointCount(0, name.length) > 5) continue
                labs += Lab(displayName(name), value, AccuracyRules.trimSpaces(unit),
                    labFlag(name, AccuracyRules.number(value), unit))
                spans += range
            }
            return Found(vitals, labs, spans)
        }

        private fun vital(label: String, groups: List<String?>): Vital? {
            fun n(i: Int): Double? = groups.getOrNull(i)?.toDoubleOrNull()
            when (label) {
                "BP" -> {
                    val sys = n(1) ?: return null
                    val dia = n(2) ?: return null
                    if (sys !in 50.0..300.0 || dia !in 20.0..200.0 || sys <= dia) return null
                    val flag = if (sys >= 140 || dia >= 90) Flag.high else if (sys < 90) Flag.low else null
                    return Vital("BP", "${sys.toInt()}/${dia.toInt()}", flag)
                }
                "HR" -> {
                    val hr = n(1) ?: return null
                    if (hr !in 20.0..250.0) return null
                    return Vital("HR", "${hr.toInt()}", if (hr > 100) Flag.high else if (hr < 60) Flag.low else null)
                }
                "RR" -> {
                    val rr = n(1) ?: return null
                    if (rr !in 4.0..80.0) return null
                    return Vital("RR", "${rr.toInt()}", if (rr > 20) Flag.high else if (rr < 12) Flag.low else null)
                }
                "Temp" -> {
                    val t = n(1) ?: return null
                    val scale = groups.getOrNull(2)?.lowercase() ?: return null
                    if (scale == "c") {
                        if (t !in 30.0..45.0) return null
                        return Vital("Temp", trimmed(t) + " °C", if (t >= 38) Flag.high else if (t < 35) Flag.low else null)
                    }
                    if (t !in 86.0..113.0) return null
                    return Vital("Temp", trimmed(t) + " °F", if (t >= 100.4) Flag.high else if (t < 95) Flag.low else null)
                }
                "SpO2" -> {
                    val s = n(1) ?: return null
                    if (s !in 40.0..100.0) return null
                    return Vital("SpO2", "${s.toInt()}%", if (s < 94) Flag.low else null)
                }
            }
            return null
        }

        private fun trimmed(x: Double): String = if (x == Math.rint(x)) x.toInt().toString() else x.toString()

        /** "albumin" → "Albumin"; an abbreviation stays as written ("CRP", "HbA1c"). */
        private fun displayName(name: String): String {
            if (name != name.lowercase() || name.isEmpty()) return name
            return name.substring(0, 1).uppercase() + name.substring(1)
        }

        /** High or low against AccuracyRules' reference range for the analyte in that unit; null when the table does not know it. */
        fun labFlag(name: String, value: Double, unit: String): Flag? {
            val analyte = AccuracyRules.labNames[name.lowercase()] ?: return null
            val u = unit.lowercase().replace("μ", "µ").replace(" ", "")
            val normal = AccuracyRules.unitAliases[u] ?: return null
            val r = AccuracyRules.labs[analyte]?.get(normal) ?: return null
            if (r.size != 4) return null
            if (value < r[2]) return Flag.low
            if (value > r[3]) return Flag.high
            return null
        }

        /** Words a sentence of observations is padded with. */
        private val filler: Set<String> = setOf(
            "his", "her", "their", "the", "and", "with", "was", "were", "are", "room", "air", "shows", "showed",
            "show", "reveal", "reveals", "revealed", "results", "bloods", "blood", "tests", "test", "investigations",
            "labs", "laboratory", "vital", "signs", "observations", "obs", "examination", "exam", "regular",
            "irregular", "per", "minute", "min", "bpm", "mmhg", "serum", "plasma", "level", "levels", "include",
            "including", "following", "has", "had", "him", "she", "they", "rate", "heart", "respiratory",
            "pressure", "oxygen", "temperature", "pulse", "saturation", "saturations", "sats", "on", "at", "of",
            "is", "in", "are", "breaths", "beats", "degrees", "admission", "arrival", "presentation", "today",
        )

        /** Whether, with what was read taken out, nothing is left but padding: at most two words that say something. */
        fun onlyObservations(sentence: String, spans: List<IntRange>): Boolean {
            val sb = StringBuilder(sentence)
            for (range in spans.sortedByDescending { it.first }) {
                if (range.last + 1 <= sb.length) sb.replace(range.first, range.last + 1, " ")
            }
            val words = sb.toString().lowercase().split(Regex("[^\\p{L}]+"))
                .filter { it.codePointCount(0, it.length) >= 3 && it !in filler }
            return words.size <= 2
        }
    }
}
