package com.stethoscore.app.exam

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.cbrt
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sqrt

// A port of ios/RedPen/Shared/WardPocket.swift: the bedside formulas
// a student meets on the wards and in the exam - body size, the anion gap,
// corrected calcium and sodium, osmolality, the A-a gradient, kidney
// function, MAP, QTc, maintenance fluids, a child's weight, a unit converter
// and MELD-Na. The scores are in WardPocketScores.kt.
//
// For learning only: every screen that shows these says so. The coefficients
// are the published ones, each cited beside its formula, and checked against
// worked examples in WardPocketTest. Pure Kotlin.

object WardPocket {
    /** The line every Ward pocket screen carries. */
    const val disclaimer: String = "For learning only — not for patient care"

    /** A longer form of it, for the foot of a calculator or score. */
    const val disclaimerDetail: String = "Built to help you learn how these are worked out and what they mean. It is not a medical device: never use it to make decisions about a real patient."

    /**
     * [x] with [places] decimals ("7.25"), as iOS's String(format: "%.2f"):
     * the double's exact value rounded half to even, so the two platforms
     * print the same digits.
     */
    fun format(x: Double, places: Int): String {
        if (!x.isFinite()) return "—"
        val text = BigDecimal(x).setScale(places, RoundingMode.HALF_EVEN).toPlainString()
        // C keeps the sign of a negative number that rounds to zero ("-0")
        return if (x < 0 && !text.startsWith("-")) "-$text" else text
    }

    /** The material for "Practise this": New set writes exam questions from it. */
    fun practiceNotes(calc: WardCalc): String {
        val lines = ArrayList<String>()
        lines.add("Write exam questions that test ${calc.title.lowercase()}: when it is used, how it is worked out from a vignette's numbers, and what the result means for the next step.")
        lines.add("How it is worked out: " + calc.formula)
        if (calc.note.isNotEmpty()) lines.add(calc.note)
        lines.add("Source: " + calc.source)
        return lines.joinToString("\n\n")
    }
}

/** Swift's rounded(): to the nearest whole number, halves away from zero. */
internal fun swiftRounded(x: Double): Double = if (x < 0) -floor(-x + 0.5) else floor(x + 0.5)

// units

/**
 * A quantity whose unit is not the same in SI and US conventional units.
 * Values are kept in SI; [usPerSI] is how many US units make one SI unit.
 */
data class WardUnit(val si: String, val us: String, val usPerSI: Double) {

    fun name(us: Boolean): String = if (us) this.us else si

    /** A value typed in the unit shown, as SI. */
    fun toSI(value: Double, us: Boolean): Double = if (us) value / usPerSI else value

    /** An SI value in the unit shown. */
    fun fromSI(value: Double, us: Boolean): Double = if (us) value * usPerSI else value

    companion object {
        /** A unit that reads the same in both systems. */
        fun plain(unit: String): WardUnit = WardUnit(unit, unit, 1.0)

        // Molar masses: glucose 180.16 g/mol, creatinine 113.12, calcium 40.08,
        // cholesterol 386.65, triolein 885.7, bilirubin 584.66; urea nitrogen is
        // two nitrogens, 28.014 mg per mmol of urea (BUN).
        val glucose = WardUnit("mmol/L", "mg/dL", 18.016)
        val creatinine = WardUnit("µmol/L", "mg/dL", 1 / 88.42)
        val urea = WardUnit("mmol/L urea", "mg/dL BUN", 2.8014)
        val calcium = WardUnit("mmol/L", "mg/dL", 4.008)
        val cholesterol = WardUnit("mmol/L", "mg/dL", 38.67)
        val triglycerides = WardUnit("mmol/L", "mg/dL", 88.57)
        val bilirubin = WardUnit("µmol/L", "mg/dL", 1 / 17.1)
        val albumin = WardUnit("g/L", "g/dL", 0.1)
        /** Sodium, chloride, bicarbonate: the same number, a different name. */
        val electrolyte = WardUnit("mmol/L", "mEq/L", 1.0)
        /** Blood gas tensions: 1 kPa = 7.50062 mmHg. */
        val gas = WardUnit("kPa", "mmHg", 7.50062)
    }
}

/** The unit converter's substances. */
@Suppress("EnumEntryName")
enum class WardSubstance(val rawValue: Int) {
    glucose(0), creatinine(1), urea(2), calcium(3), cholesterol(4), triglycerides(5);

    val title: String get() = when (this) {
        glucose -> "Glucose"
        creatinine -> "Creatinine"
        urea -> "Urea / BUN"
        calcium -> "Calcium"
        cholesterol -> "Cholesterol"
        triglycerides -> "Triglycerides"
    }

    val unit: WardUnit get() = when (this) {
        glucose -> WardUnit.glucose
        creatinine -> WardUnit.creatinine
        urea -> WardUnit.urea
        calcium -> WardUnit.calcium
        cholesterol -> WardUnit.cholesterol
        triglycerides -> WardUnit.triglycerides
    }

    companion object {
        fun from(raw: Int): WardSubstance? = entries.firstOrNull { it.rawValue == raw }
    }
}

// the formulas

/** Each formula in the units it was published in. */
object WardFormula {

    /** Body mass index, kg/m². */
    fun bmi(weightKg: Double, heightCm: Double): Double {
        val metres = heightCm / 100
        return weightKg / (metres * metres)
    }

