package com.stethoscore.app.exam

// A port of upstream/ios/RedPen/Shared/WardPocketScores.swift: the Ward
// pocket's clinical scores - each one's items and points, its interpretation
// bands and where it comes from, as published. MELD-Na is a formula rather
// than a table, so it lives with the calculators (WardCalc.meldNa) and is
// listed beside these. For learning only; every table is checked item by
// item and band by band in WardPocketTest. Pure Kotlin.

/** One answer to an item and what it scores. */
data class WardChoice(val label: String, val points: Double)

/** One item of a score: yes/no, or one of several answers. */
data class WardItem(val id: String, val label: String, val choices: List<WardChoice>) {
    /** A plain yes/no item: shown as a switch rather than a list. */
    val isYesNo: Boolean get() = choices.size == 2 && choices[0].label == "No" && choices[0].points == 0.0

    val maxPoints: Double get() = choices.maxOfOrNull { it.points } ?: 0.0
    val minPoints: Double get() = choices.minOfOrNull { it.points } ?: 0.0
}

/** A range of totals and what it means. Both ends are included. */
data class WardBand(val low: Double, val high: Double, val title: String, val detail: String) {
    fun contains(total: Double): Boolean = total >= low - 1e-9 && total <= high + 1e-9
}

/**
 * A rule outside the total: any one item scoring [points] or more, while the
 * total is below [below], gives [band] instead (NEWS2's single red score).
 */
data class WardRedFlag(val points: Double, val below: Double, val band: WardBand)

/** A clinical score: items, bands, source. */
data class WardScore(
    val id: String,
    val name: String,
    /** What it is for, in one line. */
    val purpose: String,
    val items: List<WardItem>,
    val bands: List<WardBand>,
    val source: String,
    val note: String = "",
    val redFlag: WardRedFlag? = null,
) {
    /** The total for these answers (item id to choice index; an item left out counts as its first answer). */
    fun total(picks: Map<String, Int>): Double {
        var sum = 0.0
        for (item in items) {
            val index = picks[item.id] ?: 0
            val safe = minOf(maxOf(index, 0), item.choices.size - 1)
            sum += item.choices[safe].points
        }
        return sum
    }

    fun band(total: Double): WardBand? = bands.firstOrNull { it.contains(total) }

    /** What these answers mean, the red-flag rule included. */
    fun verdict(picks: Map<String, Int>): WardBand? {
        val sum = total(picks)
        val flag = redFlag
        if (flag != null && sum < flag.below && highestItem(picks) >= flag.points) return flag.band
        return band(sum)
    }

    private fun highestItem(picks: Map<String, Int>): Double {
        var top = 0.0
        for (item in items) {
            val index = minOf(maxOf(picks[item.id] ?: 0, 0), item.choices.size - 1)
            top = maxOf(top, item.choices[index].points)
        }
        return top
    }

    val lowest: Double get() = items.sumOf { it.minPoints }
    val highest: Double get() = items.sumOf { it.maxPoints }

    /** Every total the items can make. */
    val reachableTotals: Set<Double> get() {
        var sums: Set<Double> = setOf(0.0)
        for (item in items) {
            val next = HashSet<Double>()
            for (s in sums) for (c in item.choices) next.add(s + c.points)
            sums = next
        }
        return sums
    }

    /** The material for "Practise this". */
    val practiceNotes: String get() {
        val lines = ArrayList<String>()
        lines.add("Write exam questions that test the $name: $purpose Give a vignette with the findings needed to score it, and ask for the score, its meaning or the next step.")
        for (item in items) {
            val answers = item.choices.map { it.label + " = " + WardScores.points(it.points) }
            lines.add(item.label + ": " + answers.joinToString("; "))
        }
        for (band in bands) {
            val range = WardScores.points(band.low) + " to " + WardScores.points(band.high)
            lines.add(range + ": " + band.title + ". " + band.detail)
        }
        if (note.isNotEmpty()) lines.add(note)
        lines.add("Source: " + source)
        return lines.joinToString("\n")
    }
}

/** What the Scores tab lists: a table score, or MELD-Na's formula. */
sealed class WardScoreEntry {
    data class Table(val score: WardScore) : WardScoreEntry()
    data class Formula(val calc: WardCalc) : WardScoreEntry()

    val id: String get() = when (this) {
        is Table -> score.id
        is Formula -> calc.rawValue
    }

