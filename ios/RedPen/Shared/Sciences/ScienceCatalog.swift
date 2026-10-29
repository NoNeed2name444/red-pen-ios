import Foundation

/// What the Sciences screens offer, laid out the way a medical course is:
/// by subject (anatomy, physiology, pathology and the rest) and by body
/// system. Each topic is a short note written for this app, a few points to
/// remember, the tools that let the student try it, and the parts of the 3D
/// atlas that show it.
///
/// Written for this app from standard medical science (facts, not anyone's
/// text; docs/sciences/sources.md). Foundation only: the screens choose
/// symbols and colours.

enum ScienceSubject: String, CaseIterable, Identifiable {
    case anatomy, physiology, biochemistry, pathology, microbiology, immunology, genetics, pharmacology, biostatistics
    var id: String { rawValue }

    var name: String {
        switch self {
        case .biostatistics: return "Biostatistics"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// One line on what the subject is, for the hub.
    var blurb: String {
        switch self {
        case .anatomy: return "The body's structures in 3D, where they lie and what supplies them"
        case .physiology: return "How the body works, as simulations you can change"
        case .biochemistry: return "Enzymes and the pathways of metabolism, step by step"
        case .pathology: return "How disease changes cells, tissues and organs"
        case .microbiology: return "The bacteria that matter, and how a lab tells them apart"
        case .immunology: return "The immune cells, antibodies, complement and hypersensitivity"
        case .genetics: return "Inheritance, carrier risk and the genetic code"
        case .pharmacology: return "What the body does to a drug, and the drug to the body"
        case .biostatistics: return "Reading tests and trials in numbers"
        }
    }
}

enum BodySystem: String, CaseIterable, Identifiable {
    case cardiovascular, respiratory, renal, digestive, endocrine, reproductive, nervous, musculoskeletal, blood, skin
    var id: String { rawValue }

    var name: String {
        switch self {
        case .renal: return "Renal and urinary"
        case .blood: return "Blood and immune"
        case .nervous: return "Nervous and senses"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// An interactive tool, each backed by one of the science engines.
enum ScienceTool: String, CaseIterable, Identifiable {
    case atlas
    case membranePotential, actionPotential, cardiacCycle, haemodynamics, starling
    case oxygenCurve, alveolarGas, renalClearance, acidBase
    case enzymeKinetics, pathways
    case shock, infarct, necrosis, glomerular, tumourNames
    case microbeKey, microbes, growthCurve
    case immuneCells, antibodyResponse, hypersensitivity, complement
    case punnett, hardyWeinberg, geneticCode
    case pharmacokinetics
    case diagnosticTests
    var id: String { rawValue }

    var name: String {
        switch self {
        case .atlas: return "3D anatomy atlas"
        case .membranePotential: return "Membrane potential"
        case .actionPotential: return "Action potential"
        case .cardiacCycle: return "Cardiac cycle"
        case .haemodynamics: return "Blood pressure and flow"
        case .starling: return "Capillary forces"
        case .oxygenCurve: return "Oxygen dissociation curve"
        case .alveolarGas: return "Alveolar gas"
        case .renalClearance: return "Renal clearance"
        case .acidBase: return "Blood gas reader"
        case .enzymeKinetics: return "Enzyme kinetics"
        case .pathways: return "Metabolic pathways"
        case .shock: return "Shock profiles"
        case .infarct: return "Infarct by age"
        case .necrosis: return "Kinds of necrosis"
        case .glomerular: return "Nephrotic or nephritic"
        case .tumourNames: return "Naming tumours"
        case .microbeKey: return "Bacteria key"
        case .microbes: return "Organisms"
        case .growthCurve: return "Bacterial growth"
        case .immuneCells: return "Immune cells"
        case .antibodyResponse: return "Antibody response"
        case .hypersensitivity: return "Hypersensitivity"
        case .complement: return "Complement"
        case .punnett: return "Punnett square"
        case .hardyWeinberg: return "Carrier risk"
        case .geneticCode: return "Genetic code"
        case .pharmacokinetics: return "Drug levels"
        case .diagnosticTests: return "Tests and trials"
        }
    }

    var subject: ScienceSubject {
        switch self {
        case .atlas: return .anatomy
        case .membranePotential, .actionPotential, .cardiacCycle, .haemodynamics, .starling,
             .oxygenCurve, .alveolarGas, .renalClearance, .acidBase: return .physiology
        case .enzymeKinetics, .pathways: return .biochemistry
        case .shock, .infarct, .necrosis, .glomerular, .tumourNames: return .pathology
        case .microbeKey, .microbes, .growthCurve: return .microbiology
        case .immuneCells, .antibodyResponse, .hypersensitivity, .complement: return .immunology
        case .punnett, .hardyWeinberg, .geneticCode: return .genetics
        case .pharmacokinetics: return .pharmacology
        case .diagnosticTests: return .biostatistics
        }
    }

    /// What it lets the student do, in a line.
    var blurb: String {
        switch self {
        case .atlas: return "Turn the body, peel back the skin, and tap any structure for its name"
        case .membranePotential: return "Change the ions inside and out and watch the resting potential follow"
        case .actionPotential: return "Fire a neuron, block its channels, and see why it refuses to fire twice"
        case .cardiacCycle: return "The pressure-volume loop and pressures through a beat, for ten hearts"
        case .haemodynamics: return "Mean pressure, output and resistance, and why radius rules flow"
        case .starling: return "The pressures across a capillary, and the four ways to make oedema"
        case .oxygenCurve: return "Shift the curve with acid, carbon dioxide and heat, and compare fetal blood"
        case .alveolarGas: return "The alveolar oxygen and the A-a gradient from a blood gas"
        case .renalClearance: return "Clearance, GFR, filtration fraction and FENa from urine and plasma"
        case .acidBase: return "A blood gas read step by step: primary disorder, compensation, gaps"
        case .enzymeKinetics: return "Michaelis-Menten and its three inhibitions, on both plots"
        case .pathways: return "Eight pathways step by step, with the rate-limiting enzyme and its disease"
        case .shock: return "Each kind of shock by its pressures, and which one a set of numbers fits"
        case .infarct: return "What an infarct looks like from the first hour to the scar"
        case .necrosis: return "Six kinds of necrosis, what each looks like and where"
        case .glomerular: return "Nephrotic against nephritic, and the diseases behind each"
        case .tumourNames: return "Benign or malignant, by tissue, and the names that break the rule"
        case .microbeKey: return "Gram stain to species, one bench test at a time"
        case .microbes: return "Thirty-nine organisms with what they cause"
        case .growthCurve: return "Lag, log, stationary and death phases of a culture"
        case .immuneCells: return "Who does what, innate and adaptive, with their markers"
        case .antibodyResponse: return "IgM and IgG after a first and a second exposure"
        case .hypersensitivity: return "The four types: mechanism, timing and examples"
        case .complement: return "Three pathways to one attack, and what each deficiency causes"
        case .punnett: return "Cross any two genotypes and read the ratios"
        case .hardyWeinberg: return "From how common a disease is to the risk for a carrier's child"
        case .geneticCode: return "Transcribe, translate, and classify a mutation"
        case .pharmacokinetics: return "Doses, half-lives and steady state, as curves"
        case .diagnosticTests: return "Sensitivity, predictive values, likelihood ratios and NNT"
        }
    }
}

struct ScienceTopic: Hashable, Identifiable {
    let id: String
    let title: String
    let subject: ScienceSubject
    /// Empty for general topics that belong to no one system.
    let systems: [BodySystem]
    let note: String
    let points: [String]
    let tools: [ScienceTool]
    /// Parts of the 3D atlas (AnatomyPart ids) that show it.
    let atlas: [String]
}

enum ScienceCatalog {

    static func topics(_ subject: ScienceSubject) -> [ScienceTopic] { topics.filter { $0.subject == subject } }

    static func topics(_ system: BodySystem) -> [ScienceTopic] { topics.filter { $0.systems.contains(system) } }

    static func topic(_ id: String) -> ScienceTopic? { topics.first { $0.id == id } }

    static func tools(_ subject: ScienceSubject) -> [ScienceTool] { ScienceTool.allCases.filter { $0.subject == subject } }

    /// Topics whose title, note or points hold every word of the query.
    static func search(_ query: String) -> [ScienceTopic] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard !words.isEmpty else { return [] }
        return topics.filter { t in
            let text = ([t.title, t.note] + t.points).joined(separator: " ").lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    static let topics: [ScienceTopic] = anatomy + physiology + biochemistry + pathology + microbiology
        + immunology + genetics + pharmacology + biostatistics

    // MARK: anatomy

    static let anatomy: [ScienceTopic] = [
        ScienceTopic(id: "anatomy-heart", title: "The heart", subject: .anatomy, systems: [.cardiovascular],
                     note: "The heart lies in the middle mediastinum, two thirds of it left of the midline, its apex at the fifth intercostal space in the midclavicular line. The right atrium takes in the venae cavae; the left ventricle, the thickest-walled chamber, pumps into the aorta.",
                     points: ["Valves: tricuspid and pulmonary on the right, mitral and aortic on the left",
                              "The left anterior descending artery feeds the front of the left ventricle, the front two thirds of the septum and the apex",
                              "The circumflex feeds the lateral wall; the right coronary the right ventricle and, in most people, the inferior wall and the AV node"],
                     tools: [.atlas, .cardiacCycle], atlas: ["heart"]),
        ScienceTopic(id: "anatomy-vessels", title: "The great arteries and veins", subject: .anatomy, systems: [.cardiovascular],
                     note: "The arch of the aorta gives off the brachiocephalic trunk, the left common carotid and the left subclavian. The abdominal aorta's branches come off at landmark levels, and the portal vein forms behind the neck of the pancreas from the superior mesenteric and splenic veins.",
                     points: ["Coeliac trunk T12, superior mesenteric L1, renal arteries L1 to L2, inferior mesenteric L3, the bifurcation L4",
                              "Where portal and systemic veins meet (oesophagus, rectum, round the umbilicus) they swell in portal hypertension",
                              "The left renal vein crosses in front of the aorta, under the superior mesenteric artery"],
                     tools: [.atlas], atlas: ["vessels"]),
        ScienceTopic(id: "anatomy-lungs", title: "Lungs and airways", subject: .anatomy, systems: [.respiratory],
                     note: "The right lung has three lobes and the left two, with the lingula in place of a middle lobe. The trachea divides at the carina, level with the sternal angle (T4 to T5); the right main bronchus is wider, shorter and more upright, so inhaled objects usually go right.",
                     points: ["Each lung has about ten bronchopulmonary segments, each with its own bronchus and artery: the unit a surgeon can remove",
                              "The pulmonary arteries carry deoxygenated blood and run with the bronchi; the veins run between segments"],
                     tools: [.atlas], atlas: ["lungs", "airways"]),
        ScienceTopic(id: "anatomy-larynx", title: "The larynx", subject: .anatomy, systems: [.respiratory],
                     note: "The larynx is built on the thyroid and cricoid cartilages, the cricoid being the only complete ring in the airway. The arytenoids pivot on the cricoid to open and close the vocal folds.",
                     points: ["Posterior cricoarytenoid: the only muscle that opens the folds",
                              "Every intrinsic muscle has the recurrent laryngeal nerve except cricothyroid (external laryngeal nerve)",
                              "The left recurrent nerve loops under the aortic arch: an aneurysm or a lung cancer there causes hoarseness"],
                     tools: [.atlas], atlas: ["larynx", "larynx-muscles", "hyoid"]),
        ScienceTopic(id: "anatomy-gut", title: "The digestive tract", subject: .anatomy, systems: [.digestive],
                     note: "The gut is supplied in three parts: the foregut by the coeliac trunk, the midgut (to two thirds of the way along the transverse colon) by the superior mesenteric artery, the hindgut by the inferior mesenteric. Most of the duodenum and the ascending and descending colon lie behind the peritoneum.",
                     points: ["The jejunum and ileum hang on a mesentery; the ileum has more fat and more arcades",
                              "The transverse and sigmoid colon have mesenteries and move",
                              "The salivary glands: parotid, submandibular and sublingual"],
                     tools: [.atlas], atlas: ["mouth", "small-intestine", "colon"]),
        ScienceTopic(id: "anatomy-liver", title: "Liver, gallbladder and pancreas", subject: .anatomy, systems: [.digestive],
                     note: "The liver has eight segments, each with its own portal branch and hepatic vein drainage, and two blood supplies: the portal vein brings about three quarters of its blood, the hepatic artery the rest. Bile runs down the common bile duct to meet the pancreatic duct at the ampulla, opening into the duodenum at the major papilla.",
                     points: ["The cystic duct joins the common hepatic duct to make the common bile duct",
                              "The pancreas's head sits in the curve of the duodenum, behind the peritoneum",
                              "The accessory pancreatic duct opens at the minor papilla, above the major one"],
                     tools: [.atlas], atlas: ["liver", "gallbladder", "biliary-tree", "pancreas"]),
        ScienceTopic(id: "anatomy-urinary", title: "Kidneys and urinary tract", subject: .anatomy, systems: [.renal],
                     note: "The kidneys lie behind the peritoneum from T12 to L3, the right a little lower under the liver. At the hilum, from front to back, come the renal vein, artery and pelvis.",
                     points: ["Stones stick where the ureter narrows: where it leaves the pelvis, where it crosses the iliac vessels, where it enters the bladder",
                              "The trigone lies between the two ureteric openings and the urethra's",
                              "The male urethra runs through the prostate, the pelvic floor, then the penis"],
                     tools: [.atlas], atlas: ["kidneys", "bladder", "urethra"]),
        ScienceTopic(id: "anatomy-male-pelvis", title: "The male pelvic organs", subject: .anatomy, systems: [.reproductive],
                     note: "Each vas deferens joins the duct of a seminal vesicle to make an ejaculatory duct, which opens into the prostatic urethra on the seminal colliculus. The prostate surrounds the first part of the urethra below the bladder.",
                     points: ["The peripheral zone, felt from the rectum, is where most prostate cancers start",
                              "The transition zone, round the urethra, is where benign enlargement starts"],
                     tools: [.atlas], atlas: ["prostate", "genital-ducts"]),
        ScienceTopic(id: "anatomy-endocrine", title: "The endocrine glands", subject: .anatomy, systems: [.endocrine],
                     note: "The pituitary sits in the sella turcica just below the optic chiasm, held to the hypothalamus by its stalk. The thyroid wraps the front of the trachea, its isthmus over the second to fourth rings; the adrenals cap the kidneys; the islets are scattered through the pancreas.",
                     points: ["A pituitary tumour growing up presses on the chiasm: loss of both outer fields of vision",
                              "Islet cells: alpha make glucagon, beta insulin, delta somatostatin",
                              "The atlas has the pancreas and hypothalamus; the thyroid, adrenals and pituitary are still to come"],
                     tools: [.atlas], atlas: ["pancreas", "brain"]),
        ScienceTopic(id: "anatomy-brain", title: "The brain", subject: .anatomy, systems: [.nervous],
                     note: "The frontal lobe plans and moves, the parietal feels, the temporal hears and remembers, the occipital sees. Deep inside lie the basal ganglia, the thalamus (the relay to the cortex) and the hypothalamus; below, the brainstem and the cerebellum, which coordinates movement on its own side.",
                     points: ["Broca's area (speaking) is in the inferior frontal gyrus, Wernicke's (understanding) in the superior temporal gyrus, both on the dominant side, usually the left",
                              "The hippocampus, in the medial temporal lobe, lays down new memories",
                              "Cerebrospinal fluid flows from the lateral ventricles through the third and the aqueduct to the fourth"],
                     tools: [.atlas], atlas: ["brain"]),
        ScienceTopic(id: "anatomy-spine", title: "The spinal cord and column", subject: .anatomy, systems: [.nervous, .musculoskeletal],
                     note: "There are 7 cervical, 12 thoracic and 5 lumbar vertebrae, then the sacrum and coccyx. In adults the cord ends at L1 to L2, so a lumbar puncture goes in at L3 to L4 or L4 to L5, below it (the iliac crests mark L4).",
                     points: ["Fine touch and position sense go up the dorsal columns on the same side and cross in the medulla",
                              "Pain and temperature cross within a segment or two and go up the spinothalamic tract",
                              "Movement comes down the corticospinal tract, which crosses at the pyramids in the medulla"],
                     tools: [.atlas], atlas: ["spinal-cord", "vertebral-column"]),
        ScienceTopic(id: "anatomy-eye", title: "The eye and the visual pathway", subject: .anatomy, systems: [.nervous],
                     note: "Six muscles move each eye: the lateral rectus has the abducens nerve (VI), the superior oblique the trochlear (IV), the rest the oculomotor (III). Fibres from the nasal half of each retina cross at the chiasm, so a lesion there takes out both outer fields.",
                     points: ["The superior oblique pulls the eye down when it is turned in: tested looking down towards the nose",
                              "Optic nerve, chiasm, tract, lateral geniculate body, optic radiation, occipital cortex"],
                     tools: [.atlas], atlas: ["eyes", "eye-muscles", "optic-nerves"]),
        ScienceTopic(id: "anatomy-lower-limb", title: "Pelvis, hip and knee", subject: .anatomy, systems: [.musculoskeletal],
                     note: "The hip bone forms from the ilium, ischium and pubis, which fuse at the acetabulum. The femoral head gets most of its blood from the medial circumflex femoral artery, so a displaced neck fracture can leave the head to die.",
                     points: ["The anterior cruciate stops the tibia sliding forward on the femur",
                              "The medial meniscus is fixed to the tibial collateral ligament, so it tears more often",
                              "Rectus femoris crosses both hip and knee: it flexes one and straightens the other"],
                     tools: [.atlas], atlas: ["pelvis", "legs", "knee-muscles"]),
        ScienceTopic(id: "anatomy-lymphoid", title: "Spleen, thymus and tonsils", subject: .anatomy, systems: [.blood],
                     note: "The spleen lies under the left 9th to 11th ribs; its red pulp clears old red cells, its white pulp mounts immune responses. The thymus, large in children and shrinking after puberty, is where T cells learn to tolerate self.",
                     points: ["Without a spleen, encapsulated bacteria are the danger: pneumococcus, Haemophilus type b, meningococcus",
                              "The tonsils (palatine, pharyngeal, lingual and tubal) ring the throat"],
                     tools: [.atlas], atlas: ["spleen", "thymus", "tonsils"]),
        ScienceTopic(id: "anatomy-skin", title: "The skin", subject: .anatomy, systems: [.skin],
                     note: "The epidermis renews itself from the basal layer up through the spinous and granular layers to the dead, flattened cells of the stratum corneum; thick skin of palms and soles adds a stratum lucidum. Below lies the dermis with its vessels, nerves, hair follicles and glands.",
                     points: ["Melanocytes sit in the basal layer and hand pigment up to the keratinocytes",
                              "The atlas draws the skin as a faint shell, so the organs show through"],
                     tools: [.atlas], atlas: ["skin"]),
    ]

    // MARK: physiology

    static let physiology: [ScienceTopic] = [
        ScienceTopic(id: "phys-membrane", title: "The resting membrane potential", subject: .physiology, systems: [.nervous],
                     note: "Each ion has an equilibrium potential set by its concentrations either side (the Nernst equation). The resting potential is the average of them weighted by how permeable the membrane is to each (the Goldman equation), and at rest that means mostly potassium.",
                     points: ["Rest is about -70 mV, near potassium's -90 mV",
                              "A high potassium outside depolarises cells: the danger in hyperkalaemia"],
                     tools: [.membranePotential], atlas: []),
        ScienceTopic(id: "phys-action-potential", title: "The action potential", subject: .physiology, systems: [.nervous],
                     note: "At threshold, sodium channels open and the membrane shoots up towards sodium's equilibrium. They then shut (inactivate) while slower potassium channels open, bringing the membrane back down and briefly below rest.",
                     points: ["Absolute refractory period: the sodium channels are inactivated and no stimulus works",
                              "Relative refractory period: a stronger stimulus can fire it",
                              "Tetrodotoxin blocks the sodium channels: no action potential at all"],
                     tools: [.actionPotential, .membranePotential], atlas: []),
        ScienceTopic(id: "phys-cardiac-cycle", title: "The cardiac cycle", subject: .physiology, systems: [.cardiovascular],
                     note: "Each beat has four phases: filling, isovolumetric contraction, ejection and isovolumetric relaxation. The first heart sound is the mitral and tricuspid valves closing, the second the aortic and pulmonary.",
                     points: ["On the pressure-volume loop, the end-diastolic volume is preload, the pressure of ejection afterload",
                              "Stronger contraction moves the end-systolic corner up and left",
                              "Stenosis and regurgitation each change the loop's shape in their own way"],
                     tools: [.cardiacCycle], atlas: ["heart"]),
        ScienceTopic(id: "phys-haemodynamics", title: "Blood pressure and flow", subject: .physiology, systems: [.cardiovascular],
                     note: "Cardiac output is heart rate times stroke volume, and the pressure drop across the circulation is output times resistance. Flow through a tube goes with the fourth power of its radius, which is why the arterioles, by changing their width, set the resistance.",
                     points: ["Mean arterial pressure is about diastolic plus a third of the pulse pressure",
                              "Halving a radius cuts the flow to a sixteenth",
                              "Ejection fraction: stroke volume over end-diastolic volume, normally about 55 to 70%"],
                     tools: [.haemodynamics], atlas: ["vessels"]),
        ScienceTopic(id: "phys-starling", title: "Capillary exchange and oedema", subject: .physiology, systems: [.cardiovascular],
                     note: "Fluid leaves a capillary where its hydrostatic pressure beats the plasma proteins' oncotic pull, and most of it comes back further along or through the lymph. Oedema is what happens when that balance tips.",
                     points: ["Higher capillary pressure: heart failure, venous obstruction",
                              "Lower oncotic pressure: nephrotic syndrome, cirrhosis, starvation",
                              "Leakier capillaries: inflammation, burns",
                              "Blocked lymph: tumour, surgery, filariasis"],
                     tools: [.starling], atlas: []),
        ScienceTopic(id: "phys-oxygen", title: "Oxygen transport", subject: .physiology, systems: [.respiratory, .blood],
                     note: "Haemoglobin's curve is S-shaped because each oxygen bound makes the next easier. It shifts right, giving oxygen up more easily, with acid, carbon dioxide, heat and 2,3-BPG: just what working tissue has.",
                     points: ["P50, the oxygen pressure at half saturation, is about 27 mmHg",
                              "Shifted left: fetal haemoglobin, carbon monoxide, cold, alkalosis",
                              "Oxygen content is 1.34 x Hb x saturation plus 0.003 x PO2"],
                     tools: [.oxygenCurve], atlas: ["lungs"]),
        ScienceTopic(id: "phys-gas-exchange", title: "Gas exchange", subject: .physiology, systems: [.respiratory],
                     note: "The alveolar oxygen comes from the alveolar gas equation: the inspired oxygen less what carbon dioxide displaces. The gap between it and the arterial oxygen, the A-a gradient, tells a lung problem from a breathing one.",
                     points: ["A normal gradient is about age / 4 + 4 mmHg",
                              "Low oxygen with a normal gradient: hypoventilation or altitude",
                              "A wide gradient: ventilation-perfusion mismatch, shunt or a diffusion problem"],
                     tools: [.alveolarGas, .oxygenCurve], atlas: ["lungs", "airways"]),
        ScienceTopic(id: "phys-renal", title: "Renal clearance", subject: .physiology, systems: [.renal],
                     note: "Clearance is the volume of plasma cleared of a substance each minute: urine concentration times urine flow over plasma concentration. Inulin's clearance is the GFR, PAH's is close to the renal plasma flow.",
                     points: ["Filtration fraction: GFR over renal plasma flow, about 20%",
                              "FENa under 1% points to a prerenal cause, over 2% to tubular injury",
                              "Creatinine clearance slightly overestimates GFR, as the tubules secrete a little"],
                     tools: [.renalClearance], atlas: ["kidneys"]),
        ScienceTopic(id: "phys-acid-base", title: "Acid and base", subject: .physiology, systems: [.renal, .respiratory],
                     note: "The pH follows the ratio of bicarbonate to carbon dioxide (the Henderson-Hasselbalch equation). Read a gas in order: the pH, the primary change, whether the compensation is what it should be, then the anion gap.",
                     points: ["In a metabolic acidosis the expected PaCO2 is 1.5 x HCO3 + 8 (Winter's formula), give or take 2",
                              "Anion gap: sodium less chloride and bicarbonate, about 12",
                              "Add 2.5 to the gap for every 10 g/L the albumin is below 40"],
                     tools: [.acidBase], atlas: []),
        ScienceTopic(id: "phys-endocrine", title: "Hormone axes and feedback", subject: .physiology, systems: [.endocrine],
                     note: "Most glands answer to the pituitary, which answers to the hypothalamus, and the final hormone switches both off (negative feedback). So the pair of levels tells where the fault is.",
                     points: ["Low thyroxine with a high TSH: the thyroid has failed (primary)",
                              "Low thyroxine with a low or normal TSH: the pituitary or hypothalamus (secondary)",
                              "CRH, then ACTH, then cortisol; cortisol switches both off"],
                     tools: [], atlas: ["brain"]),
        ScienceTopic(id: "phys-gut", title: "Digestion and absorption", subject: .physiology, systems: [.digestive],
                     note: "Parietal cells pump acid with the proton pump, driven by gastrin, histamine and acetylcholine. Secretin calls for bicarbonate from the pancreas; cholecystokinin for its enzymes, and squeezes the gallbladder.",
                     points: ["Iron is absorbed in the duodenum",
                              "Vitamin B12, bound to intrinsic factor, and bile salts are absorbed in the terminal ileum"],
                     tools: [], atlas: ["small-intestine", "pancreas", "gallbladder"]),
        ScienceTopic(id: "phys-reproduction", title: "The menstrual cycle", subject: .physiology, systems: [.reproductive],
                     note: "In the follicular phase FSH grows follicles and their oestradiol rises until it switches to positive feedback, and the LH surge sets off ovulation. The corpus luteum then makes progesterone; without the hCG of a pregnancy it fails after about 14 days, and menstruation follows.",
                     points: ["The luteal phase is about 14 days; it is the follicular phase that varies",
                              "In the testis, LH drives the Leydig cells to make testosterone, FSH the Sertoli cells"],
                     tools: [], atlas: []),
        ScienceTopic(id: "phys-muscle", title: "Muscle contraction", subject: .physiology, systems: [.musculoskeletal],
                     note: "The action potential runs down the T tubules; in skeletal muscle the voltage sensor there pulls open the calcium channels of the sarcoplasmic reticulum. Calcium binds troponin, tropomyosin moves off the actin, and the myosin heads cycle.",
                     points: ["Heart muscle needs calcium coming in to release more calcium (calcium-induced calcium release)",
                              "ATP lets myosin let go: without it the muscle locks, as in rigor mortis"],
                     tools: [], atlas: ["knee-muscles", "eye-muscles"]),
        ScienceTopic(id: "phys-skin", title: "Skin: barrier, heat and vitamin D", subject: .physiology, systems: [.skin],
                     note: "The stratum corneum keeps water in and microbes out. Skin sheds heat by sweating and widening its vessels, and holds it by narrowing them.",
                     points: ["UVB turns 7-dehydrocholesterol in the skin into vitamin D3",
                              "The liver then adds a 25-hydroxyl, the kidney the 1-alpha that makes it active"],
                     tools: [], atlas: ["skin"]),
    ]

    // MARK: biochemistry

    static let biochemistry: [ScienceTopic] = [
        ScienceTopic(id: "bio-enzymes", title: "Enzyme kinetics", subject: .biochemistry, systems: [],
                     note: "Km is the substrate concentration that gives half the maximum rate, so a low Km means a tight grip. Inhibitors tell themselves apart by what they do to Km and Vmax.",
                     points: ["Competitive: Km goes up, Vmax stays; enough substrate wins",
                              "Non-competitive: Vmax goes down, Km stays",
                              "Uncompetitive: both go down",
                              "On a Lineweaver-Burk plot, the y-intercept is 1/Vmax and the x-intercept -1/Km"],
                     tools: [.enzymeKinetics], atlas: []),
        ScienceTopic(id: "bio-glycolysis", title: "Glycolysis and the citric acid cycle", subject: .biochemistry, systems: [],
                     note: "Glycolysis turns glucose into two pyruvates, for a net 2 ATP and 2 NADH, its pace set by phosphofructokinase-1. Pyruvate dehydrogenase makes acetyl-CoA for the citric acid cycle.",
                     points: ["Pyruvate dehydrogenase needs thiamine, lipoic acid, CoA, FAD and NAD",
                              "Each acetyl-CoA through the cycle gives 3 NADH, 1 FADH2, 1 GTP and 2 CO2"],
                     tools: [.pathways], atlas: []),
        ScienceTopic(id: "bio-fasting", title: "Fasting: making glucose and burning fat", subject: .biochemistry, systems: [.endocrine],
                     note: "In a fast, glucagon has the liver make glucose from lactate, amino acids and glycerol (gluconeogenesis) and the tissues burn fat. Long fasts turn the liver's acetyl-CoA into ketone bodies for the brain.",
                     points: ["Fructose-1,6-bisphosphatase sets the pace of gluconeogenesis",
                              "Malonyl-CoA blocks carnitine palmitoyltransferase I, so fat is not burned while it is being made"],
                     tools: [.pathways], atlas: ["liver"]),
        ScienceTopic(id: "bio-urea", title: "The urea cycle and ammonia", subject: .biochemistry, systems: [.digestive],
                     note: "The liver turns ammonia into urea, starting in the mitochondria with carbamoyl phosphate synthetase I, which needs N-acetylglutamate. A block anywhere in the cycle lets ammonia build up and poison the brain.",
                     points: ["Ornithine transcarbamylase deficiency, X-linked, is the commonest",
                              "It spills orotic acid into the urine, without the anaemia of UMP synthase deficiency"],
                     tools: [.pathways], atlas: ["liver"]),
        ScienceTopic(id: "bio-g6pd", title: "The pentose phosphate pathway and G6PD", subject: .biochemistry, systems: [.blood],
                     note: "Glucose-6-phosphate dehydrogenase makes the NADPH that keeps glutathione ready to mop up oxidants. Red cells have no other source, so when it is short an oxidant stress makes them haemolyse.",
                     points: ["Triggers: fava beans, infection, primaquine, dapsone, sulfonamides",
                              "Heinz bodies (clumped haemoglobin) and bite cells on the film"],
                     tools: [.pathways], atlas: []),
        ScienceTopic(id: "bio-haem", title: "Haem and the porphyrias", subject: .biochemistry, systems: [.blood],
                     note: "Haem is made from glycine and succinyl-CoA, its pace set by ALA synthase, which needs vitamin B6. A block further down piles up the intermediates before it: the porphyrias.",
                     points: ["Lead blocks ALA dehydratase and ferrochelatase",
                              "Acute intermittent porphyria (porphobilinogen deaminase): attacks of abdominal pain and neuropathy, no rash",
                              "Porphyria cutanea tarda (uroporphyrinogen decarboxylase), the commonest: blisters on sun-exposed skin"],
                     tools: [.pathways], atlas: []),
    ]

    // MARK: pathology

    static let pathology: [ScienceTopic] = [
        ScienceTopic(id: "path-cell-injury", title: "Cell injury and death", subject: .pathology, systems: [],
                     note: "An injured cell first swells and may gather fat; if the injury stops, it recovers. Past the point of no return, membranes and mitochondria fail and the nucleus shrinks, breaks up and fades: necrosis, which inflames what is around it.",
                     points: ["Apoptosis is death by programme: the cell shrinks, caspases cut it up, and there is no inflammation",
                              "The nucleus in necrosis: pyknosis, karyorrhexis, karyolysis"],
                     tools: [.necrosis], atlas: []),
        ScienceTopic(id: "path-inflammation", title: "Inflammation", subject: .pathology, systems: [],
                     note: "Acute inflammation starts with the vessels widening and leaking, then neutrophils, which dominate the first 6 to 24 hours before macrophages take over by 24 to 48. Chronic inflammation is lymphocytes, macrophages and plasma cells, with tissue being destroyed and repaired at once.",
                     points: ["Heat, redness, swelling, pain and loss of function",
                              "A granuloma is a ball of activated macrophages: tuberculosis, sarcoidosis, Crohn's disease"],
                     tools: [.immuneCells], atlas: []),
        ScienceTopic(id: "path-thrombosis", title: "Thrombosis, embolism and infarction", subject: .pathology, systems: [.cardiovascular],
                     note: "Thrombosis needs one of Virchow's three: an injured wall, sluggish or turbulent flow, or blood that clots too easily. Most emboli are pieces of thrombus from the deep veins of the leg, which stop in the lungs.",
                     points: ["White infarcts: an artery blocked in a solid organ with no second supply (heart, kidney, spleen)",
                              "Red infarcts: a blocked vein, loose tissue, a double supply (lung, small bowel) or blood let back in"],
                     tools: [.infarct], atlas: ["vessels"]),
        ScienceTopic(id: "path-shock", title: "Shock", subject: .pathology, systems: [.cardiovascular],
                     note: "Shock is too little blood reaching the tissues for their needs. Its kind shows in three numbers: the cardiac output, the resistance of the arterioles, and how full the heart is (the wedge pressure).",
                     points: ["Low output with high resistance: the body clamping down (hypovolaemic, cardiogenic, obstructive)",
                              "High output with low resistance: distributive, as in sepsis",
                              "A slow heart with low pressure: neurogenic"],
                     tools: [.shock, .haemodynamics], atlas: ["heart", "vessels"]),
        ScienceTopic(id: "path-mi", title: "Myocardial infarction", subject: .pathology, systems: [.cardiovascular],
                     note: "Heart muscle starts dying after 20 to 30 minutes without blood, from the inner wall outwards. Troponin rises within a few hours and stays up for a week or more; what the infarct looks like dates it.",
                     points: ["Days 3 to 7, the softest point: the time of rupture",
                              "CK-MB falls back in 2 to 3 days, so it shows a second infarct",
                              "Weeks later: Dressler syndrome, an aneurysm"],
                     tools: [.infarct, .cardiacCycle], atlas: ["heart"]),
        ScienceTopic(id: "path-atherosclerosis", title: "Atherosclerosis", subject: .pathology, systems: [.cardiovascular],
                     note: "LDL gets into an injured intima, is oxidised and eaten by macrophages, which become foam cells; smooth muscle moves in and lays down a fibrous cap over the fatty core. A cap that ruptures exposes the core, and a clot forms on it.",
                     points: ["Worst in the abdominal aorta, then the coronary, popliteal and internal carotid arteries",
                              "Risk factors: smoking, high LDL, high blood pressure, diabetes, age, family history"],
                     tools: [], atlas: ["vessels", "heart"]),
        ScienceTopic(id: "path-lung", title: "Obstructive and restrictive lung disease", subject: .pathology, systems: [.respiratory],
                     note: "Obstruction slows the air coming out: the FEV1 falls more than the FVC, so their ratio drops below 0.7. Restriction stops the lungs filling: the volumes are small, but the ratio is normal or high.",
                     points: ["Obstructive: COPD, asthma, bronchiectasis",
                              "Restrictive: lung fibrosis, chest wall deformity, weak breathing muscles",
                              "Smoking's emphysema is centriacinar, in the upper lobes; alpha-1 antitrypsin deficiency's is panacinar, in the lower"],
                     tools: [.alveolarGas], atlas: ["lungs", "airways"]),
        ScienceTopic(id: "path-glomerular", title: "Glomerular disease", subject: .pathology, systems: [.renal],
                     note: "A damaged glomerulus either leaks protein (nephrotic) or bleeds with inflammation (nephritic), and some diseases do both. The picture, the patient and a few clues narrow the cause.",
                     points: ["Nephrotic: over 3.5 g of protein a day, low albumin, oedema, high lipids",
                              "Nephritic: red cell casts, high blood pressure, a rising creatinine"],
                     tools: [.glomerular, .renalClearance], atlas: ["kidneys"]),
        ScienceTopic(id: "path-liver", title: "Cirrhosis", subject: .pathology, systems: [.digestive],
                     note: "Cirrhosis is scarring through the whole liver with nodules of regrowing cells between the scars. Its causes are mostly alcohol, hepatitis B and C, and fatty liver disease (MASLD); its consequences, a failing liver and portal hypertension.",
                     points: ["Portal hypertension: varices, ascites, a big spleen",
                              "It raises the risk of hepatocellular carcinoma",
                              "AST more than twice the ALT suggests alcohol"],
                     tools: [], atlas: ["liver", "spleen"]),
        ScienceTopic(id: "path-ibd", title: "Inflammatory bowel disease", subject: .pathology, systems: [.digestive],
                     note: "Crohn's disease can strike anywhere from mouth to anus, in patches, through the whole thickness of the wall, most often at the terminal ileum. Ulcerative colitis starts at the rectum and spreads up in one continuous stretch of the lining.",
                     points: ["Crohn's: granulomas, strictures, fistulae",
                              "Ulcerative colitis: crypt abscesses, toxic megacolon, primary sclerosing cholangitis",
                              "Both raise the risk of colorectal cancer"],
                     tools: [], atlas: ["colon", "small-intestine"]),
        ScienceTopic(id: "path-diabetes", title: "Diabetes mellitus", subject: .pathology, systems: [.endocrine],
                     note: "In type 1 diabetes the immune system destroys the beta cells, and without insulin the body tips into ketoacidosis. In type 2 the tissues resist insulin and the beta cells cannot keep up; the extreme is the hyperosmolar state.",
                     points: ["Diagnosis: fasting glucose 7.0 mmol/L or more, HbA1c 48 mmol/mol (6.5%) or more, or 11.1 two hours after a glucose load",
                              "Small vessels: eyes, kidneys, nerves; large vessels: heart attack, stroke, limbs"],
                     tools: [.pathways], atlas: ["pancreas"]),
        ScienceTopic(id: "path-prostate", title: "Prostate enlargement and cancer", subject: .pathology, systems: [.reproductive],
                     note: "Benign hyperplasia grows in the transition zone round the urethra, so it obstructs the flow early. Prostate cancer, an adenocarcinoma, mostly starts in the peripheral zone, where a finger in the rectum can feel it.",
                     points: ["Gleason grading scores how glandular the cancer still looks",
                              "PSA rises in both, and in prostatitis"],
                     tools: [.tumourNames], atlas: ["prostate", "bladder", "urethra"]),
        ScienceTopic(id: "path-stroke", title: "Stroke", subject: .pathology, systems: [.nervous],
                     note: "About 85% of strokes are ischaemic, the rest bleeds. A middle cerebral artery stroke weakens the opposite face and arm more than the leg, and on the dominant side takes speech; an anterior cerebral one takes the opposite leg.",
                     points: ["A brain infarct liquefies, unlike the heart's",
                              "Hypertension is the biggest single risk"],
                     tools: [.necrosis], atlas: ["brain", "vessels"]),
        ScienceTopic(id: "path-anaemia", title: "Anaemia by red cell size", subject: .pathology, systems: [.blood],
                     note: "The size of the red cells sorts anaemia. Small cells mean too little haemoglobin made; large ones, a DNA problem in the marrow or a membrane change; normal ones, loss, destruction, or a marrow not told to make more.",
                     points: ["Small: iron deficiency, thalassaemia, sometimes chronic disease, lead",
                              "Normal: bleeding, haemolysis, kidney disease, chronic disease",
                              "Large: B12 or folate (megaloblastic), alcohol, liver disease, hypothyroidism"],
                     tools: [.oxygenCurve], atlas: ["spleen"]),
        ScienceTopic(id: "path-osteoporosis", title: "Osteoporosis", subject: .pathology, systems: [.musculoskeletal],
                     note: "Osteoporosis is too little bone, normally mineralised, so the blood calcium, phosphate and alkaline phosphatase are normal. It shows as fractures from falls that should not break bone.",
                     points: ["A T-score of -2.5 or less on a bone density scan",
                              "Vertebral bodies, the femoral neck, the wrist"],
                     tools: [], atlas: ["vertebral-column", "pelvis", "legs"]),
        ScienceTopic(id: "path-skin-cancer", title: "Skin cancers", subject: .pathology, systems: [.skin],
                     note: "Basal cell carcinoma is the commonest: it invades locally but almost never spreads. Squamous cell carcinoma follows sun damage, often from an actinic keratosis; melanoma is rarer and the most dangerous.",
                     points: ["A mole that is asymmetrical, with an irregular border, uneven colour, over 6 mm or changing (ABCDE)",
                              "For a melanoma that has not spread, its thickness (Breslow) best predicts the outcome"],
                     tools: [.tumourNames], atlas: ["skin"]),
        ScienceTopic(id: "path-neoplasia", title: "Neoplasia", subject: .pathology, systems: [],
                     note: "A benign tumour stays where it is and looks like its tissue; a malignant one invades and can spread. The grade says how abnormal it looks, the stage how far it has gone, and the stage predicts more.",
                     points: ["Tumours spread by lymph (carcinomas, mostly), by blood (sarcomas, mostly) and across body cavities",
                              "Staging: tumour size, nodes, metastases (TNM)"],
                     tools: [.tumourNames], atlas: []),
    ]

    // MARK: microbiology

    static let microbiology: [ScienceTopic] = [
        ScienceTopic(id: "micro-identify", title: "Identifying bacteria", subject: .microbiology, systems: [],
                     note: "The Gram stain splits bacteria by their wall: thick peptidoglycan holds the purple dye (Gram-positive), a thin layer under an outer membrane does not (Gram-negative). Shape and a few bench tests take it from there.",
                     points: ["Gram-positive cocci: catalase positive is staphylococcus, negative streptococcus",
                              "Staphylococcus aureus is coagulase positive",
                              "Streptococci by haemolysis: alpha (green), beta (clear), gamma (none)"],
                     tools: [.microbeKey, .microbes], atlas: []),
        ScienceTopic(id: "micro-organisms", title: "The organisms that matter", subject: .microbiology, systems: [],
                     note: "A few dozen bacteria cause most of what a doctor treats. Each has a habitat, a way of causing disease and a signature illness.",
                     points: ["Each organism links to NCBI Taxonomy to check its name"],
                     tools: [.microbes, .microbeKey], atlas: []),
        ScienceTopic(id: "micro-growth", title: "How bacteria grow", subject: .microbiology, systems: [],
                     note: "A culture lags while it adapts, then doubles at a steady rate (the log phase), levels off as food runs out and waste builds up, then dies away.",
                     points: ["E. coli can double in about 20 minutes in good conditions",
                              "Many antibiotics work best on bacteria in the log phase"],
                     tools: [.growthCurve], atlas: []),
    ]

    // MARK: immunology

    static let immunology: [ScienceTopic] = [
        ScienceTopic(id: "imm-cells", title: "Cells of the immune system", subject: .immunology, systems: [.blood],
                     note: "The innate cells (neutrophils, macrophages, dendritic cells, natural killer cells) answer at once and the same way each time. The adaptive ones, B and T lymphocytes, take days the first time but remember.",
                     points: ["Dendritic cells carry antigen to the lymph nodes to start the adaptive response",
                              "CD4 T cells help; CD8 T cells kill infected cells"],
                     tools: [.immuneCells], atlas: ["spleen", "thymus", "tonsils"]),
        ScienceTopic(id: "imm-antibodies", title: "Antibodies", subject: .immunology, systems: [.blood],
                     note: "IgM comes first, as a pentamer; on a second meeting, memory B cells switch quickly to IgG, more of it and binding tighter. IgA guards the mucosa, IgE drives allergy and fights parasites.",
                     points: ["IgG crosses the placenta",
                              "A rising IgM means a new infection; IgG alone, an old one or a vaccine"],
                     tools: [.antibodyResponse], atlas: []),
        ScienceTopic(id: "imm-hypersensitivity", title: "Hypersensitivity", subject: .immunology, systems: [],
                     note: "Four ways the immune system does harm: type I is IgE on mast cells, in minutes; type II antibodies against a cell or tissue; type III immune complexes lodging in vessels; type IV T cells, over days.",
                     points: ["Type I: anaphylaxis, asthma, hay fever",
                              "Type IV: the tuberculin test, contact dermatitis"],
                     tools: [.hypersensitivity], atlas: []),
        ScienceTopic(id: "imm-complement", title: "Complement", subject: .immunology, systems: [.blood],
                     note: "Three pathways (classical, lectin, alternative) all lead to C3, then to the membrane attack complex. On the way it coats microbes for eating, calls in neutrophils and punches holes.",
                     points: ["Missing C5 to C9: recurrent Neisseria infections",
                              "Missing C1 inhibitor: hereditary angioedema"],
                     tools: [.complement], atlas: []),
    ]

    // MARK: genetics

    static let genetics: [ScienceTopic] = [
        ScienceTopic(id: "gen-inheritance", title: "Patterns of inheritance", subject: .genetics, systems: [],
                     note: "A dominant condition shows in every generation and each child of an affected parent has a 1 in 2 chance. A recessive one skips generations; two carriers have a 1 in 4 chance with each child.",
                     points: ["X-linked recessive: affected males through carrier mothers, never father to son",
                              "Mitochondrial: from the mother to all her children"],
                     tools: [.punnett], atlas: []),
        ScienceTopic(id: "gen-population", title: "Carrier risk", subject: .genetics, systems: [],
                     note: "The Hardy-Weinberg equation turns how common a recessive disease is into how common its carriers are: twice the square root of the incidence, near enough. That gives the risk for a relative's child.",
                     points: ["Cystic fibrosis at 1 in 2,500 births means about 1 in 25 are carriers",
                              "An unaffected sibling of an affected child has a 2 in 3 chance of being a carrier"],
                     tools: [.hardyWeinberg, .punnett], atlas: []),
        ScienceTopic(id: "gen-code", title: "The genetic code and mutations", subject: .genetics, systems: [.blood],
                     note: "DNA is transcribed into messenger RNA and read three bases at a time. A change can leave the protein the same (silent), swap one amino acid (missense), stop it short (nonsense), or shift the reading frame.",
                     points: ["Sickle cell: GAG to GTG in the beta-globin gene, glutamate to valine (Glu6Val)",
                              "A deletion of three bases keeps the frame: cystic fibrosis's commonest, F508del"],
                     tools: [.geneticCode], atlas: []),
    ]

    // MARK: pharmacology

    static let pharmacology: [ScienceTopic] = [
        ScienceTopic(id: "pharm-pk", title: "Pharmacokinetics", subject: .pharmacology, systems: [],
                     note: "The volume of distribution says how widely a drug spreads, the clearance how fast it is removed, and together they set the half-life. A regular dose reaches a steady state after four to five half-lives.",
                     points: ["Half-life = 0.693 x volume / clearance",
                              "Loading dose = target level x volume / bioavailability",
                              "Maintenance dose rate = target level x clearance / bioavailability"],
                     tools: [.pharmacokinetics], atlas: []),
        ScienceTopic(id: "pharm-pd", title: "Dose and response", subject: .pharmacology, systems: [],
                     note: "An agonist activates its receptor; a partial agonist cannot reach the full effect however much is given. A competitive antagonist shifts the dose-response curve right without lowering its top; a non-competitive one lowers the top.",
                     points: ["Potency is where the curve sits; efficacy is how high it goes",
                              "Therapeutic index: the toxic dose over the effective dose"],
                     tools: [.enzymeKinetics], atlas: []),
    ]

    // MARK: biostatistics

    static let biostatistics: [ScienceTopic] = [
        ScienceTopic(id: "stats-tests", title: "Diagnostic tests", subject: .biostatistics, systems: [],
                     note: "Sensitivity and specificity belong to the test; predictive values depend on how common the disease is in those tested. A good test for a rare disease still gives mostly false positives.",
                     points: ["A sensitive test, when negative, rules out; a specific one, when positive, rules in",
                              "Likelihood ratio of a positive: sensitivity / (1 - specificity)"],
                     tools: [.diagnosticTests], atlas: []),
        ScienceTopic(id: "stats-trials", title: "Treatment effects", subject: .biostatistics, systems: [],
                     note: "The absolute risk reduction is the control group's event rate less the treated group's. Its inverse is the number needed to treat for one patient to benefit.",
                     points: ["Relative risk reduction can sound large when the absolute benefit is small",
                              "The number needed to harm works the same way for side effects"],
                     tools: [.diagnosticTests], atlas: []),
    ]
}
