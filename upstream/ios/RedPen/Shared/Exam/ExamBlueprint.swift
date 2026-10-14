import Foundation

/// One area of the plan the app studies to: a blueprint line with its
/// syllabus subtopics, the primary exam's share, and the weight it gets once
/// a second exam is counted in.
struct BlueprintArea: Identifiable, Hashable {
    let domain: ExamDomain
    let title: String
    /// Percent of the primary exam (0 for an area only the second exam has).
    let percent: Double
    /// Percent of the combined plan: 70% primary, 30% second exam.
    let weight: Double
    let syllabus: SyllabusArea
    var id: String { domain.rawValue }
}

/// Where the student stands on one blueprint area.
struct BlueprintStanding: Identifiable, Hashable {
    let area: BlueprintArea
    /// 0-1: covered subtopics count 1, thin ones a half.
    let coverage: Double
    let answered: Int
    let correct: Int
    /// 0-1: the expected share right on this area's questions on the day -
    /// the student's own answers, pulled towards a prior set by coverage
    /// while there are few of them.
    let readiness: Double
    /// Weight x weakness: how much studying this area now is worth.
    let priority: Double
    var id: String { area.id }
}

/// An exam's blueprint turned into the coverage map, the readiness estimate,
/// what to study next, and the share of a generated set each area gets.
///
/// Pure Foundation over CoverageEngine, so all of it is tested on Linux.
enum ExamBlueprint {

    /// How much a second exam counts in the combined plan.
    static let secondaryShare = 0.3

    // MARK: - Subtopics per domain

    /// The syllabus subtopics each domain is matched with: the coverage
    /// engine's shared blocks, the exam-specific areas already written for
    /// PLAB, USMLE and MRCS, and a few basic-science blocks of our own.
    static func subtopics(_ domain: ExamDomain) -> [SyllabusSubtopic] {
        switch domain {
        case .anatomy: return area(Syllabus.mrcs, "Applied surgical anatomy")
        case .physiology: return area(Syllabus.mrcs, "Applied physiology")
        case .biochemistry: return area(Syllabus.plab, "Clinical biochemistry") + generalPrinciples([0, 7])
        case .pathology: return area(Syllabus.mrcs, "Applied pathology")
        case .pharmacology: return Syllabus.pharmacology
        case .microbiology: return microbiology
        case .immunology: return Syllabus.immunology
        case .genetics: return Syllabus.genetics
        case .multisystem: return area(Syllabus.usmle, "Multisystem processes and disorders")
        case .biostatistics: return Syllabus.epidemiology
        case .ethics: return Syllabus.ethics
        case .forensic: return forensic
        case .community: return area(Syllabus.plab, "Social and population health")
        case .cardio: return Syllabus.cardiology
        case .resp: return Syllabus.respiratory
        case .gi: return Syllabus.gastro
        case .endocrine: return Syllabus.endocrine
        case .renal: return Syllabus.renal
        case .neuro: return Syllabus.neurology
        case .msk: return Syllabus.rheumatology
        case .heme: return Syllabus.haematology
        case .id: return Syllabus.infection
        case .derm: return Syllabus.dermatology
        case .psychiatry: return Syllabus.mentalHealth
        case .peds: return Syllabus.childHealth
        case .obstetrics: return Syllabus.obstetrics
        case .gynaecology: return Syllabus.gynaecology
        case .ent: return Syllabus.ent
        case .ophthalmology: return Syllabus.ophthalmology
        case .oncology: return Syllabus.oncology
        case .surgery: return area(Syllabus.plab, "Surgery")
        case .orthopaedics: return orthopaedics
        case .anaesthesia: return Syllabus.perioperative
        case .radiology: return area(Syllabus.plab, "Clinical imaging")
        case .emergency: return area(Syllabus.plab, "Acute and emergency")
        case .geriatrics: return Syllabus.olderAdults
        case .palliative: return Syllabus.palliative
        case .sexualHealth: return Syllabus.sexualHealth
        case .omm: return omm
        }
    }

    private static func area(_ list: [SyllabusArea], _ name: String) -> [SyllabusSubtopic] {
        list.first { $0.name == name }?.subtopics ?? []
    }

    /// Some of USMLE's "General principles" subtopics, by position.
    private static func generalPrinciples(_ picks: [Int]) -> [SyllabusSubtopic] {
        let all: [SyllabusSubtopic] = area(Syllabus.usmle, "General principles")
        return picks.compactMap { all.indices.contains($0) ? all[$0] : nil }
    }

