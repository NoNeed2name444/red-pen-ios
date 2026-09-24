import Foundation

/// Ready-made practice history for the owner's personal build, so the
/// readiness card, calibration, "Why you lose marks" and the rule sheet all
/// have something real-looking to show the first time they are opened.
///
/// Seeded once, after the example sets (SampleData.seedPersonalBuild), and
/// never in the App Store app. Everything written here is marked `isExample`
/// so the screens can say so.
enum InsightExamples {
    static let key = "examples.insight.v1"

    /// One example question: the right answer, the wrong ones, and why.
    private struct Item {
        var stem: String
        var correct: String
        var wrong: [String]
        var explanation: String
    }

    /// Four short practice sets, one per subject, so the Progress screen has
    /// several subjects to compare. Each is roughly how often that subject is
    /// got right in the made-up history.
    private static let subjects: [(subject: String, accuracy: Double, items: [Item])] = [
        ("Cardiology", 0.72, [
            Item(stem: "A 68-year-old man has an irregularly irregular pulse of 132/min, BP 124/78 and palpitations for three days. He is otherwise well. What is the most appropriate first drug to control his heart rate?",
                 correct: "Bisoprolol", wrong: ["Amiodarone", "Digoxin", "Flecainide"],
                 explanation: "In stable atrial fibrillation a beta-blocker (or a rate-limiting calcium-channel blocker) is first line for rate control. Digoxin is kept for sedentary patients or as an add-on."),
            Item(stem: "A 55-year-old woman has 40 minutes of central crushing chest pain. The ECG shows ST elevation in II, III and aVF. Which artery is most likely occluded?",
                 correct: "Right coronary artery", wrong: ["Left anterior descending", "Left circumflex", "Left main stem"],
                 explanation: "The inferior leads II, III and aVF look at territory supplied by the right coronary artery in most people. The left anterior descending supplies the anterior wall (V1-V4)."),
            Item(stem: "Which murmur is most typical of aortic stenosis?",
                 correct: "Ejection systolic murmur radiating to the carotids",
                 wrong: ["Early diastolic murmur at the left sternal edge", "Pansystolic murmur radiating to the axilla", "Mid-diastolic rumble at the apex"],
                 explanation: "Aortic stenosis gives an ejection systolic murmur loudest in the aortic area and radiating to the carotids. A soft second heart sound suggests severe disease."),
            Item(stem: "A 30-year-old has pleuritic chest pain eased by sitting forward. The ECG shows widespread saddle-shaped ST elevation with PR depression. What is the most likely diagnosis?",
                 correct: "Acute pericarditis", wrong: ["Anterior STEMI", "Pulmonary embolism", "Aortic dissection"],
                 explanation: "Pericarditis causes widespread concave ST elevation and PR depression that do not fit one coronary territory. Pain eased by leaning forward is the classic clue.")
        ]),
        ("Respiratory", 0.8, [
            Item(stem: "Which spirometry finding is most characteristic of COPD?",
                 correct: "Post-bronchodilator FEV1/FVC below 0.7",
                 wrong: ["Reduced FVC with a normal FEV1/FVC ratio", "Raised transfer factor", "Full reversibility with salbutamol"],
                 explanation: "COPD is defined by persistent airflow obstruction: a post-bronchodilator FEV1/FVC below 0.7. Marked reversibility points to asthma instead."),
            Item(stem: "A 60-year-old with a 40 pack-year history has hyponatraemia with concentrated urine and a central lung mass. Which tumour type is most likely?",
                 correct: "Small cell carcinoma", wrong: ["Squamous cell carcinoma", "Adenocarcinoma", "Mesothelioma"],
                 explanation: "SIADH is the classic paraneoplastic syndrome of small cell lung cancer. Squamous cell carcinoma is the one linked to hypercalcaemia through PTHrP."),
            Item(stem: "Which organism is the most common cause of community-acquired pneumonia in adults?",
                 correct: "Streptococcus pneumoniae", wrong: ["Haemophilus influenzae", "Staphylococcus aureus", "Legionella pneumophila"],
                 explanation: "Streptococcus pneumoniae is the commonest cause of community-acquired pneumonia in adults of every age."),
            Item(stem: "Ten days after a caesarean section a 35-year-old becomes suddenly breathless and tachycardic. The chest X-ray is normal. Which investigation best confirms the likely diagnosis?",
                 correct: "CT pulmonary angiography", wrong: ["D-dimer", "Spirometry", "Echocardiography"],
                 explanation: "With a high clinical probability of pulmonary embolism, go straight to CTPA. A D-dimer only helps to rule PE out when the probability is low, and is raised after surgery anyway.")
        ]),
        ("Endocrinology", 0.6, [
            Item(stem: "A 45-year-old woman has weight loss, a diffuse goitre, proptosis and pretibial myxoedema. What is the most likely cause?",
                 correct: "Graves disease", wrong: ["Toxic multinodular goitre", "Subacute thyroiditis", "Toxic adenoma"],
                 explanation: "Eye signs and pretibial myxoedema are specific to Graves disease, caused by antibodies that stimulate the TSH receptor."),
            Item(stem: "A patient taking carbimazole develops a sore throat and fever. What is the most important next step?",
                 correct: "Stop carbimazole and check a full blood count urgently",
                 wrong: ["Start amoxicillin", "Halve the dose of carbimazole", "Recheck thyroid function in six weeks"],
                 explanation: "Agranulocytosis is a rare but dangerous side effect of carbimazole. Stop the drug and check the neutrophil count at once."),
            Item(stem: "Which electrolyte pattern is most typical of primary adrenal insufficiency?",
                 correct: "Low sodium, high potassium",
                 wrong: ["High sodium, low potassium", "Low sodium, low potassium", "High calcium, low phosphate"],
                 explanation: "Loss of aldosterone causes sodium loss and potassium retention: hyponatraemia with hyperkalaemia."),
            Item(stem: "A 19-year-old with type 1 diabetes is vomiting. Glucose is 28 mmol/L, ketones 5.2 mmol/L and pH 7.12. Once IV fluids are running, what is the next treatment?",
                 correct: "Fixed-rate intravenous insulin infusion",
                 wrong: ["Subcutaneous rapid-acting insulin", "Intravenous sodium bicarbonate", "Variable-rate insulin infusion"],
                 explanation: "UK guidance for DKA uses a fixed-rate IV insulin infusion at 0.1 units/kg/hour alongside fluids. Bicarbonate is not given routinely.")
        ]),
        ("Neurology", 0.45, [
            Item(stem: "A 70-year-old has sudden right arm and face weakness with expressive dysphasia that began 90 minutes ago. CT head shows no haemorrhage. What is the most appropriate treatment?",
                 correct: "Intravenous thrombolysis", wrong: ["Aspirin 300 mg and observe", "Warfarin", "Urgent carotid endarterectomy"],
                 explanation: "Within 4.5 hours of an ischaemic stroke, once haemorrhage is excluded on CT, IV thrombolysis is given unless there is a contraindication."),
            Item(stem: "A 28-year-old woman has painful loss of vision in one eye over several days, with poor colour vision. What is the most likely diagnosis?",
                 correct: "Optic neuritis", wrong: ["Central retinal artery occlusion", "Acute angle-closure glaucoma", "Retinal detachment"],
                 explanation: "Optic neuritis gives subacute painful loss of vision in one eye with red desaturation and a relative afferent pupillary defect; it is often the first sign of multiple sclerosis."),
            Item(stem: "Which drug is first line for trigeminal neuralgia?",
                 correct: "Carbamazepine", wrong: ["Amitriptyline", "Gabapentin", "Sumatriptan"],
                 explanation: "Carbamazepine is the first-line treatment for trigeminal neuralgia."),
            Item(stem: "Which lesion causes foot drop with weak eversion but normal inversion?",
                 correct: "Common peroneal nerve palsy", wrong: ["L5 root lesion", "Tibial nerve palsy", "Femoral nerve palsy"],
                 explanation: "A common peroneal palsy weakens dorsiflexion and eversion but spares inversion (tibialis posterior, tibial nerve). An L5 root lesion weakens inversion as well.")
        ])
    ]

