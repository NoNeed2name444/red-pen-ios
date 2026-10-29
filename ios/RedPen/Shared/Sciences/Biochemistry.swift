import Foundation

/// Enzyme kinetics: the Michaelis-Menten rate with the three kinds of
/// reversible inhibition, and the Hill equation for cooperative binding.
///
/// v = Vmax[S] / (Km + [S]). A competitive inhibitor multiplies the
/// apparent Km by α = 1 + [I]/Ki and leaves Vmax; a non-competitive (pure)
/// one divides Vmax by α and leaves Km; an uncompetitive one divides both
/// by α'. The Lineweaver-Burk line, 1/v = (Km/Vmax)(1/[S]) + 1/Vmax, is
/// what the double-reciprocal plot draws. Foundation only.
enum EnzymeKinetics {

    enum Inhibition: String, CaseIterable, Identifiable {
        case none, competitive, noncompetitive, uncompetitive
        var id: String { rawValue }

        var name: String {
            switch self {
            case .none: return "No inhibitor"
            case .competitive: return "Competitive"
            case .noncompetitive: return "Non-competitive"
            case .uncompetitive: return "Uncompetitive"
            }
        }

        /// What it does to the constants, the way it is examined.
        var effect: String {
            switch self {
            case .none: return "Km and Vmax as they are."
            case .competitive: return "Km rises, Vmax unchanged: enough substrate outcompetes it. On the double-reciprocal plot the lines cross on the y-axis."
            case .noncompetitive: return "Vmax falls, Km unchanged: it binds away from the active site. The lines cross on the x-axis."
            case .uncompetitive: return "Vmax and Km both fall by the same factor: it binds only the enzyme-substrate complex. The lines run parallel."
            }
        }
    }

    struct Constants: Hashable {
        var vmax: Double
        var km: Double
    }

    /// The apparent constants with `inhibitor` at concentration `i` and
    /// dissociation constant `ki` (same units as [I]).
    static func apparent(_ c: Constants, _ inhibition: Inhibition, inhibitor i: Double, ki: Double) -> Constants {
        guard ki > 0 else { return c }
        let alpha: Double = 1 + max(0, i) / ki
        switch inhibition {
        case .none: return c
        case .competitive: return Constants(vmax: c.vmax, km: c.km * alpha)
        case .noncompetitive: return Constants(vmax: c.vmax / alpha, km: c.km)
        case .uncompetitive: return Constants(vmax: c.vmax / alpha, km: c.km / alpha)
        }
    }

    static func rate(substrate s: Double, _ c: Constants) -> Double {
        guard s > 0 else { return 0 }
        return c.vmax * s / (c.km + s)
    }

    /// The Lineweaver-Burk line: slope Km/Vmax and y-intercept 1/Vmax;
    /// it meets the x-axis at −1/Km.
    static func lineweaverBurk(_ c: Constants) -> (slope: Double, yIntercept: Double, xIntercept: Double) {
        (c.km / c.vmax, 1 / c.vmax, -1 / c.km)
    }

    /// The Hill equation: fraction bound = [L]ⁿ / (K50ⁿ + [L]ⁿ). n above 1
    /// is positive cooperativity (haemoglobin's is about 2.7), 1 is
    /// Michaelis-Menten's hyperbola.
    static func hill(ligand l: Double, k50: Double, n: Double) -> Double {
        guard l > 0, k50 > 0 else { return 0 }
        let a: Double = pow(l, n)
        return a / (pow(k50, n) + a)
    }
}

/// The metabolic pathways a medical student is examined on, step by step,
/// with each step's enzyme, what it makes or spends, how it is controlled
/// and the disease that names it.
///
/// Written for this app from the standard biochemistry (facts, not anyone's
/// text). Each pathway carries its Reactome stable identifier (Reactome's
/// data is CC0, its diagrams CC BY 4.0) so a student can open the curated,
/// referenced diagram there.
struct MetabolicStep: Hashable, Identifiable {
    var id: String { "\(number)" }
    let number: Int
    /// "Glucose → glucose 6-phosphate".
    let reaction: String
    let enzyme: String
    /// What the step spends or makes ("−1 ATP", "+1 NADH").
    let yield: [String]
    /// Rate-limiting, irreversible, its activators and inhibitors.
    let control: String?
    /// Deficiency or poison that this step is known for.
    let clinical: String?
    var irreversible: Bool = false
    var rateLimiting: Bool = false
}

