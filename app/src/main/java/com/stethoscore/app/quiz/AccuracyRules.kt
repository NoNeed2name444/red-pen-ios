package com.stethoscore.app.quiz

import java.util.regex.Pattern

// The parts of upstream/ios/RedPen/Shared/Accuracy/AccuracyRules.swift the
// question chart needs (PatientChart): the lab reference table, the unit and
// analyte names, the regex helper and the sentence splitter. The rest of the
// accuracy engine (doses, notation, look-alikes, retired practice) comes with
// the accuracy check (parity batch 20). Plain Kotlin, so the tests run on the JVM.
//
// java.util.regex stands in for NSRegularExpression: both match on UTF-16
// code units, so a match's start and end are the same numbers iOS gets.

object AccuracyRules {

    // BEGIN LABS (the server's table, as iOS writes it out)
    const val labTable: String = """
        sodium|mmol~l=95:195:135:145;sodium|meq~l=95:195:135:145;potassium|mmol~l=1.2:10:3.5:5.3;
        potassium|meq~l=1.2:10:3.5:5.3;chloride|mmol~l=60:150:96:107;chloride|meq~l=60:150:96:107;
        bicarbonate|mmol~l=2:55:22:29;bicarbonate|meq~l=2:55:22:29;calcium|mg~dl=3:20:8.5:10.5;
        calcium|mmol~l=0.8:5:2.1:2.6;calcium|meq~l=1.6:10:4.2:5.2;magnesium|mg~dl=0.4:12:1.7:2.4;magnesium|mmol~l=0.15:5:0.7:1.05;
        magnesium|meq~l=0.3:10:1.4:2.1;glucose|mg~dl=10:2500:70:100;glucose|mmol~l=0.5:140:3.9:5.6;
        creatinine|mg~dl=0.1:30:0.6:1.3;creatinine|µmol~l=10:2700:50:115;urea|mmol~l=0.5:120:2.5:7.8;
        urea|mg~dl=1:350:7:20;bun|mg~dl=1:350:7:20;haemoglobin|g~dl=1.5:26:12:17.5;
        haemoglobin|g~l=15:260:120:175;hemoglobin|g~dl=1.5:26:12:17.5;hemoglobin|g~l=15:260:120:175;
        albumin|g~dl=0.5:7:3.5:5;albumin|g~l=5:70:35:50;bilirubin|mg~dl=0.05:60:0.1:1.2;
        bilirubin|µmol~l=1:1000:3:21;lactate|mmol~l=0.1:35:0.5:2.2;lactate|mg~dl=0.9:315:4.5:19.8;tsh|miu~l=0.001:1000:0.4:4.5;
        tsh|mu~l=0.001:1000:0.4:4.5;hba1c|%=3:20:4:5.6;hba1c|mmol~mol=10:200:20:38;paco2|mmhg=8:160:35:45;
        paco2|kpa=1:21:4.7:6;pao2|mmhg=15:700:75:100;pao2|kpa=2:95:10:13.3;ph|=6.5:7.9:7.35:7.45;
        inr|=0.5:20:0.8:1.2;
        """
    // END LABS

    /** analyte -> unit -> [plausible low, plausible high, reference low, reference high]. */
    val labs: Map<String, Map<String, List<Double>>> by lazy {
        val out = LinkedHashMap<String, MutableMap<String, List<Double>>>()
        for ((name, values) in entries(labTable)) {
            val parts = name.split("|")
            if (parts.size != 2) continue
            out.getOrPut(parts[0]) { LinkedHashMap() }[parts[1]] = values
        }
        out
    }

    private fun entries(table: String): List<Pair<String, List<Double>>> {
        val flat = table.replace("\n", "")
        val out = mutableListOf<Pair<String, List<Double>>>()
        for (raw in flat.split(";")) {
            val entry = raw.trim(' ', '\t')
            val eq = entry.lastIndexOf('=')
            if (eq < 0) continue
            // the tables write "/" as "~" and separate numbers with ":"
            val name = entry.substring(0, eq).replace("~", "/")
            val values = entry.substring(eq + 1).split(":").mapNotNull { it.toDoubleOrNull() }
            out += name to values
        }
        return out
    }

