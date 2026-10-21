package com.stethoscore.app.exam

import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.pow

// A port of upstream/ios/RedPen/Tests/WardPocketTests.swift, check for check:
// the Ward pocket's formulas and scores, each against worked examples from the
// original papers or the standard calculators (MDCalc, the NKF eGFR
// calculator, OPTN's MELD policy), with the boundary values where a threshold
// or a band changes. Also: every score's bands cover every total it can reach
// exactly once, and the unit conversions go both ways.
class WardPocketTest {

    private val failures = ArrayList<String>()

    private fun check(label: String, ok: Boolean, detail: String = "") {
        if (!ok) failures.add("$label  | $detail")
    }

    private fun done() = assertTrue(failures.joinToString("\n"), failures.isEmpty())

    private fun near(a: Double?, b: Double, tolerance: Double = 0.05): Boolean = a != null && abs(a - b) <= tolerance

    private fun v(vararg pairs: Pair<String, Number>): Map<String, Double> = pairs.associate { it.first to it.second.toDouble() }

    private fun values(o: WardOutcome?): List<String>? = o?.lines?.map { it.value }

    @Test fun units() {
        check("glucose 180 mg/dL is about 10 mmol/L", near(WardUnit.glucose.toSI(180.0, us = true), 9.99, 0.01))
        check("creatinine 1 mg/dL is 88.4 umol/L", near(WardUnit.creatinine.toSI(1.0, us = true), 88.42, 0.01))
        check("BUN 28 mg/dL is urea 10 mmol/L", near(WardUnit.urea.toSI(28.014, us = true), 10.0, 0.001))
        check("calcium 2.5 mmol/L is 10 mg/dL", near(WardUnit.calcium.fromSI(2.5, us = true), 10.02, 0.01))
        check("cholesterol 5 mmol/L is 193 mg/dL", near(WardUnit.cholesterol.fromSI(5.0, us = true), 193.35, 0.01))
        check("albumin 3.5 g/dL is 35 g/L", near(WardUnit.albumin.toSI(3.5, us = true), 35.0, 0.0001))
        check("bilirubin 17.1 umol/L is 1 mg/dL", near(WardUnit.bilirubin.fromSI(17.1, us = true), 1.0, 0.0001))
        check("PaCO2 5.33 kPa is 40 mmHg", near(WardUnit.gas.fromSI(5.333, us = true), 40.0, 0.01))
        var roundTrips = true
        for (s in WardSubstance.entries) {
            val back = s.unit.toSI(s.unit.fromSI(7.3, us = true), us = true)
            if (abs(back - 7.3) > 1e-9) roundTrips = false
        }
        check("every converter unit goes there and back", roundTrips)
        check("SI values stay as typed in SI", WardUnit.glucose.toSI(5.5, us = false) == 5.5)

        val toUS = WardCalc.convert.compute(v("what" to 0, "dir" to 0, "value" to 10), us = false)
        check("converter: glucose 10 mmol/L -> 180 mg/dL", toUS?.lines?.firstOrNull()?.value == "180 mg/dL", "$toUS")
        val toSI = WardCalc.convert.compute(v("what" to 1, "dir" to 1, "value" to 1.2), us = false)
        check("converter: creatinine 1.2 mg/dL -> 106 umol/L", toSI?.lines?.firstOrNull()?.value == "106 µmol/L", "$toSI")
        done()
    }

    @Test fun bodySize() {
        check("BMI 70 kg, 175 cm = 22.9", near(WardFormula.bmi(70.0, 175.0), 22.86, 0.01))
        check("BSA (Mosteller) 70 kg, 170 cm = 1.82 m2", near(WardFormula.bsaMosteller(70.0, 170.0), 1.818, 0.001))
        check("BMI 18.4 underweight, 18.5 healthy", WardFormula.bmiClass(18.4).startsWith("Underweight") && WardFormula.bmiClass(18.5).startsWith("Healthy"))
        check("BMI 24.9 healthy, 25 overweight", WardFormula.bmiClass(24.9).startsWith("Healthy") && WardFormula.bmiClass(25.0).startsWith("Overweight"))
        check("BMI 30 class I, 35 class II, 40 class III",
            WardFormula.bmiClass(30.0).contains("class I ") && WardFormula.bmiClass(35.0).contains("class II ")
                && WardFormula.bmiClass(40.0).contains("class III"))
        val body = WardCalc.bodySize.compute(v("wt" to 70, "ht" to 175), us = false)
        check("body size shows BMI and BSA", values(body) == listOf("22.9 kg/m²", "1.84 m²"), "$body")
        check("no answer without a height", WardCalc.bodySize.compute(v("wt" to 70), us = false) == null)
        done()
    }

    @Test fun anionGap() {
        check("anion gap 140 - (104 + 24) = 12", WardFormula.anionGap(140.0, 104.0, 24.0) == 12.0)
        check("albumin 20 g/L adds 5 to the gap (Figge)", WardFormula.albuminCorrectedGap(12.0, albuminGL = 20.0) == 17.0)
        check("albumin 40 g/L adds nothing", WardFormula.albuminCorrectedGap(12.0, albuminGL = 40.0) == 12.0)
        check("gap 12 is within range, 13 raised, 7 low",
            WardCalc.gapVerdict(12.0).startsWith("Within") && WardCalc.gapVerdict(13.0).startsWith("Raised") && WardCalc.gapVerdict(7.0).startsWith("Low"))
        val gapUS = WardCalc.anionGap.compute(v("na" to 140, "cl" to 104, "hco3" to 24, "alb" to 20), us = true)
        check("gap in US units says mEq/L and judges the corrected gap",
            values(gapUS) == listOf("12 mEq/L", "17.0 mEq/L") && gapUS?.verdict?.startsWith("Raised") == true, "$gapUS")
        done()
    }

