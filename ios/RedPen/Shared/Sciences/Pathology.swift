import Foundation

/// The general pathology a medical student is examined on, as tools: the
/// haemodynamic profile of each kind of shock, and a reader that names the
/// kind from three measurements; what a myocardial infarct looks like at
/// each age; the kinds of necrosis; nephritic against nephrotic syndrome;
/// and how tumours are named, with the names that break the rule.
///
/// Written for this app from standard pathology (facts, not anyone's
/// text). Foundation only.

/// Which way a measurement goes.
enum ShockTrend: String, Hashable, CaseIterable {
    case up, down, normal, varies

    var arrow: String {
        switch self {
        case .up: return "\u{2191}"
        case .down: return "\u{2193}"
        case .normal: return "\u{2194}"
        case .varies: return "\u{2195}"
        }
    }
}

struct ShockProfile: Hashable, Identifiable {
    enum Kind: String, Hashable, CaseIterable {
        case hypovolaemic, cardiogenic, obstructive, distributive, neurogenic
    }
    let kind: Kind
    var id: String { kind.rawValue }
    let name: String
    let cardiacOutput: ShockTrend
    /// Systemic vascular resistance.
    let resistance: ShockTrend
    /// Pulmonary capillary wedge pressure: how full the left heart is.
    let wedge: ShockTrend
    /// Central venous pressure: how full the right heart is.
    let cvp: ShockTrend
    let heartRate: ShockTrend
    let causes: [String]
    let note: String
}

/// One age of a myocardial infarct, from the start of the ischaemia.
struct InfarctStage: Hashable, Identifiable {
    var id: Double { from }
    /// Hours; `to` is infinite for the last stage.
    let from: Double
    let to: Double
    let span: String
    let gross: String
    let micro: String
    /// What the infarct risks at this age, if anything particular.
    let risk: String?
}

struct NecrosisKind: Hashable, Identifiable {
    let id: String
    let name: String
    let looks: String
    let sites: String
}

struct GlomerularDisease: Hashable, Identifiable {
    let id: String
    let name: String
    let picture: Pathology.Glomerular
    let who: String
    let clues: String
}

struct TumourTissue: Hashable, Identifiable {
    var id: String { tissue }
    let tissue: String
    /// Nil where the tissue has no benign tumour of its own.
    let benign: String?
    let malignant: String
}

enum Pathology {

    // MARK: shock

    static let shock: [ShockProfile] = [
        ShockProfile(kind: .hypovolaemic, name: "Hypovolaemic",
                     cardiacOutput: .down, resistance: .up, wedge: .down, cvp: .down, heartRate: .up,
                     causes: ["Haemorrhage", "Vomiting, diarrhoea", "Burns"],
                     note: "Too little blood comes back to the heart, so it fills poorly and its output falls; the arterioles clamp down to hold the pressure up."),
        ShockProfile(kind: .cardiogenic, name: "Cardiogenic",
                     cardiacOutput: .down, resistance: .up, wedge: .up, cvp: .up, heartRate: .up,
                     causes: ["Myocardial infarction", "Acute valve failure", "Arrhythmia", "Myocarditis"],
                     note: "The pump fails: blood backs up behind it, so the filling pressures are high while the output is low."),
        ShockProfile(kind: .obstructive, name: "Obstructive",
                     cardiacOutput: .down, resistance: .up, wedge: .varies, cvp: .up, heartRate: .up,
                     causes: ["Massive pulmonary embolism", "Cardiac tamponade", "Tension pneumothorax"],
                     note: "Something stops blood reaching or leaving the heart. The right side backs up; the wedge is low behind a pulmonary embolus and high, equal to the other pressures, in tamponade."),
        ShockProfile(kind: .distributive, name: "Distributive (septic, anaphylactic)",
                     cardiacOutput: .up, resistance: .down, wedge: .down, cvp: .down, heartRate: .up,
                     causes: ["Sepsis", "Anaphylaxis"],
                     note: "The arterioles open wide, so resistance falls and the heart pumps harder into them: warm peripheries early on. Late in sepsis the output can fall as well."),
        ShockProfile(kind: .neurogenic, name: "Neurogenic",
                     cardiacOutput: .down, resistance: .down, wedge: .down, cvp: .down, heartRate: .down,
                     causes: ["Spinal cord injury above T6", "High spinal anaesthesia"],
                     note: "Sympathetic tone is lost: the vessels dilate and the heart slows, so this is the one shock with a slow pulse."),
    ]