    val name: String get() = when (this) {
        is Table -> score.name
        is Formula -> calc.title
    }
}

object WardScores {

    /** "2", "1.5", "−1". */
    fun points(x: Double): String {
        val whole = x == swiftRounded(x)
        val text = if (whole) x.toLong().toString() else WardPocket.format(x, 1)
        return text.replace("-", "−")
    }

    // building blocks

    fun c(label: String, points: Number): WardChoice = WardChoice(label, points.toDouble())

    fun yes(id: String, label: String, points: Number = 1): WardItem = WardItem(id, label, listOf(c("No", 0), c("Yes", points)))

    fun pick(id: String, label: String, choices: List<WardChoice>): WardItem = WardItem(id, label, choices)

    fun band(low: Number, high: Number, title: String, detail: String): WardBand = WardBand(low.toDouble(), high.toDouble(), title, detail)

    /** In the order the Scores tab lists them, MELD-Na after Child-Pugh. */
    val entries: List<WardScoreEntry> get() {
        val out: MutableList<WardScoreEntry> = all.map { WardScoreEntry.Table(it) }.toMutableList()
        val found = all.indexOfFirst { it.id == "childPugh" }
        val after = (if (found >= 0) found else all.size - 1) + 1
        out.add(after, WardScoreEntry.Formula(WardCalc.meldNa))
        return out
    }

    val all: List<WardScore> by lazy {
        listOf(gcs, wellsDVT, wellsPE, perc, curb65, qsofa, chads, hasbled, childPugh,
            centor, blatchford, ranson, apgar, alvarado, news2, timi, heart, bishop, abcd2)
    }

    fun named(id: String): WardScore? = all.firstOrNull { it.id == id }

    // neurology and trauma

    // Teasdale G, Jennett B. Lancet 1974;2:81; the current wording from
    // Teasdale G et al. Lancet Neurol 2014;13:844.
    val gcs = WardScore(
        id = "gcs", name = "Glasgow Coma Scale",
        purpose = "Level of consciousness, from the best eye, verbal and motor responses.",
        items = listOf(
            pick("eye", "Eye opening", listOf(c("Spontaneous", 4), c("To sound", 3), c("To pressure", 2), c("None", 1))),
            pick("verbal", "Verbal response", listOf(c("Orientated", 5), c("Confused", 4), c("Words", 3), c("Sounds", 2), c("None", 1))),
            pick("motor", "Motor response", listOf(c("Obeys commands", 6), c("Localising", 5), c("Normal flexion (withdraws)", 4),
                                             c("Abnormal flexion", 3), c("Extension", 2), c("None", 1)))
        ),
        bands = listOf(
            band(3, 8, "Severe", "8 or less: coma; the airway may not be protected"),
            band(9, 12, "Moderate", "9\u201312"),
            band(13, 15, "Mild", "13\u201315")
        ),
        source = "Teasdale G, Jennett B. Lancet 1974;2:81; Teasdale G et al. Lancet Neurol 2014;13:844.",
        note = "Report the parts as well as the total (E4 V5 M6). A part that cannot be tested (intubated, eyes swollen) is recorded as NT, not scored as 1. The mild/moderate/severe bands are the usual head-injury classification.")

    // Johnston SC et al. Lancet 2007;369:283.
    val abcd2 = WardScore(
        id = "abcd2", name = "ABCD\u00B2 score",
        purpose = "Short-term stroke risk after a transient ischaemic attack.",
        items = listOf(
            yes("age", "Age 60 or over"),
            yes("bp", "BP 140/90 mmHg or higher at first assessment"),
            pick("clinical", "Clinical features", listOf(c("Other", 0), c("Speech disturbance without weakness", 1), c("Unilateral weakness", 2))),
            pick("duration", "Duration", listOf(c("Under 10 minutes", 0), c("10\u201359 minutes", 1), c("60 minutes or more", 2))),
            yes("diabetes", "Diabetes")
        ),
        bands = listOf(
            band(0, 3, "Low risk", "2-day stroke risk about 1.0%"),
            band(4, 5, "Moderate risk", "2-day stroke risk about 4.1%"),
            band(6, 7, "High risk", "2-day stroke risk about 8.1%")
        ),
        source = "Johnston SC et al. Lancet 2007;369:283.",
        note = "NICE (NG128, 2019) no longer uses ABCD\u00B2 to triage: everyone with a suspected TIA is seen by a specialist within 24 hours. It still appears in exams.")

