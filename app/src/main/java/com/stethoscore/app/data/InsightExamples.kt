package com.stethoscore.app.data

// A port of upstream/ios/RedPen/Features/Insight/InsightExamples.swift: the
// ready-made practice history iOS seeds once in the owner's personal build,
// so the readiness card, calibration, "Why you lose marks" and the rule
// sheet have something real-looking the first time they are opened.
// Android has no personal build, so nothing seeds it: [make] is the history
// itself, worked out the same way (the same sets, the same seed, the same
// rolls), for a build that wants it. Everything it makes is marked isExample.
object InsightExamples {
    const val key = "examples.insight.v1"

    /** One example question: the right answer, the wrong ones, and why. */
    private class Item(val stem: String, val correct: String, val wrong: List<String>, val explanation: String)

    private class Entry(val subject: String, val accuracy: Double, val items: List<Item>)

    /** Four short practice sets, one per subject; each roughly how often that subject is got right. */
    private val subjects: List<Entry> = listOf(
        Entry("Cardiology", 0.72, listOf(
            Item("A 68-year-old man has an irregularly irregular pulse of 132/min, BP 124/78 and palpitations for three days. He is otherwise well. What is the most appropriate first drug to control his heart rate?",
                "Bisoprolol", listOf("Amiodarone", "Digoxin", "Flecainide"),
                "In stable atrial fibrillation a beta-blocker (or a rate-limiting calcium-channel blocker) is first line for rate control. Digoxin is kept for sedentary patients or as an add-on."),
            Item("A 55-year-old woman has 40 minutes of central crushing chest pain. The ECG shows ST elevation in II, III and aVF. Which artery is most likely occluded?",
                "Right coronary artery", listOf("Left anterior descending", "Left circumflex", "Left main stem"),
                "The inferior leads II, III and aVF look at territory supplied by the right coronary artery in most people. The left anterior descending supplies the anterior wall (V1-V4)."),
            Item("Which murmur is most typical of aortic stenosis?",
                "Ejection systolic murmur radiating to the carotids",
                listOf("Early diastolic murmur at the left sternal edge", "Pansystolic murmur radiating to the axilla", "Mid-diastolic rumble at the apex"),
                "Aortic stenosis gives an ejection systolic murmur loudest in the aortic area and radiating to the carotids. A soft second heart sound suggests severe disease."),
            Item("A 30-year-old has pleuritic chest pain eased by sitting forward. The ECG shows widespread saddle-shaped ST elevation with PR depression. What is the most likely diagnosis?",
                "Acute pericarditis", listOf("Anterior STEMI", "Pulmonary embolism", "Aortic dissection"),
                "Pericarditis causes widespread concave ST elevation and PR depression that do not fit one coronary territory. Pain eased by leaning forward is the classic clue."),
        )),
        Entry("Respiratory", 0.8, listOf(
            Item("Which spirometry finding is most characteristic of COPD?",
                "Post-bronchodilator FEV1/FVC below 0.7",
                listOf("Reduced FVC with a normal FEV1/FVC ratio", "Raised transfer factor", "Full reversibility with salbutamol"),
                "COPD is defined by persistent airflow obstruction: a post-bronchodilator FEV1/FVC below 0.7. Marked reversibility points to asthma instead."),
            Item("A 60-year-old with a 40 pack-year history has hyponatraemia with concentrated urine and a central lung mass. Which tumour type is most likely?",
                "Small cell carcinoma", listOf("Squamous cell carcinoma", "Adenocarcinoma", "Mesothelioma"),
                "SIADH is the classic paraneoplastic syndrome of small cell lung cancer. Squamous cell carcinoma is the one linked to hypercalcaemia through PTHrP."),
            Item("Which organism is the most common cause of community-acquired pneumonia in adults?",
                "Streptococcus pneumoniae", listOf("Haemophilus influenzae", "Staphylococcus aureus", "Legionella pneumophila"),
                "Streptococcus pneumoniae is the commonest cause of community-acquired pneumonia in adults of every age."),
            Item("Ten days after a caesarean section a 35-year-old becomes suddenly breathless and tachycardic. The chest X-ray is normal. Which investigation best confirms the likely diagnosis?",
                "CT pulmonary angiography", listOf("D-dimer", "Spirometry", "Echocardiography"),
                "With a high clinical probability of pulmonary embolism, go straight to CTPA. A D-dimer only helps to rule PE out when the probability is low, and is raised after surgery anyway."),
        )),
        Entry("Endocrinology", 0.6, listOf(
            Item("A 45-year-old woman has weight loss, a diffuse goitre, proptosis and pretibial myxoedema. What is the most likely cause?",
                "Graves disease", listOf("Toxic multinodular goitre", "Subacute thyroiditis", "Toxic adenoma"),
                "Eye signs and pretibial myxoedema are specific to Graves disease, caused by antibodies that stimulate the TSH receptor."),
            Item("A patient taking carbimazole develops a sore throat and fever. What is the most important next step?",
                "Stop carbimazole and check a full blood count urgently",
                listOf("Start amoxicillin", "Halve the dose of carbimazole", "Recheck thyroid function in six weeks"),
                "Agranulocytosis is a rare but dangerous side effect of carbimazole. Stop the drug and check the neutrophil count at once."),
            Item("Which electrolyte pattern is most typical of primary adrenal insufficiency?",
                "Low sodium, high potassium",
                listOf("High sodium, low potassium", "Low sodium, low potassium", "High calcium, low phosphate"),
                "Loss of aldosterone causes sodium loss and potassium retention: hyponatraemia with hyperkalaemia."),
            Item("A 19-year-old with type 1 diabetes is vomiting. Glucose is 28 mmol/L, ketones 5.2 mmol/L and pH 7.12. Once IV fluids are running, what is the next treatment?",
                "Fixed-rate intravenous insulin infusion",
                listOf("Subcutaneous rapid-acting insulin", "Intravenous sodium bicarbonate", "Variable-rate insulin infusion"),
                "UK guidance for DKA uses a fixed-rate IV insulin infusion at 0.1 units/kg/hour alongside fluids. Bicarbonate is not given routinely."),
        )),
        Entry("Neurology", 0.45, listOf(
            Item("A 70-year-old has sudden right arm and face weakness with expressive dysphasia that began 90 minutes ago. CT head shows no haemorrhage. What is the most appropriate treatment?",
                "Intravenous thrombolysis", listOf("Aspirin 300 mg and observe", "Warfarin", "Urgent carotid endarterectomy"),
                "Within 4.5 hours of an ischaemic stroke, once haemorrhage is excluded on CT, IV thrombolysis is given unless there is a contraindication."),
            Item("A 28-year-old woman has painful loss of vision in one eye over several days, with poor colour vision. What is the most likely diagnosis?",
                "Optic neuritis", listOf("Central retinal artery occlusion", "Acute angle-closure glaucoma", "Retinal detachment"),
                "Optic neuritis gives subacute painful loss of vision in one eye with red desaturation and a relative afferent pupillary defect; it is often the first sign of multiple sclerosis."),
            Item("Which drug is first line for trigeminal neuralgia?",
                "Carbamazepine", listOf("Amitriptyline", "Gabapentin", "Sumatriptan"),
                "Carbamazepine is the first-line treatment for trigeminal neuralgia."),
            Item("Which lesion causes foot drop with weak eversion but normal inversion?",
                "Common peroneal nerve palsy", listOf("L5 root lesion", "Tibial nerve palsy", "Femoral nerve palsy"),
                "A common peroneal palsy weakens dorsiflexion and eversion but spares inversion (tibialis posterior, tibial nerve). An L5 root lesion weakens inversion as well."),
        )),
    )

