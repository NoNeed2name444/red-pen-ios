// The life-science tools against the numbers every textbook gives:
// Michaelis-Menten and its inhibitors, the pathways' balance sheets,
// Punnett ratios, Hardy-Weinberg for cystic fibrosis, the genetic code and
// the sickle-cell mutation, drug levels and half-lives, the 2 x 2 table, the
// bacteria key reaching every organism, and the immunology tables.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Double?, _ b: Double, _ tol: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tol
}

// MARK: enzyme kinetics

let enzyme = EnzymeKinetics.Constants(vmax: 100, km: 5)
check("at [S] = Km the rate is half Vmax", near(EnzymeKinetics.rate(substrate: 5, enzyme), 50, 1e-9))
check("at [S] = 9 Km the rate is 90% of Vmax", near(EnzymeKinetics.rate(substrate: 45, enzyme), 90, 1e-9))
check("no substrate, no rate", EnzymeKinetics.rate(substrate: 0, enzyme) == 0)
let competitive = EnzymeKinetics.apparent(enzyme, .competitive, inhibitor: 10, ki: 10)
check("a competitive inhibitor doubles Km at [I] = Ki and leaves Vmax",
      competitive.km == 10 && competitive.vmax == 100, "\(competitive)")
let noncompetitive = EnzymeKinetics.apparent(enzyme, .noncompetitive, inhibitor: 10, ki: 10)
check("a non-competitive inhibitor halves Vmax and leaves Km",
      noncompetitive.km == 5 && noncompetitive.vmax == 50, "\(noncompetitive)")
let uncompetitive = EnzymeKinetics.apparent(enzyme, .uncompetitive, inhibitor: 10, ki: 10)
check("an uncompetitive inhibitor halves both, keeping Km/Vmax",
      uncompetitive.km == 2.5 && uncompetitive.vmax == 50
      && near(uncompetitive.km / uncompetitive.vmax, enzyme.km / enzyme.vmax, 1e-12), "\(uncompetitive)")
check("enough substrate overcomes a competitive inhibitor",
      EnzymeKinetics.rate(substrate: 10_000, competitive) > 99.8)
let lb = EnzymeKinetics.lineweaverBurk(enzyme)
check("Lineweaver-Burk: y-intercept 1/Vmax, x-intercept −1/Km, slope Km/Vmax",
      near(lb.yIntercept, 0.01, 1e-12) && near(lb.xIntercept, -0.2, 1e-12) && near(lb.slope, 0.05, 1e-12))
let lbCompetitive = EnzymeKinetics.lineweaverBurk(competitive)
let lbNoncompetitive = EnzymeKinetics.lineweaverBurk(noncompetitive)
let lbUncompetitive = EnzymeKinetics.lineweaverBurk(uncompetitive)
check("competitive lines meet on the y-axis", near(lbCompetitive.yIntercept, lb.yIntercept, 1e-12))
check("non-competitive lines meet on the x-axis", near(lbNoncompetitive.xIntercept, lb.xIntercept, 1e-12))
check("uncompetitive lines run parallel", near(lbUncompetitive.slope, lb.slope, 1e-12))
check("every inhibition type explains itself", EnzymeKinetics.Inhibition.allCases.allSatisfy { !$0.effect.isEmpty })
check("Hill: half bound at K50 whatever n",
      near(EnzymeKinetics.hill(ligand: 26, k50: 26, n: 2.7), 0.5, 1e-12)
      && near(EnzymeKinetics.hill(ligand: 26, k50: 26, n: 1), 0.5, 1e-12))
check("Hill: cooperativity makes the curve steeper",
      EnzymeKinetics.hill(ligand: 40, k50: 26, n: 2.7) > EnzymeKinetics.hill(ligand: 40, k50: 26, n: 1)
      && EnzymeKinetics.hill(ligand: 15, k50: 26, n: 2.7) < EnzymeKinetics.hill(ligand: 15, k50: 26, n: 1))

// MARK: pathways

