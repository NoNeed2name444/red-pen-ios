package com.stethoscore.app.accuracy

import java.util.regex.Pattern
import kotlin.math.abs
import kotlin.math.max

/**
 * The accuracy engine's rule checks: deterministic, free, offline.
 *
 * A model can miss a wrong dose; a table cannot. These catch what needs no
 * judgement - a dose far outside anything the drug is given at, a lab value
 * that cannot exist in the unit it is written in, an explanation naming a
 * different answer from the key - and they are signals for the accuracy
 * model, not verdicts.
 *
 * A port of iOS Shared/Accuracy/AccuracyRules.swift, itself a port of
 * server/accuracy-rules.js: the same item has to get the same hits on every
 * platform. The tables are the server's, written out as text. Patterns run
 * with Unicode classes and case, as ICU's (NSRegularExpression) do.
 */
object AccuracyRules {

    data class Hit(val rule: String, /** "severe" or "minor" */ val severity: String, val detail: String) {
        val isSevere: Boolean get() = severity == "severe"
    }

    // MARK: the tables (the same as the server's)

    // BEGIN DRUGS
    const val drugTable: String = """
        paracetamol=80:4000;acetaminophen=80:4000;ibuprofen=200:3200;aspirin=75:4000;naproxen=220:1500;
        amoxicillin=125:6000;co-amoxiclav=250:3600;ceftriaxone=50:4000;vancomycin=125:4000;
        ciprofloxacin=100:1500;doxycycline=20:200;azithromycin=250:2000;clarithromycin=250:1000;
        metronidazole=200:4000;nitrofurantoin=50:400;trimethoprim=100:400;benzylpenicillin=300:14400;
        flucloxacillin=250:8000;metformin=250:3000;gliclazide=30:320;atorvastatin=10:80;simvastatin=5:80;
        rosuvastatin=5:40;pravastatin=10:80;lisinopril=2.5:80;ramipril=1.25:10;enalapril=2.5:40;
        losartan=12.5:150;candesartan=2:32;amlodipine=2.5:10;nifedipine=5:120;bisoprolol=1.25:20;
        metoprolol=5:400;atenolol=25:100;propranolol=10:320;furosemide=10:1000;bumetanide=0.5:10;
        spironolactone=12.5:400;bendroflumethiazide=1.25:5;hydrochlorothiazide=6.25:100;warfarin=0.5:15;
        apixaban=2.5:20;rivaroxaban=2.5:30;dabigatran=75:300;clopidogrel=75:600;ticagrelor=60:180;
        digoxin=0.0625:1.5;levothyroxine=0.0125:0.3;carbimazole=5:60;propylthiouracil=50:1200;morphine=1:200;
        oxycodone=2.5:160;codeine=15:240;tramadol=50:400;fentanyl=0.012:0.8;naloxone=0.04:10;
        adrenaline=0.01:1;epinephrine=0.01:1;atropine=0.1:5;adenosine=3:18;amiodarone=50:1200;
        prednisolone=1:100;prednisone=1:100;methylprednisolone=4:1000;dexamethasone=0.5:40;
        hydrocortisone=5:500;diazepam=1:40;lorazepam=0.25:10;midazolam=0.5:20;haloperidol=0.5:20;
        olanzapine=2.5:20;quetiapine=25:800;sertraline=25:200;fluoxetine=10:80;citalopram=10:40;
        amitriptyline=10:150;lithium=100:2400;phenytoin=50:2000;sodium valproate=100:2500;
        levetiracetam=250:3000;carbamazepine=100:1600;lamotrigine=25:500;ondansetron=2:32;
        metoclopramide=5:30;omeprazole=10:80;lansoprazole=15:60;allopurinol=50:900;colchicine=0.3:2;
        alteplase=0.5:100;tranexamic acid=250:4000;enoxaparin=20:200;salbutamol=0.1:10;albuterol=0.1:10;
        ipratropium=0.02:0.5;magnesium sulfate=1000:6000;magnesium sulphate=1000:6000;
        calcium gluconate=500:3000;acetazolamide=125:1000;mannitol=12500:100000;sildenafil=20:100;
        finasteride=1:5;tamsulosin=0.4:0.8;methotrexate=2.5:30;
        """
    // END DRUGS

    // BEGIN LABS
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

    private data class Entry(val name: String, val values: List<Double>)

    private fun entries(table: String): List<Entry> {
        val flat = table.replace("\n", "")
        val out = mutableListOf<Entry>()
        for (raw in flat.split(";")) {
            val entry = raw.trimSpaces()
            val eq = entry.lastIndexOf('=')
            if (eq < 0) continue
            // the tables write "/" as "~" and separate numbers with ":"
            val name = entry.substring(0, eq).replace("~", "/")
            val values = entry.substring(eq + 1).split(":").mapNotNull { it.toDoubleOrNull() }
            out += Entry(name, values)
        }
        return out
    }

    /** drug -> [lowest sensible dose, highest single dose or daily total], mg. */
    val drugs: Map<String, List<Double>> by lazy { entries(drugTable).associate { it.name to it.values } }