    /** The WHO adult class of a BMI (WHO Technical Report Series 894, 2000). */
    fun bmiClass(bmi: Double): String {
        if (bmi < 18.5) return "Underweight (below 18.5)"
        if (bmi < 25) return "Healthy weight (18.5–24.9)"
        if (bmi < 30) return "Overweight (25–29.9)"
        if (bmi < 35) return "Obesity class I (30–34.9)"
        if (bmi < 40) return "Obesity class II (35–39.9)"
        return "Obesity class III (40 or more)"
    }

    /** Body surface area, m²: Mosteller, sqrt(height cm x weight kg / 3600). Mosteller RD. N Engl J Med 1987;317:1098. */
    fun bsaMosteller(weightKg: Double, heightCm: Double): Double = sqrt(heightCm * weightKg / 3600)

    /** Anion gap, Na - (Cl + HCO3), without potassium. */
    fun anionGap(sodium: Double, chloride: Double, bicarbonate: Double): Double = sodium - (chloride + bicarbonate)

    /**
     * The gap corrected for a low albumin: + 0.25 for each g/L of albumin
     * below 40 (2.5 per g/dL below 4.0). Figge J et al. Crit Care Med
     * 1998;26:1807; 40 g/L is the reference MDCalc and most teaching use.
     */
    fun albuminCorrectedGap(gap: Double, albuminGL: Double): Double = gap + 0.25 * (40 - albuminGL)

    /** Adjusted calcium, mmol/L: Ca + 0.02 x (40 - albumin g/L) (Payne RB et al. BMJ 1973;4:643, simplified). */
    fun correctedCalcium(calciumMmol: Double, albuminGL: Double): Double = calciumMmol + 0.02 * (40 - albuminGL)

    /**
     * Sodium corrected for hyperglycaemia: + [factor] mmol/L for each 100
     * mg/dL of glucose above 100. Katz 1973 (1.6); Hillier 1999 (2.4). No
     * correction at a glucose of 100 mg/dL (5.6 mmol/L) or below.
     */
    fun correctedSodium(sodium: Double, glucoseMgdl: Double, factor: Double): Double {
        val excess = maxOf(0.0, glucoseMgdl - 100)
        return sodium + factor * excess / 100
    }

    /** Calculated serum osmolality, mOsm/kg: 2Na + glucose + urea, all in mmol/L. Dorwart WV, Chalmers L. Clin Chem 1975;21:190. */
    fun osmolality(sodium: Double, glucoseMmol: Double, ureaMmol: Double): Double = 2 * sodium + glucoseMmol + ureaMmol

    /** Alveolar oxygen, mmHg, from the alveolar gas equation at sea level: FiO2 x (760 - 47) - PaCO2 / 0.8. */
    fun alveolarO2(fio2: Double, paco2: Double): Double = fio2 * (760 - 47) - paco2 / 0.8

    /** The A-a gradient, mmHg. */
    fun aaGradient(fio2: Double, pao2: Double, paco2: Double): Double = alveolarO2(fio2, paco2) - pao2

    /** The usual bedside estimate of the upper limit of a normal A-a gradient breathing air, mmHg: age / 4 + 4. */
    fun expectedAaGradient(age: Double): Double = age / 4 + 4

    /** Creatinine clearance, mL/min: (140 - age) x weight / (72 x Cr mg/dL), x 0.85 for a woman. Cockcroft DW, Gault MH. Nephron 1976;16:31. */
    fun cockcroftGault(age: Double, weightKg: Double, creatinineMgdl: Double, female: Boolean): Double {
        val men = (140 - age) * weightKg / (72 * creatinineMgdl)
        return if (female) men * 0.85 else men
    }

    /**
     * eGFR, mL/min/1.73 m², by the race-free CKD-EPI creatinine equation
     * (2021). Inker LA et al. N Engl J Med 2021;385:1737.
     */
    fun ckdEpi2021(age: Double, creatinineMgdl: Double, female: Boolean): Double {
        val kappa = if (female) 0.7 else 0.9
        val alpha = if (female) -0.241 else -0.302
        val ratio = creatinineMgdl / kappa
        val low = minOf(ratio, 1.0).pow(alpha)
        val high = maxOf(ratio, 1.0).pow(-1.200)
        val aging = 0.9938.pow(age)
        val sex = if (female) 1.012 else 1.0
        return 142 * low * high * aging * sex
    }

    /** The KDIGO 2012 GFR category. */
    fun gfrCategory(gfr: Double): String {
        if (gfr >= 90) return "G1: normal or high (90 or more)"
        if (gfr >= 60) return "G2: mildly decreased (60–89)"
        if (gfr >= 45) return "G3a: mildly to moderately decreased (45–59)"
        if (gfr >= 30) return "G3b: moderately to severely decreased (30–44)"
        if (gfr >= 15) return "G4: severely decreased (15–29)"
        return "G5: kidney failure (below 15)"
    }

    /** Mean arterial pressure, mmHg: DBP + (SBP - DBP) / 3. */
    fun meanArterialPressure(systolic: Double, diastolic: Double): Double = diastolic + (systolic - diastolic) / 3

    /** QTc, ms, by Bazett: QT / sqrt(RR in s). Bazett HC. Heart 1920;7:353. */
    fun qtcBazett(qtMs: Double, heartRate: Double): Double {
        val rr = 60 / heartRate
        return qtMs / sqrt(rr)
    }