    // venous thromboembolism

    // Wells PS et al. N Engl J Med 2003;349:1227 (the two-level score with
    // previous DVT).
    val wellsDVT = WardScore(
        id = "wellsDVT", name = "Wells score for DVT",
        purpose = "Clinical probability of a deep vein thrombosis.",
        items = listOf(
            yes("cancer", "Active cancer (treatment ongoing, within 6 months, or palliative)"),
            yes("paralysis", "Paralysis, paresis or recent plaster immobilisation of the leg"),
            yes("bedridden", "Bedridden 3 days or more, or major surgery within 12 weeks"),
            yes("tender", "Localised tenderness along the deep veins"),
            yes("leg", "Entire leg swollen"),
            yes("calf", "Calf swelling 3 cm or more than the other leg (10 cm below the tibial tuberosity)"),
            yes("pitting", "Pitting oedema confined to the symptomatic leg"),
            yes("collateral", "Collateral superficial veins (not varicose)"),
            yes("previous", "Previously documented DVT"),
            yes("alternative", "An alternative diagnosis at least as likely as DVT", -2)
        ),
        bands = listOf(
            band(-2, 1, "DVT unlikely", "1 or less: D-dimer; if positive, proximal leg ultrasound"),
            band(2, 9, "DVT likely", "2 or more: proximal leg ultrasound (within 4 hours, or interim anticoagulation)")
        ),
        source = "Wells PS et al. N Engl J Med 2003;349:1227; NICE NG158 (2020).",
        note = "The older three-level version (Wells 1997): 0 or less low, 1\u20132 moderate, 3 or more high probability.")

    // Wells PS et al. Thromb Haemost 2000;83:416.
    val wellsPE = WardScore(
        id = "wellsPE", name = "Wells score for PE",
        purpose = "Clinical probability of a pulmonary embolism.",
        items = listOf(
            yes("dvt", "Clinical signs and symptoms of DVT", 3),
            yes("likely", "PE is the most likely diagnosis (an alternative is less likely)", 3),
            yes("hr", "Heart rate over 100/min", 1.5),
            yes("immobile", "Immobilisation 3 days or more, or surgery in the previous 4 weeks", 1.5),
            yes("previous", "Previous DVT or PE", 1.5),
            yes("haemoptysis", "Haemoptysis"),
            yes("cancer", "Malignancy (treatment within 6 months, or palliative)")
        ),
        bands = listOf(
            band(0, 4, "PE unlikely", "4 or less: D-dimer; if positive, CT pulmonary angiogram"),
            band(4.5, 12.5, "PE likely", "More than 4: CT pulmonary angiogram (interim anticoagulation if delayed)")
        ),
        source = "Wells PS et al. Thromb Haemost 2000;83:416; NICE NG158 (2020).",
        note = "The three-level version: below 2 low, 2\u20136 moderate, above 6 high probability.")

    // Kline JA et al. J Thromb Haemost 2004;2:1247.
    val perc = WardScore(
        id = "perc", name = "PERC rule",
        purpose = "Rules out PE without a D-dimer when the pre-test probability is already low.",
        items = listOf(
            yes("age", "Age 50 or over"),
            yes("hr", "Heart rate 100/min or more"),
            yes("sat", "SaO\u2082 below 95% on air"),
            yes("leg", "Unilateral leg swelling"),
            yes("haemoptysis", "Haemoptysis"),
            yes("surgery", "Surgery or trauma within 4 weeks that needed a general anaesthetic"),
            yes("previous", "Previous PE or DVT"),
            yes("hormones", "Hormone use (oral contraceptive, HRT or oestrogen)")
        ),
        bands = listOf(
            band(0, 0, "PERC negative", "No criteria: with a low clinical probability (under 15%), PE is ruled out without testing"),
            band(1, 8, "PERC positive", "Any criterion: PERC cannot rule PE out; go on to Wells and D-dimer")
        ),
        source = "Kline JA et al. J Thromb Haemost 2004;2:1247.",
        note = "Use only when the clinician\u2019s gestalt already puts the probability of PE below 15%.")

    // infection and sepsis

