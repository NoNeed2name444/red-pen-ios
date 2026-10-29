import Foundation

/// The immunology a medical student is examined on: the cells and what
/// they do, the antibody classes, the four types of hypersensitivity, the
/// complement pathways and their deficiencies, and the shape of the
/// primary and secondary antibody responses.
///
/// Written for this app from standard immunology (facts, not anyone's
/// text). Cells carry their Cell Ontology identifiers (CC BY 4.0) so they
/// can be looked up there. Foundation only.
struct ImmuneCell: Hashable, Identifiable {
    let id: String
    let name: String
    enum Arm: String, Hashable { case innate, adaptive }
    let arm: Arm
    let role: String
    let markers: String?
    /// Cell Ontology id, "CL:0000775".
    let cellOntology: String

    var ontologyURL: String {
        "https://www.ebi.ac.uk/ols4/ontologies/cl/classes?obo_id=\(cellOntology)"
    }
}

struct AntibodyClass: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let form: String
    let serumShare: String
    let roles: [String]
}

struct Hypersensitivity: Hashable, Identifiable {
    var id: Int { type }
    let type: Int
    let name: String
    let mechanism: String
    let timing: String
    let examples: [String]
}

struct ComplementPathway: Hashable, Identifiable {
    var id: String { name }
    let name: String
    let trigger: String
    let steps: String
}

struct ComplementDeficiency: Hashable, Identifiable {
    var id: String { missing }
    let missing: String
    let result: String
}

enum Immunology {

    static let cells: [ImmuneCell] = [
        ImmuneCell(id: "neutrophil", name: "Neutrophil", arm: .innate,
                   role: "First to arrive in acute inflammation; engulfs and kills bacteria and fungi, and forms pus.",
                   markers: "Multilobed nucleus", cellOntology: "CL:0000775"),
        ImmuneCell(id: "monocyte", name: "Monocyte", arm: .innate,
                   role: "Circulates in the blood and becomes a macrophage or dendritic cell in the tissues.",
                   markers: "CD14", cellOntology: "CL:0000576"),
        ImmuneCell(id: "macrophage", name: "Macrophage", arm: .innate,
                   role: "Engulfs microbes and debris, presents antigen on MHC class II, and makes IL-1, IL-6 and TNF-α; forms granulomas when activated by IFN-γ.",
                   markers: "CD14, CD68", cellOntology: "CL:0000235"),
        ImmuneCell(id: "dendritic", name: "Dendritic cell", arm: .innate,
                   role: "The most potent antigen-presenting cell: carries antigen to the lymph node and starts the response of naive T cells.",
                   markers: "MHC class II, CD80/86", cellOntology: "CL:0000451"),
        ImmuneCell(id: "nk", name: "Natural killer cell", arm: .innate,
                   role: "Kills virus-infected and tumour cells that have lost MHC class I, without prior sensitisation; also kills antibody-coated cells (ADCC).",
                   markers: "CD16, CD56", cellOntology: "CL:0000623"),
        ImmuneCell(id: "mast", name: "Mast cell", arm: .innate,
                   role: "Sits in tissues with IgE bound; on cross-linking releases histamine and other mediators (type I hypersensitivity).",
                   markers: "FcεRI, c-kit", cellOntology: "CL:0000097"),
        ImmuneCell(id: "eosinophil", name: "Eosinophil", arm: .innate,
                   role: "Defends against helminths with major basic protein; raised in allergy and asthma.",
                   markers: "Bilobed nucleus, red granules", cellOntology: "CL:0000771"),
        ImmuneCell(id: "basophil", name: "Basophil", arm: .innate,
                   role: "The blood's counterpart of the mast cell: histamine and heparin.",
                   markers: "Dark blue granules", cellOntology: "CL:0000767"),
        ImmuneCell(id: "bcell", name: "B cell", arm: .adaptive,
                   role: "Recognises antigen with its surface antibody, presents it to T helper cells, and becomes a plasma cell or memory cell.",
                   markers: "CD19, CD20, CD21", cellOntology: "CL:0000236"),
        ImmuneCell(id: "plasma", name: "Plasma cell", arm: .adaptive,
                   role: "Secretes large amounts of one antibody.",
                   markers: "CD138; clock-face chromatin", cellOntology: "CL:0000786"),
        ImmuneCell(id: "cd4", name: "CD4 T helper cell", arm: .adaptive,
                   role: "Sees peptide on MHC class II. Th1 (IFN-γ) activates macrophages; Th2 (IL-4, IL-5, IL-13) drives IgE and eosinophils; Th17 (IL-17) recruits neutrophils; follicular helpers help B cells switch class.",
                   markers: "CD3, CD4", cellOntology: "CL:0000624"),
        ImmuneCell(id: "cd8", name: "CD8 cytotoxic T cell", arm: .adaptive,
                   role: "Sees peptide on MHC class I, found on every nucleated cell, and kills infected or tumour cells with perforin and granzymes.",
                   markers: "CD3, CD8", cellOntology: "CL:0000625"),
        ImmuneCell(id: "treg", name: "Regulatory T cell", arm: .adaptive,
                   role: "Keeps tolerance with IL-10 and TGF-β; loss of FOXP3 causes IPEX syndrome.",
                   markers: "CD4, CD25, FOXP3", cellOntology: "CL:0000815"),
    ]

