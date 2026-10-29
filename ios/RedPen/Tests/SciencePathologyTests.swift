// The pathology tools: each kind of shock read back from its own profile,
// the infarct dated hour by hour without a gap, the glomerular picture from
// protein and casts, and tumour names by the rule and its exceptions.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

// MARK: shock

check("five kinds of shock, each once", Pathology.shock.map(\.kind) == ShockProfile.Kind.allCases)
for p in Pathology.shock {
    let read = Pathology.readShock(cardiacOutput: p.cardiacOutput, resistance: p.resistance,
                                   wedge: p.wedge == .varies ? .down : p.wedge)
    check("\(p.name) is read back from its own profile", read.contains(p.kind), "\(read)")
}
check("low output, high resistance, low wedge: hypovolaemic, or an embolus",
      Pathology.readShock(cardiacOutput: .down, resistance: .up, wedge: .down) == [.hypovolaemic, .obstructive])
check("low output, high resistance, high wedge: the pump, or tamponade",
      Pathology.readShock(cardiacOutput: .down, resistance: .up, wedge: .up) == [.cardiogenic, .obstructive])
check("high output, low resistance: distributive",
      Pathology.readShock(cardiacOutput: .up, resistance: .down, wedge: .down) == [.distributive])
check("everything low: neurogenic",
      Pathology.readShock(cardiacOutput: .down, resistance: .down, wedge: .down) == [.neurogenic])
check("a picture no shock gives reads as none",
      Pathology.readShock(cardiacOutput: .up, resistance: .up, wedge: .up).isEmpty)
check("only neurogenic shock has a slow heart",
      Pathology.shock.filter { $0.heartRate == .down }.map(\.kind) == [.neurogenic])
check("the cardiogenic and obstructive right hearts are full", Pathology.shock(.cardiogenic)?.cvp == .up && Pathology.shock(.obstructive)?.cvp == .up)
check("every profile names causes and says why", Pathology.shock.allSatisfy { !$0.causes.isEmpty && $0.note.count > 40 })

// MARK: the infarct

let stages = Pathology.infarct
check("the stages run from the start without a gap or overlap",
      stages.first?.from == 0 && zip(stages, stages.dropFirst()).allSatisfy { $0.to == $1.from } && stages.last?.to == .infinity)
func stageAt(_ h: Double) -> String { Pathology.infarctStage(hours: h)?.span ?? "none" }
check("at 2 hours nothing shows by light microscopy", Pathology.infarctStage(hours: 2)?.micro.hasPrefix("Usually nothing") == true, stageAt(2))
check("at 2 days the neutrophils pour in", Pathology.infarctStage(hours: 48)?.micro.contains("neutrophils") == true, stageAt(48))
check("at 5 days macrophages clear it and it may rupture",
      Pathology.infarctStage(hours: 120)?.micro.contains("macrophages") == true
        && Pathology.infarctStage(hours: 120)?.risk?.contains("Rupture") == true, stageAt(120))
check("at 12 days, granulation tissue", Pathology.infarctStage(hours: 288)?.micro.contains("Granulation") == true, stageAt(288))
check("at 3 months, a dense scar", Pathology.infarctStage(hours: 24 * 90)?.micro.contains("Dense collagen") == true)
check("an age on a boundary belongs to the later stage", stageAt(72) == "3 to 7 days" && stageAt(24) == "1 to 3 days")
check("a negative age has no stage", Pathology.infarctStage(hours: -1) == nil)
check("rupture is the risk from day 3 to day 10 only",
      stages.filter { $0.risk?.contains("upture") == true }.map(\.from) == [72, 168])

// MARK: necrosis

check("six kinds of necrosis, ids unique", Pathology.necrosis.count == 6 && Set(Pathology.necrosis.map(\.id)).count == 6)
check("the brain liquefies, the heart coagulates",
      Pathology.necrosis.first { $0.id == "liquefactive" }?.sites.contains("brain") == true
        && Pathology.necrosis.first { $0.id == "coagulative" }?.sites.contains("heart") == true)
check("tuberculosis is caseous", Pathology.necrosis.first { $0.sites.contains("Tuberculosis") }?.id == "caseous")

// MARK: the glomerulus

check("over 3.5 g of protein alone is nephrotic", Pathology.glomerular(proteinGramsPerDay: 6, redCellCasts: false) == .nephrotic)
check("red cell casts with modest protein are nephritic", Pathology.glomerular(proteinGramsPerDay: 1.2, redCellCasts: true) == .nephritic)
check("both is mixed", Pathology.glomerular(proteinGramsPerDay: 4, redCellCasts: true) == .mixed)
check("exactly 3.5 g is not yet nephrotic", Pathology.glomerular(proteinGramsPerDay: 3.5, redCellCasts: false) == .neither)
let diseases = Pathology.glomerularDiseases
check("ids unique", Set(diseases.map(\.id)).count == diseases.count)
check("minimal change, FSGS and membranous are nephrotic",
      ["minimal-change", "fsgs", "membranous"].allSatisfy { id in diseases.first { $0.id == id }?.picture == .nephrotic })
check("post-streptococcal, IgA and anti-GBM are nephritic",
      ["psgn", "iga", "anti-gbm"].allSatisfy { id in diseases.first { $0.id == id }?.picture == .nephritic })
check("every disease gives who and clues", diseases.allSatisfy { !$0.who.isEmpty && $0.clues.count > 20 })
check("nephrotic features name the 3.5 g line", Pathology.nephroticFeatures.first?.contains("3.5 g") == true)

// MARK: tumours

check("fat: lipoma and liposarcoma",
      Pathology.tumourName(tissue: "fat", malignant: false) == "Lipoma"
        && Pathology.tumourName(tissue: "Fat", malignant: true) == "Liposarcoma")
check("glandular epithelium: adenoma and adenocarcinoma",
      Pathology.tumourName(tissue: "Glandular epithelium", malignant: false) == "Adenoma"
        && Pathology.tumourName(tissue: "Glandular epithelium", malignant: true) == "Adenocarcinoma")
check("lymphocytes have no benign tumour", Pathology.tumourName(tissue: "Lymphocytes", malignant: false) == nil)
check("an unknown tissue has no name", Pathology.tumourName(tissue: "Moon rock", malignant: true) == nil)
let mesenchymal: Set<String> = ["Fibrous tissue", "Fat", "Smooth muscle", "Skeletal muscle", "Bone", "Cartilage"]
check("malignant mesenchymal tumours are sarcomas",
      Pathology.tumourTissues.filter { mesenchymal.contains($0.tissue) }.allSatisfy { $0.malignant.hasSuffix("sarcoma") })
check("benign ones end in -oma or are named otherwise, never carcinoma or sarcoma",
      Pathology.tumourTissues.compactMap(\.benign).allSatisfy { !$0.contains("carcinoma") && !$0.contains("sarcoma") })
check("each misleading -oma that is malignant is in the table as malignant",
      ["Lymphoma", "Melanoma", "Mesothelioma", "Seminoma"].allSatisfy { name in
          Pathology.tumourTissues.contains { $0.malignant == name }
            && Pathology.misleadingNames.first { $0.name == name }?.truth.hasPrefix("Malignant") == true
      })
check("hamartoma and choristoma are not tumours",
      Pathology.misleadingNames.filter { $0.truth.hasPrefix("Not a tumour") }.map(\.name) == ["Hamartoma", "Choristoma"])
check("benign against malignant: four features", Pathology.benignAgainstMalignant.count == 4)

print(failures.isEmpty ? "all passed" : "\(failures.count) failed")
exit(failures.isEmpty ? 0 : 1)