    /** analyte -> unit -> [plausible low, plausible high, reference low, reference high]. */
    val labs: Map<String, Map<String, List<Double>>> by lazy {
        val out = linkedMapOf<String, LinkedHashMap<String, List<Double>>>()
        for (entry in entries(labTable)) {
            val parts = entry.name.split("|")
            if (parts.size != 2) continue
            out.getOrPut(parts[0]) { linkedMapOf() }[parts[1]] = entry.values
        }
        out
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

    val mass: Map<String, Double> = mapOf(
        "g" to 1000.0, "mg" to 1.0, "mcg" to 0.001, "µg" to 0.001, "ug" to 0.001, "microgram" to 0.001, "micrograms" to 0.001,
        "ng" to 0.000001, "gram" to 1000.0, "grams" to 1000.0, "milligram" to 1.0, "milligrams" to 1.0,
    )

    val nonAnswers: List<String> = listOf("all of the above", "none of the above", "all of these", "none of these")

    // MARK: a small regex helper

    data class Found(val groups: List<String?>, val start: Int, val end: Int)

    private val compiled = HashMap<String, Pattern>()

    private fun regex(pattern: String, caseless: Boolean): Pattern? = synchronized(compiled) {
        val key = (if (caseless) "i:" else "c:") + pattern
        compiled[key]?.let { return it }
        val flags = Pattern.UNICODE_CHARACTER_CLASS or (if (caseless) Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE else 0)
        val re = runCatching { Pattern.compile(pattern, flags) }.getOrNull() ?: return null
        if (compiled.size > 600) compiled.clear()
        compiled[key] = re
        re
    }

    fun find(pattern: String, text: String, caseless: Boolean = false): List<Found> {
        val re = regex(pattern, caseless) ?: return emptyList()
        val m = re.matcher(text)
        val out = mutableListOf<Found>()
        while (m.find()) {
            out += Found((0..m.groupCount()).map { m.group(it) }, m.start(), m.end())
        }
        return out
    }

    fun matches(pattern: String, text: String): Boolean = find(pattern, text).isNotEmpty()

    fun esc(s: String): String = Pattern.quote(s)

    fun number(s: String): Double = s.replace(",", "").toDoubleOrNull() ?: 0.0

    private fun tail(text: String, from: Int): String = if (from < text.length) text.substring(from) else ""

    // MARK: reading doses and values

    data class Dose(val drug: String, val mg: Double, val said: String)
    data class LabValue(val analyte: String, val name: String, val value: Double, val unit: String, val said: String, val fluid: String = "")

    const val doseUnit: String = "(g|mg|mcg|µg|ug|ng|micrograms?|milligrams?|grams?)"

    fun doses(text: String): List<Dose> {
        val t = text.lowercase().replace("μ", "µ")
        val out = mutableListOf<Dose>()
        // per kilogram, minute or hour is a rate; per mL or litre a concentration
        val perRate = "^\\s*(/|per\\s+)(kg|min|minute|h|hr|hour|m2|m²|ml|l\\b|dl|litre|liter)"
        // "serum digoxin level, which is 3.7 ng" is a level, not a dose
        val measured = "\\b(?:level|levels|concentration|serum|plasma|blood|trough|peak)\\b"
        for (drug in drugs.keys.sorted()) {
            if (!t.contains(drug)) continue
            val name = esc(drug)
            // no comma, "and" or other drug between the name and the number
            val after = "\\b" + name + "\\b([^.;,\\n\\d]{0,25}?)(\\d+(?:[.,]\\d+)?)\\s*" + doseUnit + "\\b"
            val before = "(\\d+(?:[.,]\\d+)?)\\s*" + doseUnit + "\\b\\s+(?:of\\s+)?(?:iv\\s+|oral\\s+|im\\s+)?" + name + "\\b"
            for ((pattern, isAfter) in listOf(after to true, before to false)) {
                for (m in find(pattern, t)) {
                    if (matches(perRate, tail(t, m.end))) continue
                    // a combination product's strength belongs to no one drug alone
                    if (matches("^\\s*/\\s*\\d", tail(t, m.end))) continue
                    if (isAfter) {
                        val beforeText = t.substring(0, m.start)
                        val afterName = tail(t, m.start + drug.length)
                        if (matches("[-/]$", beforeText) || matches("^[-/][a-z]", afterName)) continue
                        val gap = m.groups[1] ?: ""
                        if (matches(measured, m.groups[0] ?: "") || matches("\\b(?:and|or|with|plus|then|vs|versus)\\b", gap)) continue
                        if (drugs.keys.any { it != drug && gap.contains(it) }) continue
                    }
                    val valueGroup = if (isAfter) 2 else 1
                    val value = m.groups[valueGroup] ?: continue
                    val unit = m.groups[valueGroup + 1] ?: continue
                    val factor = mass[unit] ?: continue
                    val said = (m.groups[0] ?: "").trimSpaces()
                    out += Dose(drug, number(value) * factor, said)
                }
            }
        }
        return out
    }

    private fun alternation(keys: Collection<String>): String =
        keys.sortedWith { a, b -> if (a.length != b.length) b.length - a.length else a.compareTo(b) }.joinToString("|") { esc(it) }

    fun labValues(text: String): List<LabValue> {
        val t = text.lowercase().replace("μ", "µ")
        val names = alternation(labNames.keys)
        val units = alternation(unitAliases.keys)
        val pattern = "(?:^|[^a-z0-9-])(" + names + ")(?![a-z0-9])\\s*(?:level|concentration|of|is|was|:|=|\\s)*\\s*(\\d+(?:\\.\\d+)?)\\s*(" + units + ")?(?![a-z0-9/])"
        val out = mutableListOf<LabValue>()
        for (m in find(pattern, t)) {
            val name = m.groups[1] ?: continue
            val analyte = labNames[name] ?: continue
            val raw = m.groups[2] ?: continue
            val unit = m.groups[3]?.let { unitAliases[it] } ?: ""
            val unitless = labs[analyte]?.get("") != null
            if (unit.isEmpty() && !unitless) continue
            if (unit.isEmpty() && name.length <= 2 && analyte != "ph") continue
            val said = (m.groups[0] ?: "").trim()
            out += LabValue(analyte, name, number(raw), unit, said, fluidBefore(t, m.start))
        }
        return out
    }

    /**
     * The body fluid a result belongs to: the nearest fluid word before it in
     * the last 200 characters. The reference table is for blood, so a result
     * from anything else is not judged against it. "" when nothing says.
     */
    const val fluidWords: String = """\b(serum|plasma|blood|arterial|venous|abg|urine|urinary|urinalysis|dipstick|gastric|stomach|vaginal|stool|f(?:a)?ecal|csf|cerebrospinal|lumbar puncture|spinal fluid|pleural|ascitic|peritoneal|synovial|sweat|saliva|semen|cement|dentin|enamel|solution|buffer|skin)\b"""
    val bloodWords: Set<String> = setOf("serum", "plasma", "blood", "arterial", "venous", "abg")

    fun fluidBefore(t: String, at: Int): String {
        val from = max(0, at - 200)
        val window = t.substring(from, minOf(t.length, at + 1))
        val w = find(fluidWords, window).lastOrNull()?.groups?.get(1) ?: return ""
        return if (w in bloodWords) "blood" else w
    }

    private data class StatedRange(val analyte: String, val lo: Double, val hi: Double, val unit: String)

    private fun statedRanges(text: String): List<StatedRange> {
        val t = text.lowercase().replace("μ", "µ").replace("–", "-").replace("—", "-")
        val names = alternation(labNames.keys)
        val units = alternation(unitAliases.keys)
        val pattern = "(?:normal|reference)\\s+(?:serum\\s+|plasma\\s+|blood\\s+)?(" + names + ")(?![a-z0-9])[^\\d\\n]{0,25}?(\\d+(?:\\.\\d+)?)\\s*(?:-|to)\\s*(\\d+(?:\\.\\d+)?)\\s*(" + units + ")?"
        return find(pattern, t).mapNotNull { m ->
            val name = m.groups[1] ?: return@mapNotNull null
            val analyte = labNames[name] ?: return@mapNotNull null
            val lo = m.groups[2] ?: return@mapNotNull null
            val hi = m.groups[3] ?: return@mapNotNull null
            val unit = m.groups[4]?.let { unitAliases[it] } ?: ""
            StatedRange(analyte, number(lo), number(hi), unit)
        }
    }

    // MARK: questions

    /**
     * The key an explanation opens with, as exam banks write it: "Ans-a.",
     * "Answer- A.", "Ans: B.", "Ans. is 'd' i.e.", "Ans (c)". The letter must
     * be marked off, so "Answer is a combination" is not read as option A.
     */
    const val keyLead: String = """^\W{0,3}ans(?:wer)?\b\.?\s*(?:is\b\.?)?\s*[:\-–—=]?\s*(?:is\b\.?\s*)?(?:option\s*)?(?:['"‘’“”(\[]\s*([a-j])\s*['"‘’“”)\]]|([a-j])(?=\s*[.,:;)\-–—]|\s*$))"""

    /** Which option the explanation plainly says is right, if any. */
    fun explainedAnswer(explanation: String, options: List<String>): Int? {
        find(keyLead, explanation, caseless = true).firstOrNull()?.let { lead ->
            val l = (lead.groups[1] ?: lead.groups[2])?.uppercase()
            if (!l.isNullOrEmpty()) {
                val i = l[0].code - 65
                if (i >= 0 && i < options.size) return i
            }
        }
        val byLetter = find("\\b(?:correct\\s+(?:answer|option|choice)|the\\s+answer|answer)\\s*(?:is|:)\\s*(?:option\\s*)?\\(?([A-J])\\)?(?![A-Za-z0-9])", explanation) +
            find("\\b(?:option|choice)\\s*\\(?([A-J])\\)?\\s+is\\s+(?:the\\s+)?(?:correct|right|best)\\b", explanation, caseless = true)
        byLetter.lastOrNull()?.groups?.get(1)?.uppercase()?.let { l ->
            if (l.isNotEmpty()) {
                val i = l[0].code - 65
                if (i >= 0 && i < options.size) return i
            }
        }
        val le = explanation.lowercase()
        for ((i, option) in options.withIndex()) {
            val o = option.lowercase().trimSpaces()
            if (o.length < 4 || o in nonAnswers) continue
            val eo = esc(o)
            val a = "(?:correct|right|best)\\s+(?:answer|option|choice)\\s+is\\s+$eo(?![a-z])"
            val b = "(?:^|[^a-z])$eo\\s+is\\s+(?:the\\s+)?(?:correct|right|best)\\s+(?:answer|option|choice)"
            if (matches("$a|$b", le)) return i
        }
        return null
    }

    private fun normalised(s: String): String {
        val lower = s.lowercase().replace("−", "-").replace("–", "-")
        val out = StringBuilder()
        var gap = false
        for (ch in lower) {
            // everything but spaces, ASCII punctuation and markdown kept: signs,
            // arrows and Greek letters
            val keep = !ch.isWhitespace() && ".,;:!?()[]{}\"'`|_/\\*#".indexOf(ch) < 0
            if (keep) {
                if (gap && out.isNotEmpty()) out.append(' ')
                out.append(ch)
                gap = false
            } else {
                gap = true
            }
        }
        return out.toString()
    }

    private fun fmt(x: Double): String {
        if (x >= 1) {
            val r = Math.round(x * 100) / 100.0
            return if (r % 1.0 == 0.0) r.toLong().toString() else swiftDouble(r)
        }
        return swiftDouble(x)
    }

    /** A Double as Swift's String(Double) writes it (shortest round-trip, no exponent for ordinary sizes). */
    private fun swiftDouble(x: Double): String {
        val s = x.toString()
        if (!s.contains('E')) return s
        return java.math.BigDecimal(s).toPlainString()
    }

    const val negatedStem: String = "\\b(?:NOT|EXCEPT)\\b|\\bleast\\s+likely\\b|\\bis\\s+false\\b|\\bincorrect\\s+statement\\b|\\bfalse\\s+statement\\b"

    /** What an item asserts as true: a question's stem, its keyed answer and its explanation; anything else's text. */
    fun assertedText(item: AccuracyItem): String {
        if (item.kind != AccuracyKind.mcq) return item.text.trim()
        val key = if (item.key in item.options.indices) item.options[item.key] else ""
        return (item.stem + "\n" + key + "\n" + item.explanation).trim()
    }

    /** Every rule hit for one item. */
    fun hits(item: AccuracyItem): List<Hit> {
        val out = mutableListOf<Hit>()
        val add: (String, String, String) -> Unit = { rule, severity, detail -> out += Hit(rule, severity, detail.take(160)) }
        if (item.kind == AccuracyKind.mcq) questionHits(item, add)
        val text = item.checkedText

        for (said in notation(text)) add("dose-notation", "minor", said)
        // what the item asserts, not a question's distractors: they are wrong on purpose
        val judged = assertedText(item)
        for (said in lookAlike(judged)) add("look-alike-drug", "severe", said)
        for (old in superseded(item)) add("outdated-practice", old.severity, old.says)
        for (d in doses(judged)) {
            val range = drugs[d.drug] ?: continue
            if (range.size != 2) continue
            val lo = range[0]; val hi = range[1]
            val span = fmt(lo) + "–" + fmt(hi) + " mg"
            if (d.mg > hi * 2 || d.mg < lo / 5) {
                add("dose-range", "severe", d.said + ": outside any usual dose of " + d.drug + " (" + span + ").")
            } else if (d.mg > hi || d.mg < lo) {
                add("dose-range", "minor", d.said + ": unusual for " + d.drug + " (" + span + ").")
            }
        }
        for (v in labValues(judged)) {
            // judged only as blood: a pH needs to be said to be blood's
            if (v.fluid.isNotEmpty() && v.fluid != "blood") continue
            if (v.analyte == "ph" && v.fluid != "blood") continue
            val ranges = labs[v.analyte] ?: continue
            val r = ranges[v.unit]
            if (r == null) {
                if (v.unit.contains("/") && v.name.length > 2) {
                    add("lab-unit", "minor", v.said + ": " + v.analyte + " is not reported in " + v.unit + ".")
                }
                continue
            }
            if (v.value < r[0] || v.value > r[1]) {
                val unitName = v.unit.ifEmpty { "these units" }
                add("lab-implausible", "severe", v.said + ": not a possible " + v.analyte + " in " + unitName + " (wrong unit?).")
            }
        }
        for (s in statedRanges(judged)) {
            val table = labs[s.analyte] ?: continue
            // a range written without a unit is right if it is right in any
            // unit the analyte is reported in, as the server does
            val candidates: List<Pair<String, List<Double>>> = if (s.unit.isEmpty()) orderedRanges(s.analyte)
                else table[s.unit]?.let { listOf(s.unit to it) } ?: emptyList()
            if (candidates.isEmpty()) continue
            if (candidates.any { !off(s.lo, it.second[2]) && !off(s.hi, it.second[3]) }) continue
            val named = s.unit.isNotEmpty() || candidates.size > 1
            val should = candidates.joinToString(" or ") { "${fmt(it.second[2])}–${fmt(it.second[3])}" + if (named) " " + it.first else "" }
            val said = "${fmt(s.lo)}–${fmt(s.hi)}"
            add("reference-range", "severe", "Normal ${s.analyte} is about $should, not $said.")
        }
        val t = judged.lowercase()
        for (name in labNames.values.toSet().sorted()) {
            val n = esc(name)
            val up = matches("\\b$n\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:increased|elevated|raised|high)\\b", t)
            val down = matches("\\b$n\\s+(?:is\\s+|are\\s+|level\\s+is\\s+)?(?:decreased|reduced|low|lowered)\\b", t)
            if (up && down) add("direction-conflict", "minor", "$name is said to be both raised and lowered.")
        }
        return out
    }

    /** Every unit an analyte is reported in, in the order the table lists them. */
    private fun orderedRanges(analyte: String): List<Pair<String, List<Double>>> {
        val out = mutableListOf<Pair<String, List<Double>>>()
        for (line in labTable.replace("\n", "").split(";")) {
            val entry = line.trimSpaces()
            val eq = entry.lastIndexOf('=')
            if (entry.startsWith("$analyte|") && eq >= 0) {
                val head = entry.substring(0, eq)
                val unit = head.drop(analyte.length + 1).replace("~", "/")
                labs[analyte]?.get(unit)?.let { out += unit to it }
            }
        }
        return out
    }

    // MARK: dose notation and look-alike drugs

    data class NotationRule(val pattern: String, val caseless: Boolean, val says: String)

    /** Notation the Joint Commission's "Do Not Use" list bans because it is misread tenfold or as another word. */
    val notationRules: List<NotationRule> = listOf(
        NotationRule("""\b\d+\.0+\s?(?:mg|mcg|µg|ug|g|ml|units?)(?![\w/])""", true, "drop the trailing zero (\"1.0 mg\" is read as 10 mg)"),
        NotationRule("""(?<![\w.])\.\d+\s?(?:mg|mcg|µg|ug|g|ml|units?)(?![\w/])""", true, "write a leading zero (\".5 mg\" is read as 5 mg)"),
        NotationRule("""\b\d+(?:\.\d+)?\s?U(?![\w/])""", false, "write \"units\" (\"U\" is misread as 0 or 4)"),
        NotationRule("""(?<![A-Za-z])(?:QD|QOD|q\.d\.|q\.o\.d\.)(?![A-Za-z])""", false, "write \"daily\" or \"every other day\" (\"QD\" is misread as QID)"),
    )

    fun notation(text: String): List<String> {
        val out = mutableListOf<String>()
        for (rule in notationRules) {
            for (f in find(rule.pattern, text, rule.caseless)) {
                val said = text.substring(f.start, f.end).trimSpaces()
                out += "\"" + said + "\": " + rule.says + "."
            }
        }
        return out
    }

    data class Drug(val name: String, val uses: List<String>)

    /**
     * Look-alike, sound-alike pairs from the ISMP list, each drug with what it
     * is for: a drug said to be for its partner's use, and not its own, is the
     * classic swap (hydroxyzine for hypertension).
     */
    val lookAlikePairs: List<Pair<Drug, Drug>> = listOf(
        Drug("hydralazine", listOf("hypertension", "high blood pressure", "pre-eclampsia", "preeclampsia", "eclampsia", "heart failure")) to
            Drug("hydroxyzine", listOf("anxiety", "pruritus", "itch", "urticaria", "allerg", "sedation")),
        Drug("clonidine", listOf("hypertension", "high blood pressure", "adhd", "attention deficit", "hot flush", "hot flash")) to
            Drug("clonazepam", listOf("seizure", "epilep", "panic")),
        Drug("metformin", listOf("diabetes", "diabetic", "hyperglyc", "polycystic ovar", "pcos")) to
            Drug("metronidazole", listOf("anaerob", "bacterial vaginosis", "trichomon", "clostridi", "c. diff", "amoeb", "ameb", "giardia", "h. pylori", "helicobacter")),
        Drug("lamotrigine", listOf("epilep", "seizure", "bipolar")) to Drug("lamivudine", listOf("hiv", "hepatitis b", "hbv")),
        Drug("risperidone", listOf("schizophren", "psychos", "bipolar", "mania", "autis", "irritability")) to Drug("ropinirole", listOf("parkinson", "restless leg")),
        Drug("tramadol", listOf("pain", "analges")) to Drug("trazodone", listOf("depress", "insomnia", "sleep")),
        Drug("chlorpromazine", listOf("schizophren", "psychos", "nausea", "vomiting", "hiccup")) to Drug("chlorpropamide", listOf("diabetes", "diabetic", "hyperglyc")),
        Drug("sulfasalazine", listOf("ulcerative colitis", "crohn", "rheumatoid arthritis", "inflammatory bowel")) to Drug("sulfadiazine", listOf("toxoplasm", "burn")),
    )

    private const val useCue: String = """\b(?:for|to treat|treats|treating|treatment of|indicated for|indicated in|used for|used in|management of)\b"""
    private const val negated: String = """\b(?:not|never|no)\b"""

    fun lookAlike(text: String): List<String> {
        val t = text.lowercase()
        val out = mutableListOf<String>()
        for ((first, second) in lookAlikePairs) {
            for ((me, partner) in listOf(first to second, second to first)) {
                for (f in find("\\b" + esc(me.name) + "\\b", t)) {
                    // the rest of this sentence, at most 90 characters
                    var end = f.end
                    while (end < t.length && end - f.start < 90) {
                        if (".;!?\n".indexOf(t[end]) >= 0) break
                        end += 1
                    }
                    val span = t.substring(f.end, end)
                    val cue = find(useCue, span).firstOrNull() ?: continue
                    val before = span.substring(0, cue.start)
                    val after = span.substring(cue.end)
                    if (matches(negated, before) || before.contains(partner.name) || after.contains(partner.name)) continue
                    val mentions: (String) -> Boolean = { use -> matches("\\b" + esc(use), after) }
                    val wrong = partner.uses.firstOrNull(mentions)
                    if (wrong != null && !me.uses.any(mentions)) {
                        val said = cue.groups.firstOrNull() ?: "for"
                        out += me.name + " " + said + " " + wrong + "…: that is what " + partner.name + " is for; check the name (look-alike drugs)."
                    }
                }
            }
        }
        return out
    }

    // MARK: retired practice

    /** Abbreviations spelled out before matching, case and all, so "PEA" is the rhythm and not the vegetable. */
    val expand: List<Pair<String, String>> = listOf(
        """\bPEA\b""" to "pulseless electrical activity",
        """\bMONA\b""" to "morphine oxygen nitrates aspirin",
        """\bHES\b""" to "hydroxyethyl starch",
        """\bACS\b""" to "acute coronary syndrome",
        """\b(?:N?STE)?MI\b""" to "myocardial infarction",
        """\bO2\b""" to "oxygen",
        """\bICU\b""" to "intensive care",
        """\bAKI\b""" to "acute kidney injury",
        """\b[Nn]ot vigorous\b""" to "non-vigorous",
    )

    data class Retired(val id: String, val severity: String, val cue: String, val context: List<String>, val unless: String?, val says: String)

    /** Practice current guidance has retired, with what replaced it and where that was decided. */
    val retired: List<Retired> = listOf(
        Retired("atropine-arrest", "severe", """\batropine\b""",
            listOf("""\basystole\b|pulseless electrical activity|\bnon-?shockable\b|cardiac arrest"""),
            """bradycardi|heart block|\bav block|organophosphate|secretions|premedicat""",
            "Atropine is no longer used in asystole or PEA (AHA and ERC since 2010): adrenaline and CPR."),
        Retired("adult-cpr-15-2", "severe", """\b15\s*:\s*2\b|\b15 compressions? (?:to|and|:) 2 (?:rescue )?breaths\b""",
            listOf("""\badults?\b"""),
            """child|infant|paediatric|pediatric|neonat|newborn|bab(?:y|ies)""",
            "Adult CPR is 30 compressions to 2 breaths (AHA and ERC since 2005); 15:2 is for children with two rescuers."),
        Retired("ipecac", "severe", """\bipecac(?:uanha)?\b""",
            listOf("""poison|overdose|ingest|toxic|vomit|emesis|decontaminat"""), null,
            "Ipecac is no longer given for poisoning (AACT/EAPCCT 2004): no proven benefit, and it delays charcoal."),
        Retired("starch-fluids", "severe", """hydroxy-?ethyl ?starch|\b(?:heta|tetra|penta)starch\b|\bvoluven\b""",
            listOf("""resuscitat|sepsis|septic|shock|hypovol|fluid|volume|colloid"""), null,
            "Starch fluids raised deaths and dialysis in sepsis (6S trial, NEJM 2012): use crystalloids."),
        Retired("renal-dose-dopamine", "severe", """\b(?:renal|low)[- ]dose dopamine\b|\bdopamine\b[^.;]{0,40}\b(?:renal|kidney) (?:protect|dose)""",
            listOf("""prevent|protect|treat|\bused\b|\bgiven\b|oliguri|acute kidney injury|renal failure|management|indicated|urine output"""), null,
            "Low-dose dopamine does not protect the kidneys (ANZICS trial, Lancet 2000)."),
        Retired("dextropropoxyphene", "severe", """\b(?:dextro)?propoxyphene\b|\bco-?proxamol\b|\bdistalgesic\b""",
            listOf("""analges|\bpain\b|prescri|\btreat|\bgiven\b|\bused\b|indicated|drug of choice|first[- ]line"""),
            """overdose|toxicity|poison""",
            "Dextropropoxyphene was withdrawn (EU 2009, US 2010) for fatal heart-rhythm toxicity."),
        Retired("tight-icu-glucose", "severe", """\b8[01]\s*(?:-|–|to|and)\s*1(?:08|10)\s*mg\s*/\s*dl\b|\b4\.[45]\s*(?:-|–|to|and)\s*6\.[01]\s*mmol""",
            listOf("""intensive care|critically ill|critical illness|ventilated|septic|sepsis"""), null,
            "Tight ICU glucose targets raised deaths (NICE-SUGAR, NEJM 2009): aim for 140–180 mg/dL (7.8–10 mmol/L)."),
        Retired("prophylactic-lidocaine", "severe", """\b(?:prophylactic|routine)(?:ally)?\s+(?:iv\s+)?(?:lidocaine|lignocaine)\b|\b(?:lidocaine|lignocaine)\b[^.;]{0,40}\bprophyla""",
            listOf("""myocardial infarction|acute coronary syndrome|heart attack"""), null,
            "Prophylactic lidocaine after MI is not recommended: no benefit, and a trend to more deaths."),
        Retired("mona", "minor", """\bmorphine,? oxygen,? nitrates?,? (?:and )?aspirin\b""",
            emptyList(), null,
            "MONA is outdated: oxygen only if SpO2 is under 90%, morphine with caution (ESC ACS guideline 2023)."),
        Retired("routine-oxygen-acs", "minor", """\b(?:all|every|routine(?:ly)?|regardless)\b[^.;]{0,60}\boxygen\b|\boxygen\b[^.;]{0,60}\b(?:all|every|routine(?:ly)?|regardless)\b""",
            listOf("""acute coronary syndrome|myocardial infarction|chest pain|heart attack"""),
            """hypox|saturation|spo2|\bsats\b|below|under|less than|<|\bif\b|unless|\bwhen\b|morphine,? oxygen,? nitrates""",
            "Oxygen is for ACS with SpO2 under 90%, not routinely (ESC 2023; DETO2X-AMI, NEJM 2017)."),
        Retired("ranitidine", "minor", """\branitidine\b""",
            listOf("""\btreat|\bgive\b|\bgiven\b|prescri|used (?:for|in|to)|drug of choice|first[- ]line|management|indicated"""), null,
            "Ranitidine was withdrawn in the US and EU in 2020 (NDMA impurity); famotidine is the usual H2 blocker."),
        Retired("bed-rest-back-pain", "minor", """\bbed[- ]?rest\b""",
            listOf("""back pain|lumbago|sciatica"""), null,
            "Low back pain: stay active rather than rest in bed (NICE NG59)."),
        Retired("meconium-suction", "minor", """\bintubat\w*|tracheal suction\w*|suction\w* (?:below the cords|the trachea)""",
            listOf("""meconium""", """\ball\b|routine|every|non-?vigorous|immediately|should|must"""), null,
            "Routine tracheal suction of non-vigorous meconium-stained babies is no longer advised: ventilate (AHA 2015)."),
    )

    /** A sentence that says the practice is no longer done is teaching the change. */
    const val retiredSaid: String = """\b(?:not|no longer|never|avoid(?:ed)?|abandon(?:ed)?|obsolete|outdated|out of date|removed|withdrawn|discouraged|replaced|superseded|previously|formerly|historically|used to be|once used|was once|old(?:er)? (?:guidelines?|teaching|practi[cs]e)|myth|harmful|contraindicated|stopped|ineffective|banned|discontinued|dropped|abolished|(?:isn|aren|don|doesn|didn|wasn|weren)['’]t)\b|\bno (?:role|benefit|place|evidence|use|longer)\b"""

    /** Words just before the practice that set it aside; after it they would promote it, so they only count before. */
    const val setAsideBefore: String = """\b(?:rather than|instead of|in preference to|preferred (?:to|over)|chosen over|better than|superior to|in place of|unlike|without|not|never|no|avoid(?:ing)?)\s+(?:[a-z0-9-]+\s+){0,3}$"""

    /** Sentences: at a line break, or after . ! ? ; and a space (so 0.5 mg is one). */
    fun sentences(text: String): List<String> {
        val out = mutableListOf<String>()
        var from = 0
        for (cut in find("""\n|(?<=[.!?;])\s+""", text)) {
            out += text.substring(from, cut.start)
            from = cut.end
        }
        out += text.substring(from)
        return out.map { it.trimSpaces() }.filter { it.isNotEmpty() }
    }

    fun spelled(s: String): String {
        var t = s
        for ((pattern, words) in expand) {
            val re = regex(pattern, caseless = false) ?: continue
            t = re.matcher(t).replaceAll(java.util.regex.Matcher.quoteReplacement(words))
        }
        return t.lowercase()
    }

    data class Superseded(val id: String, val severity: String, val says: String)

    /**
     * Retired practice an item teaches, one hit per practice. A question's
     * keyed answer is read with its stem at the practice's severity; its
     * explanation's sentences count as minor. Anything else is read sentence
     * by sentence.
     */
    fun superseded(item: AccuracyItem): List<Superseded> {
        val found = mutableListOf<Superseded>()
        fun test(cueIn: String, contextIn: String, excuseIn: String, severity: String?) {
            for (e in retired) {
                val cue = find(e.cue, cueIn).firstOrNull() ?: continue
                if (!e.context.all { matches(it, contextIn) }) continue
                if (e.unless != null && matches(e.unless, contextIn)) continue
                if (matches(retiredSaid, excuseIn)) continue
                if (matches(setAsideBefore, cueIn.substring(0, cue.start))) continue
                val level = severity ?: e.severity
                val at = found.indexOfFirst { it.id == e.id }
                if (at >= 0) {
                    if (found[at].severity != "severe") found[at] = Superseded(e.id, level, e.says)
                } else {
                    found += Superseded(e.id, level, e.says)
                }
            }
        }
        if (item.kind == AccuracyKind.mcq) {
            if (item.key in item.options.indices) {
                val key = spelled(item.options[item.key])
                val stem = sentences(item.stem)
                test(key, spelled(item.stem) + " " + key, spelled(stem.lastOrNull() ?: "") + " " + key, null)
            }
            for (sentence in sentences(item.explanation)) {
                val t = spelled(sentence)
                test(t, t, t, "minor")
            }
        } else {
            for (sentence in sentences(item.text)) {
                val t = spelled(sentence)
                test(t, t, t, null)
            }
        }
        return found
    }

    private fun off(x: Double, y: Double): Boolean = abs(x - y) > max(0.2 * abs(y), 1e-9)

    private fun questionHits(item: AccuracyItem, add: (String, String, String) -> Unit) {
        val options = item.options.map { it.trim() }
        val key = item.key
        val keyed = key in options.indices
        if (!keyed) add("no-key", "severe", "The keyed answer is not one of the options.")
        val seen = HashMap<String, Int>()
        for ((i, o) in options.withIndex()) {
            val n = normalised(o)
            if (n.isEmpty()) continue
            val first = seen[n]
            if (first != null) {
                val severity = if (first == key || i == key) "severe" else "minor"
                add("duplicate-option", severity, "Options " + AccuracyItem.letter(first) + " and " + AccuracyItem.letter(i) + " say the same thing.")
            } else {
                seen[n] = i
            }
        }
        val kinds = options.map { o -> nonAnswers.indexOf(o.lowercase().trimEnd('.', ' ')) }
        val nonIdx = kinds.withIndex().filter { it.value >= 0 }.map { it.index }
        if (nonIdx.any { it != options.size - 1 }) {
            add("non-answer-position", "minor", "\"All/none of the above\" is not the last option.")
        }
        val hasAll = kinds.any { it == 0 || it == 2 }
        val hasNone = kinds.any { it == 1 || it == 3 }
        if (hasAll && hasNone) add("all-and-none", "minor", "Both \"all of the above\" and \"none of the above\" are options.")
        if (!keyed) return

        val keyText = options[key].lowercase()
        val explanation = item.explanation
        val said = explainedAnswer(explanation, options)
        if (said != null && said != key) {
            add("key-explanation-conflict", "severe", "The key is " + AccuracyItem.letter(key) + " but the explanation says " + AccuracyItem.letter(said) + ".")
        }
        val lowerExplanation = explanation.lowercase()
        if (keyText.length >= 4 && keyText !in nonAnswers) {
            val pattern = "(?:^|[^a-z])" + esc(keyText) + "\\s+is\\s+(?:not\\s+(?:the\\s+)?(?:correct|right|answer)|incorrect|wrong)"
            if (matches(pattern, lowerExplanation)) add("key-called-wrong", "severe", "The explanation calls the keyed answer wrong.")
        }
        val negatedStemHit = matches(negatedStem, item.stem)
        if (negatedStemHit && keyText.length >= 4) {
            val pattern = esc(keyText) + "\\s+is\\s+(?:a\\s+)?(?:true|correct|recognised|recognized|typical|characteristic)\\b"
            if (matches(pattern, lowerExplanation)) {
                add("negation-mismatch", "minor", "The stem asks for the exception, but the explanation calls the key true.")
            }
        }
        if (kinds[key] == 0 && hasNone) {
            add("all-above-contradiction", "severe", "\"All of the above\" is keyed although \"none of the above\" is an option.")
        }
        val stemLabs = labValues(item.stem)
        val explanationLabs = labValues(explanation)
        for (a in stemLabs) {
            val b = explanationLabs.firstOrNull { it.analyte == a.analyte && it.unit == a.unit } ?: continue
            if (abs(a.value - b.value) > max(0.05 * abs(a.value), 1e-9)) {
                add("numbers-disagree", "minor", "The stem gives " + a.analyte + " " + fmt(a.value) + " but the explanation says " + fmt(b.value) + ".")
                break
            }
        }
        if (doses(options[key]).isEmpty()) {
            val keyNumber = find("^\\s*(\\d+(?:\\.\\d+)?)\\s*(mg|g|mcg|ml|units?|%)\\b", options[key], caseless = true).firstOrNull()
            val value = keyNumber?.groups?.get(1)
            val unitRaw = keyNumber?.groups?.get(2)
            if (value != null && unitRaw != null) {
                val unit = unitRaw.lowercase()
                val inExplanation = find("(\\d+(?:\\.\\d+)?)\\s*" + esc(unit) + "\\b", lowerExplanation).mapNotNull { it.groups[1]?.let(::number) }
                val first = inExplanation.firstOrNull()
                if (first != null && number(value) !in inExplanation) {
                    val saidKey = (keyNumber.groups[0] ?: "").trimSpaces()
                    add("numbers-disagree", "minor", "The key says " + saidKey + " but the explanation gives " + fmt(first) + " " + unit + ".")
                }
            }
        }
    }

    // MARK: how much of an item its source contains

    val stopwords: Set<String> = setOf(
        "the", "and", "with", "for", "that", "this", "which", "what", "most", "best", "following", "patient",
        "next", "step", "from", "into", "than", "then", "there", "their", "have", "been", "were", "will", "would", "should",
        "these", "those", "also", "over", "under", "about", "after", "before", "other", "answer", "explanation", "keyed",
    )

    fun terms(text: String): Set<String> =
        text.lowercase().split(Regex("[^a-z]+")).filter { it.length >= 4 && it !in stopwords }.toSet()

    /** The share of the item's own vocabulary its source contains; null with no source. */
    fun sourceMatch(item: AccuracyItem): Double? {
        val source = item.source.trim()
        if (source.isEmpty()) return null
        val mine = terms(item.checkedText)
        if (mine.isEmpty()) return 0.0
        val theirs = terms(source)
        return mine.intersect(theirs).size.toDouble() / mine.size
    }

    /** Trims spaces and tabs only, as Swift's `.whitespaces`. */
    private fun String.trimSpaces(): String = trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
}