struct MetabolicPathway: Hashable, Identifiable {
    let id: String
    let name: String
    /// Where in the cell, and in which tissues.
    let location: String
    let summary: String
    let reactome: String
    let steps: [MetabolicStep]
    /// The balance sheet, one line each.
    let net: [String]

    var reactomeURL: String { "https://reactome.org/content/detail/\(reactome)" }
    var rateLimitingStep: MetabolicStep? { steps.first(where: \.rateLimiting) }
}

enum MetabolicPathways {

    static let all: [MetabolicPathway] = [glycolysis, pyruvateDehydrogenase, citricAcidCycle,
                                          betaOxidation, ureaCycle, gluconeogenesis,
                                          pentosePhosphate, hemeSynthesis]

    static func pathway(_ id: String) -> MetabolicPathway? { all.first { $0.id == id } }

    static let glycolysis = MetabolicPathway(
        id: "glycolysis", name: "Glycolysis",
        location: "Cytosol of every cell; red cells depend on it alone.",
        summary: "One glucose is split into two pyruvate, with a small net gain of ATP and NADH and no oxygen needed.",
        reactome: "R-HSA-70171",
        steps: [
            MetabolicStep(number: 1, reaction: "Glucose → glucose 6-phosphate", enzyme: "Hexokinase (glucokinase in liver and pancreatic β cells)",
                          yield: ["−1 ATP"], control: "Hexokinase is inhibited by its product, glucose 6-phosphate; glucokinase is not, and has a high Km, so the liver takes glucose up only when there is plenty.",
                          clinical: "Glucokinase mutations cause a form of maturity-onset diabetes of the young (MODY 2).", irreversible: true),
            MetabolicStep(number: 2, reaction: "Glucose 6-phosphate ⇌ fructose 6-phosphate", enzyme: "Phosphoglucose isomerase",
                          yield: [], control: nil, clinical: nil),
            MetabolicStep(number: 3, reaction: "Fructose 6-phosphate → fructose 1,6-bisphosphate", enzyme: "Phosphofructokinase-1 (PFK-1)",
                          yield: ["−1 ATP"], control: "The committed, rate-limiting step. Activated by AMP and fructose 2,6-bisphosphate; inhibited by ATP and citrate.",
                          clinical: "Muscle PFK deficiency is glycogen storage disease type VII (Tarui).", irreversible: true, rateLimiting: true),
            MetabolicStep(number: 4, reaction: "Fructose 1,6-bisphosphate → DHAP + glyceraldehyde 3-phosphate", enzyme: "Aldolase",
                          yield: [], control: nil, clinical: nil),
            MetabolicStep(number: 5, reaction: "DHAP ⇌ glyceraldehyde 3-phosphate", enzyme: "Triose phosphate isomerase",
                          yield: [], control: "From here every step happens twice per glucose.", clinical: nil),
            MetabolicStep(number: 6, reaction: "Glyceraldehyde 3-phosphate → 1,3-bisphosphoglycerate", enzyme: "Glyceraldehyde 3-phosphate dehydrogenase",
                          yield: ["+2 NADH"], control: nil,
                          clinical: "Arsenate replaces phosphate here; its product falls apart before step 7, so that step's ATP is never made."),
            MetabolicStep(number: 7, reaction: "1,3-Bisphosphoglycerate → 3-phosphoglycerate", enzyme: "Phosphoglycerate kinase",
                          yield: ["+2 ATP"], control: "Substrate-level phosphorylation.",
                          clinical: "In red cells a side branch (bisphosphoglycerate mutase) turns 1,3-BPG into 2,3-BPG, which lowers haemoglobin's oxygen affinity."),
            MetabolicStep(number: 8, reaction: "3-Phosphoglycerate ⇌ 2-phosphoglycerate", enzyme: "Phosphoglycerate mutase",
                          yield: [], control: nil, clinical: nil),
            MetabolicStep(number: 9, reaction: "2-Phosphoglycerate → phosphoenolpyruvate", enzyme: "Enolase",
                          yield: [], control: nil, clinical: "Fluoride inhibits enolase, which is why glucose samples go in fluoride tubes."),
            MetabolicStep(number: 10, reaction: "Phosphoenolpyruvate → pyruvate", enzyme: "Pyruvate kinase",
                          yield: ["+2 ATP"], control: "Activated by fructose 1,6-bisphosphate (feed-forward); inhibited by ATP and alanine, and in the liver by glucagon (phosphorylation).",
                          clinical: "Pyruvate kinase deficiency: a hereditary haemolytic anaemia, as red cells run out of ATP.", irreversible: true),
        ],
        net: ["2 pyruvate", "+2 ATP net (4 made, 2 spent)", "+2 NADH",
              "Without oxygen, lactate dehydrogenase turns pyruvate into lactate to regenerate NAD+."])