    /** QTc, ms, by Fridericia: QT / cube root(RR in s). Fridericia LS. Acta Med Scand 1920;53:469. */
    fun qtcFridericia(qtMs: Double, heartRate: Double): Double {
        val rr = 60 / heartRate
        return qtMs / cbrt(rr)
    }

    /** Maintenance fluid, mL/h, by the 4-2-1 rule. Holliday MA, Segar WE. Pediatrics 1957;19:823. */
    fun maintenancePerHour(weightKg: Double): Double {
        val first = minOf(weightKg, 10.0)
        val second = minOf(maxOf(weightKg - 10, 0.0), 10.0)
        val rest = maxOf(weightKg - 20, 0.0)
        return 4 * first + 2 * second + rest
    }

    /** The same rule per day, mL: 100 / 50 / 20 mL/kg/day. */
    fun maintenancePerDay(weightKg: Double): Double {
        val first = minOf(weightKg, 10.0)
        val second = minOf(maxOf(weightKg - 10, 0.0), 10.0)
        val rest = maxOf(weightKg - 20, 0.0)
        return 100 * first + 50 * second + 20 * rest
    }

    /**
     * A child's weight, kg, by the APLS formulas (APLS 5th edition, 2011):
     * 0-12 months (0.5 x months) + 4; 1-5 years (2 x years) + 8; 6-12 years
     * (3 x years) + 7. Null past 12 years. Whole completed years are used.
     */
    fun childWeight(ageMonths: Double): Double? {
        if (!(ageMonths >= 0)) return null
        if (ageMonths <= 12) return 0.5 * ageMonths + 4
        val years = floor(ageMonths / 12)
        if (years <= 5) return 2 * years + 8
        if (years <= 12) return 3 * years + 7
        return null
    }

    /** Which APLS formula [childWeight] used. */
    fun childWeightRule(ageMonths: Double): String {
        if (ageMonths <= 12) return "0–12 months: (0.5 × age in months) + 4"
        val years = floor(ageMonths / 12)
        if (years <= 5) return "1–5 years: (2 × age in years) + 8"
        return "6–12 years: (3 × age in years) + 7"
    }

    /** MELD and MELD-Na. */
    data class Meld(val meld: Double, val meldNa: Double)

    /**
     * MELD and MELD-Na as UNOS/OPTN computed them from January 2016 to July
     * 2023 (OPTN policy 9.1; Kim WR et al. N Engl J Med 2008;359:1018).
     * Bilirubin, INR and creatinine below 1 count as 1; creatinine is capped
     * at 4, and set to 4 after dialysis twice in the past week; sodium is
     * held between 125 and 137. The result is a whole number from 6 to 40.
     */
    fun meld(bilirubinMgdl: Double, inr: Double, creatinineMgdl: Double, sodium: Double, dialysis: Boolean): Meld {
        val bili = maxOf(bilirubinMgdl, 1.0)
        val clot = maxOf(inr, 1.0)
        val cr = if (dialysis) 4.0 else minOf(maxOf(creatinineMgdl, 1.0), 4.0)
        val na = minOf(maxOf(sodium, 125.0), 137.0)
        val a = 0.957 * ln(cr)
        val b = 0.378 * ln(bili)
        val c = 1.120 * ln(clot)
        val raw = a + b + c + 0.643
        val initial = swiftRounded(raw * 10) / 10 * 10
        var withNa = initial
        if (initial > 11) {
            val gap = 137 - na
            withNa = initial + 1.32 * gap - 0.033 * initial * gap
        }
        val meld = minOf(maxOf(swiftRounded(initial), 6.0), 40.0)
        val meldNa = minOf(maxOf(swiftRounded(withNa), 6.0), 40.0)
        return Meld(meld, meldNa)
    }

    /** Three-month mortality by MELD, hospitalised patients (Wiesner R et al. Gastroenterology 2003;124:91). */
    fun meldMortality(score: Double): String {
        if (score <= 9) return "9 or less: about 1.9% three-month mortality"
        if (score <= 19) return "10–19: about 6.0% three-month mortality"
        if (score <= 29) return "20–29: about 19.6% three-month mortality"
        if (score <= 39) return "30–39: about 52.6% three-month mortality"
        return "40 or more: about 71.3% three-month mortality"
    }
}

// the calculators

/** How one input on a calculator is entered. */
sealed class WardFieldKind {
    /** A number, typed in the unit shown and kept in SI. */
    data class Number(val unit: WardUnit) : WardFieldKind()
    /** Yes or no, kept as 1 or 0. */
    object Toggle : WardFieldKind()
    /** One of these, kept as its index. */
    data class Choice(val options: List<String>) : WardFieldKind()
}

/** One input on a calculator. Left empty, an [optional] one still lets the calculator give what it can. */
data class WardField(val id: String, val label: String, val kind: WardFieldKind, val optional: Boolean = false)

/** One line of a calculator's answer: "Anion gap", "18 mmol/L". */
data class WardLine(val label: String, val value: String)

/** A calculator's answer: its numbers, and what they mean. */
data class WardOutcome(val lines: List<WardLine>, val verdict: String?)

/** The Ward pocket's calculators. MELD-Na is listed with the scores. */
@Suppress("EnumEntryName")
enum class WardCalc(val rawValue: String) {
    bodySize("bodySize"), anionGap("anionGap"), calcium("calcium"), sodium("sodium"), osmolality("osmolality"),
    aaGradient("aaGradient"), crcl("crcl"), egfr("egfr"), map("map"), qtc("qtc"),
    fluids("fluids"), childWeight("childWeight"), convert("convert"), meldNa("meldNa");