let pathways = MetabolicPathways.all
check("eight pathways, ids unique", pathways.count == 8 && Set(pathways.map(\.id)).count == 8)
check("every pathway has a Reactome human id",
      pathways.allSatisfy { $0.reactome.hasPrefix("R-HSA-") && Int($0.reactome.dropFirst(6)) != nil },
      pathways.map(\.reactome).joined(separator: ", "))
// (Not every one is irreversible: CPT-I's carnitine transfer is a control
// point, not a one-way step.)
check("every pathway names exactly one rate-limiting step",
      pathways.allSatisfy { p in p.steps.filter(\.rateLimiting).count == 1 },
      pathways.filter { $0.steps.filter(\.rateLimiting).count != 1 }.map(\.id).joined(separator: ", "))
check("steps are numbered 1, 2, 3 in order",
      pathways.allSatisfy { p in p.steps.map(\.number) == Array(1...p.steps.count) })
check("every pathway has a balance sheet", pathways.allSatisfy { !$0.net.isEmpty && !$0.summary.isEmpty })

/// Adds up a pathway's "+2 ATP" and "−1 ATP" lines for one currency.
func balance(_ p: MetabolicPathway, _ currency: String) -> Int {
    p.steps.flatMap(\.yield).reduce(0) { total, line in
        let parts = line.split(separator: " ")
        guard parts.count == 2, parts[1] == Substring(currency) else { return total }
        let sign: Int = parts[0].hasPrefix("−") || parts[0].hasPrefix("-") ? -1 : 1
        return total + sign * (Int(parts[0].dropFirst()) ?? 0)
    }
}

let glycolysis = MetabolicPathways.glycolysis
check("glycolysis has ten steps", glycolysis.steps.count == 10)
check("glycolysis nets 2 ATP and 2 NADH per glucose",
      balance(glycolysis, "ATP") == 2 && balance(glycolysis, "NADH") == 2,
      "ATP \(balance(glycolysis, "ATP")), NADH \(balance(glycolysis, "NADH"))")
check("PFK-1 is glycolysis's rate-limiting step", glycolysis.rateLimitingStep?.number == 3)
check("glycolysis's irreversible steps are 1, 3 and 10",
      glycolysis.steps.filter(\.irreversible).map(\.number) == [1, 3, 10])
let tca = MetabolicPathways.pathway("tca")
check("the citric acid cycle has eight steps", tca?.steps.count == 8)
check("one turn makes 3 NADH, 1 FADH2 and 1 GTP",
      tca.map { balance($0, "NADH") == 3 && balance($0, "FADH2") == 1 && balance($0, "GTP") == 1 } == true,
      tca.map { "NADH \(balance($0, "NADH")), FADH2 \(balance($0, "FADH2")), GTP \(balance($0, "GTP"))" } ?? "")
check("isocitrate dehydrogenase limits the cycle's rate",
      tca?.rateLimitingStep?.enzyme.lowercased().contains("isocitrate") == true)
check("lookup by id", MetabolicPathways.pathway("urea")?.name == "Urea cycle" && MetabolicPathways.pathway("nope") == nil)
check("Reactome link", glycolysis.reactomeURL == "https://reactome.org/content/detail/R-HSA-70171")

// MARK: Punnett squares

let monohybrid = Genetics.cross("Aa", "Aa")
check("Aa x Aa: 1 AA, 2 Aa, 1 aa", monohybrid?.genotypes == ["AA": 1, "Aa": 2, "aa": 1], "\(String(describing: monohybrid?.genotypes))")
check("Aa x Aa: 3:1", monohybrid.map { Genetics.ratio($0.phenotypes) } == "3:1")
let dihybrid = Genetics.cross("AaBb", "AaBb")
check("AaBb x AaBb: sixteen boxes, nine genotypes", dihybrid?.total == 16 && dihybrid?.genotypes.count == 9)
check("AaBb x AaBb: 9:3:3:1", dihybrid.map { Genetics.ratio($0.phenotypes) } == "9:3:3:1",
      dihybrid.map { Genetics.ratio($0.phenotypes) } ?? "nil")