    static let pyruvateDehydrogenase = MetabolicPathway(
        id: "pdh", name: "Pyruvate dehydrogenase",
        location: "Mitochondrial matrix.",
        summary: "Pyruvate is decarboxylated to acetyl-CoA, linking glycolysis to the citric acid cycle. It cannot run backwards, so fat cannot be made into glucose.",
        reactome: "R-HSA-70268",
        steps: [
            MetabolicStep(number: 1, reaction: "Pyruvate + CoA + NAD+ → acetyl-CoA + CO2 + NADH", enzyme: "Pyruvate dehydrogenase complex",
                          yield: ["+1 NADH", "+1 CO2"],
                          control: "Needs five cofactors: thiamine pyrophosphate (B1), lipoic acid, CoA (B5), FAD (B2) and NAD+ (B3). Inhibited by acetyl-CoA, NADH and ATP; switched off by phosphorylation, on by insulin.",
                          clinical: "Deficiency causes lactic acidosis. Thiamine deficiency (alcohol use) stalls it: give thiamine before glucose. Arsenite binds lipoic acid.",
                          irreversible: true, rateLimiting: true),
        ],
        net: ["Per glucose: 2 acetyl-CoA, 2 NADH, 2 CO2"])

    static let citricAcidCycle = MetabolicPathway(
        id: "tca", name: "Citric acid cycle",
        location: "Mitochondrial matrix (succinate dehydrogenase sits in the inner membrane).",
        summary: "Acetyl-CoA's two carbons leave as CO2 while their energy is caught as NADH, FADH2 and GTP for the electron transport chain.",
        reactome: "R-HSA-71403",
        steps: [
            MetabolicStep(number: 1, reaction: "Acetyl-CoA + oxaloacetate → citrate", enzyme: "Citrate synthase",
                          yield: [], control: "Inhibited by citrate, ATP and NADH.", clinical: nil, irreversible: true),
            MetabolicStep(number: 2, reaction: "Citrate ⇌ isocitrate", enzyme: "Aconitase",
                          yield: [], control: nil, clinical: "Fluoroacetate (a rodenticide) is made into fluorocitrate, which blocks aconitase."),
            MetabolicStep(number: 3, reaction: "Isocitrate → α-ketoglutarate", enzyme: "Isocitrate dehydrogenase",
                          yield: ["+1 NADH", "+1 CO2"], control: "Rate-limiting. Activated by ADP and calcium; inhibited by ATP and NADH.",
                          clinical: "Mutations in its NADP-dependent relatives, IDH1 and IDH2, are found in gliomas and acute myeloid leukaemia.", irreversible: true, rateLimiting: true),
            MetabolicStep(number: 4, reaction: "α-Ketoglutarate → succinyl-CoA", enzyme: "α-Ketoglutarate dehydrogenase complex",
                          yield: ["+1 NADH", "+1 CO2"], control: "The same five cofactors as pyruvate dehydrogenase; inhibited by its products.",
                          clinical: "Slowed by thiamine deficiency.", irreversible: true),
            MetabolicStep(number: 5, reaction: "Succinyl-CoA → succinate", enzyme: "Succinyl-CoA synthetase",
                          yield: ["+1 GTP"], control: "Substrate-level phosphorylation.", clinical: "Succinyl-CoA is also the start of haem synthesis."),
            MetabolicStep(number: 6, reaction: "Succinate → fumarate", enzyme: "Succinate dehydrogenase (complex II)",
                          yield: ["+1 FADH2"], control: nil, clinical: "Succinate dehydrogenase mutations predispose to paraganglioma and phaeochromocytoma."),
            MetabolicStep(number: 7, reaction: "Fumarate ⇌ malate", enzyme: "Fumarase",
                          yield: [], control: nil, clinical: "Fumarate hydratase mutations cause hereditary leiomyomatosis and renal cell cancer."),
            MetabolicStep(number: 8, reaction: "Malate ⇌ oxaloacetate", enzyme: "Malate dehydrogenase",
                          yield: ["+1 NADH"], control: nil, clinical: nil),
        ],
        net: ["Per acetyl-CoA: 3 NADH, 1 FADH2, 1 GTP, 2 CO2",
              "About 10 ATP per turn after the electron transport chain (2.5 per NADH, 1.5 per FADH2)",
              "About 30 to 32 ATP per glucose in all; older books say 36 to 38"])