    @Test fun calcium() {
        check("Ca 2.00 mmol/L, albumin 25 g/L -> 2.30 (Payne)", near(WardFormula.correctedCalcium(2.0, 25.0), 2.30, 0.0001))
        val caUS = WardCalc.calcium.compute(mapOf("ca" to WardUnit.calcium.toSI(8.0, us = true),
            "alb" to WardUnit.albumin.toSI(2.0, us = true)), us = true)
        check("Ca 8.0 mg/dL, albumin 2.0 g/dL -> 9.6 mg/dL", caUS?.lines?.firstOrNull()?.value == "9.6 mg/dL", "$caUS")
        check("calcium bands at 2.20 and 2.60", WardCalc.calciumVerdict(2.2).startsWith("Within") && WardCalc.calciumVerdict(2.19).startsWith("Low")
            && WardCalc.calciumVerdict(2.6).startsWith("Within") && WardCalc.calciumVerdict(2.61).startsWith("High"))
        done()
    }

    @Test fun sodium() {
        check("Na 130, glucose 600 mg/dL -> 138 (Katz)", near(WardFormula.correctedSodium(130.0, 600.0, 1.6), 138.0, 0.0001))
        check("Na 130, glucose 600 mg/dL -> 142 (Hillier)", near(WardFormula.correctedSodium(130.0, 600.0, 2.4), 142.0, 0.0001))
        check("no correction at glucose 100 mg/dL or below", WardFormula.correctedSodium(130.0, 80.0, 1.6) == 130.0)
        val naSI = WardCalc.sodium.compute(v("na" to 130, "glu" to 600 / 18.016), us = false)
        check("sodium calculator from mmol/L glucose", values(naSI) == listOf("138.0 mmol/L", "142.0 mmol/L"), "$naSI")
        done()
    }

    @Test fun osmolality() {
        check("2 x 140 + 5 + 5 = 290", WardFormula.osmolality(140.0, 5.0, 5.0) == 290.0)
        val osmUS = WardCalc.osmolality.compute(mapOf("na" to 140.0, "glu" to WardUnit.glucose.toSI(90.0, us = true),
            "urea" to WardUnit.urea.toSI(14.0, us = true), "measured" to 310.0), us = true)
        check("MDCalc-style: Na 140, glucose 90, BUN 14 -> 290; gap 20", values(osmUS) == listOf("290 mOsm/kg", "20 mOsm/kg")
            && osmUS?.verdict?.startsWith("Osmolar gap above 10") == true, "$osmUS")
        val osmTen = WardCalc.osmolality.compute(v("na" to 140, "glu" to 5, "urea" to 5, "measured" to 300), us = false)
        check("an osmolar gap of exactly 10 is not raised", osmTen?.verdict?.startsWith("Osmolar gap 10 or less") == true)
        done()
    }

    @Test fun aaGradient() {
        check("PAO2 on air with PaCO2 40 = 99.7 mmHg", near(WardFormula.alveolarO2(0.21, 40.0), 99.73, 0.01))
        check("A-a gradient: air, PaCO2 40, PaO2 90 -> 9.7", near(WardFormula.aaGradient(0.21, 90.0, 40.0), 9.73, 0.01))
        check("expected A-a at 40 years = 14", WardFormula.expectedAaGradient(40.0) == 14.0)
        val aaUS = WardCalc.aaGradient.compute(mapOf("fio2" to 21.0, "pao2" to WardUnit.gas.toSI(90.0, us = true),
            "paco2" to WardUnit.gas.toSI(40.0, us = true), "age" to 40.0), us = true)
        check("A-a in mmHg, normal for age", values(aaUS) == listOf("100 mmHg", "10 mmHg", "14 mmHg")
            && aaUS?.verdict?.startsWith("Normal") == true, "$aaUS")
        val aaSI = WardCalc.aaGradient.compute(v("fio2" to 21, "pao2" to 8, "paco2" to 5.3, "age" to 40), us = false)
        // 0.21 x 713 - 39.75/0.8 = 100.04; minus 60.0 = 40.0 mmHg = 5.3 kPa
        check("A-a in kPa: PaO2 8, PaCO2 5.3 -> 5.3 kPa, raised", aaSI?.lines?.getOrNull(1)?.value == "5.3 kPa"
            && aaSI.verdict?.startsWith("Raised") == true, "$aaSI")
        val aaFraction = WardCalc.aaGradient.compute(mapOf("fio2" to 0.21, "pao2" to WardUnit.gas.toSI(90.0, us = true),
            "paco2" to WardUnit.gas.toSI(40.0, us = true), "age" to 40.0), us = true)
        check("FiO2 typed as 0.21 reads as 21%", aaFraction == aaUS, "$aaFraction")
        val aaSlip = WardCalc.aaGradient.compute(v("fio2" to 21, "pao2" to 20, "paco2" to 5.3), us = false)
        check("a PaO2 above the alveolar value is flagged as a slip", aaSlip?.verdict?.startsWith("PaO₂ is above") == true, "$aaSlip")
        check("an FiO2 over 100% is refused", WardCalc.aaGradient.compute(v("fio2" to 150, "pao2" to 8, "paco2" to 5), us = false) == null)
        done()
    }