    val id: String get() = rawValue

    val title: String get() = when (this) {
    bodySize -> "BMI and body surface area"
    anionGap -> "Anion gap"
    calcium -> "Corrected calcium"
    sodium -> "Corrected sodium for glucose"
    osmolality -> "Osmolality and osmolar gap"
    aaGradient -> "A\u2013a gradient"
    crcl -> "Creatinine clearance (Cockcroft\u2013Gault)"
    egfr -> "eGFR (CKD-EPI 2021)"
    map -> "Mean arterial pressure"
    qtc -> "QTc (Bazett and Fridericia)"
    fluids -> "Maintenance fluids (4-2-1)"
    childWeight -> "Child\u2019s weight from age"
    convert -> "Unit converter"
    meldNa -> "MELD-Na"
    }

    /** iOS's SF Symbol name; the screen draws the nearest Material icon. */
    val symbol: String get() = when (this) {
    bodySize -> "figure.stand"
    anionGap, osmolality -> "drop.halffull"
    calcium, sodium -> "testtube.2"
    aaGradient -> "lungs"
    crcl, egfr -> "cross.vial"
    map -> "heart"
    qtc -> "waveform.path.ecg"
    fluids -> "ivfluid.bag"
    childWeight -> "figure.and.child.holdinghands"
    convert -> "arrow.left.arrow.right"
    meldNa -> "list.number"
    }

    val fields: List<WardField> get() = when (this) {
        bodySize -> listOf(weight, height)
        anionGap -> listOf(salt("na", "Sodium"), salt("cl", "Chloride"), salt("hco3", "Bicarbonate"),
            WardField("alb", "Albumin", WardFieldKind.Number(WardUnit.albumin), optional = true))
        calcium -> listOf(WardField("ca", "Total calcium", WardFieldKind.Number(WardUnit.calcium)),
            WardField("alb", "Albumin", WardFieldKind.Number(WardUnit.albumin)))
        sodium -> listOf(salt("na", "Sodium"), WardField("glu", "Glucose", WardFieldKind.Number(WardUnit.glucose)))
        osmolality -> listOf(salt("na", "Sodium"), WardField("glu", "Glucose", WardFieldKind.Number(WardUnit.glucose)),
            WardField("urea", "Urea", WardFieldKind.Number(WardUnit.urea)),
            WardField("measured", "Measured osmolality", WardFieldKind.Number(WardUnit.plain("mOsm/kg")), optional = true))
        aaGradient -> listOf(WardField("fio2", "FiO₂", WardFieldKind.Number(WardUnit.plain("%"))),
            WardField("pao2", "PaO₂", WardFieldKind.Number(WardUnit.gas)),
            WardField("paco2", "PaCO₂", WardFieldKind.Number(WardUnit.gas)),
            WardField("age", "Age", WardFieldKind.Number(WardUnit.plain("years")), optional = true))
        crcl -> listOf(age, weight, female, creatinine)
        egfr -> listOf(age, female, creatinine)
        map -> listOf(WardField("sbp", "Systolic", WardFieldKind.Number(WardUnit.plain("mmHg"))),
            WardField("dbp", "Diastolic", WardFieldKind.Number(WardUnit.plain("mmHg"))))
        qtc -> listOf(WardField("qt", "QT interval", WardFieldKind.Number(WardUnit.plain("ms"))),
            WardField("hr", "Heart rate", WardFieldKind.Number(WardUnit.plain("/min"))), female)
        fluids -> listOf(weight)
        childWeight -> listOf(WardField("age", "Age", WardFieldKind.Number(WardUnit.plain(""))),
            WardField("per", "Age in", WardFieldKind.Choice(listOf("Months", "Years"))))
        convert -> listOf(WardField("what", "Substance", WardFieldKind.Choice(WardSubstance.entries.map { it.title })),
            WardField("dir", "Direction", WardFieldKind.Choice(listOf("SI → US", "US → SI"))),
            WardField("value", "Value", WardFieldKind.Number(WardUnit.plain(""))))
        meldNa -> listOf(WardField("bili", "Bilirubin", WardFieldKind.Number(WardUnit.bilirubin)),
            WardField("inr", "INR", WardFieldKind.Number(WardUnit.plain(""))), creatinine,
            salt("na", "Sodium"),
            WardField("dialysis", "Dialysis twice (or 24 h CVVHD) in the past week", WardFieldKind.Toggle))
    }