    static let betaOxidation = MetabolicPathway(
        id: "betaox", name: "Fatty acid β-oxidation",
        location: "Mitochondrial matrix; very-long-chain fatty acids start in peroxisomes.",
        summary: "Each turn cuts two carbons off a fatty acyl-CoA as acetyl-CoA, making one FADH2 and one NADH. In the fasting liver the acetyl-CoA becomes ketone bodies.",
        reactome: "R-HSA-77289",
        steps: [
            MetabolicStep(number: 1, reaction: "Long-chain fatty acyl-CoA → acylcarnitine → into the matrix", enzyme: "Carnitine palmitoyltransferase I (CPT-I) and the carnitine shuttle",
                          yield: [], control: "Rate-limiting. Inhibited by malonyl-CoA, so fat is not burned while it is being made.",
                          clinical: "CPT-II deficiency: muscle pain and myoglobinuria with exercise. Carnitine deficiency: hypoketotic hypoglycaemia.",
                          rateLimiting: true),
            MetabolicStep(number: 2, reaction: "Acyl-CoA → trans-Δ2-enoyl-CoA", enzyme: "Acyl-CoA dehydrogenase",
                          yield: ["+1 FADH2"], control: nil,
                          clinical: "Medium-chain acyl-CoA dehydrogenase (MCAD) deficiency: hypoketotic hypoglycaemia when fasting; found on newborn screening."),
            MetabolicStep(number: 3, reaction: "Enoyl-CoA → 3-hydroxyacyl-CoA", enzyme: "Enoyl-CoA hydratase", yield: [], control: nil, clinical: nil),
            MetabolicStep(number: 4, reaction: "3-Hydroxyacyl-CoA → 3-ketoacyl-CoA", enzyme: "3-Hydroxyacyl-CoA dehydrogenase",
                          yield: ["+1 NADH"], control: nil, clinical: nil),
            MetabolicStep(number: 5, reaction: "3-Ketoacyl-CoA + CoA → acetyl-CoA + acyl-CoA two carbons shorter", enzyme: "β-Ketothiolase",
                          yield: ["+1 acetyl-CoA"], control: nil, clinical: nil),
        ],
        net: ["Palmitate (16 carbons): 7 turns give 8 acetyl-CoA, 7 FADH2 and 7 NADH",
              "About 106 ATP net (2 spent activating it)"])

