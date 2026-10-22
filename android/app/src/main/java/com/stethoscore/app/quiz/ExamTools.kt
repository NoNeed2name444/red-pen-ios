package com.stethoscore.app.quiz

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

// A port of ios/RedPen/Shared/Exam/ExamTools.swift.
//
// The exam screen's own tools, as the real test interfaces have them: the
// stem cut into pieces the highlighter can mark, a basic calculator, and the
// reference ranges printed with the paper. Plain Kotlin, so the logic is
// tested on the JVM (ExamToolsTest).

// MARK: - highlighter

/** A stem in the pieces the highlighter marks: sentences, and a long sentence's clauses, so a finding can be marked without its whole sentence. */
object StemPieces {
    /** Pieces that, joined with nothing between them, give back the stem. */
    fun split(stem: String): List<String> {
        val out = mutableListOf<String>()
        val piece = StringBuilder()
        var length = 0
        val chars = stem
        var i = 0
        while (i < chars.length) {
            val c = chars[i]
            piece.append(c)
            if (!Character.isLowSurrogate(c)) length++
            val next: Char? = if (i + 1 < chars.length) chars[i + 1] else null
            if (isBreak(c, next, length)) {
                // the space after it goes with this piece
                while (i + 1 < chars.length && chars[i + 1] == ' ') {
                    piece.append(' ')
                    i++
                }
                out += piece.toString()
                piece.setLength(0)
                length = 0
            }
            i++
        }
        if (piece.isNotEmpty()) out += piece.toString()
        return out
    }

    private fun isBreak(c: Char, next: Char?, length: Int): Boolean {
        val spaceNext = next == null || next == ' ' || next == '\n'
        if (c == '\n') return true
        if ((c == '.' || c == '?' || c == '!') && spaceNext) return true
        // a clause of a long sentence
        if ((c == ',' || c == ';') && next == ' ' && length >= 40) return true
        return false
    }
}

// MARK: - calculator

/** The exam's basic four-function calculator. */
class ExamCalculator {
    enum class Op(val rawValue: String) { add("+"), subtract("−"), multiply("×"), divide("÷") }

    var display: String = "0"
        private set
    private var stored: Double? = null
    private var pending: Op? = null
    /** True once a result or an operator is showing: the next digit starts afresh. */
    private var fresh: Boolean = true

    val value: Double get() = display.toDoubleOrNull() ?: 0.0
    val pendingOp: Op? get() = pending

    fun digit(d: Int) {
        if (d !in 0..9) return
        if (fresh || display == "0" || display == "Error") {
            display = d.toString()
            fresh = false
        } else if (display.length < 14) {
            display += d.toString()
        }
    }

    fun dot() {
        if (fresh || display == "Error") {
            display = "0."
            fresh = false
        } else if (!display.contains(".")) {
            display += "."
        }
    }

    fun negate() {
        if (display == "0" || display == "Error") return
        display = if (display.startsWith("-")) display.substring(1) else "-$display"
    }

    fun percent() {
        display = format(value / 100)
        fresh = true
    }

    fun op(next: Op) {
        val p = pending
        val s = stored
        if (p != null && s != null && !fresh) {
            display = format(apply(p, s, value))
        }
        stored = if (display == "Error") null else value
        pending = if (display == "Error") null else next
        fresh = true
    }

    fun equals() {
        val p = pending ?: return
        val s = stored ?: return
        display = format(apply(p, s, value))
        pending = null
        stored = null
        fresh = true
    }

    fun clear() {
        display = "0"
        stored = null
        pending = null
        fresh = true
    }

    companion object {
        fun apply(op: Op, a: Double, b: Double): Double = when (op) {
            Op.add -> a + b
            Op.subtract -> a - b
            Op.multiply -> a * b
            Op.divide -> if (b == 0.0) Double.NaN else a / b
        }

        /** Up to ten significant figures, no trailing zeros; "Error" for a division by zero. */
        fun format(x: Double): String {
            if (!x.isFinite()) return "Error"
            if (x == Math.rint(x) && kotlin.math.abs(x) < 1e15) return x.toLong().toString()
            var text = formatG10(x)
            if (text.contains(".") && !text.contains("e")) {
                text = text.trimEnd('0')
                if (text.endsWith(".")) text = text.dropLast(1)
            }
            return text
        }

        /** C's "%.10g", which Swift's String(format:) uses: ten significant figures, scientific below 1e-4 or from 1e10. */
        private fun formatG10(x: Double): String {
            if (x == 0.0) return "0"
            val rounded = BigDecimal(x).round(MathContext(10, RoundingMode.HALF_EVEN))
            val exponent = rounded.precision() - rounded.scale() - 1
            if (exponent < -4 || exponent >= 10) {
                val mantissa = rounded.movePointLeft(exponent).setScale(9, RoundingMode.HALF_EVEN).stripTrailingZeros().toPlainString()
                val sign = if (exponent < 0) "-" else "+"
                val e = kotlin.math.abs(exponent).toString().padStart(2, '0')
                return "${mantissa}e$sign$e"
            }
            return rounded.setScale(maxOf(0, 9 - exponent), RoundingMode.HALF_EVEN).toPlainString()
        }
    }
}

