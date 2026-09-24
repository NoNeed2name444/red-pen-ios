import Foundation

/// Ready-made Reasoning material for the owner's personal build, so every
/// tool can be tried at once without writing anything: groin hernias, acute
/// coronary syndrome, and DKA against HHS.
///
/// The ids are fixed rather than made fresh on each launch, so a score from
/// yesterday still belongs to the same case today.
enum ReasoningExamples {

    /// The pretend set the examples hang from. It is never saved to the library.
    static let setId = fixed(0)

    static let set = StudySet(id: setId, name: "Examples: hernia, ACS, DKA", subject: "Medicine & surgery", kind: .book)

    static let pack = ReasoningPack(setId: setId, cases: cases, duels: duels, scripts: scripts,
                                    updatedAt: Date(timeIntervalSince1970: 0))

    private static func fixed(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "5EA50000-0000-4000-8000-%012ld", n)) ?? UUID()
    }

    // MARK: clue-by-clue cases

    static let cases: [ClueCase] = [
        ClueCase(
            id: fixed(101),
            clues: [
                "A 24-year-old man.",
                "He has noticed a lump in his right groin over the last three months.",
                "It grows when he lifts heavy boxes at work and goes away when he lies down.",
                "Standing, the lump runs down into the top of the scrotum, and you cannot get above it.",
                "It emerges above and medial to the pubic tubercle and has a cough impulse.",
                "Once reduced, pressure over the midpoint of the inguinal ligament stops it coming back on coughing.",
                "At laparoscopic repair the sac comes through the deep ring, lateral to the inferior epigastric vessels.",
            ],
            diagnosis: "Indirect inguinal hernia",
            differentials: ["Direct inguinal hernia", "Femoral hernia", "Hydrocele"],
            teachingPoint: "Lateral to the inferior epigastric vessels means indirect; the deep-ring test only suggests it.",
            decisiveClue: 6),
        ClueCase(
            id: fixed(102),
            clues: [
                "A 62-year-old man.",
                "Central chest tightness for 40 minutes that began while he was sitting watching television.",
                "He smokes and has type 2 diabetes; the pain spreads to his left arm and jaw and he is sweating.",
                "He is pale and clammy; BP 150/90 in both arms, pulse 98, chest clear, no murmur.",
                "12-lead ECG: 2 mm horizontal ST depression in V4\u{2013}V6, no ST elevation.",
                "High-sensitivity troponin on arrival is above the 99th centile.",
                "The repeat troponin three hours later has risen markedly.",
            ],
            diagnosis: "NSTEMI",
            differentials: ["Unstable angina", "Aortic dissection", "Pulmonary embolism"],
            teachingPoint: "The ECG cannot separate NSTEMI from unstable angina: a rising or falling troponin does.",
            decisiveClue: 7),
        ClueCase(
            id: fixed(103),
            clues: [
                "A 19-year-old woman.",
                "A day of vomiting and abdominal pain.",
                "For two weeks she has been very thirsty, passing a lot of urine, and losing weight.",
                "She is drowsy and dry, pulse 118, with deep, sighing breathing.",
                "Capillary glucose 24 mmol/L; urine ketones 3+.",
                "Venous blood gas: pH 7.12, bicarbonate 9 mmol/L.",
                "Blood ketones 5.2 mmol/L; serum osmolality 298 mOsm/kg.",
            ],
            diagnosis: "Diabetic ketoacidosis",
            differentials: ["Hyperosmolar hyperglycaemic state", "Acute pancreatitis", "Gastroenteritis"],
            teachingPoint: "DKA is three things together: ketones \u{2265}3 mmol/L, glucose >11 mmol/L, and pH <7.3 or bicarbonate <15.",
            decisiveClue: 6),
    ]

    // MARK: lookalike duels

    static let duels: [LookalikePair] = [
        LookalikePair(
            id: fixed(201), a: "Indirect inguinal hernia", b: "Direct inguinal hernia",
            features: [
                f(202, "Passes through the deep inguinal ring", .a, "It follows the path of the processus vaginalis."),
                f(203, "Sac lateral to the inferior epigastric vessels", .a, "The deep ring lies lateral to them."),
                f(204, "Bulges through Hesselbach's triangle", .b, "A weak posterior wall, medial to the vessels."),
                f(205, "Often descends into the scrotum", .a, "It runs the whole length of the canal."),
                f(206, "Common in children and young men", .a, "A patent processus vaginalis."),
                f(207, "Typically an older man with a weak abdominal wall", .b, "Acquired weakness of the transversalis fascia."),
                f(208, "Controlled by pressure over the deep ring", .a, "The classic sign, though unreliable in practice."),
                f(209, "Wide neck, so rarely strangulates", .b, "A broad defect lets contents slide back."),
                f(210, "Emerges above and medial to the pubic tubercle", .both, "True of every inguinal hernia."),
                f(211, "Cough impulse", .both, "Any reducible hernia has one."),
                f(212, "Mesh repair in adults, open or laparoscopic", .both, "The same operation treats both."),
                f(213, "The most common groin hernia in both sexes", .a, "Even in women it outnumbers femoral hernia."),
            ],
            bottomLine: "The inferior epigastric vessels decide it: lateral is indirect, medial is direct \u{2014} settled at operation, not by examination."),
        LookalikePair(
            id: fixed(221), a: "Femoral hernia", b: "Saphena varix",
            features: [
                f(222, "Lies below and lateral to the pubic tubercle", .both, "Both sit at the saphenofemoral region."),
                f(223, "Cough impulse", .both, "Raised pressure reaches both."),
                f(224, "Thrill when the saphenous vein below is tapped", .b, "It is a dilated vein full of blood."),
                f(225, "Bluish, soft, and empties when the leg is raised", .b, "Blood drains away on elevation."),
                f(226, "Varicose veins elsewhere in the leg", .b, "It is part of the same venous disease."),
                f(227, "Often irreducible, with a narrow neck", .a, "The femoral canal is tight and unyielding."),
                f(228, "High risk of strangulation", .a, "The narrow femoral ring traps bowel."),
                f(229, "Commoner in older women", .a, "A wider female pelvis widens the femoral canal."),
                f(230, "Can present as small-bowel obstruction", .a, "Trapped bowel obstructs, sometimes as a Richter's hernia."),
                f(231, "Duplex ultrasound shows reflux at the saphenofemoral junction", .b, "Incompetent valves let blood flow back."),
                f(232, "Repaired soon after diagnosis", .a, "Watchful waiting is unsafe for femoral hernia."),
                f(233, "A lump in the groin", .both, "Which is why they are confused."),
            ],
            bottomLine: "A saphena varix empties on lying or leg elevation and thrills when the vein below is tapped; a femoral hernia is often irreducible and must be repaired promptly."),
        LookalikePair(
            id: fixed(241), a: "Diabetic ketoacidosis", b: "Hyperosmolar hyperglycaemic state",
            features: [
                f(242, "Blood ketones \u{2265}3.0 mmol/L", .a, "Insulin deficiency drives ketogenesis."),
                f(243, "pH below 7.3 or bicarbonate below 15 mmol/L", .a, "Ketoacids consume bicarbonate."),
                f(244, "Serum osmolality \u{2265}320 mOsm/kg", .b, "Hyperosmolality is its defining feature."),
                f(245, "Glucose usually \u{2265}30 mmol/L", .b, "Days of osmotic diuresis concentrate the glucose."),
                f(246, "Develops over hours to a day", .a, "Acidosis makes people unwell fast."),
                f(247, "Develops over several days", .b, "Enough insulin to stop ketosis lets it smoulder."),
                f(248, "Typically a young person with type 1 diabetes", .a, "Absolute insulin deficiency."),
                f(249, "Typically an older person with type 2 diabetes", .b, "Relative insulin deficiency."),
                f(250, "Kussmaul breathing and abdominal pain", .a, "Respiratory compensation for acidosis; ketones irritate the gut."),
                f(251, "Insulin held back until fluids alone stop the glucose falling", .b, "A rapid fall in osmolality risks cerebral oedema."),
                f(252, "Starts with IV 0.9% sodium chloride", .both, "Both are fluid-depleted."),
                f(253, "Potassium needs close monitoring and replacement", .both, "Insulin and fluids drive potassium down."),
            ],
            bottomLine: "DKA is ketoacidosis (ketones \u{2265}3, pH <7.3 or bicarbonate <15); HHS is hyperosmolality (\u{2265}320 mOsm/kg) with glucose \u{2265}30 and little ketosis \u{2014} fluids first, insulin later."),
    ]

    private static func f(_ n: Int, _ text: String, _ side: LookalikeSide, _ why: String) -> LookalikeFeature {
        LookalikeFeature(id: fixed(n), text: text, side: side, why: why)
    }

    // MARK: disease scripts

    static let scripts: [IllnessScript] = [
        IllnessScript(
            id: fixed(301), disease: "Indirect inguinal hernia",
            who: "Far more men than women; infants (patent processus vaginalis) and young to middle-aged men; lifting, chronic cough and constipation raise the pressure.",
            timeCourse: "A groin lump that grows over months and may reach the scrotum; sudden pain if it incarcerates.",
            keyFeatures: ["Groin lump, worse on standing and straining", "Dragging discomfort", "Goes away on lying down", "May extend into the scrotum"],
            examSigns: ["Above and medial to the pubic tubercle", "Cough impulse", "Cannot get above an inguinoscrotal lump", "Controlled by deep-ring pressure (unreliable)"],
            decisiveTest: "A clinical diagnosis; ultrasound if in doubt. A sac lateral to the inferior epigastric vessels at operation confirms it is indirect.",
            firstLine: "Mesh repair (open Lichtenstein or laparoscopic) when symptomatic; emergency surgery if irreducible and tender.",
            lookalikes: ["Direct inguinal hernia", "Femoral hernia", "Hydrocele"]),
        IllnessScript(
            id: fixed(302), disease: "Femoral hernia",
            who: "Commoner in women than men, and in older and multiparous women \u{2014} though inguinal hernias still outnumber it in women.",
            timeCourse: "A small lump, often unnoticed until it becomes irreducible or obstructs the bowel.",
            keyFeatures: ["Small, firm lump at the top of the thigh", "Often painless until it strangulates", "Colicky pain, vomiting and distension if bowel is trapped"],
            examSigns: ["Below and lateral to the pubic tubercle", "Often irreducible", "Cough impulse often absent"],
            decisiveTest: "Groin ultrasound (CT if obstructed): a sac through the femoral canal, medial to the femoral vein.",
            firstLine: "Repair soon after diagnosis because of the strangulation risk; emergency surgery if strangulated.",
            lookalikes: ["Indirect inguinal hernia", "Saphena varix", "Inguinal lymphadenopathy"]),
        IllnessScript(
            id: fixed(303), disease: "Diabetic ketoacidosis",
            who: "Type 1 diabetes, often young, sometimes as the first presentation; set off by infection, missed insulin, or SGLT2 inhibitors (which can cause euglycaemic DKA).",
            timeCourse: "Develops over hours to a day.",
            keyFeatures: ["Thirst, polyuria and weight loss", "Abdominal pain and vomiting", "Drowsiness"],
            examSigns: ["Kussmaul (deep, sighing) breathing", "Ketotic, pear-drop breath", "Dehydration and tachycardia"],
            decisiveTest: "Blood ketones \u{2265}3.0 mmol/L, glucose >11 mmol/L (or known diabetes), and pH <7.3 or bicarbonate <15 mmol/L.",
            firstLine: "IV 0.9% sodium chloride, fixed-rate IV insulin at 0.1 units/kg/h, potassium replacement, and treat the trigger.",
            lookalikes: ["Hyperosmolar hyperglycaemic state", "Acute pancreatitis", "Starvation ketosis"]),
        IllnessScript(
            id: fixed(304), disease: "Hyperosmolar hyperglycaemic state",
            who: "Older people with type 2 diabetes, sometimes undiagnosed; set off by infection, stroke or MI, and drugs such as steroids and thiazides.",
            timeCourse: "Develops over several days, ending in profound dehydration.",
            keyFeatures: ["Days of thirst and polyuria", "Confusion or reduced consciousness", "Weakness"],
            examSigns: ["Marked dehydration and hypotension", "Reduced consciousness", "Seizures or focal neurology in some"],
            decisiveTest: "Serum osmolality \u{2265}320 mOsm/kg and glucose \u{2265}30 mmol/L, without significant ketonaemia (<3.0 mmol/L) or acidosis (pH >7.3, bicarbonate >15).",
            firstLine: "IV 0.9% sodium chloride first, bringing osmolality down gradually; low-dose insulin (0.05 units/kg/h) only once fluids alone stop the glucose falling; LMWH prophylaxis.",
            lookalikes: ["Diabetic ketoacidosis", "Sepsis", "Stroke"]),
    ]
}