    // Lim WS et al. Thorax 2003;58:377.
    val curb65 = WardScore(
        id = "curb65", name = "CURB-65",
        purpose = "Severity of community-acquired pneumonia, for where to treat it.",
        items = listOf(
            yes("confusion", "Confusion (new)"),
            yes("urea", "Urea over 7 mmol/L (BUN over 19 mg/dL)"),
            yes("rr", "Respiratory rate 30/min or more"),
            yes("bp", "Systolic BP below 90 or diastolic 60 mmHg or less"),
            yes("age", "Age 65 or over")
        ),
        bands = listOf(
            band(0, 1, "Low severity", "30-day mortality about 1.5%: consider treatment at home"),
            band(2, 2, "Moderate severity", "30-day mortality about 9.2%: consider hospital treatment"),
            band(3, 5, "High severity", "30-day mortality about 22%: treat in hospital as severe; with 4\u20135, assess for critical care")
        ),
        source = "Lim WS et al. Thorax 2003;58:377; Lim WS et al. BTS CAP guideline, Thorax 2009;64 Suppl 3:iii1.",
        note = "CRB-65 (without urea) is the version for the community.")

    // Seymour CW et al. JAMA 2016;315:762; Singer M et al. JAMA 2016;315:801.
    val qsofa = WardScore(
        id = "qsofa", name = "qSOFA",
        purpose = "Bedside prompt for sepsis with a poor outcome, outside intensive care.",
        items = listOf(
            yes("rr", "Respiratory rate 22/min or more"),
            yes("mentation", "Altered mentation (GCS below 15)"),
            yes("sbp", "Systolic BP 100 mmHg or less")
        ),
        bands = listOf(
            band(0, 1, "Not positive", "0\u20131: does not rule sepsis out"),
            band(2, 3, "qSOFA positive", "2 or more: higher risk of death or a long ICU stay; look for organ dysfunction")
        ),
        source = "Seymour CW et al. JAMA 2016;315:762; Singer M et al. (Sepsis-3) JAMA 2016;315:801.",
        note = "The Surviving Sepsis Campaign (2021) recommends against qSOFA alone as a screening tool, compared with SIRS, NEWS or MEWS.")

    // Centor RM et al. Med Decis Making 1981;1:239; McIsaac WJ et al. CMAJ
    // 1998;158:75.
    val centor = WardScore(
        id = "centor", name = "Centor score (McIsaac)",
        purpose = "Likelihood of group A streptococcal pharyngitis.",
        items = listOf(
            yes("temp", "Temperature over 38 \u00B0C"),
            yes("cough", "Cough absent"),
            yes("nodes", "Tender or swollen anterior cervical nodes"),
            yes("tonsils", "Tonsillar swelling or exudate"),
            pick("age", "Age (McIsaac)", listOf(c("15\u201344 years", 0), c("3\u201314 years", 1), c("45 or over", -1)))
        ),
        bands = listOf(
            band(-1, 0, "Very low", "Strep about 1\u20132.5%: no test, no antibiotic"),
            band(1, 1, "Low", "Strep about 5\u201310%: no test, no antibiotic"),
            band(2, 2, "Intermediate", "Strep about 11\u201317%: test (rapid antigen or culture)"),
            band(3, 3, "Intermediate", "Strep about 28\u201335%: test (rapid antigen or culture)"),
            band(4, 5, "High", "Strep about 51\u201353%: test, or treat empirically")
        ),
        source = "Centor RM et al. Med Decis Making 1981;1:239; McIsaac WJ et al. CMAJ 1998;158:75 and JAMA 2004;291:1587.",
        note = "NICE (NG84) uses FeverPAIN or Centor without the age item: Centor 3\u20134 suggests a back-up or immediate antibiotic.")

    // cardiology

    // Lip GYH et al. Chest 2010;137:263.
    val chads = WardScore(
        id = "chads", name = "CHA\u2082DS\u2082-VASc",
        purpose = "Stroke risk in non-valvular atrial fibrillation.",
        items = listOf(
            yes("chf", "Congestive heart failure (or LV dysfunction)"),
            yes("htn", "Hypertension"),
            pick("age", "Age", listOf(c("Under 65", 0), c("65\u201374", 1), c("75 or over", 2))),
            yes("dm", "Diabetes"),
            yes("stroke", "Stroke, TIA or thromboembolism", 2),
            yes("vascular", "Vascular disease (previous MI, peripheral arterial disease, aortic plaque)"),
            yes("female", "Female sex")
        ),
        bands = listOf(
            band(0, 0, "Low risk", "No anticoagulation"),
            band(1, 1, "Low to moderate", "A man: consider anticoagulation. A woman scoring 1 for sex alone: low risk, no anticoagulation"),
            band(2, 2, "Moderate", "A man: anticoagulation recommended. A woman: consider anticoagulation"),
            band(3, 9, "High risk", "Anticoagulation recommended (weigh the bleeding risk, HAS-BLED)")
        ),
        source = "Lip GYH et al. Chest 2010;137:263; ESC AF guideline 2020 (Hindricks G et al. Eur Heart J 2021;42:373); NICE NG196 (2021).",
        note = "The ESC 2024 guideline drops the sex point (CHA\u2082DS\u2082-VA): anticoagulation recommended from 2, considered at 1.")