// MARK: - reference ranges

/** One laboratory value's typical adult reference range, in SI units and in US conventional units. */
data class LabRange(val group: String, val name: String, val si: String, val us: String) {
    val id: String get() = "$group/$name"
    fun value(conventional: Boolean): String = if (conventional) us else si
}

/** Which units a track reads its papers in. */
object LabUnits {
    /** USMLE papers use US conventional units (with SI alongside); the UK exams use SI. */
    fun conventional(track: ExamTrack): Boolean = track == ExamTrack.usmle
}

/**
 * The reference ranges, as a paper prints them at the back. Typical adult
 * values; a laboratory's own ranges vary a little and the paper's own list
 * always wins.
 */
object LabRanges {
    const val caveat: String = "Typical adult reference ranges. Laboratories differ slightly; in the exam, use the ranges the paper gives."

    private fun r(group: String, name: String, si: String, us: String) = LabRange(group, name, si, us)

    val groups: List<String> = listOf("Urea and electrolytes", "Liver and bone", "Haematology", "Coagulation",
        "Blood gases", "Endocrine", "Lipids and glucose", "CSF")

    val chemistry: List<LabRange> = listOf(
        r("Urea and electrolytes", "Sodium", "135–145 mmol/L", "135–145 mEq/L"),
        r("Urea and electrolytes", "Potassium", "3.5–5.0 mmol/L", "3.5–5.0 mEq/L"),
        r("Urea and electrolytes", "Chloride", "98–106 mmol/L", "98–106 mEq/L"),
        r("Urea and electrolytes", "Bicarbonate", "22–28 mmol/L", "22–28 mEq/L"),
        r("Urea and electrolytes", "Urea (BUN in the US)", "2.5–7.8 mmol/L", "BUN 7–20 mg/dL"),
        r("Urea and electrolytes", "Creatinine", "53–106 µmol/L", "0.6–1.2 mg/dL"),
        r("Urea and electrolytes", "Magnesium", "0.7–1.0 mmol/L", "1.7–2.4 mg/dL"),
        r("Urea and electrolytes", "Urate", "180–480 µmol/L", "3.0–8.0 mg/dL"),
        r("Urea and electrolytes", "Osmolality (serum)", "275–295 mOsm/kg", "275–295 mOsm/kg"),
        r("Urea and electrolytes", "Lactate", "0.5–2.2 mmol/L", "4.5–19.8 mg/dL"),
        r("Urea and electrolytes", "C-reactive protein", "<5 mg/L", "<0.5 mg/dL"),
        r("Urea and electrolytes", "Amylase", "25–125 U/L", "25–125 U/L"),
    )

    val liver: List<LabRange> = listOf(
        r("Liver and bone", "Bilirubin (total)", "3–17 µmol/L", "0.2–1.0 mg/dL"),
        r("Liver and bone", "ALT", "10–40 U/L", "10–40 U/L"),
        r("Liver and bone", "AST", "10–40 U/L", "10–40 U/L"),
        r("Liver and bone", "Alkaline phosphatase", "30–130 U/L", "25–100 U/L"),
        r("Liver and bone", "Albumin", "35–50 g/L", "3.5–5.0 g/dL"),
        r("Liver and bone", "Total protein", "60–80 g/L", "6.0–8.0 g/dL"),
        r("Liver and bone", "Calcium (adjusted)", "2.20–2.60 mmol/L", "8.8–10.4 mg/dL"),
        r("Liver and bone", "Phosphate", "0.8–1.5 mmol/L", "2.5–4.5 mg/dL"),
    )