    @Test fun kidneyFunction() {
        check("Cockcroft-Gault: 60 y, 72 kg, Cr 1.0, man -> 80", near(WardFormula.cockcroftGault(60.0, 72.0, 1.0, female = false), 80.0, 0.0001))
        check("Cockcroft-Gault: the same woman -> 68", near(WardFormula.cockcroftGault(60.0, 72.0, 1.0, female = true), 68.0, 0.0001))
        val crclSI = WardCalc.crcl.compute(v("age" to 60, "wt" to 72, "cr" to 88.42, "female" to 0), us = false)
        check("Cockcroft-Gault from umol/L", crclSI?.lines?.firstOrNull()?.value == "80 mL/min", "$crclSI")
        // NKF CKD-EPI 2021 calculator values
        check("CKD-EPI 2021: man 50 y, Cr 1.0 -> 92", near(WardFormula.ckdEpi2021(50.0, 1.0, female = false), 91.69, 0.01))
        check("CKD-EPI 2021: woman 50 y, Cr 0.7 -> 105", near(WardFormula.ckdEpi2021(50.0, 0.7, female = true), 105.30, 0.01))
        check("CKD-EPI 2021: man 70 y, Cr 2.0 -> 35", near(WardFormula.ckdEpi2021(70.0, 2.0, female = false), 35.24, 0.01))
        check("CKD-EPI 2021: woman 60 y, Cr 0.5 (below kappa) -> 107", near(WardFormula.ckdEpi2021(60.0, 0.5, female = true), 107.31, 0.01))
        check("CKD-EPI 2021: woman 80 y, Cr 1.5 -> 35", near(WardFormula.ckdEpi2021(80.0, 1.5, female = true), 35.01, 0.01))
        val atKappa = WardFormula.ckdEpi2021(40.0, 0.9, female = false)
        check("CKD-EPI 2021 at Scr = kappa is 142 x 0.9938^age", near(atKappa, 142 * 0.9938.pow(40.0), 1e-9))
        check("KDIGO categories at 90, 60, 45, 30, 15",
            WardFormula.gfrCategory(90.0).startsWith("G1") && WardFormula.gfrCategory(89.0).startsWith("G2")
                && WardFormula.gfrCategory(60.0).startsWith("G2") && WardFormula.gfrCategory(59.0).startsWith("G3a")
                && WardFormula.gfrCategory(45.0).startsWith("G3a") && WardFormula.gfrCategory(44.0).startsWith("G3b")
                && WardFormula.gfrCategory(30.0).startsWith("G3b") && WardFormula.gfrCategory(29.0).startsWith("G4")
                && WardFormula.gfrCategory(15.0).startsWith("G4") && WardFormula.gfrCategory(14.0).startsWith("G5"))
        val egfrSI = WardCalc.egfr.compute(v("age" to 50, "cr" to 88.42, "female" to 0), us = false)
        check("eGFR from umol/L, G1", egfrSI?.lines?.firstOrNull()?.value == "92 mL/min/1.73 m²" && egfrSI.verdict?.startsWith("G1") == true,
            "$egfrSI")
        val child = WardCalc.egfr.compute(v("age" to 12, "cr" to 50), us = false)
        check("eGFR says it is for adults", child?.verdict?.startsWith("For adults only") == true)
        done()
    }

    @Test fun mapAndQtc() {
        check("MAP 120/80 = 93.3", near(WardFormula.meanArterialPressure(120.0, 80.0), 93.33, 0.01))
        val mapLow = WardCalc.map.compute(v("sbp" to 85, "dbp" to 55), us = false)
        check("MAP 85/55 = 65 is at target", mapLow?.lines?.firstOrNull()?.value == "65 mmHg" && mapLow.verdict == "65 mmHg or more")
        check("MAP 84/55 = 64.7 is below target", WardCalc.map.compute(v("sbp" to 84, "dbp" to 55), us = false)?.verdict?.startsWith("Below 65") == true)
        check("QTc at 60/min equals QT", WardFormula.qtcBazett(400.0, 60.0) == 400.0 && near(WardFormula.qtcFridericia(400.0, 60.0), 400.0, 1e-9))
        check("QT 360 at 100/min: Bazett 465", near(WardFormula.qtcBazett(360.0, 100.0), 464.76, 0.01))
        check("QT 360 at 100/min: Fridericia 427", near(WardFormula.qtcFridericia(360.0, 100.0), 426.83, 0.01))
        check("QTc 449 man not prolonged, 450 prolonged",
            WardCalc.qtcVerdict(449.0, female = false).startsWith("Not") && WardCalc.qtcVerdict(450.0, female = false).startsWith("Prolonged"))
        check("QTc 459 woman not prolonged, 460 prolonged",
            WardCalc.qtcVerdict(459.0, female = true).startsWith("Not") && WardCalc.qtcVerdict(460.0, female = true).startsWith("Prolonged"))
        check("QTc 501 markedly prolonged", WardCalc.qtcVerdict(501.0, female = false).startsWith("Above 500"))
        done()
    }