    // Pisters R et al. Chest 2010;138:1093.
    val hasbled = WardScore(
        id = "hasbled", name = "HAS-BLED",
        purpose = "Major bleeding risk on anticoagulation for atrial fibrillation.",
        items = listOf(
            yes("htn", "Hypertension: uncontrolled, systolic over 160 mmHg"),
            yes("renal", "Abnormal renal function: dialysis, transplant, or creatinine 200 \u00B5mol/L (2.26 mg/dL) or more"),
            yes("liver", "Abnormal liver function: cirrhosis, or bilirubin over 2\u00D7 and AST/ALT/ALP over 3\u00D7 normal"),
            yes("stroke", "Stroke"),
            yes("bleeding", "Bleeding history or predisposition"),
            yes("inr", "Labile INR (time in range below 60%)"),
            yes("elderly", "Elderly: over 65"),
            yes("drugs", "Drugs: antiplatelets or NSAIDs"),
            yes("alcohol", "Alcohol: 8 or more drinks a week")
        ),
        bands = listOf(
            band(0, 2, "Low to moderate", "Bleeding risk not high"),
            band(3, 9, "High risk", "3 or more: correct what can be corrected and review more often \u2014 not by itself a reason to withhold anticoagulation")
        ),
        source = "Pisters R et al. Chest 2010;138:1093; ESC AF guideline 2020.")

    // Antman EM et al. JAMA 2000;284:835.
    val timi = WardScore(
        id = "timi", name = "TIMI score (UA/NSTEMI)",
        purpose = "Short-term risk in unstable angina or NSTEMI.",
        items = listOf(
            yes("age", "Age 65 or over"),
            yes("risk", "3 or more CAD risk factors (family history, hypertension, high cholesterol, diabetes, current smoker)"),
            yes("known", "Known coronary stenosis of 50% or more"),
            yes("aspirin", "Aspirin taken in the past 7 days"),
            yes("angina", "Severe angina: 2 or more episodes in 24 hours"),
            yes("st", "ST deviation of 0.5 mm or more"),
            yes("marker", "Raised cardiac marker")
        ),
        bands = listOf(
            band(0, 1, "Low", "14-day death, MI or urgent revascularisation about 4.7%"),
            band(2, 2, "Low", "About 8.3%"),
            band(3, 3, "Intermediate", "About 13.2%"),
            band(4, 4, "Intermediate", "About 19.9%"),
            band(5, 5, "High", "About 26.2%"),
            band(6, 7, "High", "About 40.9%")
        ),
        source = "Antman EM et al. JAMA 2000;284:835.")

    // Six AJ et al. Neth Heart J 2008;16:191; Backus BE et al. Int J
    // Cardiol 2013;168:2153.
    val heart = WardScore(
        id = "heart", name = "HEART score",
        purpose = "Major adverse cardiac events within 6 weeks, for chest pain in the emergency department.",
        items = listOf(
            pick("history", "History", listOf(c("Slightly suspicious", 0), c("Moderately suspicious", 1), c("Highly suspicious", 2))),
            pick("ecg", "ECG", listOf(c("Normal", 0), c("Non-specific repolarisation change", 1), c("Significant ST deviation", 2))),
            pick("age", "Age", listOf(c("Under 45", 0), c("45\u201364", 1), c("65 or over", 2))),
            pick("risk", "Risk factors", listOf(c("None known", 0), c("1\u20132", 1), c("3 or more, or known atherosclerotic disease", 2))),
            pick("troponin", "Troponin", listOf(c("At or below the normal limit", 0), c("1\u20133\u00D7 the normal limit", 1), c("Over 3\u00D7 the normal limit", 2)))
        ),
        bands = listOf(
            band(0, 3, "Low", "6-week MACE about 0.9\u20131.7%: early discharge may be considered"),
            band(4, 6, "Moderate", "6-week MACE about 12\u201316.6%: admit for observation and further tests"),
            band(7, 10, "High", "6-week MACE about 50\u201365%: early invasive strategy")
        ),
        source = "Six AJ et al. Neth Heart J 2008;16:191; Backus BE et al. Int J Cardiol 2013;168:2153.",
        note = "Risk factors: hypertension, high cholesterol, diabetes, obesity (BMI over 30), smoking (current or stopped within 3 months), family history. Atherosclerotic disease: previous MI, PCI or CABG, stroke or TIA, peripheral arterial disease.")

