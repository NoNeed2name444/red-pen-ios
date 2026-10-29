import Foundation

/// Inheritance and the genetic code: Punnett squares, Hardy-Weinberg
/// carrier frequencies, the textbook recurrence risks, transcription and
/// translation, and what a change in a coding sequence does to the protein.
/// Foundation only.
enum Genetics {

    // MARK: Punnett squares

    /// A genotype as gene pairs, "AaBb": each pair is one gene, upper case
    /// dominant. Nil unless it is pairs of one letter each.
    static func genes(_ genotype: String) -> [[Character]]? {
        let letters: [Character] = Array(genotype.filter { !$0.isWhitespace })
        guard !letters.isEmpty, letters.count % 2 == 0 else { return nil }
        var out: [[Character]] = []
        for i in stride(from: 0, to: letters.count, by: 2) {
            let pair: [Character] = [letters[i], letters[i + 1]]
            guard pair.allSatisfy(\.isLetter),
                  pair[0].lowercased() == pair[1].lowercased() else { return nil }
            out.append(pair)
        }
        return out
    }

    /// The gametes a genotype makes, each equally likely (independent
    /// assortment).
    static func gametes(_ genotype: String) -> [String] {
        guard let gs = genes(genotype) else { return [] }
        var out: [String] = [""]
        for pair in gs {
            out = out.flatMap { g in pair.map { g + String($0) } }
        }
        return out
    }

    /// A genotype written in the usual order: per gene, dominant first.
    static func normalised(_ genotype: String) -> String {
        guard let gs = genes(genotype) else { return genotype }
        return gs.map { pair in
            String(pair.sorted { a, b in a.isUppercase && !b.isUppercase })
        }.joined()
    }

    /// The phenotype a genotype shows, as one letter per gene: upper case
    /// when a dominant allele is there.
    static func phenotype(_ genotype: String) -> String {
        guard let gs = genes(genotype) else { return genotype }
        return gs.map { pair in
            pair.contains(where: \.isUppercase) ? String(pair[0]).uppercased() : String(pair[0]).lowercased()
        }.joined()
    }

    struct Cross: Hashable {
        /// The grid: rows are the first parent's gametes, columns the second's.
        var rows: [String]
        var columns: [String]
        var cells: [[String]]
        /// Each genotype and phenotype with its count out of `total`.
        var genotypes: [String: Int]
        var phenotypes: [String: Int]
        var total: Int
    }

    static func cross(_ a: String, _ b: String) -> Cross? {
        guard let ga = genes(a), let gb = genes(b), ga.count == gb.count,
              zip(ga, gb).allSatisfy({ $0[0].lowercased() == $1[0].lowercased() }) else { return nil }
        let rows: [String] = gametes(a), cols: [String] = gametes(b)
        var cells: [[String]] = []
        var gen: [String: Int] = [:], phen: [String: Int] = [:]
        for r in rows {
            var line: [String] = []
            for c in cols {
                let child: String = zip(r, c).map { String($0) + String($1) }.joined()
                let n: String = normalised(child)
                line.append(n)
                gen[n, default: 0] += 1
                phen[phenotype(n), default: 0] += 1
            }
            cells.append(line)
        }
        return Cross(rows: rows, columns: cols, cells: cells, genotypes: gen, phenotypes: phen,
                     total: rows.count * cols.count)
    }