    @Test fun fluidsAndChildren() {
        check("4-2-1: 10 kg = 40 mL/h", WardFormula.maintenancePerHour(10.0) == 40.0)
        check("4-2-1: 20 kg = 60 mL/h", WardFormula.maintenancePerHour(20.0) == 60.0)
        check("4-2-1: 25 kg = 65 mL/h", WardFormula.maintenancePerHour(25.0) == 65.0)
        check("4-2-1: 70 kg = 110 mL/h", WardFormula.maintenancePerHour(70.0) == 110.0)
        check("4-2-1: 5 kg = 20 mL/h", WardFormula.maintenancePerHour(5.0) == 20.0)
        check("100-50-20: 25 kg = 1600 mL/day", WardFormula.maintenancePerDay(25.0) == 1600.0)
        check("100-50-20: 10 kg = 1000, 20 kg = 1500",
            WardFormula.maintenancePerDay(10.0) == 1000.0 && WardFormula.maintenancePerDay(20.0) == 1500.0)
        val fluid = WardCalc.fluids.compute(v("wt" to 70), us = false)
        check("adult water 25-30 mL/kg/day at 70 kg", fluid?.lines?.lastOrNull()?.value == "1750–2100 mL/day", "$fluid")

        check("APLS: newborn 4 kg", WardFormula.childWeight(0.0) == 4.0)
        check("APLS: 6 months 7 kg", WardFormula.childWeight(6.0) == 7.0)
        check("APLS: 12 months 10 kg", WardFormula.childWeight(12.0) == 10.0)
        check("APLS: 3 years 14 kg", WardFormula.childWeight(36.0) == 14.0)
        check("APLS: 5 years 18 kg", WardFormula.childWeight(60.0) == 18.0)
        check("APLS: 5 years 11 months still (2 x 5) + 8", WardFormula.childWeight(71.0) == 18.0)
        check("APLS: 6 years 25 kg", WardFormula.childWeight(72.0) == 25.0)
        check("APLS: 10 years 37 kg", WardFormula.childWeight(120.0) == 37.0)
        check("APLS: 12 years 43 kg", WardFormula.childWeight(144.0) == 43.0)
        check("APLS: none past 12 years", WardFormula.childWeight(156.0) == null)
        val inYears = WardCalc.childWeight.compute(v("age" to 3, "per" to 1), us = false)
        check("child weight typed in years", inYears?.lines?.firstOrNull()?.value == "14.0 kg" && inYears.verdict?.startsWith("1–5 years") == true)
        done()
    }

    @Test fun meldNa() {
        val meldA = WardFormula.meld(2.0, 1.5, 1.2, 130.0, dialysis = false)
        check("MELD: bili 2, INR 1.5, Cr 1.2 -> 15", meldA.meld == 15.0, "$meldA")
        check("MELD-Na: with Na 130 -> 21", meldA.meldNa == 21.0, "$meldA")
        val meldLow = WardFormula.meld(0.5, 0.9, 0.6, 120.0, dialysis = false)
        check("values below 1 count as 1: MELD 6, and no sodium term at 11 or less", meldLow.meld == 6.0 && meldLow.meldNa == 6.0, "$meldLow")
        val meldTwelve = WardFormula.meld(1.8, 1.3, 1.0, 135.0, dialysis = false)
        check("MELD(i) 12 takes the sodium term: 12 + 2.64 - 0.792 -> 14", meldTwelve.meld == 12.0 && meldTwelve.meldNa == 14.0, "$meldTwelve")
        val meldClamp = WardFormula.meld(5.0, 2.5, 3.0, 110.0, dialysis = false)
        val meldAt125 = WardFormula.meld(5.0, 2.5, 3.0, 125.0, dialysis = false)
        check("sodium below 125 counts as 125: MELD 33 -> 36", meldClamp.meld == 33.0 && meldClamp.meldNa == 36.0 && meldClamp == meldAt125, "$meldClamp")
        val meldDialysis = WardFormula.meld(2.0, 1.5, 1.2, 137.0, dialysis = true)
        val meldCap = WardFormula.meld(2.0, 1.5, 9.0, 137.0, dialysis = false)
        check("dialysis sets creatinine to 4, as does a creatinine over 4", meldDialysis == meldCap && meldCap.meld == 27.0, "$meldCap")
        check("MELD is capped at 40", WardFormula.meld(40.0, 8.0, 6.0, 120.0, dialysis = true).meldNa == 40.0)
        check("MELD mortality bands at 9/10, 19/20, 29/30, 39/40",
            WardFormula.meldMortality(9.0).contains("1.9%") && WardFormula.meldMortality(10.0).contains("6.0%")
                && WardFormula.meldMortality(19.0).contains("6.0%") && WardFormula.meldMortality(20.0).contains("19.6%")
                && WardFormula.meldMortality(29.0).contains("19.6%") && WardFormula.meldMortality(30.0).contains("52.6%")
                && WardFormula.meldMortality(39.0).contains("52.6%") && WardFormula.meldMortality(40.0).contains("71.3%"))
        val meldSI = WardCalc.meldNa.compute(v("bili" to 34.2, "inr" to 1.5, "cr" to 106.1, "na" to 130), us = false)
        check("MELD-Na from SI units", values(meldSI) == listOf("15", "21"), "$meldSI")
        done()
    }