check("AaBb x AaBb: genotype ratio 4:2:2:2:2:1:1:1:1",
      dihybrid.map { Genetics.ratio($0.genotypes) } == "4:2:2:2:2:1:1:1:1")
check("test cross Aa x aa: 1:1", Genetics.cross("Aa", "aa").map { Genetics.ratio($0.phenotypes) } == "1:1")
check("AA x aa: all heterozygous", Genetics.cross("AA", "aa")?.genotypes == ["Aa": 4])
check("dominant written first", Genetics.normalised("aAbB") == "AaBb")
check("gametes of AaBb", Set(Genetics.gametes("AaBb")) == ["AB", "Ab", "aB", "ab"])
check("a box reads row gamete plus column gamete", monohybrid?.cells[0][1] == "Aa" && monohybrid?.rows == ["A", "a"])
check("genes that do not pair are refused",
      Genetics.genes("Ab") == nil && Genetics.genes("Aab") == nil && Genetics.cross("Aa", "Bb") == nil
      && Genetics.cross("Aa", "AaBb") == nil)

// MARK: populations

let cf = Genetics.hardyWeinberg(incidence: 1.0 / 2500)
check("cystic fibrosis 1 in 2500: q = 1/50", near(cf.q, 0.02, 1e-12))
check("cystic fibrosis 1 in 2500: about 1 in 25 carry it", near(1 / cf.carriers, 25.5, 0.1), "1 in \(1 / cf.carriers)")
check("Hardy-Weinberg frequencies add to 1", near(cf.homozygousDominant + cf.carriers + cf.affected, 1, 1e-12))
check("a sibling's child: 2/3 x 1/25 x 1/4, about 1 in 150",
      near(1 / Genetics.siblingsChildRisk(incidence: 1.0 / 2500), 153, 1), "1 in \(1 / Genetics.siblingsChildRisk(incidence: 1.0 / 2500))")
check("every inheritance pattern has its risks", Genetics.Pattern.allCases.allSatisfy { !$0.risks.isEmpty })

// MARK: the genetic code

check("64 codons, 61 sense and 3 stop",
      Genetics.codons.count == 64 && Genetics.codons.values.filter { $0 == "*" }.count == 3)
check("the stops are UAA, UAG and UGA",
      Set(Genetics.codons.filter { $0.value == "*" }.keys) == ["UAA", "UAG", "UGA"])
check("UUU Phe, AUG Met, UGG Trp, GGG Gly",
      Genetics.codons["UUU"] == "F" && Genetics.codons["AUG"] == "M" && Genetics.codons["UGG"] == "W"
      && Genetics.codons["GGG"] == "G")
check("Met and Trp each have one codon; Leu, Ser and Arg have six",
      Genetics.codons.values.filter { $0 == "M" }.count == 1 && Genetics.codons.values.filter { $0 == "W" }.count == 1
      && ["L", "S", "R"].allSatisfy { aa in Genetics.codons.values.filter { $0 == Character(aa) }.count == 6 })
check("twenty amino acids, each with a three-letter name",
      Set(Genetics.codons.values.filter { $0 != "*" }).count == 20
      && Set(Genetics.codons.values).allSatisfy { Genetics.threeLetter[$0] != nil })
check("transcription swaps T for U", Genetics.transcribe(coding: "ATG gct\nTAA") == "AUGGCUUAA")
check("the coding strand is the template's reverse complement", Genetics.codingStrand(template: "TTACGCCAT") == "ATGGCGTAA")

// The start of the β-globin gene (HBB): Met, then Val His Leu Thr Pro Glu Glu Lys.
let hbb: String = "ATGGTGCACCTGACTCCTGAGGAGAAGTAA"
check("β-globin translates as MVHLTPEEK", Genetics.translate(mRNA: Genetics.transcribe(coding: hbb)) == "MVHLTPEEK")
check("translation starts at the first AUG", Genetics.translate(mRNA: "CCAUGUUUUAA") == "MF")
check("no AUG, no protein", Genetics.translate(mRNA: "CCCUUUGGG") == "")
let sickle: String = "ATGGTGCACCTGACTCCTGTGGAGAAGTAA"
check("sickle cell: GAG to GTG makes valine for glutamate, a missense change",
      Genetics.classify(reference: hbb, variant: sickle) == .missense
      && Genetics.translate(mRNA: Genetics.transcribe(coding: sickle)) == "MVHLTPVEK")