    /// A small, repeatable number sequence, so every personal build starts
    /// with the same example history rather than a different one each time.
    private struct Dice {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64(1) << 53)
        }
    }

    /// Adds the example sets and their made-up history, once, in a personal
    /// build only.
    @MainActor
    static func seed(into store: Store, now: Date = Date()) {
        guard PersonalBuild.isOn, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let folderId = store.folders.first { $0.name.hasPrefix("Examples") }?.id
        var sets: [StudySet] = []
        var accuracyBySet: [UUID: Double] = [:]
        for (index, entry) in subjects.enumerated() {
            var set = StudySet(name: "Example: \(entry.subject) practice", subject: entry.subject, kind: .mcq)
            set.folderId = folderId
            set.questions = entry.items.enumerated().map { offset, item in
                // the right answer in a different place in each question
                var options = item.wrong
                let slot = (offset + index) % (item.wrong.count + 1)
                options.insert(item.correct, at: slot)
                return MCQQuestion(stem: item.stem, options: options, correctIndex: slot,
                                   explanation: item.explanation)
            }
            accuracyBySet[set.id] = entry.accuracy
            sets.append(set)
        }
        store.library.append(contentsOf: sets)

        // the example sets the personal build already has join in too
        let earlier = store.library.filter {
            $0.kind == .mcq && $0.name.hasPrefix("Example:") && accuracyBySet[$0.id] == nil
        }
        for set in earlier { accuracyBySet[set.id] = 0.5 }

        var rng = Dice(state: 0x5EED_1A5E)
        var events: [AnswerEvent] = []
        var questionsInOrder: [(question: MCQQuestion, subject: String)] = []
        for set in sets + earlier {
            let accuracy = accuracyBySet[set.id] ?? 0.6
            for question in set.questions {
                questionsInOrder.append((question: question, subject: Store.subjectName(set)))
                let times = 2 + Int(rng.next() * 3)
                for _ in 0..<times {
                    // spread over the last ten days, during the day
                    let daysAgo = rng.next() * 10
                    let date = now.addingTimeInterval(-daysAgo * 86_400)
                    let right = rng.next() < accuracy
                    let roll = rng.next()
                    let confidence: AnswerConfidence
                    if right {
                        confidence = roll < 0.6 ? .sure : (roll < 0.9 ? .maybe : .guess)
                    } else {
                        confidence = roll < 0.3 ? .sure : (roll < 0.65 ? .maybe : .guess)
                    }
                    events.append(AnswerEvent(questionId: question.id, correct: right, date: date,
                                              confidence: confidence, isExample: true))
                }
            }
        }
        events.sort { $0.date < $1.date }

        for event in events {
            var past = store.answerHistory[event.questionId] ?? []
            past.append(event.correct)
            store.answerHistory[event.questionId] = Array(past.suffix(Store.historyDepth))
        }
        store.answerLog = (events + store.answerLog).sorted { $0.date < $1.date }

        // a reason for each question whose latest answer was wrong, weighted
        // the way students usually lose marks
        let reasons: [MistakeReason] = [.didntKnow, .didntKnow, .didntKnow, .misread, .misread,
                                        .changedAnswer, .outOfTime, .lookalikes, .lookalikes]
        var latest: [UUID: AnswerEvent] = [:]
        for event in events { latest[event.questionId] = event }
        var ruled = 0
        for entry in questionsInOrder {
            guard let last = latest[entry.question.id], !last.correct else { continue }
            let reason = reasons[min(reasons.count - 1, Int(rng.next() * Double(reasons.count)))]
            store.mistakeReasons[entry.question.id] = MistakeNote(reason: reason, date: last.date, isExample: true)
            if ruled < 8, store.ruleSheet[entry.question.id] == nil {
                var rule = RuleWriter.plainRule(for: entry.question, subject: entry.subject)
                rule.date = last.date
                rule.isExample = true
                store.ruleSheet[entry.question.id] = rule
                ruled += 1
            }
        }
        store.save()
    }
}