    /** The formula in words, as shown under "How it is worked out". */
    val formula: String get() = when (this) {
    bodySize -> "BMI = weight (kg) \u00F7 height (m)\u00B2. BSA (Mosteller) = \u221A(height cm \u00D7 weight kg \u00F7 3600)."
    anionGap -> "Anion gap = Na \u2212 (Cl + HCO\u2083). Albumin-corrected gap = gap + 0.25 \u00D7 (40 \u2212 albumin g/L), or + 2.5 \u00D7 (4.0 \u2212 albumin g/dL)."
    calcium -> "Adjusted Ca (mmol/L) = Ca + 0.02 \u00D7 (40 \u2212 albumin g/L); in US units Ca (mg/dL) + 0.8 \u00D7 (4.0 \u2212 albumin g/dL)."
    sodium -> "Corrected Na = Na + 1.6 \u00D7 (glucose mg/dL \u2212 100) \u00F7 100 (Katz), or with 2.4 in place of 1.6 (Hillier). 100 mg/dL is 5.6 mmol/L."
    osmolality -> "Calculated osmolality = 2 \u00D7 Na + glucose + urea (all mmol/L), or 2 \u00D7 Na + glucose \u00F7 18 + BUN \u00F7 2.8 (mg/dL). Osmolar gap = measured \u2212 calculated."
    aaGradient -> "PAO\u2082 = FiO\u2082 \u00D7 (760 \u2212 47) \u2212 PaCO\u2082 \u00F7 0.8 (mmHg, sea level). A\u2013a gradient = PAO\u2082 \u2212 PaO\u2082. Upper limit of normal on air \u2248 age \u00F7 4 + 4 mmHg."
    crcl -> "CrCl (mL/min) = (140 \u2212 age) \u00D7 weight (kg) \u00F7 (72 \u00D7 creatinine mg/dL), \u00D7 0.85 if female."
    egfr -> "eGFR = 142 \u00D7 min(Scr/\u03BA, 1)^\u03B1 \u00D7 max(Scr/\u03BA, 1)^\u22121.200 \u00D7 0.9938^age \u00D7 1.012 if female, with Scr in mg/dL; \u03BA = 0.7 (female) or 0.9 (male), \u03B1 = \u22120.241 (female) or \u22120.302 (male)."
    map -> "MAP = diastolic + (systolic \u2212 diastolic) \u00F7 3."
    qtc -> "RR (s) = 60 \u00F7 heart rate. Bazett QTc = QT \u00F7 \u221ARR. Fridericia QTc = QT \u00F7 \u221BRR."
    fluids -> "4 mL/kg/h for the first 10 kg, 2 mL/kg/h for the next 10 kg, 1 mL/kg/h for every kg above 20 (per day: 100, 50 and 20 mL/kg)."
    childWeight -> "APLS: 0\u201312 months (0.5 \u00D7 months) + 4; 1\u20135 years (2 \u00D7 years) + 8; 6\u201312 years (3 \u00D7 years) + 7."
    convert -> "Glucose 1 mmol/L = 18.016 mg/dL; creatinine 1 mg/dL = 88.42 \u00B5mol/L; urea 1 mmol/L = 2.8014 mg/dL BUN; calcium 1 mmol/L = 4.008 mg/dL; cholesterol 1 mmol/L = 38.67 mg/dL; triglycerides 1 mmol/L = 88.57 mg/dL."
    meldNa -> "MELD(i) = 0.957 \u00D7 ln(Cr) + 0.378 \u00D7 ln(bilirubin) + 1.120 \u00D7 ln(INR) + 0.643, rounded to the tenth and \u00D7 10 (mg/dL; values below 1 count as 1; Cr at most 4, and 4 after dialysis). If MELD(i) > 11: MELD-Na = MELD(i) + 1.32 \u00D7 (137 \u2212 Na) \u2212 0.033 \u00D7 MELD(i) \u00D7 (137 \u2212 Na), with Na held between 125 and 137."
    }

    /** What to keep in mind, beside the answer. */
    val note: String get() = when (this) {
    bodySize -> "WHO adult classes. NICE lowers the thresholds for people of South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean family background: overweight from 23, obesity from 27.5."
    anionGap -> "Laboratories differ: the classic range without potassium is 8\u201312 mmol/L, and many modern analysers read lower. Each 10 g/L fall in albumin lowers the gap by about 2.5 (Figge); this uses 40 g/L as normal albumin, as MDCalc does, where Figge used 44."
    calcium -> "An estimate: ionised calcium is the measurement when it matters. Many laboratories now report an adjusted calcium with their own formula."
    sodium -> "Katz\u2019s 1.6 is the classic teaching; Hillier found 2.4 a better overall factor: sodium falls more steeply once glucose is above about 400 mg/dL (22 mmol/L)."
    osmolality -> "An osmolar gap above about 10 mOsm/kg suggests an unmeasured osmole: methanol, ethylene glycol, ethanol, mannitol."
    aaGradient -> "Assumes sea level, 37 \u00B0C and a respiratory quotient of 0.8. Enter FiO\u2082 as a percentage (21 on air) or a fraction (0.21)."
    crcl -> "Uses actual body weight, as the original did; many drug references prefer ideal or adjusted weight in obesity. Drug doses are often still labelled by Cockcroft\u2013Gault."
    egfr -> "For adults (18 and over) with a stable creatinine. Race-free: the 2021 equation dropped the race coefficient. Categories are KDIGO 2012."
    map -> "The Surviving Sepsis Campaign (2021) targets a MAP of at least 65 mmHg in septic shock."
    qtc -> "Prolonged: 450 ms or more in men, 460 ms or more in women (AHA/ACCF/HRS 2009); above 500 ms the risk of torsades rises sharply. Bazett over-corrects at fast heart rates, where Fridericia is preferred."
    fluids -> "Holliday\u2013Segar is a paediatric rule. NICE CG174 gives adults 25\u201330 mL/kg/day of water. Real prescriptions also weigh losses, sodium and illness."
    childWeight -> "A rough estimate for when a child cannot be weighed; weigh them as soon as you can."
    convert -> "Urea in mmol/L is urea itself; in US units it is reported as blood urea nitrogen (BUN)."
    meldNa -> "The UNOS/OPTN MELD-Na used for US liver allocation from 2016; MELD 3.0 replaced it in July 2023. For ages 12 and over."
    }