check("CTG to CTC keeps leucine: silent",
      Genetics.classify(reference: hbb, variant: "ATGGTGCACCTCACTCCTGAGGAGAAGTAA") == .silent)
check("AAG to TAG stops early: nonsense",
      Genetics.classify(reference: hbb, variant: "ATGGTGCACCTGACTCCTGAGGAGTAGTAA") == .nonsense)
check("one base lost: frameshift",
      Genetics.classify(reference: hbb, variant: "ATGGTGCACCTGACTCCTGAGAGAAGTAA") == .frameshift)
check("three bases lost: in-frame deletion, as in F508del",
      Genetics.classify(reference: hbb, variant: "ATGGTGCACCTGACTCCTGAGAAGTAA") == .inFrameDeletion)
check("three bases added: in-frame insertion",
      Genetics.classify(reference: hbb, variant: "ATGGTGCACCTGACTCCTGAGGAGGAGAAGTAA") == .inFrameInsertion)
check("the same sequence: no change", Genetics.classify(reference: hbb, variant: hbb.lowercased()) == Genetics.Mutation.none)

// MARK: pharmacokinetics

let drug = Pharmacokinetics.Drug(volume: 50, clearance: 5, bioavailability: 1, absorption: 1.5)
check("k = CL/Vd = 0.1 per hour; half-life 6.93 h", near(drug.elimination, 0.1, 1e-12) && near(drug.halfLife, 6.93, 0.01))
check("an IV bolus of 500 mg into 50 L starts at 10 mg/L", near(Pharmacokinetics.single(drug, dose: 500, route: .intravenous, at: 0), 10, 1e-9))
check("one half-life later it is 5 mg/L", near(Pharmacokinetics.single(drug, dose: 500, route: .intravenous, at: drug.halfLife), 5, 1e-9))
check("by mouth it starts at zero and peaks later",
      Pharmacokinetics.single(drug, dose: 500, route: .oral, at: 0) == 0
      && Pharmacokinetics.single(drug, dose: 500, route: .oral, at: 2) > Pharmacokinetics.single(drug, dose: 500, route: .oral, at: 0.2))
check("the oral curve's area equals the IV one when F is 1 (AUC = F·D/CL = 100)", {
    var oral: Double = 0, iv: Double = 0
    let dt: Double = 0.01
    for i in 0..<20_000 {
        let t: Double = Double(i) * dt
        oral += Pharmacokinetics.single(drug, dose: 500, route: .oral, at: t) * dt
        iv += Pharmacokinetics.single(drug, dose: 500, route: .intravenous, at: t) * dt
    }
    return near(oral, 100, 0.5) && near(iv, 100, 0.5)
}())
var sameRates = drug; sameRates.absorption = sameRates.elimination
check("ka = k does not divide by zero",
      Pharmacokinetics.single(sameRates, dose: 500, route: .oral, at: 10).isFinite
      && Pharmacokinetics.single(sameRates, dose: 500, route: .oral, at: 10) > 0)
check("97% of steady state after five half-lives", near(Pharmacokinetics.fractionOfSteadyState(halfLives: 5), 0.96875, 1e-12))
let regimen = Pharmacokinetics.Regimen(dose: 500, interval: drug.halfLife, route: .intravenous, doses: 30)
check("dosing every half-life doubles the level at steady state", near(Pharmacokinetics.accumulation(drug, interval: drug.halfLife), 2, 1e-9))
check("so the peak after many doses is twice the first dose's",
      near(Pharmacokinetics.concentration(drug, regimen, at: 29 * drug.halfLife), 20, 0.01))