    static let antibodies: [AntibodyClass] = [
        AntibodyClass(name: "IgG", form: "Monomer", serumShare: "About 75%",
                      roles: ["The main antibody of the secondary response", "Crosses the placenta: protects the newborn",
                              "Opsonises, neutralises and activates complement", "Four subclasses"]),
        AntibodyClass(name: "IgA", form: "Monomer in serum; dimer with J chain and secretory component in secretions", serumShare: "About 15%",
                      roles: ["Guards mucosal surfaces", "In breast milk, saliva and tears", "Selective IgA deficiency is the commonest primary immunodeficiency"]),
        AntibodyClass(name: "IgM", form: "Pentamer when secreted; monomer on B cells", serumShare: "About 10%",
                      roles: ["First made in a primary response, so it signals recent infection", "The best activator of complement",
                              "Too big to cross the placenta"]),
        AntibodyClass(name: "IgD", form: "Monomer", serumShare: "Under 1%",
                      roles: ["On the surface of naive B cells with IgM"]),
        AntibodyClass(name: "IgE", form: "Monomer", serumShare: "A trace",
                      roles: ["Binds mast cells and basophils: type I hypersensitivity", "Defends against helminths"]),
    ]

    static let hypersensitivities: [Hypersensitivity] = [
        Hypersensitivity(type: 1, name: "Immediate (anaphylactic)",
                         mechanism: "Allergen cross-links IgE on sensitised mast cells and basophils, which release histamine, tryptase and leukotrienes.",
                         timing: "Minutes, with a late phase hours later",
                         examples: ["Anaphylaxis", "Allergic asthma", "Allergic rhinitis", "Urticaria"]),
        Hypersensitivity(type: 2, name: "Antibody-mediated (cytotoxic)",
                         mechanism: "IgG or IgM binds antigens on cells or tissue, causing destruction by complement and phagocytes, or changing how a receptor works.",
                         timing: "Hours to days",
                         examples: ["ABO transfusion reaction", "Autoimmune haemolytic anaemia", "Haemolytic disease of the newborn",
                                    "Goodpasture syndrome", "Graves disease and myasthenia gravis (receptor antibodies)", "Acute rheumatic fever"]),
        Hypersensitivity(type: 3, name: "Immune complex",
                         mechanism: "Antigen-antibody complexes lodge in vessels, glomeruli and joints, activating complement and drawing in neutrophils.",
                         timing: "Days to weeks",
                         examples: ["Systemic lupus erythematosus", "Post-streptococcal glomerulonephritis", "Serum sickness", "Arthus reaction"]),
        Hypersensitivity(type: 4, name: "Delayed (cell-mediated)",
                         mechanism: "Sensitised T cells release cytokines that activate macrophages (CD4) or kill cells directly (CD8); no antibody involved.",
                         timing: "48 to 72 hours",
                         examples: ["Contact dermatitis (nickel, poison ivy)", "Tuberculin skin test", "Type 1 diabetes", "Multiple sclerosis", "Granulomas"]),
    ]

    static let complementPathways: [ComplementPathway] = [
        ComplementPathway(name: "Classical", trigger: "C1q binds antibody (IgM or IgG) on an antigen",
                          steps: "C1 cleaves C4 and C2, forming the C3 convertase C4b2a (in the traditional naming)"),
        ComplementPathway(name: "Lectin", trigger: "Mannose-binding lectin binds sugars on microbes",
                          steps: "MASPs cleave C4 and C2: the same C3 convertase as the classical pathway"),
        ComplementPathway(name: "Alternative", trigger: "C3 breaks down by itself on microbial surfaces",
                          steps: "C3b binds factor B, which factor D cleaves, forming C3bBb, stabilised by properdin"),
    ]

    /// What the pathways share once C3 is cleaved.
    static let complementEffects: [String] = [
        "C3b opsonises microbes for phagocytosis and clears immune complexes",
        "C3a and C5a are anaphylatoxins; C5a also draws neutrophils in",
        "C5b to C9 form the membrane attack complex, which lyses cells such as Neisseria",
    ]

    static let complementDeficiencies: [ComplementDeficiency] = [
        ComplementDeficiency(missing: "C1, C2 or C4 (early classical)", result: "Lupus-like disease, as immune complexes are not cleared"),
        ComplementDeficiency(missing: "C3", result: "Severe recurrent pyogenic infections"),
        ComplementDeficiency(missing: "C5 to C9 (terminal)", result: "Recurrent Neisseria infections"),
        ComplementDeficiency(missing: "C1 esterase inhibitor", result: "Hereditary angioedema, through bradykinin; ACE inhibitors are avoided"),
        ComplementDeficiency(missing: "CD55 and CD59 (decay-accelerating factor and protectin)", result: "Paroxysmal nocturnal haemoglobinuria: complement lyses red cells"),
    ]

    /// Antibody level (arbitrary units, log scale on the screen) `day` days
    /// after a first exposure, or after a second exposure when `secondary`.
    /// The shapes taught: a primary response that starts after about a
    /// week, is mostly IgM and stays low; a secondary one that starts in a
    /// few days, is mostly IgG and climbs about a hundredfold higher.
    /// Illustrative curves, not measurements.
    static func antibody(day: Double, secondary: Bool) -> (igm: Double, igg: Double) {
        func pulse(_ t: Double, start: Double, peak: Double, height: Double, decay: Double) -> Double {
            guard t > start else { return 0 }
            if t <= peak {
                let x: Double = (t - start) / (peak - start)
                return height * x * x * (3 - 2 * x)
            }
            return height * exp(-(t - peak) / decay)
        }
        if secondary {
            return (pulse(day, start: 2, peak: 7, height: 10, decay: 6),
                    pulse(day, start: 2, peak: 12, height: 1000, decay: 40))
        }
        return (pulse(day, start: 6, peak: 12, height: 10, decay: 6),
                pulse(day, start: 9, peak: 20, height: 10, decay: 20))
    }
}