    @Test fun everyCalculator() {
        for (calc in WardCalc.entries) {
            val ids = calc.fields.map { it.id }
            check("${calc.rawValue}: field ids are unique", ids.toSet().size == ids.size)
            check("${calc.rawValue}: has a formula, a source and a title",
                calc.formula.isNotEmpty() && calc.source.isNotEmpty() && calc.title.isNotEmpty())
            check("${calc.rawValue}: nothing from nothing", calc.compute(emptyMap(), us = false) == null || calc == WardCalc.childWeight || calc == WardCalc.convert)
            val notes = WardPocket.practiceNotes(calc)
            check("${calc.rawValue}: practice notes carry the formula and source", notes.contains(calc.formula) && notes.contains(calc.source))
        }
        check("MELD-Na is listed with the scores, not the calculators", !WardCalc.calculators.contains(WardCalc.meldNa)
            && WardScores.entries.contains(WardScoreEntry.Formula(WardCalc.meldNa)))
        check("the disclaimer says learning only", WardPocket.disclaimer.startsWith("For learning only") && WardPocket.disclaimer.contains("not for patient care"))
        done()
    }

    @Test fun everyScoresTable() {
        check("twenty scores in the tab", WardScores.entries.size == 20, "${WardScores.entries.size}")
        check("score ids are unique", WardScores.all.map { it.id }.toSet().size == WardScores.all.size)
        for (score in WardScores.all) {
            val ids = score.items.map { it.id }
            check("${score.id}: item ids unique", ids.toSet().size == ids.size)
            check("${score.id}: every item has two or more answers", score.items.all { it.choices.size >= 2 })
            check("${score.id}: has a source", score.source.length > 10)
            // every reachable total falls in exactly one band
            val badTotals = ArrayList<Double>()
            for (total in score.reachableTotals.sorted()) {
                val hits = score.bands.count { it.contains(total) }
                if (hits != 1) badTotals.add(total)
            }
            check("${score.id}: bands cover every total exactly once", badTotals.isEmpty(), "$badTotals")
            val first = score.bands.firstOrNull()?.low ?: Double.NaN
            val last = score.bands.lastOrNull()?.high ?: Double.NaN
            check("${score.id}: bands run from the lowest to the highest total",
                first == score.lowest && last == score.highest, "$first...$last vs ${score.lowest}...${score.highest}")
            check("${score.id}: practice notes carry the source", score.practiceNotes.contains(score.source))
        }
        done()
    }

    private fun points(score: WardScore, item: String): List<Double> =
        score.items.firstOrNull { it.id == item }?.choices?.map { it.points } ?: emptyList()

    private fun picks(@Suppress("UNUSED_PARAMETER") score: WardScore, yes: List<String>): Map<String, Int> = yes.associateWith { 1 }

    private fun verdict(score: WardScore, picks: Map<String, Int>): String = score.verdict(picks)?.title ?: "none"

    private fun d(vararg x: Number): List<Double> = x.map { it.toDouble() }