    /** A small, repeatable number sequence, so every build starts with the same example history. */
    class Dice(private var state: ULong) {
        fun next(): Double {
            state = state * 6_364_136_223_846_793_005UL + 1_442_695_040_888_963_407UL
            return (state shr 11).toDouble() / (1UL shl 53).toDouble()
        }
    }

    /** What [make] adds: the sets, and the history, reasons and rules over them and the library's own examples. */
    data class Seed(
        val sets: List<StudySet>,
        val events: List<AnswerEvent>,
        val reasons: Map<String, MistakeNote>,
        val rules: Map<String, StudyRule>,
    )

    /**
     * The example sets and their made-up history, against [library] (whose
     * own "Example:" MCQ sets join in at half right). [folderId] is the
     * examples folder, when there is one.
     */
    fun make(library: List<StudySet>, ruled: Set<String> = emptySet(), folderId: String? = null,
             now: Long = System.currentTimeMillis()): Seed {
        val sets = mutableListOf<StudySet>()
        val accuracyBySet = HashMap<String, Double>()
        subjects.forEachIndexed { index, entry ->
            val questions = entry.items.mapIndexed { offset, item ->
                // the right answer in a different place in each question
                val options = item.wrong.toMutableList()
                val slot = (offset + index) % (item.wrong.size + 1)
                options.add(slot, item.correct)
                MCQQuestion(stem = item.stem, options = options, correctIndex = slot, explanation = item.explanation)
            }
            val set = StudySet(name = "Example: ${entry.subject} practice", subject = entry.subject, kind = StudySetKind.MCQ,
                folderId = folderId, questions = questions)
            accuracyBySet[set.id] = entry.accuracy
            sets.add(set)
        }
        // the example sets the library already has join in too
        val earlier = library.filter { it.kind == StudySetKind.MCQ && it.name.startsWith("Example:") && it.id !in accuracyBySet }
        for (set in earlier) accuracyBySet[set.id] = 0.5

        val rng = Dice(0x5EED_1A5EUL)
        val events = mutableListOf<AnswerEvent>()
        val questionsInOrder = mutableListOf<Pair<MCQQuestion, String>>()
        for (set in sets + earlier) {
            val accuracy = accuracyBySet[set.id] ?: 0.6
            for (question in set.questions) {
                questionsInOrder.add(question to set.subject.trim().ifEmpty { "General" })
                val times = 2 + (rng.next() * 3).toInt()
                repeat(times) {
                    // spread over the last ten days
                    val daysAgo = rng.next() * 10
                    val at = now - (daysAgo * 86_400_000).toLong()
                    val right = rng.next() < accuracy
                    val roll = rng.next()
                    val confidence = if (right) (if (roll < 0.6) "sure" else if (roll < 0.9) "maybe" else "guess")
                    else (if (roll < 0.3) "sure" else if (roll < 0.65) "maybe" else "guess")
                    events.add(AnswerEvent(question.id, right, at, confidence, isExample = true))
                }
            }
        }
        events.sortBy { it.at }

        // a reason for each question whose latest answer was wrong, weighted
        // the way students usually lose marks
        val reasons = listOf("didntKnow", "didntKnow", "didntKnow", "misread", "misread", "changedAnswer", "outOfTime", "lookalikes", "lookalikes")
        val latest = HashMap<String, AnswerEvent>()
        for (event in events) latest[event.questionId] = event
        val notes = LinkedHashMap<String, MistakeNote>()
        val rules = LinkedHashMap<String, StudyRule>()
        for ((question, subject) in questionsInOrder) {
            val last = latest[question.id] ?: continue
            if (last.correct) continue
            val reason = reasons[minOf(reasons.size - 1, (rng.next() * reasons.size).toInt())]
            notes[question.id] = MistakeNote(reason, last.at, isExample = true)
            if (rules.size < 8 && question.id !in ruled) {
                rules[question.id] = RuleWriter.plainRule(question, subject).copy(date = last.at, isExample = true)
            }
        }
        return Seed(sets, events, notes, rules)
    }
}
