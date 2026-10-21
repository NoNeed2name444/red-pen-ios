import Foundation

// Finding things in a case, and how names are matched: the lookups the
// screens, the checks and the score use. Apart from the case file itself so
// the Playgrounds core, which keeps a Cases set's file but not its screens,
// stays small (tools/make_swiftpm.py). Foundation only; the "cases" suite.

extension CaseFile {
    // MARK: looking things up

    func step(_ id: String) -> CaseStep? { steps.first { $0.id == id } }

    func steps(in group: CaseStep.Group) -> [CaseStep] { steps.filter { $0.group == group } }

    var keySteps: [CaseStep] { steps.filter { $0.value == .key } }

    var redFlagSteps: [CaseStep] { steps.filter(\.redFlag) }

    /// The differential that is the diagnosis, if the writer listed it.
    var diagnosisDifferential: Differential? {
        differentials.first { CaseNames.same($0.name, diagnosis.name) || $0.answers(diagnosis.name) }
    }

    /// The next most likely: the first differential that is not the diagnosis.
    var runnerUp: Differential? {
        differentials.first { !isDiagnosis($0.name) }
    }

    /// Whether a name - picked or typed - is the diagnosis.
    func isDiagnosis(_ name: String) -> Bool {
        CaseNames.matches(name, [diagnosis.name] + diagnosis.accepted + (diagnosisDifferential?.accepted ?? []))
    }

    /// The case's own name for what was typed: a differential's, the
    /// diagnosis's or a distractor's; nil when it is none of them.
    func resolve(_ typed: String) -> String? {
        if isDiagnosis(typed) { return diagnosisDifferential?.name ?? diagnosis.name }
        if let d = differentials.first(where: { $0.answers(typed) }) { return d.name }
        return distractors.first { CaseNames.same($0, typed) }
    }

    /// Everything the ladder can be picked from: the differentials and the
    /// distractors, once each, in an order fixed for this case (so the list
    /// does not jump about between visits) that does not give the answer
    /// away by its place.
    var candidates: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for name in differentials.map(\.name) + distractors {
            let key: String = CaseNames.normal(name)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            names.append(name)
        }
        var generator = CaseShuffle(seed: id)
        return names.shuffled(using: &generator)
    }
}

extension Differential {
    /// Whether a typed name is this one.
    func answers(_ typed: String) -> Bool {
        CaseNames.matches(typed, [name] + accepted)
    }
}

/// How names are compared: case, accents, punctuation and spacing aside, so
/// "Pulmonary embolism", "pulmonary-embolism" and "PE" (when accepted) match.
enum CaseNames {
    static func normal(_ text: String) -> String {
        let folded: String = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var out: String = ""
        var space = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if space && !out.isEmpty { out.append(" ") }
                out.unicodeScalars.append(scalar)
                space = false
            } else {
                space = true
            }
        }
        return out
    }

    static func same(_ a: String, _ b: String) -> Bool {
        let x: String = normal(a)
        return !x.isEmpty && x == normal(b)
    }

    static func matches(_ typed: String, _ names: [String]) -> Bool {
        names.contains { same(typed, $0) }
    }
}

/// A shuffle that comes out the same for the same case every time
/// (SplitMix64, seeded from the case's id).
struct CaseShuffle: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UUID) {
        let u = seed.uuid
        let bytes: [UInt8] = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        var s: UInt64 = 0x9E3779B97F4A7C15
        for byte in bytes { s = (s ^ UInt64(byte)) &* 0x100000001B3 }
        state = s
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