    @Test fun scoresOneByOne() {
        // GCS: E4 V5 M6 = 15; E1 V1 M1 = 3; E2 V2 M4 = 8 severe; E3 V3 M3 = 9 moderate;
        // E4 V4 M4 = 12 moderate; E4 V4 M5 = 13 mild
        val gcs = WardScores.gcs
        check("GCS parts are 4, 5 and 6", points(gcs, "eye") == d(4, 3, 2, 1) && points(gcs, "verbal") == d(5, 4, 3, 2, 1)
            && points(gcs, "motor") == d(6, 5, 4, 3, 2, 1))
        check("GCS 15 by default, 3 at worst", gcs.total(emptyMap()) == 15.0 && gcs.total(mapOf("eye" to 3, "verbal" to 4, "motor" to 5)) == 3.0)
        check("GCS 8 severe, 9 moderate, 12 moderate, 13 mild",
            verdict(gcs, mapOf("eye" to 2, "verbal" to 3, "motor" to 2)) == "Severe"
                && verdict(gcs, mapOf("eye" to 1, "verbal" to 2, "motor" to 3)) == "Moderate"
                && gcs.total(mapOf("eye" to 0, "verbal" to 1, "motor" to 2)) == 12.0
                && verdict(gcs, mapOf("eye" to 0, "verbal" to 1, "motor" to 2)) == "Moderate"
                && verdict(gcs, mapOf("eye" to 0, "verbal" to 1, "motor" to 1)) == "Mild")

        // Wells DVT: range -2..9; 1 unlikely, 2 likely
        val dvt = WardScores.wellsDVT
        check("Wells DVT: nine items of 1 and one of -2", dvt.items.size == 10 && dvt.lowest == -2.0 && dvt.highest == 9.0
            && points(dvt, "alternative") == d(0, -2))
        check("Wells DVT 1 unlikely, 2 likely",
            verdict(dvt, picks(dvt, listOf("cancer"))) == "DVT unlikely"
                && verdict(dvt, picks(dvt, listOf("cancer", "calf"))) == "DVT likely"
                && verdict(dvt, picks(dvt, listOf("cancer", "calf", "leg", "alternative"))) == "DVT unlikely")

        // Wells PE: 4 unlikely, 4.5 likely (Wells 2000)
        val pe = WardScores.wellsPE
        check("Wells PE weights 3, 3, 1.5, 1.5, 1.5, 1, 1", pe.items.map { it.maxPoints } == d(3, 3, 1.5, 1.5, 1.5, 1, 1) && pe.highest == 12.5)
        check("Wells PE 4.0 unlikely", verdict(pe, picks(pe, listOf("dvt", "cancer"))) == "PE unlikely" && pe.total(picks(pe, listOf("dvt", "cancer"))) == 4.0)
        check("Wells PE 4.5 likely", verdict(pe, picks(pe, listOf("dvt", "hr"))) == "PE likely")
        check("Wells PE 3 + 1.5 + 1.5 + 1.5 = 7.5", pe.total(picks(pe, listOf("likely", "hr", "immobile", "previous"))) == 7.5)

        // PERC: eight criteria; 0 negative, 1 positive
        val perc = WardScores.perc
        check("PERC has eight criteria", perc.items.size == 8 && perc.highest == 8.0)
        check("PERC surgery or trauma: within 4 weeks, needing general anaesthesia (Kline 2004)",
            perc.items[5].label.contains("4 weeks") && perc.items[5].label.contains("general anaesthetic"))
        check("PERC 0 negative, 1 positive", verdict(perc, emptyMap()) == "PERC negative" && verdict(perc, picks(perc, listOf("hormones"))) == "PERC positive")

        // CURB-65 (Lim 2003): 0-1, 2, 3-5
        val curb = WardScores.curb65
        check("CURB-65 five items of 1", curb.items.size == 5 && curb.highest == 5.0)
        check("CURB-65 1 low, 2 moderate, 3 high",
            verdict(curb, picks(curb, listOf("age"))) == "Low severity"
                && verdict(curb, picks(curb, listOf("age", "urea"))) == "Moderate severity"
                && verdict(curb, picks(curb, listOf("age", "urea", "confusion"))) == "High severity")
        check("CURB-65 bands carry Lim's 1.5%, 9.2% and 22%", curb.bands.joinToString("") { it.detail }.contains("1.5%")
            && curb.bands[1].detail.contains("9.2%") && curb.bands[2].detail.contains("22%"))

        // qSOFA: 1 not positive, 2 positive
        val qsofa = WardScores.qsofa
        check("qSOFA 1 / 2", verdict(qsofa, picks(qsofa, listOf("rr"))) == "Not positive" && verdict(qsofa, picks(qsofa, listOf("rr", "sbp"))) == "qSOFA positive")

        // CHA2DS2-VASc: a 76-year-old woman with hypertension = 2 + 1 + 1 = 4
        val chads = WardScores.chads
        check("CHA2DS2-VASc weights", points(chads, "age") == d(0, 1, 2) && points(chads, "stroke") == d(0, 2) && chads.highest == 9.0)
        check("CHA2DS2-VASc: woman 76 with hypertension = 4, high", chads.total(mapOf("age" to 2, "female" to 1, "htn" to 1)) == 4.0
            && verdict(chads, mapOf("age" to 2, "female" to 1, "htn" to 1)) == "High risk")
        check("CHA2DS2-VASc: 0 low, 1 low-moderate, 2 moderate, 3 high",
            verdict(chads, emptyMap()) == "Low risk" && verdict(chads, mapOf("female" to 1)) == "Low to moderate"
                && verdict(chads, mapOf("age" to 2)) == "Moderate" && verdict(chads, mapOf("age" to 2, "dm" to 1)) == "High risk")

        // HAS-BLED: nine of 1; 2 / 3
        val hasbled = WardScores.hasbled
        check("HAS-BLED nine items", hasbled.items.size == 9 && hasbled.highest == 9.0)
        check("HAS-BLED 2 not high, 3 high", verdict(hasbled, picks(hasbled, listOf("elderly", "drugs"))) == "Low to moderate"
            && verdict(hasbled, picks(hasbled, listOf("elderly", "drugs", "alcohol"))) == "High risk")

        // Child-Pugh: 5-6 A, 7-9 B, 10-15 C
        val cp = WardScores.childPugh
        check("Child-Pugh: 5 at best, 15 at worst", cp.lowest == 5.0 && cp.highest == 15.0 && cp.total(emptyMap()) == 5.0)
        check("Child-Pugh 6 A, 7 B, 9 B, 10 C",
            verdict(cp, mapOf("bili" to 1)) == "Class A" && verdict(cp, mapOf("bili" to 1, "alb" to 1)) == "Class B"
                && verdict(cp, mapOf("bili" to 2, "alb" to 2)) == "Class B" && verdict(cp, mapOf("bili" to 2, "alb" to 2, "inr" to 1)) == "Class C")
        check("Child-Pugh bilirubin cut-offs 34 and 50 umol/L (2 and 3 mg/dL)",
            cp.items[0].choices[1].label.startsWith("34–50") && cp.items[0].choices[1].label.contains("2–3 mg/dL"))
        check("Child-Pugh INR cut-offs 1.7 and 2.3", cp.items[2].choices.map { it.label } == listOf("Below 1.7", "1.7–2.3", "Above 2.3"))

        // Centor / McIsaac
        val centor = WardScores.centor
        check("McIsaac age: 3-14 +1, 45+ -1", points(centor, "age") == d(0, 1, -1) && centor.lowest == -1.0 && centor.highest == 5.0)
        check("Centor 4 in a 10-year-old = 5, high", centor.total(mapOf("temp" to 1, "cough" to 1, "nodes" to 1, "tonsils" to 1, "age" to 1)) == 5.0
            && verdict(centor, mapOf("temp" to 1, "cough" to 1, "nodes" to 1, "tonsils" to 1, "age" to 1)) == "High")
        check("McIsaac 0 very low, 1 low, 3 intermediate 28-35%",
            verdict(centor, mapOf("temp" to 1, "age" to 2)) == "Very low" && verdict(centor, mapOf("temp" to 1)) == "Low"
                && centor.verdict(mapOf("temp" to 1, "cough" to 1, "nodes" to 1))?.detail?.contains("28–35%") == true)

        // Glasgow-Blatchford (Blatchford 2000)
        val gbs = WardScores.blatchford
        check("GBS urea points 0, 2, 3, 4, 6", points(gbs, "urea") == d(0, 2, 3, 4, 6))
        check("GBS Hb points: men 1 / 3 / 6, women 1 / 6", points(gbs, "hb") == d(0, 1, 1, 3, 6))
        check("GBS systolic 1 / 2 / 3", points(gbs, "sbp") == d(0, 1, 2, 3))
        check("GBS others 1, 1, 2, 2, 2", listOf("pulse", "melaena", "syncope", "liver", "heart").map { points(gbs, it).lastOrNull() ?: 0.0 } == d(1, 1, 2, 2, 2))
        check("GBS maximum 23", gbs.highest == 23.0)
        check("GBS 0 very low, 1 not low, 5 not low, 6 high",
            verdict(gbs, emptyMap()) == "Very low risk" && verdict(gbs, mapOf("pulse" to 1)) == "Not low risk"
                && verdict(gbs, mapOf("urea" to 3, "pulse" to 1)) == "Not low risk" && verdict(gbs, mapOf("urea" to 4)) == "High risk")
        check("GBS urea labels carry 6.5, 8, 10 and 25 mmol/L", gbs.items[0].choices[1].label.startsWith("6.5")
            && gbs.items[0].choices[2].label.startsWith("8.0") && gbs.items[0].choices[3].label.startsWith("10.0")
            && gbs.items[0].choices[4].label.startsWith("25"))

        // Ranson on admission
        val ranson = WardScores.ranson
        check("Ranson: five admission criteria", ranson.items.size == 5 && ranson.items[0].label.contains("55")
            && ranson.items[1].label.contains("16") && ranson.items[2].label.contains("200 mg/dL")
            && ranson.items[3].label.contains("350") && ranson.items[4].label.contains("250"))
        check("Ranson 2 / 3", verdict(ranson, picks(ranson, listOf("age", "wbc"))) == "Fewer than 3"
            && verdict(ranson, picks(ranson, listOf("age", "wbc", "ldh"))) == "3 or more")

        // APGAR
        val apgar = WardScores.apgar
        check("APGAR 10 by default, five items of 0-2", apgar.total(emptyMap()) == 10.0 && apgar.items.all { it.maxPoints == 2.0 && it.minPoints == 0.0 })
        val apgar3 = mapOf("appearance" to 2, "pulse" to 1, "grimace" to 2, "activity" to 1, "respiration" to 1)
        val apgar4 = mapOf("appearance" to 2, "pulse" to 1, "grimace" to 1, "activity" to 1, "respiration" to 1)
        check("APGAR 7 reassuring, 6 moderately abnormal, 4 moderately abnormal, 3 low",
            verdict(apgar, mapOf("appearance" to 1, "activity" to 1, "respiration" to 1)) == "Reassuring"
                && verdict(apgar, mapOf("appearance" to 1, "activity" to 1, "respiration" to 1, "grimace" to 1)) == "Moderately abnormal"
                && apgar.total(apgar4) == 4.0 && verdict(apgar, apgar4) == "Moderately abnormal"
                && apgar.total(apgar3) == 3.0 && verdict(apgar, apgar3) == "Low")

        // Alvarado: MANTRELS, tenderness and white cells 2 each
        val alvarado = WardScores.alvarado
        check("Alvarado maximum 10, tenderness and leucocytosis 2", alvarado.highest == 10.0
            && points(alvarado, "tender") == d(0, 2) && points(alvarado, "wbc") == d(0, 2))
        check("Alvarado 4 / 5 / 7 / 9",
            verdict(alvarado, picks(alvarado, listOf("tender", "wbc"))) == "Unlikely"
                && verdict(alvarado, picks(alvarado, listOf("tender", "wbc", "temp"))) == "Possible"
                && verdict(alvarado, picks(alvarado, listOf("tender", "wbc", "temp", "shift", "rebound"))) == "Probable"
                && verdict(alvarado, picks(alvarado, listOf("tender", "wbc", "temp", "shift", "rebound", "migration", "anorexia"))) == "Very probable")

        // NEWS2 (RCP 2017)
        val news = WardScores.news2
        check("NEWS2 respiration 12-20 0, 9-11 1, 21-24 2, <=8 3, >=25 3", points(news, "rr") == d(0, 1, 2, 3, 3))
        check("NEWS2 SpO2 scale 1: >=96 0, 94-95 1, 92-93 2, <=91 3", points(news, "spo2") == d(0, 1, 2, 3))
        check("NEWS2 oxygen 2", points(news, "air") == d(0, 2))
        check("NEWS2 systolic 0, 1, 2, 3, 3", points(news, "sbp") == d(0, 1, 2, 3, 3))
        check("NEWS2 pulse 0, 1, 1, 2, 3, 3", points(news, "pulse") == d(0, 1, 1, 2, 3, 3))
        check("NEWS2 consciousness 0 / 3", points(news, "acvpu") == d(0, 3))
        check("NEWS2 temperature 0, 1, 1, 2, 3", points(news, "temp") == d(0, 1, 1, 2, 3))
        check("NEWS2 maximum 20", news.highest == 20.0)
        check("NEWS2 0 low, 4 low, 5 medium, 6 medium, 7 high",
            verdict(news, emptyMap()) == "Low" && verdict(news, mapOf("rr" to 2, "air" to 1)) == "Low"
                && verdict(news, mapOf("rr" to 2, "air" to 1, "pulse" to 1)) == "Medium"
                && verdict(news, mapOf("rr" to 2, "air" to 1, "pulse" to 3)) == "Medium"
                && verdict(news, mapOf("rr" to 2, "air" to 1, "pulse" to 3, "temp" to 1)) == "High")
        check("NEWS2 minimum observation frequency 12-hourly, 4-6-hourly, hourly, continuous",
            news.bands[0].detail.contains("12-hourly") && news.bands[1].detail.contains("4–6-hourly")
                && news.bands[2].detail.contains("hourly") && news.bands[3].detail.contains("continuous")
                && news.redFlag?.band?.detail?.contains("hourly") == true)
        check("NEWS2 a single 3 with a total of 3 is low-medium", verdict(news, mapOf("acvpu" to 1)) == "Low–medium")
        check("NEWS2 a single 3 with a total of 5 stays medium", verdict(news, mapOf("acvpu" to 1, "air" to 1)) == "Medium")
        check("NEWS2 a total of 3 without any single 3 stays low", verdict(news, mapOf("air" to 1, "temp" to 1)) == "Low")

        // TIMI UA/NSTEMI (Antman 2000)
        val timi = WardScores.timi
        check("TIMI seven items", timi.items.size == 7 && timi.highest == 7.0)
        val timiDetails = (0..7).map { timi.band(it.toDouble())?.detail ?: "" }
        check("TIMI risks 4.7, 4.7, 8.3, 13.2, 19.9, 26.2, 40.9, 40.9",
            timiDetails[0].contains("4.7%") && timiDetails[1].contains("4.7%") && timiDetails[2].contains("8.3%")
                && timiDetails[3].contains("13.2%") && timiDetails[4].contains("19.9%") && timiDetails[5].contains("26.2%")
                && timiDetails[6].contains("40.9%") && timiDetails[7].contains("40.9%"))

        // HEART (Six 2008; Backus 2013)
        val heartScore = WardScores.heart
        check("HEART five items of 0-2", heartScore.items.size == 5 && heartScore.highest == 10.0)
        check("HEART 3 low, 4 moderate, 6 moderate, 7 high",
            verdict(heartScore, mapOf("history" to 1, "age" to 2)) == "Low" && verdict(heartScore, mapOf("history" to 2, "age" to 2)) == "Moderate"
                && verdict(heartScore, mapOf("history" to 2, "age" to 2, "risk" to 2)) == "Moderate"
                && verdict(heartScore, mapOf("history" to 2, "age" to 2, "risk" to 2, "ecg" to 1)) == "High")

        // Bishop (Bishop 1964)
        val bishop = WardScores.bishop
        check("Bishop maximum 13", bishop.highest == 13.0 && points(bishop, "dilation") == d(0, 1, 2, 3)
            && points(bishop, "consistency") == d(0, 1, 2) && points(bishop, "position") == d(0, 1, 2))
        check("Bishop 6 unfavourable, 7 favourable, 8 favourable, 9 very favourable",
            verdict(bishop, mapOf("dilation" to 2, "effacement" to 2, "station" to 2)) == "Unfavourable"
                && verdict(bishop, mapOf("dilation" to 2, "effacement" to 2, "station" to 2, "position" to 1)) == "Favourable"
                && verdict(bishop, mapOf("dilation" to 2, "effacement" to 2, "station" to 2, "position" to 2)) == "Favourable"
                && verdict(bishop, mapOf("dilation" to 2, "effacement" to 2, "station" to 2, "position" to 2, "consistency" to 1)) == "Very favourable")

        // ABCD2 (Johnston 2007)
        val abcd = WardScores.abcd2
        check("ABCD2 weights", points(abcd, "clinical") == d(0, 1, 2) && points(abcd, "duration") == d(0, 1, 2) && abcd.highest == 7.0)
        check("ABCD2 3 low, 4 moderate, 5 moderate, 6 high",
            verdict(abcd, mapOf("age" to 1, "clinical" to 2)) == "Low risk" && verdict(abcd, mapOf("age" to 1, "bp" to 1, "clinical" to 2)) == "Moderate risk"
                && verdict(abcd, mapOf("age" to 1, "bp" to 1, "clinical" to 2, "diabetes" to 1)) == "Moderate risk"
                && verdict(abcd, mapOf("age" to 1, "bp" to 1, "clinical" to 2, "duration" to 2)) == "High risk")
        check("ABCD2 2-day risks 1.0, 4.1, 8.1", abcd.bands[0].detail.contains("1.0%") && abcd.bands[1].detail.contains("4.1%")
            && abcd.bands[2].detail.contains("8.1%"))

        check("points read with a real minus", WardScores.points(-2.0) == "−2" && WardScores.points(1.5) == "1.5")
        done()
    }
}