check("the average at steady state is F·dose / (CL·τ)",
      near(Pharmacokinetics.averageSteadyState(drug, regimen), 500 / (5 * drug.halfLife), 1e-9))
check("a single dose ignores the later ones",
      Pharmacokinetics.concentration(drug, Pharmacokinetics.Regimen(dose: 500, interval: 0, route: .intravenous, doses: 5), at: 30)
      == Pharmacokinetics.single(drug, dose: 500, route: .intravenous, at: 30))
check("the curve starts at 0 and ends at the last hour",
      Pharmacokinetics.curve(drug, regimen, hours: 48, points: 97).first?.t == 0 && Pharmacokinetics.curve(drug, regimen, hours: 48, points: 97).last?.t == 48)
check("loading dose C x Vd / F: 15 mg/L in 50 L by mouth at F 0.5 is 1500 mg",
      near(Pharmacokinetics.loadingDose(target: 15, volume: 50, bioavailability: 0.5), 1500, 1e-9))
check("maintenance dose C x CL x τ / F: 10 mg/L at 5 L/h every 12 h is 600 mg",
      near(Pharmacokinetics.maintenanceDose(target: 10, clearance: 5, interval: 12), 600, 1e-9))
check("an infusion reaches R/CL: 50 mg/h at 5 L/h tends to 10 mg/L, half of it at one half-life",
      near(Pharmacokinetics.infusion(drug, rate: 50, at: drug.halfLife), 5, 1e-9)
      && near(Pharmacokinetics.infusion(drug, rate: 50, at: 1000), 10, 1e-6))

// MARK: biostatistics

let test = Biostatistics.TwoByTwo(truePositive: 90, falsePositive: 50, falseNegative: 10, trueNegative: 850)
check("sensitivity 90%, specificity 94.4%", near(test.sensitivity, 0.9, 1e-12) && near(test.specificity, 850.0 / 900, 1e-12))
check("PPV 64%, NPV 98.8%", near(test.positivePredictive, 90.0 / 140, 1e-12) && near(test.negativePredictive, 850.0 / 860, 1e-12))
check("prevalence 10%, accuracy 94%", near(test.prevalence, 0.1, 1e-12) && near(test.accuracy, 0.94, 1e-12))
check("LR+ = sens / (1 − spec) = 16.2; LR− = (1 − sens) / spec = 0.106",
      near(test.positiveLikelihood, 16.2, 1e-9) && near(test.negativeLikelihood, 0.1 / (850.0 / 900), 1e-12))
check("post-test probability through odds matches the PPV",
      near(Biostatistics.postTest(pretest: 0.1, likelihoodRatio: test.positiveLikelihood ?? 0), test.positivePredictive ?? 0, 1e-9))
check("an LR of 1 changes nothing", near(Biostatistics.postTest(pretest: 0.3, likelihoodRatio: 1), 0.3, 1e-12))
check("certainty stays certain", Biostatistics.postTest(pretest: 1, likelihoodRatio: 0.1) == 1 && Biostatistics.postTest(pretest: 0, likelihoodRatio: 10) == 0)
let rare = Biostatistics.TwoByTwo.from(sensitivity: 0.99, specificity: 0.99, prevalence: 0.001, population: 100_000)
check("a 99% test for a 1-in-1000 disease: most positives are false (PPV about 9%)",
      near(rare.positivePredictive, 0.09, 0.001), "\(rare.positivePredictive ?? -1)")
check("a perfect specificity has no LR+", Biostatistics.TwoByTwo(truePositive: 5, falsePositive: 0, falseNegative: 5, trueNegative: 10).positiveLikelihood == nil)
check("an empty table answers nothing", Biostatistics.TwoByTwo(truePositive: 0, falsePositive: 0, falseNegative: 0, trueNegative: 0).sensitivity == nil)
let trial = Biostatistics.Trial(treatedEvents: 10, treatedTotal: 100, controlEvents: 20, controlTotal: 100)
check("10% against 20%: RR 0.5, ARR 10%, RRR 50%, NNT 10",
      near(trial.relativeRisk, 0.5, 1e-12) && near(trial.absoluteRiskReduction, 0.1, 1e-12)
      && near(trial.relativeRiskReduction, 0.5, 1e-12) && near(trial.numberNeededToTreat, 10, 1e-9))