    val source: String get() = when (this) {
    bodySize -> "WHO Technical Report Series 894 (2000); NICE obesity guidance (ethnicity thresholds, 2022); Mosteller RD. N Engl J Med 1987;317:1098."
    anionGap -> "Emmett M, Narins RG. Medicine 1977;56:38; Figge J et al. Crit Care Med 1998;26:1807."
    calcium -> "Payne RB et al. BMJ 1973;4:643 (the simplified formula in common use)."
    sodium -> "Katz MA. N Engl J Med 1973;289:843; Hillier TA et al. Am J Med 1999;106:399."
    osmolality -> "Dorwart WV, Chalmers L. Clin Chem 1975;21:190."
    aaGradient -> "The alveolar gas equation (West, Respiratory Physiology); age estimate as used by MDCalc."
    crcl -> "Cockcroft DW, Gault MH. Nephron 1976;16:31."
    egfr -> "Inker LA et al. N Engl J Med 2021;385:1737; KDIGO CKD guideline 2012."
    map -> "Evans L et al. Surviving Sepsis Campaign guidelines 2021. Intensive Care Med 2021;47:1181."
    qtc -> "Bazett HC. Heart 1920;7:353; Fridericia LS. Acta Med Scand 1920;53:469; Rautaharju PM et al. (AHA/ACCF/HRS) Circulation 2009;119:e241."
    fluids -> "Holliday MA, Segar WE. Pediatrics 1957;19:823; NICE NG29 (2015) and CG174 (2013)."
    childWeight -> "Advanced Life Support Group. Advanced Paediatric Life Support, 5th edition (2011)."
    convert -> "Molar masses; SI conversion factors as in the AMA Manual of Style."
    meldNa -> "Kim WR et al. N Engl J Med 2008;359:1018; OPTN policy 9.1 (2016); Wiesner R et al. Gastroenterology 2003;124:91."
    }

    // working it out

    /**
     * The answer, from values in SI (numbers), 0/1 (toggles) or an index
     * (choices); null while something needed is missing or impossible. [us]
     * chooses the units the answer is written in.
     */
    fun compute(v: Map<String, Double>, us: Boolean): WardOutcome? = when (this) {
        bodySize -> bodySize(v)
        anionGap -> anionGap(v, us)
        calcium -> calcium(v, us)
        sodium -> sodium(v, us)
        osmolality -> osmolality(v)
        aaGradient -> aaGradient(v, us)
        crcl -> crcl(v)
        egfr -> egfr(v)
        map -> map(v)
        qtc -> qtc(v)
        fluids -> fluids(v)
        childWeight -> childWeight(v)
        convert -> convert(v)
        meldNa -> meldNa(v)
    }