    // gastroenterology and hepatology

    // Pugh RNH et al. Br J Surg 1973;60:646.
    val childPugh = WardScore(
        id = "childPugh", name = "Child\u2013Pugh score",
        purpose = "Severity of chronic liver disease (cirrhosis).",
        items = listOf(
            pick("bili", "Bilirubin", listOf(c("Below 34 \u00B5mol/L (below 2 mg/dL)", 1), c("34\u201350 \u00B5mol/L (2\u20133 mg/dL)", 2), c("Above 50 \u00B5mol/L (above 3 mg/dL)", 3))),
            pick("alb", "Albumin", listOf(c("Above 35 g/L (above 3.5 g/dL)", 1), c("28\u201335 g/L (2.8\u20133.5 g/dL)", 2), c("Below 28 g/L (below 2.8 g/dL)", 3))),
            pick("inr", "INR", listOf(c("Below 1.7", 1), c("1.7\u20132.3", 2), c("Above 2.3", 3))),
            pick("ascites", "Ascites", listOf(c("None", 1), c("Mild (or controlled with diuretics)", 2), c("Moderate to severe (or refractory)", 3))),
            pick("enceph", "Encephalopathy", listOf(c("None", 1), c("Grade 1\u20132 (or controlled with treatment)", 2), c("Grade 3\u20134 (or refractory)", 3)))
        ),
        bands = listOf(
            band(5, 6, "Class A", "Well-compensated disease"),
            band(7, 9, "Class B", "Significant functional compromise"),
            band(10, 15, "Class C", "Decompensated disease")
        ),
        source = "Child CG, Turcotte JG. 1964; Pugh RNH et al. Br J Surg 1973;60:646.",
        note = "Commonly quoted survival: about 100% at 1 year and 85% at 2 years for class A, 80% and 60% for B, 45% and 35% for C. MELD-Na predicts short-term mortality better.")

    // Blatchford O et al. Lancet 2000;356:1318.
    val blatchford = WardScore(
        id = "blatchford", name = "Glasgow\u2013Blatchford score",
        purpose = "Need for intervention in an upper GI bleed, at presentation, before endoscopy.",
        items = listOf(
            pick("urea", "Blood urea", listOf(c("Below 6.5 mmol/L (BUN below 18.2 mg/dL)", 0), c("6.5\u20137.9 mmol/L (BUN 18.2\u201322.3)", 2),
                                        c("8.0\u20139.9 mmol/L (BUN 22.4\u201327.9)", 3), c("10.0\u201324.9 mmol/L (BUN 28\u201369.9)", 4),
                                        c("25 mmol/L or more (BUN 70 or more)", 6))),
            pick("hb", "Haemoglobin", listOf(c("Men 130 g/L or more; women 120 or more", 0), c("Men 120\u2013129 g/L (12.0\u201312.9 g/dL)", 1),
                                        c("Women 100\u2013119 g/L (10.0\u201311.9 g/dL)", 1), c("Men 100\u2013119 g/L (10.0\u201311.9 g/dL)", 3),
                                        c("Either sex below 100 g/L (below 10 g/dL)", 6))),
            pick("sbp", "Systolic BP", listOf(c("110 mmHg or more", 0), c("100\u2013109", 1), c("90\u201399", 2), c("Below 90", 3))),
            yes("pulse", "Pulse 100/min or more"),
            yes("melaena", "Presentation with melaena"),
            yes("syncope", "Presentation with syncope", 2),
            yes("liver", "Hepatic disease", 2),
            yes("heart", "Cardiac failure", 2)
        ),
        bands = listOf(
            band(0, 0, "Very low risk", "May be suitable for outpatient management and endoscopy"),
            band(1, 5, "Not low risk", "Admit for endoscopy; some guidelines accept 1 as low risk"),
            band(6, 23, "High risk", "6 or more: over 50% need an intervention (transfusion, endoscopic therapy or surgery)")
        ),
        source = "Blatchford O et al. Lancet 2000;356:1318; Stanley AJ et al. BMJ 2017;356:i6432; NICE CG141.",
        note = "Women with Hb 120\u2013129 g/L score 0; the man-only bands apply only to men.")