    static func shock(_ kind: ShockProfile.Kind) -> ShockProfile? { shock.first { $0.kind == kind } }

    /// The kinds of shock a set of measurements fits: each given trend must
    /// match the profile's, and a profile whose wedge varies fits either.
    static func readShock(cardiacOutput: ShockTrend, resistance: ShockTrend, wedge: ShockTrend) -> [ShockProfile.Kind] {
        func fits(_ profile: ShockTrend, _ given: ShockTrend) -> Bool { profile == .varies || profile == given }
        return shock.filter {
            fits($0.cardiacOutput, cardiacOutput) && fits($0.resistance, resistance) && fits($0.wedge, wedge)
        }.map(\.kind)
    }

    // MARK: the infarct by age

    static let infarct: [InfarctStage] = [
        InfarctStage(from: 0, to: 0.5, span: "Under 30 minutes",
                     gross: "Nothing to see.",
                     micro: "Nothing by light microscopy. The injury can still be reversed; the electron microscope shows swollen mitochondria and lost glycogen.",
                     risk: "Ventricular fibrillation and sudden death, most of them in the first hour."),
        InfarctStage(from: 0.5, to: 4, span: "30 minutes to 4 hours",
                     gross: "Nothing to see.",
                     micro: "Usually nothing; wavy fibres at the edge.",
                     risk: "Arrhythmia."),
        InfarctStage(from: 4, to: 12, span: "4 to 12 hours",
                     gross: "Sometimes dark mottling.",
                     micro: "Coagulative necrosis begins; oedema and haemorrhage.",
                     risk: "Arrhythmia."),
        InfarctStage(from: 12, to: 24, span: "12 to 24 hours",
                     gross: "Dark mottling.",
                     micro: "Necrosis goes on: shrunken dark nuclei, deeply pink fibres, contraction bands at the edge; the first neutrophils arrive.",
                     risk: "Arrhythmia."),
        InfarctStage(from: 24, to: 72, span: "1 to 3 days",
                     gross: "Mottled, with a yellow-tan centre.",
                     micro: "Coagulative necrosis with nuclei and striations lost; neutrophils pour in.",
                     risk: "Fibrinous pericarditis over a full-thickness infarct."),
        InfarctStage(from: 72, to: 168, span: "3 to 7 days",
                     gross: "A red border round a soft yellow-tan centre.",
                     micro: "Dead fibres break up and neutrophils die; macrophages start clearing from the edge.",
                     risk: "Rupture of the free wall, septum or a papillary muscle: the softest the infarct will be."),
        InfarctStage(from: 168, to: 240, span: "7 to 10 days",
                     gross: "At its most yellow and soft, the edges red-tan and sunken.",
                     micro: "Clearing well advanced; granulation tissue at the edges.",
                     risk: "Rupture, still."),
        InfarctStage(from: 240, to: 336, span: "10 to 14 days",
                     gross: "Red-grey, sunken edges.",
                     micro: "Granulation tissue with new vessels and collagen.",
                     risk: nil),
        InfarctStage(from: 336, to: 1344, span: "2 to 8 weeks",
                     gross: "A grey-white scar, spreading from the edge to the core.",
                     micro: "More collagen, fewer cells.",
                     risk: "Dressler syndrome (an autoimmune pericarditis); a ventricular aneurysm forming."),
        InfarctStage(from: 1344, to: .infinity, span: "Over 2 months",
                     gross: "Scarring complete.",
                     micro: "Dense collagen.",
                     risk: "Aneurysm, mural thrombus, heart failure and arrhythmia from the scar."),
    ]

    /// The stage an infarct of this age is at (hours from the start of the
    /// ischaemia); nil for a negative age.
    static func infarctStage(hours: Double) -> InfarctStage? {
        guard hours >= 0 else { return nil }
        return infarct.first { hours >= $0.from && hours < $0.to }
    }

    // MARK: necrosis

