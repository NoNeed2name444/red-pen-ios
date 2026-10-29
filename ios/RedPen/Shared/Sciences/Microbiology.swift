import Foundation

/// The bacteria a medical student is examined on, and the laboratory key
/// that tells them apart: Gram stain and shape first, then the bench tests
/// (catalase, coagulase, haemolysis, lactose, oxidase and the rest).
///
/// Written for this app from standard microbiology (facts, not anyone's
/// text). Each organism carries its NCBI Taxonomy identifier (a US
/// government work, public domain) so the name can be checked there.
/// Foundation only.
struct Microbe: Hashable, Identifiable {
    let id: String
    /// The binomial name, as NCBI Taxonomy spells it.
    let name: String
    enum Gram: String, Hashable { case positive, negative, none }
    let gram: Gram
    let shape: String
    let oxygen: String
    /// What sets it apart on the bench and at the bedside.
    let features: [String]
    let diseases: [String]
    let taxonomy: Int

    var taxonomyURL: String { "https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=\(taxonomy)" }
}

/// One question of the key, with an answer leading to the next question or
/// to one or more organisms.
struct MicrobeKeyNode: Hashable, Identifiable {
    let id: String
    let question: String
    let answers: [Answer]

    struct Answer: Hashable {
        let label: String
        let next: Next
    }

    enum Next: Hashable {
        case node(String)
        case organisms([String])
    }
}

enum Microbiology {