    private static func t(_ name: String, _ keywords: String) -> SyllabusSubtopic {
        SyllabusSubtopic(name: name, keywords: keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    static let microbiology: [SyllabusSubtopic] = [
        t("Bacteriology", "gram positive, gram negative, staphylococcus, streptococcus, clostridium, mycobacterium, bacterial toxin, exotoxin, endotoxin"),
        t("Virology", "virus, viral, dna virus, rna virus, herpes, influenza, retrovirus, hepatitis virus"),
        t("Mycology", "fungus, fungal, candida, aspergillus, cryptococcus, dermatophyte"),
        t("Parasitology", "parasite, protozoa, helminth, malaria, plasmodium, giardia, entamoeba, tapeworm"),
        t("Sterilisation and laboratory diagnosis", "sterilisation, disinfection, culture medium, gram stain, pcr, serology"),
    ]

    static let forensic: [SyllabusSubtopic] = [
        t("Thanatology", "rigor mortis, livor mortis, post mortem, postmortem, autopsy, time since death"),
        t("Injuries and wounds", "abrasion, contusion, laceration, incised wound, firearm, gunshot"),
        t("Toxicology", "poisoning, toxicology, organophosphate, arsenic, snake bite, antidote"),
        t("Asphyxia", "hanging, strangulation, drowning, asphyxia"),
        t("Medical law", "medicolegal, dying declaration, inquest, consent, negligence, ipc"),
    ]

    static let orthopaedics: [SyllabusSubtopic] = [
        t("Fractures", "fracture, colles, scaphoid, supracondylar, neck of femur, open fracture"),
        t("Dislocations and nerve injuries", "dislocation, shoulder dislocation, hip dislocation, nerve injury, wrist drop, foot drop"),
        t("Bone infection and tumours", "osteomyelitis, osteosarcoma, ewing, giant cell tumour, bone tumour"),
        t("Paediatric orthopaedics", "developmental dysplasia, perthes, slipped capital femoral epiphysis, clubfoot"),
        t("Spine and joints", "prolapsed disc, spondylolisthesis, osteoarthritis, compartment syndrome"),
    ]

    static let omm: [SyllabusSubtopic] = [
        t("Somatic dysfunction and diagnosis", "somatic dysfunction, tart, tissue texture, restriction, asymmetry"),
        t("Techniques", "counterstrain, muscle energy, hvla, high velocity, myofascial release, osteopathic manipulative"),
        t("Viscerosomatic and Chapman reflexes", "viscerosomatic, chapman point, somatovisceral"),
        t("Spinal and rib mechanics", "fryette, rib dysfunction, sacral torsion, vertebral motion"),
    ]

    // MARK: - The plan

    /// The areas to study to, the primary exam's first by share, then any
    /// the second exam adds. Each area appears once, however many blueprint
    /// lines share its domain.
    static func plan(primary: TargetExam, secondary: TargetExam? = nil) -> [BlueprintArea] {
        let second: TargetExam? = (secondary?.id == primary.id) ? nil : secondary
        let own: Double = second == nil ? 1 : 1 - secondaryShare
        var out: [BlueprintArea] = []
        var seen = Set<ExamDomain>()
        // names are how the coverage map matches areas, so none repeats
        var titles = Set<String>()
        func add(_ domain: ExamDomain, _ label: String, percent: Double, weight: Double) {
            let title: String = titles.insert(label).inserted ? label : domain.title
            titles.insert(title)
            out.append(BlueprintArea(domain: domain, title: title, percent: percent, weight: weight,
                                     syllabus: SyllabusArea(name: title, subtopics: subtopics(domain))))
        }
        for row in primary.shares where seen.insert(row.domain).inserted {
            let p: Double = primary.percent(row.domain)
            let extra: Double = second.map { $0.percent(row.domain) * secondaryShare } ?? 0
            add(row.domain, row.title, percent: p, weight: p * own + extra)
        }
        if let second {
            for row in second.shares where seen.insert(row.domain).inserted {
                add(row.domain, row.title, percent: 0, weight: second.percent(row.domain) * secondaryShare)
            }
        }
        return out
    }

    /// The coverage map's areas for the plan.
    static func syllabus(_ plan: [BlueprintArea]) -> [SyllabusArea] {
        plan.map(\.syllabus)
    }

    // MARK: - Standing, readiness, priority

    /// A prior for an area's share right, from how well the library covers
    /// it: 35% with nothing, 65% when all of it is covered.
    static func prior(coverage: Double) -> Double { 0.35 + 0.3 * min(1, max(0, coverage)) }

    /// How many answers the prior is worth.
    static let priorAnswers = 8.0

    static func coverage(_ area: AreaCoverage) -> Double {
        guard !area.subtopics.isEmpty else { return 0 }
        let points: Double = area.subtopics.reduce(0) { sum, s in
            sum + (s.status == .covered ? 1 : s.status == .thin ? 0.5 : 0)
        }
        return points / Double(area.subtopics.count)
    }

    /// Each plan area's standing, from the coverage engine's assessment of
    /// the same areas (matched by name).
    static func standings(plan: [BlueprintArea], assessed: [AreaCoverage]) -> [BlueprintStanding] {
        var byName: [String: AreaCoverage] = [:]
        for a in assessed { byName[a.area.name] = a }
        return plan.map { area in
            let found: AreaCoverage? = byName[area.title]
            let cov: Double = found.map(coverage) ?? 0
            let answered: Int = found?.subtopics.reduce(0) { $0 + $1.answered } ?? 0
            let correct: Int = found?.subtopics.reduce(0) { $0 + $1.correct } ?? 0
            let ready: Double = (Double(correct) + prior(coverage: cov) * priorAnswers) / (Double(answered) + priorAnswers)
            let weakness: Double = 1 - (0.5 * cov + 0.5 * ready)
            return BlueprintStanding(area: area, coverage: cov, answered: answered, correct: correct,
                                     readiness: ready, priority: area.weight * weakness)
        }
    }

    /// The expected share right on the primary exam: each area's readiness
    /// weighted by its share.
    static func predictedScore(_ standings: [BlueprintStanding]) -> Double {
        let total: Double = standings.reduce(0) { $0 + $1.area.percent }
        guard total > 0 else { return 0 }
        return standings.reduce(0) { $0 + $1.readiness * $1.area.percent } / total
    }

    /// Blueprint coverage: the primary exam's shares, weighted by coverage.
    static func weightedCoverage(_ standings: [BlueprintStanding]) -> Double {
        let total: Double = standings.reduce(0) { $0 + $1.area.percent }
        guard total > 0 else { return 0 }
        return standings.reduce(0) { $0 + $1.coverage * $1.area.percent } / total
    }

    /// What to study next: the areas worth most now, first.
    static func studyNext(_ standings: [BlueprintStanding], limit: Int = 3) -> [BlueprintStanding] {
        let ranked: [BlueprintStanding] = standings.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : $0.area.title < $1.area.title
        }
        return Array(ranked.prefix(max(0, limit)))
    }

    // MARK: - A generated set's topics

    /// How `count` questions divide across the plan: by weight, largest
    /// remainder, heaviest first; areas that get none are left out.
    static func quotas(count: Int, plan: [BlueprintArea]) -> [(area: BlueprintArea, questions: Int)] {
        guard count > 0 else { return [] }
        let total: Double = plan.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        let exact: [Double] = plan.map { Double(count) * $0.weight / total }
        var given: [Int] = exact.map { Int($0.rounded(.down)) }
        var left: Int = count - given.reduce(0, +)
        let order: [Int] = plan.indices.sorted {
            let a: Double = exact[$0] - Double(given[$0])
            let b: Double = exact[$1] - Double(given[$1])
            return a != b ? a > b : plan[$0].weight > plan[$1].weight
        }
        var k = 0
        while left > 0 && !order.isEmpty {
            given[order[k % order.count]] += 1
            left -= 1
            k += 1
        }
        let rows: [(area: BlueprintArea, questions: Int)] = plan.indices.compactMap {
            given[$0] > 0 ? (area: plan[$0], questions: given[$0]) : nil
        }
        return rows.sorted { $0.questions != $1.questions ? $0.questions > $1.questions : $0.area.weight > $1.area.weight }
    }

    // MARK: - What a piece of text is about

    private static let keywordIndex: [(ExamDomain, [CoverageEngine.Keyword])] = ExamDomain.allCases.map { d -> (ExamDomain, [CoverageEngine.Keyword]) in
        let words: [String] = subtopics(d).flatMap { $0.keywords }
        return (d, words.map { CoverageEngine.Keyword($0) })
    }

    /// The domain a question, card or topic line is most about, among
    /// `within` when given; nil when no keyword matches.
    static func domain(of text: String, within: Set<ExamDomain>? = nil) -> ExamDomain? {
        let item: CoverageEngine.Item = CoverageEngine.item(text, practice: true)
        guard !item.words.isEmpty else { return nil }
        var best: ExamDomain? = nil
        var bestScore = 0
        for (d, keys) in keywordIndex {
            if let within, !within.contains(d) { continue }
            var score = 0
            for k in keys where k.matches(item) { score += 1 }
            if score > bestScore {
                best = d
                bestScore = score
            }
        }
        return best
    }
}