    static let necrosis: [NecrosisKind] = [
        NecrosisKind(id: "coagulative", name: "Coagulative",
                     looks: "The tissue keeps its outline for days: pale pink ghost cells without nuclei.",
                     sites: "Infarcts of solid organs, the heart, kidney and spleen; not the brain."),
        NecrosisKind(id: "liquefactive", name: "Liquefactive",
                     looks: "Enzymes digest the tissue into a liquid mass.",
                     sites: "Infarcts of the brain; abscesses, from bacteria or fungi."),
        NecrosisKind(id: "caseous", name: "Caseous",
                     looks: "White, crumbly and cheese-like: a granuloma with a dead centre.",
                     sites: "Tuberculosis; some fungi, such as histoplasmosis."),
        NecrosisKind(id: "fat", name: "Fat",
                     looks: "Lipases free fatty acids that bind calcium: chalky white spots (saponification).",
                     sites: "Acute pancreatitis. A blow to the breast causes a fat necrosis without enzymes."),
        NecrosisKind(id: "fibrinoid", name: "Fibrinoid",
                     looks: "Immune complexes and fibrin in vessel walls: bright pink and smudged.",
                     sites: "Vasculitis; malignant hypertension."),
        NecrosisKind(id: "gangrenous", name: "Gangrenous",
                     looks: "A clinical word: dead tissue, usually a limb. Dry is coagulative; wet has bacteria liquefying it.",
                     sites: "Ischaemia of the toes and foot, as in diabetes and peripheral arterial disease."),
    ]

    // MARK: the glomerulus

    enum Glomerular: String, Hashable, CaseIterable {
        case nephrotic, nephritic, mixed, neither

        var name: String {
            switch self {
            case .nephrotic: return "Nephrotic"
            case .nephritic: return "Nephritic"
            case .mixed: return "Nephrotic and nephritic"
            case .neither: return "Neither"
            }
        }
    }

    /// Nephrotic range in an adult: over 3.5 g of protein a day.
    static let nephroticProtein: Double = 3.5

    /// The picture: nephrotic for protein over 3.5 g a day (an adult), and
    /// nephritic for red cell casts (blood from the glomerulus itself).
    static func glomerular(proteinGramsPerDay: Double, redCellCasts: Bool) -> Glomerular {
        let nephrotic: Bool = proteinGramsPerDay > nephroticProtein
        switch (nephrotic, redCellCasts) {
        case (true, true): return .mixed
        case (true, false): return .nephrotic
        case (false, true): return .nephritic
        case (false, false): return .neither
        }
    }

    static let nephroticFeatures: [String] = [
        "Protein over 3.5 g a day in an adult",
        "Low albumin in the blood",
        "Oedema",
        "High lipids, and fat in the urine",
        "Clots (antithrombin lost in the urine) and infections (immunoglobulins lost)",
    ]

    static let nephriticFeatures: [String] = [
        "Blood in the urine, with red cell casts",
        "High blood pressure",
        "Less urine and a rising creatinine",
        "Some protein, under 3.5 g a day",
    ]

    static let glomerularDiseases: [GlomerularDisease] = [
        GlomerularDisease(id: "minimal-change", name: "Minimal change disease", picture: .nephrotic,
                          who: "The commonest cause in children.",
                          clues: "Normal glomeruli by light microscopy; podocyte foot processes flattened on electron microscopy; responds to steroids."),
        GlomerularDisease(id: "fsgs", name: "Focal segmental glomerulosclerosis", picture: .nephrotic,
                          who: "Adults; with HIV, obesity, heroin, or no cause found.",
                          clues: "Scarring in parts of some glomeruli; often resists steroids."),
        GlomerularDisease(id: "membranous", name: "Membranous nephropathy", picture: .nephrotic,
                          who: "Adults.",
                          clues: "Antibodies to PLA2R in most primary cases; deposits under the epithelium thicken the basement membrane."),
        GlomerularDisease(id: "diabetic", name: "Diabetic nephropathy", picture: .nephrotic,
                          who: "Long-standing diabetes.",
                          clues: "Thickened basement membrane, mesangial expansion, Kimmelstiel-Wilson nodules."),
        GlomerularDisease(id: "amyloid", name: "Renal amyloidosis", picture: .nephrotic,
                          who: "Myeloma (AL), chronic inflammation (AA).",
                          clues: "Congo red stains it; apple-green under polarised light."),
        GlomerularDisease(id: "psgn", name: "Post-streptococcal glomerulonephritis", picture: .nephritic,
                          who: "Children, 1 to 3 weeks after a sore throat, longer after a skin infection.",
                          clues: "Low C3; lumpy deposits under the epithelium; usually recovers."),
        GlomerularDisease(id: "iga", name: "IgA nephropathy", picture: .nephritic,
                          who: "Young adults; blood in the urine a day or two into a cold.",
                          clues: "IgA in the mesangium; the commonest glomerulonephritis worldwide."),
        GlomerularDisease(id: "anti-gbm", name: "Anti-GBM disease (Goodpasture)", picture: .nephritic,
                          who: "Young men and older adults; may bleed into the lungs.",
                          clues: "Linear IgG along the basement membrane; crescents (rapidly progressive)."),
        GlomerularDisease(id: "anca", name: "ANCA vasculitis", picture: .nephritic,
                          who: "Older adults.",
                          clues: "Few or no immune deposits (pauci-immune) with crescents; PR3 (c-ANCA) in granulomatosis with polyangiitis, MPO (p-ANCA) in microscopic polyangiitis."),
        GlomerularDisease(id: "lupus", name: "Lupus nephritis", picture: .mixed,
                          who: "Systemic lupus erythematosus.",
                          clues: "Any picture; the diffuse proliferative class is the commonest and most severe."),
        GlomerularDisease(id: "mpgn", name: "Membranoproliferative glomerulonephritis", picture: .mixed,
                          who: "Hepatitis C, cryoglobulins, complement disorders.",
                          clues: "Split, \"tram-track\" basement membranes; low complement."),
    ]