    // Ranson JH et al. Surg Gynecol Obstet 1974;139:69 (the admission
    // criteria, non-gallstone pancreatitis).
    val ranson = WardScore(
        id = "ranson", name = "Ranson criteria (on admission)",
        purpose = "Severity of acute pancreatitis: the five criteria at admission.",
        items = listOf(
            yes("age", "Age over 55"),
            yes("wbc", "White cells over 16 \u00D710\u2079/L"),
            yes("glucose", "Glucose over 11.1 mmol/L (200 mg/dL)"),
            yes("ldh", "LDH over 350 IU/L"),
            yes("ast", "AST over 250 IU/L")
        ),
        bands = listOf(
            band(0, 2, "Fewer than 3", "Severe pancreatitis less likely so far; the 48-hour criteria complete the score"),
            band(3, 5, "3 or more", "Predicts severe pancreatitis")
        ),
        source = "Ranson JH et al. Surg Gynecol Obstet 1974;139:69; Ranson JH. Am J Gastroenterol 1982;77:633.",
        note = "At 48 hours: haematocrit fall over 10 points, urea (BUN) rise over 1.8 mmol/L (5 mg/dL), calcium below 2 mmol/L (8 mg/dL), PaO\u2082 below 8 kPa (60 mmHg), base deficit over 4, fluid sequestration over 6 L. Across all 11, mortality was about 1% with 0\u20132, 15% with 3\u20134, 40% with 5\u20136 and near 100% with 7 or more. Gallstone pancreatitis (1982) uses age over 70, white cells over 18, glucose over 12.2 mmol/L (220 mg/dL), LDH over 400.")

    // Alvarado A. Ann Emerg Med 1986;15:557.
    val alvarado = WardScore(
        id = "alvarado", name = "Alvarado score",
        purpose = "Likelihood of acute appendicitis (MANTRELS).",
        items = listOf(
            yes("migration", "Migration of pain to the right iliac fossa"),
            yes("anorexia", "Anorexia"),
            yes("nausea", "Nausea or vomiting"),
            yes("tender", "Tenderness in the right iliac fossa", 2),
            yes("rebound", "Rebound tenderness"),
            yes("temp", "Temperature 37.3 \u00B0C or more"),
            yes("wbc", "White cells over 10 \u00D710\u2079/L", 2),
            yes("shift", "Left shift (neutrophils over 75%)")
        ),
        bands = listOf(
            band(0, 4, "Unlikely", "Appendicitis unlikely"),
            band(5, 6, "Possible", "Compatible with appendicitis: observe, image"),
            band(7, 8, "Probable", "Appendicitis probable"),
            band(9, 10, "Very probable", "Appendicitis very probable")
        ),
        source = "Alvarado A. Ann Emerg Med 1986;15:557.")

    // acute care