    val haematology: List<LabRange> = listOf(
        r("Haematology", "Haemoglobin, men", "130–180 g/L", "13.5–17.5 g/dL"),
        r("Haematology", "Haemoglobin, women", "115–160 g/L", "12.0–16.0 g/dL"),
        r("Haematology", "White cells", "4.0–11.0 ×10⁹/L", "4.0–11.0 ×10³/µL"),
        r("Haematology", "Neutrophils", "2.0–7.5 ×10⁹/L", "2.0–7.5 ×10³/µL"),
        r("Haematology", "Lymphocytes", "1.0–4.0 ×10⁹/L", "1.0–4.0 ×10³/µL"),
        r("Haematology", "Platelets", "150–400 ×10⁹/L", "150–400 ×10³/µL"),
        r("Haematology", "MCV", "80–100 fL", "80–100 fL"),
        r("Haematology", "Reticulocytes", "0.5–2.5%", "0.5–2.5%"),
        r("Haematology", "Ferritin", "15–300 µg/L", "15–300 ng/mL"),
        r("Haematology", "Serum iron", "10–30 µmol/L", "60–170 µg/dL"),
        r("Haematology", "Vitamin B12", "150–660 pmol/L", "200–900 pg/mL"),
        r("Haematology", "ESR", "Men <15, women <20 mm/h", "Men <15, women <20 mm/h"),
    )

    val coagulation: List<LabRange> = listOf(
        r("Coagulation", "Prothrombin time", "11–13.5 s", "11–13.5 s"),
        r("Coagulation", "INR", "0.8–1.2 (2–3 on warfarin for most indications)", "0.8–1.2 (2–3 on warfarin for most indications)"),
        r("Coagulation", "APTT", "25–35 s", "25–35 s"),
        r("Coagulation", "Fibrinogen", "2–4 g/L", "200–400 mg/dL"),
        r("Coagulation", "D-dimer", "<0.5 mg/L FEU", "<500 ng/mL FEU"),
    )

    val gases: List<LabRange> = listOf(
        r("Blood gases", "pH (arterial)", "7.35–7.45", "7.35–7.45"),
        r("Blood gases", "PaO₂ (on air)", "10–13 kPa", "75–100 mmHg"),
        r("Blood gases", "PaCO₂", "4.7–6.0 kPa", "35–45 mmHg"),
        r("Blood gases", "Bicarbonate", "22–28 mmol/L", "22–28 mEq/L"),
        r("Blood gases", "Base excess", "−2 to +2 mmol/L", "−2 to +2 mEq/L"),
        r("Blood gases", "Anion gap (Na − [Cl + HCO₃])", "8–12 mmol/L", "8–12 mEq/L"),
    )

    val endocrine: List<LabRange> = listOf(
        r("Endocrine", "TSH", "0.4–4.0 mU/L", "0.4–4.0 µU/mL"),
        r("Endocrine", "Free T4", "12–22 pmol/L", "0.9–1.7 ng/dL"),
        r("Endocrine", "Cortisol (9 am)", "140–630 nmol/L", "5–23 µg/dL"),
        r("Endocrine", "PTH", "1.1–6.9 pmol/L", "10–65 pg/mL"),
        r("Endocrine", "25-OH vitamin D", ">50 nmol/L sufficient, <25 deficient", "20–50 ng/mL"),
        r("Endocrine", "HbA1c", "20–41 mmol/mol; diabetes ≥48", "4.0–5.6%; diabetes ≥6.5%"),
    )

    val lipids: List<LabRange> = listOf(
        r("Lipids and glucose", "Glucose (fasting)", "3.9–5.5 mmol/L", "70–99 mg/dL"),
        r("Lipids and glucose", "Total cholesterol (desirable)", "<5.0 mmol/L", "<200 mg/dL"),
        r("Lipids and glucose", "LDL cholesterol (desirable)", "<3.0 mmol/L", "<130 mg/dL"),
        r("Lipids and glucose", "HDL cholesterol", ">1.0 mmol/L", ">40 mg/dL"),
        r("Lipids and glucose", "Triglycerides (fasting)", "<1.7 mmol/L", "<150 mg/dL"),
    )

    val csf: List<LabRange> = listOf(
        r("CSF", "Opening pressure", "10–20 cmH₂O", "10–20 cmH₂O"),
        r("CSF", "Protein", "0.15–0.45 g/L", "15–45 mg/dL"),
        r("CSF", "Glucose", "2.8–4.2 mmol/L (about 60% of blood)", "50–75 mg/dL (about 60% of blood)"),
        r("CSF", "White cells", "<5 cells/µL", "<5 cells/µL"),
    )

    val all: List<LabRange> = listOf(chemistry, liver, haematology, coagulation, gases, endocrine, lipids, csf).flatten()

    /** The ranges matching [query] in the name or group, in paper order. */
    fun search(query: String): List<LabRange> {
        val q = AccuracyRules.trimSpaces(query).lowercase()
        if (q.isEmpty()) return all
        return all.filter { it.name.lowercase().contains(q) || it.group.lowercase().contains(q) }
    }
}