    companion object {
        /** Shown in the Calculators tab; MELD-Na is shown in Scores. */
        val calculators: List<WardCalc> get() = entries.filter { it != meldNa }

        fun from(raw: String?): WardCalc? = entries.firstOrNull { it.rawValue == raw }

        private val weight = WardField("wt", "Weight", WardFieldKind.Number(WardUnit.plain("kg")))
        private val height = WardField("ht", "Height", WardFieldKind.Number(WardUnit.plain("cm")))
        private val age = WardField("age", "Age", WardFieldKind.Number(WardUnit.plain("years")))
        private val female = WardField("female", "Female", WardFieldKind.Toggle)
        private val creatinine = WardField("cr", "Creatinine", WardFieldKind.Number(WardUnit.creatinine))

        private fun salt(id: String, label: String): WardField = WardField(id, label, WardFieldKind.Number(WardUnit.electrolyte))

        private fun positive(v: Map<String, Double>, key: String): Double? {
            val x = v[key] ?: return null
            return if (x.isFinite() && x > 0) x else null
        }

        private fun line(label: String, x: Double, places: Int, unit: String): WardLine {
            val number = WardPocket.format(x, places)
            return WardLine(label, if (unit.isEmpty()) number else "$number $unit")
        }

        private fun bodySize(v: Map<String, Double>): WardOutcome? {
            val wt = positive(v, "wt") ?: return null
            val ht = positive(v, "ht") ?: return null
            val bmi = WardFormula.bmi(wt, ht)
            val bsa = WardFormula.bsaMosteller(wt, ht)
            return WardOutcome(listOf(line("BMI", bmi, 1, "kg/m²"), line("Body surface area", bsa, 2, "m²")), WardFormula.bmiClass(bmi))
        }

        private fun anionGap(v: Map<String, Double>, us: Boolean): WardOutcome? {
            val na = positive(v, "na") ?: return null
            val cl = positive(v, "cl") ?: return null
            val hco3 = positive(v, "hco3") ?: return null
            val unit = WardUnit.electrolyte.name(us)
            val gap = WardFormula.anionGap(na, cl, hco3)
            val lines = mutableListOf(line("Anion gap", gap, 0, unit))
            var judged = gap
            val alb = positive(v, "alb")
            if (alb != null) {
                val corrected = WardFormula.albuminCorrectedGap(gap, alb)
                lines.add(line("Corrected for albumin", corrected, 1, unit))
                judged = corrected
            }
            return WardOutcome(lines, gapVerdict(judged))
        }

        /** Against the classic 8-12 range without potassium. */
        fun gapVerdict(gap: Double): String {
            if (gap > 12) return "Raised (above 12): a high anion gap acidosis if the bicarbonate is low — think MUDPILES / GOLDMARK"
            if (gap < 8) return "Low (below 8): hypoalbuminaemia, paraproteins, or a laboratory error"
            return "Within the classic range (8–12)"
        }

        private fun calcium(v: Map<String, Double>, us: Boolean): WardOutcome? {
            val ca = positive(v, "ca") ?: return null
            val alb = positive(v, "alb") ?: return null
            val adjusted = WardFormula.correctedCalcium(ca, alb)
            val shown = WardUnit.calcium.fromSI(adjusted, us)
            val places = if (us) 1 else 2
            return WardOutcome(listOf(line("Adjusted calcium", shown, places, WardUnit.calcium.name(us))), calciumVerdict(adjusted))
        }

        /** Against 2.20-2.60 mmol/L (8.8-10.4 mg/dL). */
        fun calciumVerdict(mmol: Double): String {
            if (mmol < 2.2) return "Low: below 2.20 mmol/L (8.8 mg/dL)"
            if (mmol > 2.6) return "High: above 2.60 mmol/L (10.4 mg/dL)"
            return "Within 2.20–2.60 mmol/L (8.8–10.4 mg/dL)"
        }

        private fun sodium(v: Map<String, Double>, us: Boolean): WardOutcome? {
            val na = positive(v, "na") ?: return null
            val glu = positive(v, "glu") ?: return null
            val mgdl = WardUnit.glucose.fromSI(glu, true)
            val unit = WardUnit.electrolyte.name(us)
            val katz = WardFormula.correctedSodium(na, mgdl, 1.6)
            val hillier = WardFormula.correctedSodium(na, mgdl, 2.4)
            return WardOutcome(listOf(line("Corrected (Katz, 1.6)", katz, 1, unit), line("Corrected (Hillier, 2.4)", hillier, 1, unit)),
                sodiumVerdict(katz))
        }

        fun sodiumVerdict(na: Double): String {
            if (na < 135) return "Below 135: a true hyponatraemia once glucose is allowed for"
            if (na > 145) return "Above 145: hypernatraemic once glucose is allowed for (a free water deficit)"
            return "Within 135–145 once glucose is allowed for"
        }

        private fun osmolality(v: Map<String, Double>): WardOutcome? {
            val na = positive(v, "na") ?: return null
            val glu = positive(v, "glu") ?: return null
            val urea = positive(v, "urea") ?: return null
            val calc = WardFormula.osmolality(na, glu, urea)
            val lines = mutableListOf(line("Calculated osmolality", calc, 0, "mOsm/kg"))
            var verdict = if (calc < 275) "Calculated value below 275: hypo-osmolar"
                else if (calc > 295) "Calculated value above 295: hyperosmolar" else "Calculated value within 275–295"
            val measured = positive(v, "measured")
            if (measured != null) {
                val gap = measured - calc
                lines.add(line("Osmolar gap", gap, 0, "mOsm/kg"))
                verdict = if (gap > 10) "Osmolar gap above 10: look for an unmeasured osmole (toxic alcohols, ethanol, mannitol)"
                    else "Osmolar gap 10 or less: no unmeasured osmole suggested"
            }
            return WardOutcome(lines, verdict)
        }

        private fun aaGradient(v: Map<String, Double>, us: Boolean): WardOutcome? {
            val typedFiO2 = positive(v, "fio2") ?: return null
            val pao2 = positive(v, "pao2") ?: return null
            val paco2 = positive(v, "paco2") ?: return null
            // 0.21 typed as a fraction means 21%
            val fio2 = if (typedFiO2 <= 1) typedFiO2 * 100 else typedFiO2
            if (fio2 > 100) return null
            val gas = WardUnit.gas
            val pao2mm = gas.fromSI(pao2, true)
            val paco2mm = gas.fromSI(paco2, true)
            val alveolar = WardFormula.alveolarO2(fio2 / 100, paco2mm)
            val gradient = alveolar - pao2mm
            // worked in mmHg; shown in kPa for SI
            val scale = if (us) 1.0 else 1 / gas.usPerSI
            val places = if (us) 0 else 1
            val name = gas.name(us)
            val lines = mutableListOf(line("Alveolar O₂ (PAO₂)", alveolar * scale, places, name),
                line("A–a gradient", gradient * scale, places, name))
            var verdict: String? = null
            val age = positive(v, "age")
            if (age != null) {
                val upper = WardFormula.expectedAaGradient(age)
                lines.add(line("Expected on air, up to", upper * scale, places, name))
                verdict = if (fio2 > 21.5) "The age estimate is for air; on added oxygen the normal gradient is wider"
                    else if (gradient > upper) "Raised for age: V/Q mismatch, shunt or a diffusion defect"
                    else "Normal for age: hypoxaemia, if any, is from hypoventilation or low inspired oxygen"
            }
            // a PaO2 above the alveolar value cannot happen: a typing slip
            if (gradient < -1) verdict = "PaO₂ is above the alveolar value, which is impossible: check the FiO₂ and the units"
            return WardOutcome(lines, verdict)
        }

        private fun crcl(v: Map<String, Double>): WardOutcome? {
            val age = positive(v, "age") ?: return null
            if (age >= 140) return null
            val wt = positive(v, "wt") ?: return null
            val cr = positive(v, "cr") ?: return null
            val mgdl = WardUnit.creatinine.fromSI(cr, true)
            val female = (v["female"] ?: 0.0) > 0.5
            val clearance = WardFormula.cockcroftGault(age, wt, mgdl, female)
            return WardOutcome(listOf(line("Creatinine clearance", clearance, 0, "mL/min")), null)
        }

        private fun egfr(v: Map<String, Double>): WardOutcome? {
            val age = positive(v, "age") ?: return null
            val cr = positive(v, "cr") ?: return null
            val mgdl = WardUnit.creatinine.fromSI(cr, true)
            val female = (v["female"] ?: 0.0) > 0.5
            val gfr = WardFormula.ckdEpi2021(age, mgdl, female)
            val verdict = if (age < 18) "For adults only: children need a paediatric equation (bedside Schwartz)"
                else WardFormula.gfrCategory(swiftRounded(gfr))
            return WardOutcome(listOf(line("eGFR", gfr, 0, "mL/min/1.73 m²")), verdict)
        }

        private fun map(v: Map<String, Double>): WardOutcome? {
            val sbp = positive(v, "sbp") ?: return null
            val dbp = positive(v, "dbp") ?: return null
            if (sbp < dbp) return null
            val pressure = WardFormula.meanArterialPressure(sbp, dbp)
            val verdict = if (pressure < 65) "Below 65 mmHg: under the usual target in septic shock" else "65 mmHg or more"
            return WardOutcome(listOf(line("MAP", pressure, 0, "mmHg")), verdict)
        }

        private fun qtc(v: Map<String, Double>): WardOutcome? {
            val qt = positive(v, "qt") ?: return null
            val hr = positive(v, "hr") ?: return null
            val female = (v["female"] ?: 0.0) > 0.5
            val bazett = WardFormula.qtcBazett(qt, hr)
            val fridericia = WardFormula.qtcFridericia(qt, hr)
            return WardOutcome(listOf(line("QTc, Bazett", bazett, 0, "ms"), line("QTc, Fridericia", fridericia, 0, "ms")),
                qtcVerdict(swiftRounded(bazett), female))
        }

        /** AHA/ACCF/HRS 2009: prolonged at 450 ms or more (men), 460 or more (women); above 500 ms, a high risk of torsades. */
        fun qtcVerdict(qtc: Double, female: Boolean): String {
            val limit = if (female) 460.0 else 450.0
            if (qtc > 500) return "Above 500 ms (Bazett): markedly prolonged, a high risk of torsades de pointes"
            if (qtc >= limit) return "Prolonged (Bazett): ${WardPocket.format(limit, 0)} ms or more"
            return "Not prolonged (Bazett)"
        }

        private fun fluids(v: Map<String, Double>): WardOutcome? {
            val wt = positive(v, "wt") ?: return null
            val hourly = WardFormula.maintenancePerHour(wt)
            val daily = WardFormula.maintenancePerDay(wt)
            val low = WardPocket.format(wt * 25, 0)
            val high = WardPocket.format(wt * 30, 0)
            return WardOutcome(listOf(line("4-2-1 rule", hourly, 0, "mL/h"), line("100-50-20 rule", daily, 0, "mL/day"),
                WardLine("Adult water (NICE, 25–30 mL/kg/day)", "$low–$high mL/day")), null)
        }

        private fun childWeight(v: Map<String, Double>): WardOutcome? {
            val age = v["age"] ?: return null
            if (!(age >= 0) || !age.isFinite()) return null
            val inYears = (v["per"] ?: 0.0) > 0.5
            val months = if (inYears) age * 12 else age
            val kg = WardFormula.childWeight(months) ?: return WardOutcome(emptyList(), "The APLS formulas stop at 12 years")
            return WardOutcome(listOf(line("Estimated weight", kg, 1, "kg")), WardFormula.childWeightRule(months))
        }

        private fun convert(v: Map<String, Double>): WardOutcome? {
            val value = v["value"] ?: return null
            if (!value.isFinite() || value < 0) return null
            val index = (v["what"] ?: 0.0).toInt()
            val substance = WardSubstance.from(index) ?: return null
            val toUS = (v["dir"] ?: 0.0) < 0.5
            val unit = substance.unit
            val out = if (toUS) unit.fromSI(value, true) else unit.toSI(value, true)
            val places = if (out >= 100) 0 else if (out >= 10) 1 else 2
            val from = unit.name(!toUS)
            val to = unit.name(toUS)
            val head = WardPocket.format(value, if (value >= 100) 0 else 2) + " " + from
            return WardOutcome(listOf(line(head, out, places, to)), null)
        }

        private fun meldNa(v: Map<String, Double>): WardOutcome? {
            val bili = positive(v, "bili") ?: return null
            val inr = positive(v, "inr") ?: return null
            val cr = positive(v, "cr") ?: return null
            val na = positive(v, "na") ?: return null
            val dialysis = (v["dialysis"] ?: 0.0) > 0.5
            val biliMg = WardUnit.bilirubin.fromSI(bili, true)
            val crMg = WardUnit.creatinine.fromSI(cr, true)
            val result = WardFormula.meld(biliMg, inr, crMg, na, dialysis)
            return WardOutcome(listOf(line("MELD", result.meld, 0, ""), line("MELD-Na", result.meldNa, 0, "")),
                WardFormula.meldMortality(result.meldNa))
        }
    }
}