check("odds ratio (10/90) / (20/80) = 0.444", near(trial.oddsRatio, (10.0 / 90) / (20.0 / 80), 1e-12))
let harm = Biostatistics.Trial(treatedEvents: 15, treatedTotal: 100, controlEvents: 10, controlTotal: 100)
check("a treatment that harms gives a negative NNT (number needed to harm 20)", near(harm.numberNeededToTreat, -20, 1e-9))

// MARK: microbiology

let organisms = Microbiology.organisms
check("organism ids are unique", Set(organisms.map(\.id)).count == organisms.count)
check("every organism has an NCBI taxonomy id, features and diseases",
      organisms.allSatisfy { $0.taxonomy > 0 && !$0.features.isEmpty && !$0.diseases.isEmpty },
      organisms.filter { $0.taxonomy <= 0 || $0.features.isEmpty || $0.diseases.isEmpty }.map(\.id).joined(separator: ", "))
check("textbook taxonomy ids: S. aureus 1280, E. coli 562, M. tuberculosis 1773",
      Microbiology.organism("saureus")?.taxonomy == 1280 && Microbiology.organism("ecoli")?.taxonomy == 562
      && Microbiology.organism("mtuberculosis")?.taxonomy == 1773)
check("node ids are unique", Set(Microbiology.key.map(\.id)).count == Microbiology.key.count)
let pointedAt: [String] = Microbiology.key.flatMap { $0.answers }.compactMap { if case .node(let n) = $0.next { return n }; return nil }
check("every answer leads to a question that exists", pointedAt.allSatisfy { Microbiology.node($0) != nil },
      pointedAt.filter { Microbiology.node($0) == nil }.joined(separator: ", "))
let named: [String] = Microbiology.key.flatMap { $0.answers }.flatMap { a -> [String] in if case .organisms(let o) = a.next { return o }; return [] }
check("every organism the key names is in the list", named.allSatisfy { Microbiology.organism($0) != nil },
      named.filter { Microbiology.organism($0) == nil }.joined(separator: ", "))
check("the key reaches every organism, each at one place",
      Set(named) == Set(organisms.map(\.id)) && named.count == Set(named).count,
      "missing \(Set(organisms.map(\.id)).subtracting(named).sorted()), twice \(named.count - Set(named).count)")
check("every question except the first is reached from another",
      Set(pointedAt) == Set(Microbiology.key.map(\.id)).subtracting([Microbiology.root]))
check("the key has no loops: every walk ends", {
    func depth(_ id: String, _ seen: Set<String>) -> Int? {
        guard !seen.contains(id), let n = Microbiology.node(id) else { return nil }
        var deepest: Int = 0
        for a in n.answers {
            if case .node(let next) = a.next {
                guard let d = depth(next, seen.union([id])) else { return nil }
                deepest = max(deepest, d)
            }
        }
        return deepest + 1
    }
    return depth(Microbiology.root, []) != nil
}())
check("S. aureus: Gram-positive cocci, catalase positive, coagulase positive",
      Microbiology.path(to: "saureus") == ["Gram-positive cocci", "Positive: staphylococci", "Positive"])
check("S. pyogenes: β-haemolytic, bacitracin sensitive",
      Microbiology.path(to: "spyogenes")?.suffix(2) == ["β: complete, a clear zone", "Sensitive: group A"])
check("S. pneumoniae: α-haemolytic, optochin sensitive",
      Microbiology.path(to: "spneumoniae")?.contains("α: partial, green") == true)
check("Pseudomonas: lactose non-fermenter, oxidase positive",
      Microbiology.path(to: "paeruginosa") == ["Gram-negative straight rods", "No", "Positive"])