    static let ureaCycle = MetabolicPathway(
        id: "urea", name: "Urea cycle",
        location: "Liver: the first two steps in the mitochondria, the rest in the cytosol.",
        summary: "Toxic ammonia from amino acids is made into urea, which the kidneys excrete.",
        reactome: "R-HSA-70635",
        steps: [
            MetabolicStep(number: 1, reaction: "NH4+ + HCO3− → carbamoyl phosphate", enzyme: "Carbamoyl phosphate synthetase I",
                          yield: ["−2 ATP"], control: "Rate-limiting; needs N-acetylglutamate as an activator.",
                          clinical: "CPS I or N-acetylglutamate synthase deficiency: hyperammonaemia without raised orotic acid.",
                          irreversible: true, rateLimiting: true),
            MetabolicStep(number: 2, reaction: "Carbamoyl phosphate + ornithine → citrulline", enzyme: "Ornithine transcarbamylase (OTC)",
                          yield: [], control: nil,
                          clinical: "OTC deficiency, the commonest urea cycle disorder (X-linked): hyperammonaemia with raised orotic acid, as carbamoyl phosphate spills into pyrimidine synthesis."),
            MetabolicStep(number: 3, reaction: "Citrulline + aspartate → argininosuccinate", enzyme: "Argininosuccinate synthetase",
                          yield: ["−1 ATP (to AMP)"], control: nil, clinical: "Deficiency: citrullinaemia."),
            MetabolicStep(number: 4, reaction: "Argininosuccinate → arginine + fumarate", enzyme: "Argininosuccinate lyase",
                          yield: ["+1 fumarate"], control: "Fumarate links the cycle to the citric acid cycle.", clinical: "Deficiency: argininosuccinic aciduria."),
            MetabolicStep(number: 5, reaction: "Arginine → urea + ornithine", enzyme: "Arginase",
                          yield: ["+1 urea"], control: nil, clinical: "Arginase deficiency: progressive spastic diplegia rather than early hyperammonaemic crises."),
        ],
        net: ["One urea from two nitrogens (one from ammonia, one from aspartate)",
              "Costs 3 ATP, 4 high-energy bonds"])

    static let gluconeogenesis = MetabolicPathway(
        id: "gng", name: "Gluconeogenesis",
        location: "Liver (and kidney cortex in long fasting); starts in the mitochondria.",
        summary: "Glucose made from lactate, glycerol and most amino acids, reversing glycolysis except at its three irreversible steps, which four other enzymes bypass.",
        reactome: "R-HSA-70263",
        steps: [
            MetabolicStep(number: 1, reaction: "Pyruvate → oxaloacetate", enzyme: "Pyruvate carboxylase",
                          yield: ["−1 ATP"], control: "Needs biotin; activated by acetyl-CoA.",
                          clinical: "Pyruvate carboxylase deficiency: lactic acidosis and developmental delay.", irreversible: true),
            MetabolicStep(number: 2, reaction: "Oxaloacetate → phosphoenolpyruvate", enzyme: "PEP carboxykinase",
                          yield: ["−1 GTP"], control: "Induced by glucagon and cortisol.", clinical: nil, irreversible: true),
            MetabolicStep(number: 3, reaction: "Fructose 1,6-bisphosphate → fructose 6-phosphate", enzyme: "Fructose 1,6-bisphosphatase",
                          yield: [], control: "Rate-limiting. Inhibited by AMP and fructose 2,6-bisphosphate, the opposite of PFK-1.",
                          clinical: nil, irreversible: true, rateLimiting: true),
            MetabolicStep(number: 4, reaction: "Glucose 6-phosphate → glucose", enzyme: "Glucose 6-phosphatase (endoplasmic reticulum)",
                          yield: [], control: "Only in liver and kidney, so muscle cannot release glucose into the blood.",
                          clinical: "Deficiency is von Gierke disease (glycogen storage disease type I): fasting hypoglycaemia, lactic acidosis and a large liver.",
                          irreversible: true),
        ],
        net: ["Two pyruvate to one glucose costs 4 ATP, 2 GTP and 2 NADH",
              "Odd-chain fatty acids give propionyl-CoA, which can feed it; even-chain fatty acids cannot"])