    val unitAliases: Map<String, String> = mapOf(
        "mmol/l" to "mmol/l", "mmol/litre" to "mmol/l", "mmol/liter" to "mmol/l", "meq/l" to "meq/l", "mg/dl" to "mg/dl",
        "µmol/l" to "µmol/l", "umol/l" to "µmol/l", "micromol/l" to "µmol/l", "g/dl" to "g/dl", "g/l" to "g/l",
        "miu/l" to "miu/l", "mu/l" to "mu/l", "µiu/ml" to "miu/l", "uiu/ml" to "miu/l", "%" to "%", "mmol/mol" to "mmol/mol",
        "mmhg" to "mmhg", "mm hg" to "mmhg", "kpa" to "kpa", "mg/l" to "mg/l", "ng/ml" to "ng/ml", "iu/l" to "iu/l", "u/l" to "u/l",
    )

    val labNames: Map<String, String> = mapOf(
        "sodium" to "sodium", "na" to "sodium", "na+" to "sodium", "potassium" to "potassium", "k" to "potassium", "k+" to "potassium",
        "chloride" to "chloride", "bicarbonate" to "bicarbonate", "hco3" to "bicarbonate", "calcium" to "calcium",
        "magnesium" to "magnesium", "glucose" to "glucose", "blood glucose" to "glucose", "blood sugar" to "glucose",
        "creatinine" to "creatinine", "urea" to "urea", "bun" to "bun", "blood urea nitrogen" to "bun",
        "haemoglobin" to "haemoglobin", "hemoglobin" to "hemoglobin", "hb" to "haemoglobin", "albumin" to "albumin",
        "bilirubin" to "bilirubin", "lactate" to "lactate", "tsh" to "tsh", "hba1c" to "hba1c", "paco2" to "paco2",
        "pco2" to "paco2", "pao2" to "pao2", "po2" to "pao2", "ph" to "ph", "inr" to "inr",
    )

    // MARK: a small regex helper

    /** One match: its groups (null for a group that took no part), and its UTF-16 start and end. */
    data class Found(val groups: List<String?>, val start: Int, val end: Int)

    private val compiled = HashMap<String, Pattern?>()

    @Synchronized private fun regex(pattern: String, caseless: Boolean): Pattern? {
        val key = (if (caseless) "i:" else "c:") + pattern
        if (compiled.containsKey(key)) return compiled[key]
        val flags = if (caseless) Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE else 0
        val re = runCatching { Pattern.compile(pattern, flags) }.getOrNull()
        if (compiled.size > 600) compiled.clear()
        compiled[key] = re
        return re
    }

    fun find(pattern: String, text: String, caseless: Boolean = false): List<Found> {
        val re = regex(pattern, caseless) ?: return emptyList()
        val m = re.matcher(text)
        val out = mutableListOf<Found>()
        while (m.find()) {
            val groups = (0..m.groupCount()).map { m.group(it) }
            out += Found(groups, m.start(), m.end())
        }
        return out
    }

    fun matches(pattern: String, text: String): Boolean = find(pattern, text).isNotEmpty()

    fun number(s: String): Double = s.replace(",", "").toDoubleOrNull() ?: 0.0

    /** Swift's `.whitespaces`: spaces and tabs, not line breaks. */
    internal fun trimSpaces(s: String): String = s.trim { it.isWhitespace() && it != '\n' && it != '\r' }

    /** Sentences: at a line break, or after . ! ? ; and a space (so 0.5 mg is one). */
    fun sentences(text: String): List<String> {
        val out = mutableListOf<String>()
        var from = 0
        for (cut in find("""\n|(?<=[.!?;])\s+""", text)) {
            out += text.substring(from, cut.start)
            from = cut.end
        }
        out += text.substring(from)
        return out.map(::trimSpaces).filter { it.isNotEmpty() }
    }
}