check("N. gonorrhoeae ferments glucose only", Microbiology.path(to: "ngonorrhoeae")?.last == "Glucose only")
check("an organism the key does not hold has no path", Microbiology.path(to: "unicorn") == nil)
check("every Gram-positive in the list is reached through a Gram-positive answer",
      organisms.filter { $0.gram == .positive }.allSatisfy { Microbiology.path(to: $0.id)?.first?.hasPrefix("Gram-positive") == true },
      organisms.filter { $0.gram == .positive && Microbiology.path(to: $0.id)?.first?.hasPrefix("Gram-positive") != true }.map(\.id).joined(separator: ", "))
check("every Gram-negative is reached through a Gram-negative answer or as a poor stainer",
      organisms.filter { $0.gram == .negative }.allSatisfy {
          let first = Microbiology.path(to: $0.id)?.first ?? ""
          return first.hasPrefix("Gram-negative") || first.hasPrefix("Stains poorly")
      })
check("twenty minutes a generation: ten generations in 200 minutes, 1024 times",
      near(Microbiology.exponential(start: 1, minutes: 200, generation: 20), 1024, 1e-9))
let culture = Microbiology.Culture()
let growth: [Double] = stride(from: 0.0, through: 30, by: 0.25).map { Microbiology.cultureLog10(culture, hours: $0) }
check("a culture: flat in the lag", Microbiology.cultureLog10(culture, hours: 1) == culture.startLog10)
check("then climbs about 0.6 log a hour at a 30-minute generation",
      near(Microbiology.cultureLog10(culture, hours: 4) - Microbiology.cultureLog10(culture, hours: 3), 0.602, 0.01))
check("never above capacity", growth.allSatisfy { $0 <= culture.capacityLog10 + 1e-9 })
check("then a plateau, then decline", {
    guard let top = growth.firstIndex(where: { $0 > culture.capacityLog10 - 0.01 }) else { return false }
    let plateau = growth[top..<(top + 16)]
    return (plateau.max()! - plateau.min()!) < 0.02 && growth.last! < culture.capacityLog10 - 1
}())

// MARK: immunology

check("thirteen immune cells, innate and adaptive", Immunology.cells.count == 13
      && Immunology.cells.contains { $0.arm == .innate } && Immunology.cells.contains { $0.arm == .adaptive })
check("every cell has a Cell Ontology id of the form CL:0000000",
      Immunology.cells.allSatisfy { $0.cellOntology.range(of: #"^CL:\d{7}$"#, options: .regularExpression) != nil })
check("cell ids and ontology ids are unique",
      Set(Immunology.cells.map(\.id)).count == 13 && Set(Immunology.cells.map(\.cellOntology)).count == 13)
check("neutrophil is CL:0000775", Immunology.cells.first { $0.id == "neutrophil" }?.cellOntology == "CL:0000775")
check("five antibody classes", Immunology.antibodies.map(\.name) == ["IgG", "IgA", "IgM", "IgD", "IgE"])
check("four types of hypersensitivity, numbered 1 to 4", Immunology.hypersensitivities.map(\.type) == [1, 2, 3, 4])
check("three complement pathways", Immunology.complementPathways.map(\.name) == ["Classical", "Lectin", "Alternative"])
check("complement deficiencies listed", Immunology.complementDeficiencies.count == 5)
let primaryPeak: Double = stride(from: 0.0, through: 60, by: 0.5).map { Immunology.antibody(day: $0, secondary: false).igg }.max()!
let secondaryPeak: Double = stride(from: 0.0, through: 60, by: 0.5).map { Immunology.antibody(day: $0, secondary: true).igg }.max()!
check("the secondary IgG response is about a hundredfold the primary", near(secondaryPeak / primaryPeak, 100, 1))
check("in a primary response IgM comes first",
      Immunology.antibody(day: 9, secondary: false).igm > Immunology.antibody(day: 9, secondary: false).igg)
check("nothing before the response starts", Immunology.antibody(day: 3, secondary: false) == (0, 0))
check("a secondary response starts sooner", Immunology.antibody(day: 4, secondary: true).igg > 0)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