    static let pentosePhosphate = MetabolicPathway(
        id: "ppp", name: "Pentose phosphate pathway",
        location: "Cytosol; busy in red cells, liver, adrenal cortex and lactating breast.",
        summary: "The oxidative phase makes NADPH, which keeps glutathione reduced and drives fatty acid and steroid synthesis; the non-oxidative phase makes ribose 5-phosphate for nucleotides.",
        reactome: "R-HSA-71336",
        steps: [
            MetabolicStep(number: 1, reaction: "Glucose 6-phosphate → 6-phosphogluconolactone", enzyme: "Glucose 6-phosphate dehydrogenase (G6PD)",
                          yield: ["+1 NADPH"], control: "Rate-limiting. Activated by NADP+, inhibited by NADPH.",
                          clinical: "G6PD deficiency (X-linked): haemolysis after oxidant stress (fava beans, primaquine, dapsone, infection), with Heinz bodies and bite cells.",
                          irreversible: true, rateLimiting: true),
            MetabolicStep(number: 2, reaction: "6-Phosphogluconolactone → 6-phosphogluconate", enzyme: "6-Phosphogluconolactonase",
                          yield: [], control: nil, clinical: nil),
            MetabolicStep(number: 3, reaction: "6-Phosphogluconate → ribulose 5-phosphate", enzyme: "6-Phosphogluconate dehydrogenase",
                          yield: ["+1 NADPH", "+1 CO2"], control: nil, clinical: nil),
            MetabolicStep(number: 4, reaction: "Ribulose 5-phosphate ⇌ ribose 5-phosphate and glycolytic intermediates", enzyme: "Transketolase and transaldolase",
                          yield: [], control: "Reversible; transketolase needs thiamine.",
                          clinical: "Red cell transketolase activity is a test of thiamine status."),
        ],
        net: ["Per glucose 6-phosphate through the oxidative phase: 2 NADPH, 1 CO2"])

    static let hemeSynthesis = MetabolicPathway(
        id: "heme", name: "Haem synthesis",
        location: "Bone marrow and liver: the first and last three steps in the mitochondria, the rest in the cytosol.",
        summary: "Glycine and succinyl-CoA are built up into protoporphyrin IX, which takes in iron to become haem. A block at each step causes a porphyria.",
        reactome: "R-HSA-189451",
        steps: [
            MetabolicStep(number: 1, reaction: "Glycine + succinyl-CoA → δ-aminolaevulinic acid (ALA)", enzyme: "ALA synthase",
                          yield: [], control: "Rate-limiting; needs pyridoxal phosphate (B6); inhibited by haem.",
                          clinical: "X-linked sideroblastic anaemia (ALAS2); isoniazid causes sideroblastic anaemia through B6 deficiency.",
                          irreversible: true, rateLimiting: true),
            MetabolicStep(number: 2, reaction: "2 ALA → porphobilinogen", enzyme: "ALA dehydratase",
                          yield: [], control: nil, clinical: "Inhibited by lead."),
            MetabolicStep(number: 3, reaction: "4 porphobilinogen → hydroxymethylbilane", enzyme: "Porphobilinogen deaminase",
                          yield: [], control: nil,
                          clinical: "Deficiency: acute intermittent porphyria (abdominal pain, neuropathy, psychiatric symptoms; urine darkens on standing; no photosensitivity)."),
            MetabolicStep(number: 4, reaction: "Hydroxymethylbilane → uroporphyrinogen III", enzyme: "Uroporphyrinogen III synthase",
                          yield: [], control: nil, clinical: "Deficiency: congenital erythropoietic porphyria."),
            MetabolicStep(number: 5, reaction: "Uroporphyrinogen III → coproporphyrinogen III", enzyme: "Uroporphyrinogen decarboxylase",
                          yield: [], control: nil, clinical: "Deficiency: porphyria cutanea tarda, the commonest porphyria (blistering on sun-exposed skin)."),
            MetabolicStep(number: 6, reaction: "Coproporphyrinogen III → protoporphyrinogen IX", enzyme: "Coproporphyrinogen oxidase",
                          yield: [], control: nil, clinical: "Deficiency: hereditary coproporphyria."),
            MetabolicStep(number: 7, reaction: "Protoporphyrinogen IX → protoporphyrin IX", enzyme: "Protoporphyrinogen oxidase",
                          yield: [], control: nil, clinical: "Deficiency: variegate porphyria."),
            MetabolicStep(number: 8, reaction: "Protoporphyrin IX + Fe2+ → haem", enzyme: "Ferrochelatase",
                          yield: [], control: nil, clinical: "Inhibited by lead (zinc protoporphyrin rises); deficiency causes erythropoietic protoporphyria."),
        ],
        net: ["Eight glycine and eight succinyl-CoA per haem",
              "Lead poisoning blocks steps 2 and 8: microcytic anaemia with basophilic stippling"])
}