    // Royal College of Physicians. National Early Warning Score (NEWS) 2,
    // December 2017. SpO2 scale 1.
    val news2 = WardScore(
        id = "news2", name = "NEWS2",
        purpose = "Early warning score for acute illness in adults (not in pregnancy or under 16).",
        items = listOf(
            pick("rr", "Respiratory rate (/min)", listOf(c("12\u201320", 0), c("9\u201311", 1), c("21\u201324", 2), c("8 or less", 3), c("25 or more", 3))),
            pick("spo2", "SpO\u2082 (scale 1, %)", listOf(c("96 or more", 0), c("94\u201395", 1), c("92\u201393", 2), c("91 or less", 3))),
            pick("air", "Air or oxygen", listOf(c("Air", 0), c("Oxygen", 2))),
            pick("sbp", "Systolic BP (mmHg)", listOf(c("111\u2013219", 0), c("101\u2013110", 1), c("91\u2013100", 2), c("90 or less", 3), c("220 or more", 3))),
            pick("pulse", "Pulse (/min)", listOf(c("51\u201390", 0), c("41\u201350", 1), c("91\u2013110", 1), c("111\u2013130", 2), c("40 or less", 3), c("131 or more", 3))),
            pick("acvpu", "Consciousness", listOf(c("Alert", 0), c("New confusion, or responds to voice or pain, or unresponsive", 3))),
            pick("temp", "Temperature (\u00B0C)", listOf(c("36.1\u201338.0", 0), c("35.1\u201336.0", 1), c("38.1\u201339.0", 1), c("39.1 or more", 2), c("35.0 or less", 3)))
        ),
        bands = listOf(
            band(0, 0, "Low", "Routine monitoring, at least 12-hourly"),
            band(1, 4, "Low", "A registered nurse assesses and decides whether to monitor more often or escalate; at least 4\u20136-hourly"),
            band(5, 6, "Medium", "Key threshold: urgent review by a clinician competent in acute illness; at least hourly"),
            band(7, 20, "High", "Emergency response by a critical-care team; continuous monitoring")
        ),
        source = "Royal College of Physicians. National Early Warning Score (NEWS) 2. London: RCP, 2017.",
        note = "Scale 2 replaces the SpO\u2082 row for a patient with confirmed hypercapnic respiratory failure and a prescribed target of 88\u201392% (not built in here).",
        redFlag = WardRedFlag(points = 3.0, below = 5.0,
                             band = band(3, 4, "Low\u2013medium", "A single parameter scoring 3: urgent ward-based review by a clinician; at least hourly")))

    // obstetrics and neonates

    // Apgar V. Curr Res Anesth Analg 1953;32:260.
    val apgar = WardScore(
        id = "apgar", name = "APGAR score",
        purpose = "A newborn\u2019s condition at 1 and 5 minutes after birth.",
        items = listOf(
            pick("appearance", "Appearance (colour)", listOf(c("Pink all over", 2), c("Body pink, hands and feet blue", 1), c("Blue or pale all over", 0))),
            pick("pulse", "Pulse", listOf(c("100/min or more", 2), c("Below 100/min", 1), c("Absent", 0))),
            pick("grimace", "Grimace (reflex irritability)", listOf(c("Cries, coughs or pulls away", 2), c("Grimace", 1), c("No response", 0))),
            pick("activity", "Activity (tone)", listOf(c("Active movement", 2), c("Some flexion", 1), c("Limp", 0))),
            pick("respiration", "Respiration", listOf(c("Good, strong cry", 2), c("Slow, irregular or weak", 1), c("Absent", 0)))
        ),
        bands = listOf(
            band(0, 3, "Low", "0\u20133"),
            band(4, 6, "Moderately abnormal", "4\u20136"),
            band(7, 10, "Reassuring", "7\u201310")
        ),
        source = "Apgar V. Curr Res Anesth Analg 1953;32:260; AAP/ACOG Committee Opinion 644 (2015).",
        note = "Resuscitation is never delayed for the 1-minute score. A score under 7 at 5 minutes is repeated every 5 minutes to 20 minutes.")

    // Bishop EH. Obstet Gynecol 1964;24:266.
    val bishop = WardScore(
        id = "bishop", name = "Bishop score",
        purpose = "How ready the cervix is for induction of labour.",
        items = listOf(
            pick("dilation", "Dilatation (cm)", listOf(c("Closed", 0), c("1\u20132", 1), c("3\u20134", 2), c("5 or more", 3))),
            pick("effacement", "Effacement (%)", listOf(c("0\u201330", 0), c("40\u201350", 1), c("60\u201370", 2), c("80 or more", 3))),
            pick("station", "Station", listOf(c("\u22123", 0), c("\u22122", 1), c("\u22121 or 0", 2), c("+1 or +2", 3))),
            pick("consistency", "Consistency", listOf(c("Firm", 0), c("Medium", 1), c("Soft", 2))),
            pick("position", "Position", listOf(c("Posterior", 0), c("Mid", 1), c("Anterior", 2)))
        ),
        bands = listOf(
            band(0, 6, "Unfavourable", "6 or less: cervical ripening first (prostaglandin or a balloon)"),
            band(7, 8, "Favourable", "More than 6 (NICE): amniotomy and oxytocin can be considered"),
            band(9, 13, "Very favourable", "More than 8 (ACOG): induction about as likely to succeed as spontaneous labour")
        ),
        source = "Bishop EH. Obstet Gynecol 1964;24:266; NICE NG207 (2021); ACOG Practice Bulletin 107 (2009).")
}