    // MARK: naming tumours

    static let tumourTissues: [TumourTissue] = [
        TumourTissue(tissue: "Squamous epithelium", benign: "Squamous papilloma", malignant: "Squamous cell carcinoma"),
        TumourTissue(tissue: "Glandular epithelium", benign: "Adenoma", malignant: "Adenocarcinoma"),
        TumourTissue(tissue: "Urothelium", benign: "Urothelial papilloma", malignant: "Urothelial carcinoma"),
        TumourTissue(tissue: "Liver cells", benign: "Hepatocellular adenoma", malignant: "Hepatocellular carcinoma"),
        TumourTissue(tissue: "Fibrous tissue", benign: "Fibroma", malignant: "Fibrosarcoma"),
        TumourTissue(tissue: "Fat", benign: "Lipoma", malignant: "Liposarcoma"),
        TumourTissue(tissue: "Smooth muscle", benign: "Leiomyoma", malignant: "Leiomyosarcoma"),
        TumourTissue(tissue: "Skeletal muscle", benign: "Rhabdomyoma", malignant: "Rhabdomyosarcoma"),
        TumourTissue(tissue: "Bone", benign: "Osteoma", malignant: "Osteosarcoma"),
        TumourTissue(tissue: "Cartilage", benign: "Chondroma", malignant: "Chondrosarcoma"),
        TumourTissue(tissue: "Blood vessels", benign: "Haemangioma", malignant: "Angiosarcoma"),
        TumourTissue(tissue: "Melanocytes", benign: "Melanocytic naevus", malignant: "Melanoma"),
        TumourTissue(tissue: "Lymphocytes", benign: nil, malignant: "Lymphoma"),
        TumourTissue(tissue: "Mesothelium", benign: nil, malignant: "Mesothelioma"),
        TumourTissue(tissue: "Germ cells of the testis", benign: nil, malignant: "Seminoma"),
    ]

    /// The rule: benign tumours end in -oma; malignant ones are carcinomas
    /// (from epithelium) or sarcomas (from mesenchyme). These names break it.
    static let misleadingNames: [(name: String, truth: String)] = [
        ("Lymphoma", "Malignant, of lymphocytes."),
        ("Melanoma", "Malignant, of melanocytes."),
        ("Mesothelioma", "Malignant, of the lining of the pleura and peritoneum."),
        ("Seminoma", "Malignant, of the testis's germ cells."),
        ("Hepatoma", "An old name for hepatocellular carcinoma: malignant."),
        ("Hamartoma", "Not a tumour: a disorganised lump of the tissue that belongs there."),
        ("Choristoma", "Not a tumour: normal tissue in the wrong place, such as pancreas in the stomach wall."),
        ("Teratoma", "From germ cells, with tissue of more than one germ layer: mature ones are benign, immature ones malignant."),
    ]

    static let benignAgainstMalignant: [(feature: String, benign: String, malignant: String)] = [
        ("Differentiation", "Looks like the tissue it came from", "Less like it, down to no resemblance (anaplasia)"),
        ("Growth", "Slow", "Often fast, with many and odd mitoses"),
        ("Edge", "Well defined, often a capsule", "Invades what lies around it"),
        ("Spread", "Never metastasises", "Can metastasise: by lymph, by blood, across body cavities"),
    ]

    /// The name of a tumour of this tissue: nil where the tissue is not in
    /// the table, or has no benign tumour.
    static func tumourName(tissue: String, malignant: Bool) -> String? {
        guard let t = tumourTissues.first(where: { $0.tissue.lowercased() == tissue.lowercased() }) else { return nil }
        return malignant ? t.malignant : t.benign
    }
}