    /// Counts reduced to their simplest ratio, largest first ("9:3:3:1").
    static func ratio(_ counts: [String: Int]) -> String {
        let values: [Int] = counts.values.sorted(by: >)
        guard let first = values.first else { return "" }
        let g: Int = values.dropFirst().reduce(first) { gcd($0, $1) }
        return values.map { String($0 / max(1, g)) }.joined(separator: ":")
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    // MARK: populations and risks

    struct HardyWeinberg: Hashable {
        /// Allele frequencies.
        var p: Double, q: Double
        /// Genotype frequencies.
        var homozygousDominant: Double, carriers: Double, affected: Double
    }

    /// For an autosomal recessive disease seen in `incidence` of births
    /// (q²): q = √incidence, carriers 2pq.
    static func hardyWeinberg(incidence: Double) -> HardyWeinberg {
        let q: Double = max(0, min(1, incidence)).squareRoot()
        let p: Double = 1 - q
        return HardyWeinberg(p: p, q: q, homozygousDominant: p * p, carriers: 2 * p * q, affected: q * q)
    }

    enum Pattern: String, CaseIterable, Identifiable {
        case autosomalDominant, autosomalRecessive, xLinkedRecessive, xLinkedDominant, mitochondrial
        var id: String { rawValue }

        var name: String {
            switch self {
            case .autosomalDominant: return "Autosomal dominant"
            case .autosomalRecessive: return "Autosomal recessive"
            case .xLinkedRecessive: return "X-linked recessive"
            case .xLinkedDominant: return "X-linked dominant"
            case .mitochondrial: return "Mitochondrial"
            }
        }

        /// The textbook risks for the classic family, as the exam asks them.
        var risks: [String] {
            switch self {
            case .autosomalDominant:
                return ["Affected parent × unaffected parent: each child 1 in 2 affected, either sex.",
                        "Seen in every generation; male-to-male transmission happens.",
                        "Variable expression and incomplete penetrance can make it skip."]
            case .autosomalRecessive:
                return ["Two carrier parents: each child 1 in 4 affected, 1 in 2 a carrier, 1 in 4 neither.",
                        "An unaffected sibling of an affected child is a carrier with probability 2 in 3.",
                        "Usually seen in one generation; consanguinity raises the risk."]
            case .xLinkedRecessive:
                return ["Carrier mother × unaffected father: each son 1 in 2 affected; each daughter 1 in 2 a carrier.",
                        "Affected father × non-carrier mother: all daughters carriers, no sons affected.",
                        "No male-to-male transmission."]
            case .xLinkedDominant:
                return ["Affected father: all daughters affected, no sons.",
                        "Affected mother: each child 1 in 2 affected, either sex."]
            case .mitochondrial:
                return ["Passed only from the mother, to all her children.",
                        "Severity varies with the share of mutant mitochondria (heteroplasmy)."]
            }
        }
    }

    /// The chance that a child of an unaffected sibling of someone with an
    /// autosomal recessive disease is affected, when the partner is from
    /// the general population: 2/3 × 2pq × 1/4.
    static func siblingsChildRisk(incidence: Double) -> Double {
        2.0 / 3.0 * hardyWeinberg(incidence: incidence).carriers * 0.25
    }

    // MARK: the genetic code

    static let codons: [String: Character] = {
        let bases: [Character] = ["U", "C", "A", "G"]
        // The standard code, in UCAG order of first, second, third base.
        let aminoAcids: String = "FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG"
        var table: [String: Character] = [:]
        var i: Int = 0
        let aa: [Character] = Array(aminoAcids)
        for a in bases { for b in bases { for c in bases {
            table[String([a, b, c])] = aa[i]; i += 1
        }}}
        return table
    }()

    static let threeLetter: [Character: String] = [
        "A": "Ala", "R": "Arg", "N": "Asn", "D": "Asp", "C": "Cys", "Q": "Gln", "E": "Glu", "G": "Gly",
        "H": "His", "I": "Ile", "L": "Leu", "K": "Lys", "M": "Met", "F": "Phe", "P": "Pro", "S": "Ser",
        "T": "Thr", "W": "Trp", "Y": "Tyr", "V": "Val", "*": "Stop",
    ]

    /// mRNA from the coding (sense) strand of DNA: T becomes U.
    static func transcribe(coding dna: String) -> String {
        String(dna.uppercased().filter { "ACGT".contains($0) }.map { $0 == "T" ? "U" : $0 })
    }

    /// The coding strand from the template strand: the reverse complement.
    static func codingStrand(template: String) -> String {
        let pairs: [Character: Character] = ["A": "T", "T": "A", "G": "C", "C": "G"]
        return String(template.uppercased().compactMap { pairs[$0] }.reversed())
    }

    /// The protein from the first AUG to the first stop codon, in one-letter
    /// code (no stop sign). Empty when there is no AUG.
    static func translate(mRNA: String) -> String {
        let rna: [Character] = Array(mRNA.uppercased().map { $0 == "T" ? "U" : $0 })
        guard let start = findStart(rna) else { return "" }
        var protein: String = ""
        var i: Int = start
        while i + 3 <= rna.count {
            guard let aa = codons[String(rna[i..<i + 3])] else { break }
            if aa == "*" { break }
            protein.append(aa)
            i += 3
        }
        return protein
    }

    private static func findStart(_ rna: [Character]) -> Int? {
        guard rna.count >= 3 else { return nil }
        for i in 0...(rna.count - 3) where rna[i] == "A" && rna[i + 1] == "U" && rna[i + 2] == "G" { return i }
        return nil
    }

    enum Mutation: String, Hashable {
        case none, silent, missense, nonsense, frameshift, inFrameInsertion, inFrameDeletion

        var name: String {
            switch self {
            case .none: return "No change"
            case .silent: return "Silent (synonymous)"
            case .missense: return "Missense"
            case .nonsense: return "Nonsense"
            case .frameshift: return "Frameshift"
            case .inFrameInsertion: return "In-frame insertion"
            case .inFrameDeletion: return "In-frame deletion"
            }
        }
    }

    /// What changing the coding DNA `reference` to `variant` does.
    static func classify(reference: String, variant: String) -> Mutation {
        let ref: String = transcribe(coding: reference), alt: String = transcribe(coding: variant)
        if ref == alt { return .none }
        let difference: Int = alt.count - ref.count
        if difference != 0 {
            if difference % 3 != 0 { return .frameshift }
            return difference > 0 ? .inFrameInsertion : .inFrameDeletion
        }
        let p1: String = translate(mRNA: ref), p2: String = translate(mRNA: alt)
        if p1 == p2 { return .silent }
        if p2.count < p1.count && p1.hasPrefix(p2) { return .nonsense }
        return .missense
    }
}