    static let organisms: [Microbe] = [
        Microbe(id: "saureus", name: "Staphylococcus aureus", gram: .positive, shape: "Cocci in clusters", oxygen: "Facultative anaerobe",
                features: ["Catalase positive", "Coagulase positive", "Golden colonies; protein A; many toxins"],
                diseases: ["Skin and soft tissue infection, abscesses", "Osteomyelitis and septic arthritis", "Endocarditis (right-sided in people who inject drugs)",
                           "Toxic shock syndrome", "Food poisoning from a preformed toxin (vomiting within hours)", "MRSA: resistant to flucloxacillin"],
                taxonomy: 1280),
        Microbe(id: "sepidermidis", name: "Staphylococcus epidermidis", gram: .positive, shape: "Cocci in clusters", oxygen: "Facultative anaerobe",
                features: ["Catalase positive", "Coagulase negative", "Novobiocin sensitive", "Makes biofilm"],
                diseases: ["Infection of lines, prosthetic joints and valves", "Common contaminant of blood cultures"], taxonomy: 1282),
        Microbe(id: "ssaprophyticus", name: "Staphylococcus saprophyticus", gram: .positive, shape: "Cocci in clusters", oxygen: "Facultative anaerobe",
                features: ["Catalase positive", "Coagulase negative", "Novobiocin resistant"],
                diseases: ["Urinary tract infection in young sexually active women"], taxonomy: 29385),
        Microbe(id: "spyogenes", name: "Streptococcus pyogenes", gram: .positive, shape: "Cocci in chains", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "β-haemolytic", "Bacitracin sensitive", "Lancefield group A; M protein"],
                diseases: ["Pharyngitis, scarlet fever", "Impetigo, cellulitis, necrotising fasciitis", "Streptococcal toxic shock",
                           "After infection: rheumatic fever (after pharyngitis) and post-streptococcal glomerulonephritis"], taxonomy: 1314),
        Microbe(id: "sagalactiae", name: "Streptococcus agalactiae", gram: .positive, shape: "Cocci in chains", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "β-haemolytic", "Bacitracin resistant", "Lancefield group B; CAMP test positive"],
                diseases: ["Neonatal sepsis, pneumonia and meningitis", "Carried in the vagina; intrapartum antibiotics prevent early-onset disease"], taxonomy: 1311),
        Microbe(id: "spneumoniae", name: "Streptococcus pneumoniae", gram: .positive, shape: "Lancet-shaped diplococci", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "α-haemolytic", "Optochin sensitive and bile soluble", "Polysaccharide capsule (the vaccines' target)"],
                diseases: ["Community-acquired pneumonia (the commonest cause)", "Otitis media and sinusitis", "Meningitis in adults",
                           "Severe infection after splenectomy or in sickle cell disease"], taxonomy: 1313),
        Microbe(id: "viridans", name: "Streptococcus mutans", gram: .positive, shape: "Cocci in chains", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "α-haemolytic", "Optochin resistant", "One of the viridans streptococci of the mouth"],
                diseases: ["Dental caries", "Subacute endocarditis on damaged valves, after dental work"], taxonomy: 1309),
        Microbe(id: "efaecalis", name: "Enterococcus faecalis", gram: .positive, shape: "Cocci in pairs and chains", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "Usually non-haemolytic", "Grows in 6.5% salt and bile; hydrolyses aesculin", "Lancefield group D"],
                diseases: ["Urinary tract infection", "Endocarditis", "Naturally resistant to cephalosporins; VRE in hospitals"], taxonomy: 1351),
        Microbe(id: "sgallolyticus", name: "Streptococcus gallolyticus", gram: .positive, shape: "Cocci in chains", oxygen: "Facultative anaerobe",
                features: ["Catalase negative", "Non-haemolytic", "Bile aesculin positive but no growth in 6.5% salt", "Formerly S. bovis; group D"],
                diseases: ["Endocarditis: look for colorectal cancer"], taxonomy: 315405),
        Microbe(id: "banthracis", name: "Bacillus anthracis", gram: .positive, shape: "Large rods in chains", oxygen: "Aerobe, forms spores",
                features: ["Polypeptide capsule", "Oedema and lethal toxins"],
                diseases: ["Cutaneous anthrax: a painless black eschar", "Inhalational anthrax: haemorrhagic mediastinitis"], taxonomy: 1392),
        Microbe(id: "bcereus", name: "Bacillus cereus", gram: .positive, shape: "Rods", oxygen: "Facultative anaerobe, forms spores",
                features: ["Spores survive cooking"], diseases: ["Food poisoning from reheated rice: vomiting within hours, or later diarrhoea"], taxonomy: 1396),
        Microbe(id: "cdifficile", name: "Clostridioides difficile", gram: .positive, shape: "Rods", oxygen: "Obligate anaerobe, forms spores",
                features: ["Toxins A and B", "Spores spread in hospitals; alcohol gel does not kill them"],
                diseases: ["Antibiotic-associated diarrhoea and pseudomembranous colitis"], taxonomy: 1496),
        Microbe(id: "cperfringens", name: "Clostridium perfringens", gram: .positive, shape: "Large rods", oxygen: "Anaerobe, forms spores",
                features: ["α-toxin (a lecithinase)", "Double zone of haemolysis"],
                diseases: ["Gas gangrene (clostridial myonecrosis)", "Food poisoning"], taxonomy: 1502),
        Microbe(id: "ctetani", name: "Clostridium tetani", gram: .positive, shape: "Rods with terminal spores (drumstick)", oxygen: "Obligate anaerobe",
                features: ["Tetanospasmin blocks the release of GABA and glycine from inhibitory neurons"],
                diseases: ["Tetanus: trismus, risus sardonicus, opisthotonos"], taxonomy: 1513),
        Microbe(id: "cbotulinum", name: "Clostridium botulinum", gram: .positive, shape: "Rods", oxygen: "Obligate anaerobe, forms spores",
                features: ["Botulinum toxin blocks acetylcholine release at the neuromuscular junction"],
                diseases: ["Botulism: descending flaccid paralysis", "Infant botulism (honey)"], taxonomy: 1491),
        Microbe(id: "listeria", name: "Listeria monocytogenes", gram: .positive, shape: "Short rods", oxygen: "Facultative anaerobe",
                features: ["Tumbling motility", "Grows in the fridge", "Lives inside cells, moving on actin tails", "Cephalosporins do not work: amoxicillin does"],
                diseases: ["Meningitis in neonates, older adults and the immunosuppressed", "Infection in pregnancy (unpasteurised cheese, deli meat)"], taxonomy: 1639),
        Microbe(id: "cdiphtheriae", name: "Corynebacterium diphtheriae", gram: .positive, shape: "Club-shaped rods", oxygen: "Facultative anaerobe",
                features: ["Metachromatic granules", "Diphtheria toxin (encoded by a phage) stops protein synthesis"],
                diseases: ["Diphtheria: a grey pseudomembrane, bull neck, myocarditis"], taxonomy: 1717),
        Microbe(id: "nmeningitidis", name: "Neisseria meningitidis", gram: .negative, shape: "Kidney-shaped diplococci", oxygen: "Aerobe",
                features: ["Oxidase positive", "Ferments glucose and maltose", "Capsule; endotoxin"],
                diseases: ["Meningitis", "Meningococcal septicaemia with a non-blanching rash", "Waterhouse-Friderichsen syndrome (adrenal haemorrhage)"], taxonomy: 487),
        Microbe(id: "ngonorrhoeae", name: "Neisseria gonorrhoeae", gram: .negative, shape: "Kidney-shaped diplococci", oxygen: "Aerobe",
                features: ["Oxidase positive", "Ferments glucose only", "No capsule; pili vary their antigens"],
                diseases: ["Gonorrhoea: urethritis, cervicitis", "Septic arthritis in young adults", "Neonatal conjunctivitis"], taxonomy: 485),
        Microbe(id: "mcatarrhalis", name: "Moraxella catarrhalis", gram: .negative, shape: "Diplococci", oxygen: "Aerobe",
                features: ["Oxidase positive", "Ferments no sugars", "Usually makes β-lactamase"],
                diseases: ["Otitis media and sinusitis", "Exacerbations of COPD"], taxonomy: 480),
        Microbe(id: "ecoli", name: "Escherichia coli", gram: .negative, shape: "Rods", oxygen: "Facultative anaerobe",
                features: ["Ferments lactose quickly (pink on MacConkey)", "Oxidase negative", "Indole positive"],
                diseases: ["Urinary tract infection (the commonest cause)", "Neonatal meningitis (K1 capsule)", "Travellers' diarrhoea (ETEC)",
                           "Haemolytic uraemic syndrome after O157:H7 (EHEC, Shiga-like toxin)"], taxonomy: 562),
        Microbe(id: "kpneumoniae", name: "Klebsiella pneumoniae", gram: .negative, shape: "Rods", oxygen: "Facultative anaerobe",
                features: ["Ferments lactose", "Large mucoid capsule", "Non-motile"],
                diseases: ["Pneumonia with upper-lobe cavities, in alcohol use disorder and diabetes", "Hospital infections; carbapenemase producers"], taxonomy: 573),
        Microbe(id: "paeruginosa", name: "Pseudomonas aeruginosa", gram: .negative, shape: "Rods", oxygen: "Obligate aerobe",
                features: ["Non-lactose fermenter", "Oxidase positive", "Blue-green pigment, grape-like smell", "Resists many antibiotics"],
                diseases: ["Hospital and ventilator pneumonia", "Chronic lung infection in cystic fibrosis", "Burn wound infection",
                           "Malignant otitis externa in diabetes", "Hot tub folliculitis"], taxonomy: 287),
        Microbe(id: "salmonella", name: "Salmonella enterica", gram: .negative, shape: "Rods", oxygen: "Facultative anaerobe",
                features: ["Non-lactose fermenter", "Oxidase negative", "Makes H2S", "Motile"],
                diseases: ["Typhoid fever (serovar Typhi): fever, rose spots, relative bradycardia", "Gastroenteritis from poultry and eggs",
                           "Osteomyelitis in sickle cell disease"], taxonomy: 28901),
        Microbe(id: "shigella", name: "Shigella", gram: .negative, shape: "Rods", oxygen: "Facultative anaerobe",
                features: ["Non-lactose fermenter", "Oxidase negative", "No H2S", "Non-motile", "Very few organisms cause infection"],
                diseases: ["Bacillary dysentery: bloody diarrhoea", "Shiga toxin (S. dysenteriae) and haemolytic uraemic syndrome"], taxonomy: 620),
        Microbe(id: "proteus", name: "Proteus mirabilis", gram: .negative, shape: "Rods", oxygen: "Facultative anaerobe",
                features: ["Non-lactose fermenter", "Makes H2S", "Urease positive", "Swarms across agar"],
                diseases: ["Urinary tract infection with struvite (staghorn) stones"], taxonomy: 584),
        Microbe(id: "hinfluenzae", name: "Haemophilus influenzae", gram: .negative, shape: "Coccobacilli", oxygen: "Facultative anaerobe",
                features: ["Needs factors X (haemin) and V (NAD) to grow: chocolate agar", "Type b capsule is the vaccine's target"],
                diseases: ["Epiglottitis and meningitis in unvaccinated children (type b)", "Otitis media, sinusitis, COPD exacerbations (non-typeable)"], taxonomy: 727),
        Microbe(id: "bpertussis", name: "Bordetella pertussis", gram: .negative, shape: "Coccobacilli", oxygen: "Aerobe",
                features: ["Pertussis toxin", "Grows on charcoal blood agar"],
                diseases: ["Whooping cough: paroxysms, inspiratory whoop, post-tussive vomiting; lymphocytosis"], taxonomy: 520),
        Microbe(id: "hpylori", name: "Helicobacter pylori", gram: .negative, shape: "Curved, spiral rods", oxygen: "Microaerophile",
                features: ["Urease positive (the basis of the breath test)", "Oxidase positive", "Flagella"],
                diseases: ["Chronic gastritis", "Duodenal and gastric ulcers", "Gastric adenocarcinoma and MALT lymphoma"], taxonomy: 210),
        Microbe(id: "vcholerae", name: "Vibrio cholerae", gram: .negative, shape: "Comma-shaped rods", oxygen: "Facultative anaerobe",
                features: ["Oxidase positive", "Grows in alkaline media", "Cholera toxin raises cAMP in gut cells"],
                diseases: ["Cholera: profuse rice-water diarrhoea"], taxonomy: 666),
        Microbe(id: "cjejuni", name: "Campylobacter jejuni", gram: .negative, shape: "Curved, S-shaped rods", oxygen: "Microaerophile",
                features: ["Oxidase positive", "Grows at 42 °C"],
                diseases: ["Gastroenteritis from undercooked poultry (a common cause of bloody diarrhoea)", "Guillain-Barré syndrome afterwards"], taxonomy: 197),
        Microbe(id: "legionella", name: "Legionella pneumophila", gram: .negative, shape: "Rods that stain poorly", oxygen: "Aerobe",
                features: ["Grows on buffered charcoal yeast extract", "Urinary antigen test", "Spread in water aerosols (air conditioning)"],
                diseases: ["Legionnaires' disease: pneumonia with diarrhoea, confusion and low sodium", "Pontiac fever (mild)"], taxonomy: 446),
        Microbe(id: "mtuberculosis", name: "Mycobacterium tuberculosis", gram: .none, shape: "Rods", oxygen: "Obligate aerobe",
                features: ["Acid-fast (Ziehl-Neelsen)", "Mycolic acid in the wall", "Grows slowly, over weeks"],
                diseases: ["Tuberculosis: primary (Ghon complex), latent, reactivation in the upper lobes", "Miliary and extrapulmonary disease (Pott's spine, meningitis)"], taxonomy: 1773),
        Microbe(id: "mleprae", name: "Mycobacterium leprae", gram: .none, shape: "Rods", oxygen: "Aerobe",
                features: ["Acid-fast", "Prefers cool parts of the body", "Cannot be grown in culture"],
                diseases: ["Leprosy: tuberculoid and lepromatous, with numb skin patches and nerve damage"], taxonomy: 1769),
        Microbe(id: "nocardia", name: "Nocardia", gram: .positive, shape: "Branching filaments", oxygen: "Aerobe",
                features: ["Weakly acid-fast", "Found in soil", "Treated with co-trimoxazole"],
                diseases: ["Lung and brain abscesses in the immunosuppressed"], taxonomy: 1817),
        Microbe(id: "actinomyces", name: "Actinomyces israelii", gram: .positive, shape: "Branching filaments", oxygen: "Anaerobe",
                features: ["Not acid-fast", "Yellow 'sulfur' granules", "Normal mouth flora", "Treated with penicillin"],
                diseases: ["Cervicofacial abscess with sinus tracts", "Pelvic infection with an intrauterine device"], taxonomy: 1659),
        Microbe(id: "mpneumoniae", name: "Mycoplasmoides pneumoniae", gram: .none, shape: "No cell wall, no fixed shape", oxygen: "Facultative anaerobe",
                features: ["No cell wall: invisible on Gram stain and untouched by β-lactams", "Cold agglutinins", "Long called Mycoplasma pneumoniae"],
                diseases: ["Atypical pneumonia in young adults", "Erythema multiforme, autoimmune haemolysis"], taxonomy: 2104),
        Microbe(id: "ctrachomatis", name: "Chlamydia trachomatis", gram: .none, shape: "Obligate intracellular", oxygen: "Inside cells",
                features: ["Elementary body infects, reticulate body divides", "Diagnosed by nucleic acid amplification"],
                diseases: ["The commonest bacterial sexually transmitted infection; pelvic inflammatory disease", "Neonatal conjunctivitis and pneumonia", "Trachoma (blindness)"], taxonomy: 813),
        Microbe(id: "tpallidum", name: "Treponema pallidum", gram: .none, shape: "Spirochaete", oxygen: "Microaerophile",
                features: ["Too thin for Gram stain: dark-field microscopy", "Serology: non-treponemal (RPR, VDRL) and treponemal tests"],
                diseases: ["Syphilis: painless chancre, then rash on palms and soles, then gummas, aortitis, tabes dorsalis", "Congenital syphilis"], taxonomy: 160),
    ]

    static func organism(_ id: String) -> Microbe? { organisms.first { $0.id == id } }

    /// The key's first question.
    static let root: String = "start"

    static let key: [MicrobeKeyNode] = [
        MicrobeKeyNode(id: "start", question: "What does the Gram stain show?", answers: [
            .init(label: "Gram-positive cocci", next: .node("gpc")),
            .init(label: "Gram-positive rods", next: .node("gpr")),
            .init(label: "Gram-positive branching filaments", next: .node("branching")),
            .init(label: "Gram-negative cocci", next: .node("gnc")),
            .init(label: "Gram-negative straight rods", next: .node("gnr")),
            .init(label: "Gram-negative curved rods", next: .node("curved")),
            .init(label: "Gram-negative coccobacilli", next: .node("coccobacilli")),
            .init(label: "Stains poorly or not at all", next: .node("unstained")),
        ]),
        MicrobeKeyNode(id: "gpc", question: "Catalase test (bubbles in hydrogen peroxide)?", answers: [
            .init(label: "Positive: staphylococci", next: .node("coagulase")),
            .init(label: "Negative: streptococci and enterococci", next: .node("haemolysis")),
        ]),
        MicrobeKeyNode(id: "coagulase", question: "Coagulase?", answers: [
            .init(label: "Positive", next: .organisms(["saureus"])),
            .init(label: "Negative", next: .node("novobiocin")),
        ]),
        MicrobeKeyNode(id: "novobiocin", question: "Novobiocin disc?", answers: [
            .init(label: "Sensitive", next: .organisms(["sepidermidis"])),
            .init(label: "Resistant", next: .organisms(["ssaprophyticus"])),
        ]),
        MicrobeKeyNode(id: "haemolysis", question: "Haemolysis on blood agar?", answers: [
            .init(label: "β: complete, a clear zone", next: .node("bacitracin")),
            .init(label: "α: partial, green", next: .node("optochin")),
            .init(label: "γ: none", next: .node("salt")),
        ]),
        MicrobeKeyNode(id: "bacitracin", question: "Bacitracin disc?", answers: [
            .init(label: "Sensitive: group A", next: .organisms(["spyogenes"])),
            .init(label: "Resistant: group B", next: .organisms(["sagalactiae"])),
        ]),
        MicrobeKeyNode(id: "optochin", question: "Optochin disc?", answers: [
            .init(label: "Sensitive (and bile soluble)", next: .organisms(["spneumoniae"])),
            .init(label: "Resistant: viridans streptococci", next: .organisms(["viridans"])),
        ]),
        MicrobeKeyNode(id: "salt", question: "Grows in 6.5% salt?", answers: [
            .init(label: "Yes: enterococci", next: .organisms(["efaecalis"])),
            .init(label: "No", next: .organisms(["sgallolyticus"])),
        ]),
        MicrobeKeyNode(id: "gpr", question: "Does it form spores?", answers: [
            .init(label: "Yes, growing in air: Bacillus", next: .organisms(["banthracis", "bcereus"])),
            .init(label: "Yes, only without air: Clostridia", next: .organisms(["cdifficile", "cperfringens", "ctetani", "cbotulinum"])),
            .init(label: "No", next: .node("nonspore")),
        ]),
        MicrobeKeyNode(id: "nonspore", question: "What else do you see?", answers: [
            .init(label: "Tumbling motility, grows in the cold", next: .organisms(["listeria"])),
            .init(label: "Club shapes with metachromatic granules", next: .organisms(["cdiphtheriae"])),
        ]),
        MicrobeKeyNode(id: "branching", question: "Acid-fast stain, and oxygen?", answers: [
            .init(label: "Weakly acid-fast, grows in air", next: .organisms(["nocardia"])),
            .init(label: "Not acid-fast, grows without air", next: .organisms(["actinomyces"])),
        ]),
        MicrobeKeyNode(id: "gnc", question: "Which sugars does it ferment?", answers: [
            .init(label: "Glucose and maltose", next: .organisms(["nmeningitidis"])),
            .init(label: "Glucose only", next: .organisms(["ngonorrhoeae"])),
            .init(label: "None", next: .organisms(["mcatarrhalis"])),
        ]),
        MicrobeKeyNode(id: "gnr", question: "Ferments lactose (pink colonies on MacConkey)?", answers: [
            .init(label: "Yes", next: .node("capsule")),
            .init(label: "No", next: .node("oxidase")),
        ]),
        MicrobeKeyNode(id: "capsule", question: "Large mucoid capsule?", answers: [
            .init(label: "Yes", next: .organisms(["kpneumoniae"])),
            .init(label: "No", next: .organisms(["ecoli"])),
        ]),
        MicrobeKeyNode(id: "oxidase", question: "Oxidase test?", answers: [
            .init(label: "Positive", next: .organisms(["paeruginosa"])),
            .init(label: "Negative", next: .node("h2s")),
        ]),
        MicrobeKeyNode(id: "h2s", question: "Makes hydrogen sulphide (black colonies)?", answers: [
            .init(label: "Yes", next: .node("urease")),
            .init(label: "No", next: .organisms(["shigella"])),
        ]),
        MicrobeKeyNode(id: "urease", question: "Urease, and swarming?", answers: [
            .init(label: "Urease positive, swarms", next: .organisms(["proteus"])),
            .init(label: "Urease negative", next: .organisms(["salmonella"])),
        ]),
        MicrobeKeyNode(id: "curved", question: "Which test?", answers: [
            .init(label: "Urease positive", next: .organisms(["hpylori"])),
            .init(label: "Grows at 42 °C", next: .organisms(["cjejuni"])),
            .init(label: "Comma-shaped, grows in alkaline media", next: .organisms(["vcholerae"])),
        ]),
        MicrobeKeyNode(id: "coccobacilli", question: "Needs factors X and V (grows on chocolate agar)?", answers: [
            .init(label: "Yes", next: .organisms(["hinfluenzae"])),
            .init(label: "No: charcoal blood agar", next: .organisms(["bpertussis"])),
        ]),
        MicrobeKeyNode(id: "unstained", question: "What shows it instead?", answers: [
            .init(label: "Acid-fast (Ziehl-Neelsen), grows in culture over weeks", next: .organisms(["mtuberculosis"])),
            .init(label: "Acid-fast, never grows in culture", next: .organisms(["mleprae"])),
            .init(label: "Charcoal yeast extract agar, urinary antigen", next: .organisms(["legionella"])),
            .init(label: "No cell wall at all", next: .organisms(["mpneumoniae"])),
            .init(label: "Only inside cells", next: .organisms(["ctrachomatis"])),
            .init(label: "A spirochaete on dark-field microscopy", next: .organisms(["tpallidum"])),
        ]),
    ]

    static func node(_ id: String) -> MicrobeKeyNode? { key.first { $0.id == id } }

    /// The path of answers from the root to `organism`, or nil if the key
    /// never reaches it.
    static func path(to organism: String) -> [String]? {
        func walk(_ id: String, _ trail: [String]) -> [String]? {
            guard let n = node(id) else { return nil }
            for a in n.answers {
                switch a.next {
                case .organisms(let ids) where ids.contains(organism): return trail + [a.label]
                case .organisms: continue
                case .node(let next):
                    if let found = walk(next, trail + [a.label]) { return found }
                }
            }
            return nil
        }
        return walk(root, [])
    }

    // MARK: growth

    /// Cells after `minutes` of exponential growth from `start` cells with a
    /// doubling time of `generation` minutes: N = N0 × 2^(t/g).
    static func exponential(start: Double, minutes: Double, generation: Double) -> Double {
        guard generation > 0 else { return start }
        return start * pow(2, minutes / generation)
    }

    /// A batch culture's four phases, as log10 of the cell count against
    /// hours: a lag, exponential growth to the medium's capacity
    /// (logistic), a stationary plateau and a slow decline. Illustrative
    /// rates; the shape is what is examined.
    struct Culture: Hashable {
        var startLog10: Double = 3
        var capacityLog10: Double = 9
        var lagHours: Double = 2
        /// Doubling time in exponential growth, minutes.
        var generationMinutes: Double = 30
        var stationaryHours: Double = 6
        /// log10 units lost per hour in the death phase.
        var deathPerHour: Double = 0.25
    }

    static func cultureLog10(_ c: Culture, hours t: Double) -> Double {
        guard t > c.lagHours else { return c.startLog10 }
        let r: Double = log(2) / (c.generationMinutes / 60)
        let n0: Double = pow(10, c.startLog10), k: Double = pow(10, c.capacityLog10)
        let grow: Double = t - c.lagHours
        let n: Double = k / (1 + (k / n0 - 1) * exp(-r * grow))
        let full: Double = log10(n)
        // When the culture is within 1% of capacity the stationary phase
        // begins; after it, cells die.
        let reach: Double = c.lagHours + log((k / n0 - 1) / (1 / 0.99 - 1)) / r
        let deathStart: Double = reach + c.stationaryHours
        if t > deathStart { return max(0, c.capacityLog10 - c.deathPerHour * (t - deathStart)) }
        return full
    }
}
