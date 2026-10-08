import Foundation

// The themed hierarchy (plan §3d): one structure, two pictures.
//
// Every folder is a concept cluster - every note in it and in the folders
// inside it. In the Neurons theme a cluster is a cell; in the Circuit theme
// the same cluster is a circuit. Its parts (level 2), their files (level 3)
// and each file's atomic bullets (level 4) are the SAME seven slots, files
// and bullets in both: switching the theme changes only the names and the
// drawing, never what is in them.
//
//   slot        from the app's data                       Neurons       Circuit
//   core        the cluster's core note: its one-line     soma          load
//               idea, its detail, its worked examples     idea.md       outcome.md
//                                                         detail.md     detail.md
//                                                         examples.md   application.md
//   incoming    notes outside that link in, by hand or    dendrites     capacitors
//               with [[Title]]                            from-X.md     X.md
//   outgoing    notes outside it links out to             axon          conductors
//                                                         to-X.md       path-X.md
//   reference   where its notes came from (Save to Ideas  nucleus       ground
//               sources: the question set, lecture...)    source.md     baseline.md
//   energy      why it matters: notes tagged high yield,  mitochondria  source
//               lines headed Why / Key point / High yield why.md        voltage.md
//   confidence  verified / sourced / unchecked notes      myelin        resistors
//               (tags, and whether a note has a source)   confidence.md limits.md
//   links       the links made by hand (Note.links)       synapse       switches
//                                                         link-X.md     if-X.md
//
// The nucleus and ground are both the reference point (the canonical
// source, the baseline); the mitochondria and the circuit's source are
// both where the energy comes from (why it matters, its voltage).
//
// Between clusters, links are nerve fibres or wires (AnatomyFiber):
// strength 1-10 from what joins them (hand-made links, [[Title]] mentions,
// links both ways, a shared source or tag); a fibre is excitatory, or
// inhibitory where the mention reads as a contrast ("not", "vs",
// "contraindicated"...), or modulatory where the link was only drawn by
// hand; a wire's resistance is 11 - strength, its current digital for a
// hand-made link and analog for a written mention. Direction: one way, or
// both when each side links to the other.
//
// Levels 3 and 4 are built only when asked for (AnatomyDetail: the camera
// close enough), every list is bounded (the rest counted in `more`), and
// no part is ever drawn smaller than a page (AnatomySizes).
//
// Foundation only, pure and deterministic. Tested on Linux
// (Tests/GraphAnatomyTests.swift).

// MARK: - the input

// AnatomyNote and AnatomyInput live in GraphUniverse.swift, beside the
// UniverseInput that carries them to the Neurons and Circuit planners.

// MARK: - the vocabulary

nonisolated enum AnatomyTheme: Int, Sendable, CaseIterable {
    case neuron = 0
    case circuit = 1
}

/// The seven parts every cluster has, in both themes.
nonisolated enum AnatomySlot: Int, Sendable, CaseIterable {
    case core = 0
    case incoming
    case outgoing
    case reference
    case energy
    case confidence
    case links

    /// The part's folder name in a theme.
    func part(_ theme: AnatomyTheme) -> String {
        switch theme {
        case .neuron:
            return ["soma", "dendrites", "axon", "nucleus", "mitochondria", "myelin", "synapse"][rawValue]
        case .circuit:
            return ["load", "capacitors", "conductors", "ground", "source", "resistors", "switches"][rawValue]
        }
    }
}

/// What a level-3 file is.
nonisolated enum AnatomyFileKind: Sendable, Equatable {
    case idea
    case detail
    case examples
    /// One per note outside that links in.
    case from(String)
    /// One per note outside linked to.
    case to(String)
    case source
    case why
    case confidence
    /// One per hand-made link.
    case link(String)

    /// The file's name in a theme ("from-heart-failure.md", "path-stemi.md").
    func name(_ theme: AnatomyTheme) -> String {
        let neuron: Bool = theme == .neuron
        switch self {
        case .idea: return neuron ? "idea.md" : "outcome.md"
        case .detail: return "detail.md"
        case .examples: return neuron ? "examples.md" : "application.md"
        case .from(let title): return (neuron ? "from-" : "") + GraphAnatomy.slug(title) + ".md"
        case .to(let title): return (neuron ? "to-" : "path-") + GraphAnatomy.slug(title) + ".md"
        case .source: return neuron ? "source.md" : "baseline.md"
        case .why: return neuron ? "why.md" : "voltage.md"
        case .confidence: return neuron ? "confidence.md" : "limits.md"
        case .link(let title): return (neuron ? "link-" : "if-") + GraphAnatomy.slug(title) + ".md"
        }
    }
}

// MARK: - the output

/// One atomic idea (level 4), and the note it came from.
nonisolated struct AnatomyBullet: Sendable, Equatable {
    let text: String
    let note: UUID?
}

/// A level-3 file. `bullets` is empty until level 4 is built;
/// `bulletCount` always says how many it has, `more` how many were left
/// out of `bullets`.
nonisolated struct AnatomyFile: Sendable, Equatable {
    let kind: AnatomyFileKind
    /// The note outside the cluster it is about (from-, to-, link-).
    let concept: UUID?
    /// 1-10: how strong the connection it is about (1 for the rest).
    let strength: Int
    let bulletCount: Int
    var bullets: [AnatomyBullet]
    var more: Int
}

/// A level-2 part. `files` is empty until level 3 is built; `fileCount`
/// always says how many it has. `measure` is the part's own 0...1 dial:
/// the myelin's verified share, the mitochondria's high-yield share, the
/// dendrites' and axon's strongest link over 10.
nonisolated struct AnatomyPart: Sendable, Equatable {
    let slot: AnatomySlot
    let fileCount: Int
    var files: [AnatomyFile]
    var more: Int
    let measure: Double

    func label(_ theme: AnatomyTheme) -> String {
        slot.part(theme) + " \u{00B7} \(fileCount)"
    }
}

/// A cluster built to `levels` (2, 3 or 4).
nonisolated struct AnatomyCell: Sendable, Equatable {
    let folder: UUID
    let name: String
    let notes: Int
    /// The core note (soma / load), nil for an empty cluster.
    let core: UUID?
    let parts: [AnatomyPart]
    let levels: Int
}

// MARK: - connections

nonisolated enum FiberKind: Int, Sendable, CaseIterable {
    case excitatory = 0
    case inhibitory = 1
    case modulatory = 2
}

/// A colour, 0...1 a channel.
nonisolated struct AnatomyRGB: Sendable, Equatable {
    let r: Double
    let g: Double
    let b: Double
}

/// One link between two notes, read the §3d way.
nonisolated struct AnatomyLink: Sendable, Equatable {
    let from: UUID
    let to: UUID
    let strength: Int
    let kind: FiberKind
    let twoWay: Bool
    let hand: Bool
    let written: Bool
}

/// A nerve fibre (or a wire) between two clusters.
nonisolated struct AnatomyFiber: Sendable, Equatable {
    /// The sending cluster's folder (the side that links out more).
    let from: UUID
    let to: UUID
    let strength: Int
    let kind: FiberKind
    let twoWay: Bool
    /// How many note links it gathers.
    let links: Int
    /// Whether most of them were made by hand: a wire's digital current.
    let digital: Bool
    /// Up to three "A → B" pairs it is drawn from.
    let evidence: [String]

    /// A wire's resistance, 1 (easy) to 10.
    var resistance: Int { 11 - strength }

    /// Green excitatory, red inhibitory, yellow modulatory; a wire orange
    /// when digital, blue when analog.
    func colour(_ theme: AnatomyTheme) -> AnatomyRGB {
        switch theme {
        case .neuron:
            switch kind {
            case .excitatory: return AnatomyRGB(r: 0.30, g: 0.95, b: 0.45)
            case .inhibitory: return AnatomyRGB(r: 1.00, g: 0.28, b: 0.30)
            case .modulatory: return AnatomyRGB(r: 1.00, g: 0.86, b: 0.25)
            }
        case .circuit:
            return digital ? AnatomyRGB(r: 1.00, g: 0.55, b: 0.12) : AnatomyRGB(r: 0.25, g: 0.60, b: 1.00)
        }
    }

    /// Its radius, `unit` the thickest: a fibre's grows with strength, a
    /// wire's falls with resistance (low resistance, thick wire).
    func thickness(_ theme: AnatomyTheme, unit: Double) -> Double {
        switch theme {
        case .neuron: return unit * (0.25 + 0.75 * Double(strength) / 10)
        case .circuit: return unit * (0.25 + 0.75 / Double(resistance))
        }
    }
}

// MARK: - level of detail and sizes

/// Which levels are built: the cell (level 2's parts) from afar, files
/// (3) within `fileReach` cell radii of the camera, bullets (4) within
/// `bulletReach`. A 10% band keeps a level from flickering at its edge.
nonisolated enum AnatomyDetail {
    static let fileReach: Double = 9
    static let bulletReach: Double = 4.5
    static let band: Double = 0.1

    static func levels(distance: Double, unit: Double, current: Int = 2) -> Int {
        let u: Double = max(unit, 0.0001)
        let d: Double = distance / u
        func inside(_ reach: Double, held: Bool) -> Bool {
            d < reach * (held ? 1 + band : 1 - band)
        }
        if inside(bulletReach, held: current >= 4) { return 4 }
        if inside(fileReach, held: current >= 3) { return 3 }
        return 2
    }
}

/// How big each level is drawn: always a step down from the level above
/// and never smaller than `page` (the theme's smallest page).
nonisolated enum AnatomySizes {
    static func sphere(level: Int, cell: Double, page: Double) -> Double {
        let shares: [Double] = [1, 0.45, 0.3, 0.2]
        let i: Int = min(max(level - 1, 0), shares.count - 1)
        return max(cell * shares[i], page)
    }
}

/// One drawn piece of a cell, centred relative to the cell's centre.
nonisolated struct AnatomyPlace: Sendable, Equatable {
    let level: Int
    let slot: AnatomySlot
    /// The file's index in its part (-1 for a part).
    let file: Int
    /// The bullet's index in its file (-1 otherwise).
    let bullet: Int
    let centre: SIMD3<Double>
    let sphere: Double
    /// The index of the place it hangs from (-1: the cell itself).
    let parent: Int
    let label: String
}

// MARK: - the mapping

nonisolated enum GraphAnatomy {
    /// At most this many files in a part, bullets in a file.
    static let maxFiles: Int = 5
    static let maxBullets: Int = 4
    /// A bullet's longest text.
    static let bulletLength: Int = 60

    // MARK: words

    /// "Heart failure (HFrEF)" -> "heart-failure-hfref", at most 32 long.
    static func slug(_ title: String) -> String {
        var out: String = ""
        var dash: Bool = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber {
                if dash && !out.isEmpty { out.append("-") }
                out.append(ch)
                dash = false
            } else {
                dash = true
            }
            if out.count >= 32 { break }
        }
        return out.isEmpty ? "untitled" : out
    }

    /// A tag as compared: lower case, no "#", spaces, dashes or underscores.
    static func tagKey(_ tag: String) -> String {
        String(tag.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "?" })
    }

    static let highYieldTags: Set<String> = ["highyield", "hy", "important", "key", "exam", "mustknow"]
    static let verifiedTags: Set<String> = ["verified", "checked", "confident", "sure", "reviewed"]
    static let unsureTags: Set<String> = ["unsure", "check", "verify", "unverified", "todo", "doubt", "?"]

    static func isHighYield(_ note: AnatomyNote) -> Bool {
        note.tags.contains { highYieldTags.contains(tagKey($0)) }
    }

    /// 2 verified by tag, 1 saved from a source (and not marked unsure),
    /// 0 unchecked.
    static func confidence(_ note: AnatomyNote) -> Int {
        let keys: [String] = note.tags.map(tagKey)
        if keys.contains(where: { unsureTags.contains($0) }) { return 0 }
        if keys.contains(where: { verifiedTags.contains($0) }) { return 2 }
        return note.source == nil ? 0 : 1
    }

    /// A body's lines as atomic ideas: list markers stripped, headings and
    /// empty lines left out, `[[Title|shown]]` read as its shown text.
    static func bullets(_ body: String) -> [String] {
        var out: [String] = []
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let text: String = plain(stripMarker(line))
            if !text.isEmpty { out.append(text) }
        }
        return out
    }

    static func stripMarker(_ line: String) -> String {
        var s: Substring = Substring(line)
        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "+ ", "> "] where s.hasPrefix(marker) {
            s = s.dropFirst(marker.count)
            return String(s).trimmingCharacters(in: .whitespaces)
        }
        // "1. " / "12) "
        let digits = s.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count < 4 {
            let rest = s.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return String(s)
    }

    /// `[[Title]]` -> Title, `[[Title|shown]]` -> shown, `**x**` -> x.
    static func plain(_ text: String) -> String {
        var out: String = ""
        var rest: Substring = Substring(text)
        while let open = rest.range(of: "[[") {
            out += rest[rest.startIndex..<open.lowerBound]
            let after: Substring = rest[open.upperBound...]
            guard let close = after.range(of: "]]") else {
                out += rest[open.lowerBound...]
                rest = ""
                break
            }
            let inner: Substring = after[after.startIndex..<close.lowerBound]
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            out += (parts.count > 1 ? parts[1] : parts.first ?? "")
            rest = after[close.upperBound...]
        }
        out += rest
        return out.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }

    static func clip(_ text: String) -> String {
        text.count > bulletLength ? String(text.prefix(bulletLength - 1)) + "\u{2026}" : text
    }

    /// A body's sections: (heading lowercased, or "" before the first, its lines).
    static func sections(_ body: String) -> [(String, [String])] {
        var out: [(String, [String])] = [("", [])]
        for raw in body.split(separator: "\n", omittingEmptySubsequences: true) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let heading: String = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                out.append((heading, []))
            } else if !line.isEmpty {
                let text: String = plain(stripMarker(line))
                if !text.isEmpty { out[out.count - 1].1.append(text) }
            }
        }
        return out
    }

    static let exampleHeadings: [String] = ["example", "case", "vignette", "scenario", "worked"]
    static let whyHeadings: [String] = ["why", "high yield", "high-yield", "key point", "clinical relevance",
                                        "matters", "remember", "pearl"]

    /// The core note's one-line idea, its detail, and its worked examples.
    static func coreFiles(_ note: AnatomyNote) -> (idea: [String], detail: [String], examples: [String]) {
        var idea: [String] = []
        var detail: [String] = []
        var examples: [String] = []
        for (heading, lines) in sections(note.body) {
            let isExample: Bool = exampleHeadings.contains { heading.contains($0) }
            for line in lines {
                let low: String = line.lowercased()
                if isExample || low.hasPrefix("e.g.") || low.hasPrefix("example:") || low.hasPrefix("eg ") {
                    examples.append(line)
                } else if idea.isEmpty {
                    idea.append(line)
                } else {
                    detail.append(line)
                }
            }
        }
        if idea.isEmpty { idea = [note.title.isEmpty ? "Untitled" : note.title] }
        return (idea, detail, examples)
    }

    /// The lines saying why a note matters: under a Why / High yield / Key
    /// point heading, or starting with one of those words.
    static func whyLines(_ note: AnatomyNote) -> [String] {
        var out: [String] = []
        for (heading, lines) in sections(note.body) {
            let under: Bool = whyHeadings.contains { heading.contains($0) }
            for line in lines {
                let low: String = line.lowercased()
                if under || whyHeadings.contains(where: { low.hasPrefix($0) }) { out.append(line) }
            }
        }
        return out
    }

    // MARK: links

    /// Words that make a mention a contrast: an inhibitory fibre.
    static let contrastCues: [String] = [" not ", "n't ", " vs", "versus", "contraindicat", "unlike", "rather than",
                                         "instead of", "exclude", "rules out", "rule out", " never ", " no ",
                                         "differs from", "distinguish"]

    /// The line in `body` that mentions `[[title]]`, if any.
    static func mention(of title: String, in body: String) -> String? {
        let key: String = "[[" + title.lowercased()
        for raw in body.split(separator: "\n") {
            let line: String = raw.lowercased()
            if let r = line.range(of: key) {
                let tail: Substring = line[r.upperBound...]
                if tail.hasPrefix("]]") || tail.hasPrefix("|") { return String(raw) }
            }
        }
        return nil
    }

    static func isContrast(_ line: String) -> Bool {
        let low: String = " " + line.lowercased() + " "
        return contrastCues.contains { low.contains($0) }
    }

    /// How `a` links to `b`, nil if it does not. Strength 1-10: 1, +3 made
    /// by hand, +3 written as [[b]], +2 when b links back, +1 a shared
    /// source, +1 a shared tag.
    static func link(_ a: AnatomyNote, _ b: AnatomyNote) -> AnatomyLink? {
        read(a, b)?.link
    }

    /// The link and the line of `a` that names `b` (nil when it was only
    /// drawn by hand), read once.
    static func read(_ a: AnatomyNote, _ b: AnatomyNote) -> (link: AnatomyLink, line: String?)? {
        let hand: Bool = a.hand.contains(b.id)
        let written: Bool = a.written.contains(b.id)
        guard hand || written, a.id != b.id else { return nil }
        let back: Bool = b.hand.contains(a.id) || b.written.contains(a.id)
        var strength: Int = 1 + (hand ? 3 : 0) + (written ? 3 : 0) + (back ? 2 : 0)
        if let s = a.source, s == b.source { strength += 1 }
        if !a.tags.isEmpty, !b.tags.isEmpty {
            let tagsA: Set<String> = Set(a.tags.map(tagKey))
            if b.tags.contains(where: { tagsA.contains(tagKey($0)) }) { strength += 1 }
        }
        let line: String? = written ? mention(of: b.title, in: a.body) : nil
        var kind: FiberKind = .excitatory
        if let line, isContrast(line) {
            kind = .inhibitory
        } else if hand && !written {
            kind = .modulatory
        }
        return (AnatomyLink(from: a.id, to: b.id, strength: min(max(strength, 1), 10), kind: kind,
                            twoWay: back, hand: hand, written: written), line)
    }
}

// MARK: - the index (built once a vault)

/// The vault read once for the anatomy: notes by id, each folder's cluster
/// (its notes and its sub-folders' notes), every note's links out and in.
nonisolated struct AnatomyIndex: Sendable {
    let notes: [AnatomyNote]
    let folders: [UniverseFolder]
    let position: [UUID: Int]
    /// Each folder's top-level ancestor (itself for a top-level folder).
    let top: [UUID: UUID]
    /// Each folder's ancestors, nearest first.
    let ancestors: [UUID: [UUID]]
    /// Notes linking to each note (by position).
    let incoming: [[Int]]
    /// Notes each note links to (by position), each once.
    let outgoing: [[Int]]

    init(_ input: AnatomyInput) {
        notes = input.notes
        folders = input.folders
        var position: [UUID: Int] = [:]
        for (i, note) in input.notes.enumerated() where position[note.id] == nil { position[note.id] = i }
        self.position = position
        var parent: [UUID: UUID] = [:]
        for folder in input.folders { if let p = folder.parent { parent[folder.id] = p } }
        let known: Set<UUID> = Set(input.folders.map(\.id))
        var top: [UUID: UUID] = [:]
        var ancestors: [UUID: [UUID]] = [:]
        for folder in input.folders {
            var chain: [UUID] = []
            var at: UUID = folder.id
            var seen: Set<UUID> = [at]
            while let p = parent[at], known.contains(p), seen.insert(p).inserted {
                chain.append(p)
                at = p
            }
            ancestors[folder.id] = chain
            top[folder.id] = at
        }
        self.top = top
        self.ancestors = ancestors
        var incoming = [[Int]](repeating: [], count: input.notes.count)
        var outgoing = [[Int]](repeating: [], count: input.notes.count)
        for (i, note) in input.notes.enumerated() {
            var seen: Set<Int> = [i]
            for id in note.hand + note.written {
                guard let j = position[id], seen.insert(j).inserted else { continue }
                outgoing[i].append(j)
                incoming[j].append(i)
            }
        }
        self.incoming = incoming
        self.outgoing = outgoing
    }

    /// Whether note `i` is in folder `folder`'s cluster.
    func inCluster(_ i: Int, _ folder: UUID) -> Bool {
        guard let f = notes[i].folder else { return false }
        return f == folder || (ancestors[f]?.contains(folder) ?? false)
    }

    /// The positions of every note in a folder's cluster.
    func cluster(_ folder: UUID) -> [Int] {
        notes.indices.filter { inCluster($0, folder) }
    }
}

extension GraphAnatomy {
    // MARK: building a cell

    /// Folder `folder`'s cell, built to `levels` (2: parts and counts; 3:
    /// and the files; 4: and their bullets).
    static func cell(_ folder: UUID, in index: AnatomyIndex, levels: Int) -> AnatomyCell? {
        guard let info = index.folders.first(where: { $0.id == folder }) else { return nil }
        let depth: Int = min(max(levels, 2), 4)
        let members: [Int] = index.cluster(folder)
        let inside: Set<Int> = Set(members)
        let notes: [AnatomyNote] = index.notes

        // the core note: a page before an idea, then the most linked, the
        // longest, the oldest, the first by title
        func score(_ i: Int) -> (Int, Int, Int) {
            (notes[i].isPage ? 1 : 0, index.incoming[i].count + index.outgoing[i].count, notes[i].body.count)
        }
        let core: Int? = members.max { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa < sb }
            if notes[a].created != notes[b].created { return notes[a].created > notes[b].created }
            return notes[a].title > notes[b].title
        }

        var parts: [AnatomyPart] = []
        let wantFiles: Bool = depth >= 3
        let wantBullets: Bool = depth >= 4

        func file(_ kind: AnatomyFileKind, concept: UUID?, strength: Int, lines: [AnatomyBullet]) -> AnatomyFile {
            let kept: [AnatomyBullet] = wantBullets ? Array(lines.prefix(maxBullets)).map {
                AnatomyBullet(text: clip($0.text), note: $0.note)
            } : []
            return AnatomyFile(kind: kind, concept: concept, strength: strength, bulletCount: lines.count,
                               bullets: kept, more: lines.count - kept.count)
        }
        func part(_ slot: AnatomySlot, _ all: [AnatomyFile], measure: Double) -> AnatomyPart {
            let kept: [AnatomyFile] = wantFiles ? Array(all.prefix(maxFiles)) : []
            return AnatomyPart(slot: slot, fileCount: all.count, files: kept, more: all.count - kept.count,
                               measure: min(max(measure, 0), 1))
        }

        // core: soma / load
        var somaFiles: [AnatomyFile] = []
        if let core {
            let id: UUID = notes[core].id
            let parsed = coreFiles(notes[core])
            somaFiles = [
                file(.idea, concept: nil, strength: 1, lines: parsed.idea.map { AnatomyBullet(text: $0, note: id) }),
                file(.detail, concept: nil, strength: 1, lines: parsed.detail.map { AnatomyBullet(text: $0, note: id) }),
                file(.examples, concept: nil, strength: 1,
                     lines: parsed.examples.map { AnatomyBullet(text: $0, note: id) }),
            ]
        }
        parts.append(part(.core, somaFiles, measure: core == nil ? 0 : 1))

        // incoming and outgoing: one file per note outside, strongest first
        struct Edge { let outside: Int; let link: AnatomyLink; let line: AnatomyBullet }
        struct Pair: Hashable { let a: Int; let b: Int }
        var ins: [Int: [Edge]] = [:]
        var outs: [Int: [Edge]] = [:]
        var handFiles: [(Int, Int, AnatomyLink)] = []
        var handSeen: Set<Pair> = []
        func addHand(_ a: Int, _ b: Int, _ l: AnatomyLink) {
            if handSeen.insert(Pair(a: min(a, b), b: max(a, b))).inserted { handFiles.append((a, b, l)) }
        }
        /// The line of `a` that names `b`, or "A → B" for a link drawn by hand.
        func said(_ a: Int, _ b: Int, _ line: String?) -> String {
            line.map { plain(stripMarker($0.trimmingCharacters(in: .whitespaces))) }
                ?? (notes[a].title + " \u{2192} " + notes[b].title)
        }
        for i in members {
            for j in index.incoming[i] where !inside.contains(j) {
                guard let (l, line) = read(notes[j], notes[i]) else { continue }
                ins[j, default: []].append(Edge(outside: j, link: l,
                                                line: AnatomyBullet(text: said(j, i, line), note: notes[j].id)))
                // a hand link made from outside onto this cluster is one of its synapses too
                if l.hand { addHand(j, i, l) }
            }
            for j in index.outgoing[i] {
                let outside: Bool = !inside.contains(j)
                // inside the cluster only its hand links matter (synapses)
                guard outside || notes[i].hand.contains(notes[j].id) else { continue }
                guard let (l, line) = read(notes[i], notes[j]) else { continue }
                if l.hand { addHand(i, j, l) }
                guard outside else { continue }
                outs[j, default: []].append(Edge(outside: j, link: l,
                                                 line: AnatomyBullet(text: said(i, j, line), note: notes[i].id)))
            }
        }
        func ranked(_ groups: [Int: [Edge]]) -> [(Int, [Edge], Int)] {
            groups.map { ($0.key, $0.value, $0.value.map(\.link.strength).max() ?? 1) }
                .sorted { a, b in
                    if a.2 != b.2 { return a.2 > b.2 }
                    if notes[a.0].title != notes[b.0].title { return notes[a.0].title < notes[b.0].title }
                    return a.0 < b.0
                }
        }
        let inRanked = ranked(ins)
        let outRanked = ranked(outs)
        let inFiles: [AnatomyFile] = inRanked.map { (j, edges, s) in
            file(.from(notes[j].title), concept: notes[j].id, strength: s, lines: edges.map(\.line))
        }
        let outFiles: [AnatomyFile] = outRanked.map { (j, edges, s) in
            file(.to(notes[j].title), concept: notes[j].id, strength: s, lines: edges.map(\.line))
        }
        parts.append(part(.incoming, inFiles, measure: Double(inRanked.first?.2 ?? 0) / 10))
        parts.append(part(.outgoing, outFiles, measure: Double(outRanked.first?.2 ?? 0) / 10))

        // reference: nucleus / ground - where the notes came from
        var bySource: [String: Int] = [:]
        for i in members { if let s = notes[i].source { bySource[s, default: 0] += 1 } }
        var sourceLines: [AnatomyBullet] = bySource.sorted { a, b in
            a.value != b.value ? a.value > b.value : a.key < b.key
        }.map { AnatomyBullet(text: $0.key + " (\($0.value))", note: nil) }
        let written: Int = members.count - bySource.values.reduce(0, +)
        if written > 0 { sourceLines.append(AnatomyBullet(text: "Written here (\(written))", note: nil)) }
        let sourced: Double = members.isEmpty ? 0 : Double(members.count - written) / Double(members.count)
        parts.append(part(.reference, [file(.source, concept: nil, strength: 1, lines: sourceLines)], measure: sourced))

        // energy: mitochondria / source - why it matters
        var whys: [AnatomyBullet] = []
        var highYield: Int = 0
        for i in members.sorted(by: { notes[$0].title < notes[$1].title }) {
            let tagged: Bool = isHighYield(notes[i])
            if tagged { highYield += 1 }
            let lines: [String] = whyLines(notes[i])
            if lines.isEmpty && tagged {
                whys.append(AnatomyBullet(text: "High yield: " + notes[i].title, note: notes[i].id))
            }
            whys += lines.map { AnatomyBullet(text: $0, note: notes[i].id) }
        }
        let yieldShare: Double = members.isEmpty ? 0 : Double(highYield) / Double(members.count)
        parts.append(part(.energy, [file(.why, concept: nil, strength: 1, lines: whys)], measure: yieldShare))

        // confidence: myelin / resistors - verified first, unchecked last
        var verified: Double = 0
        let marks: [String] = ["? ", "\u{25D0} ", "\u{2713} "]
        let words: [String] = [" \u{2014} unchecked", " \u{2014} sourced", " \u{2014} verified"]
        let rated: [(Int, Int)] = members.map { ($0, confidence(notes[$0])) }.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : notes[a.0].title < notes[b.0].title
        }
        for (_, c) in rated { verified += c == 2 ? 1 : (c == 1 ? 0.5 : 0) }
        let confidenceLines: [AnatomyBullet] = rated.map { (i, c) in
            AnatomyBullet(text: marks[c] + notes[i].title + words[c], note: notes[i].id)
        }
        let share: Double = members.isEmpty ? 0 : verified / Double(members.count)
        parts.append(part(.confidence, [file(.confidence, concept: nil, strength: 1, lines: confidenceLines)],
                          measure: share))

        // links: synapse / switches - one file per hand-made link
        let handSorted = handFiles.sorted { a, b in
            if a.2.strength != b.2.strength { return a.2.strength > b.2.strength }
            let ta: String = notes[a.0].title + notes[a.1].title
            let tb: String = notes[b.0].title + notes[b.1].title
            return ta < tb
        }
        let linkFiles: [AnatomyFile] = handSorted.map { (a, b, l) in
            // named after the end outside the cluster, or the target
            let other: Int = inside.contains(b) && !inside.contains(a) ? a : b
            let arrow: String = l.twoWay ? " \u{2194} " : " \u{2192} "
            let kind: String = ["excitatory", "inhibitory", "modulatory"][l.kind.rawValue]
            return file(.link(notes[other].title), concept: notes[other].id, strength: l.strength, lines: [
                AnatomyBullet(text: notes[a].title + arrow + notes[b].title, note: notes[a].id),
                AnatomyBullet(text: "strength \(l.strength) \u{00B7} " + kind, note: nil),
            ])
        }
        parts.append(part(.links, linkFiles, measure: Double(handSorted.first?.2.strength ?? 0) / 10))

        return AnatomyCell(folder: folder, name: info.name, notes: members.count,
                           core: core.map { notes[$0].id }, parts: parts, levels: depth)
    }

    // MARK: fibres between clusters

    /// The fibres (wires) between top-level clusters: one a pair that links
    /// either way, strongest first.
    static func fibers(_ index: AnatomyIndex) -> [AnatomyFiber] {
        let notes: [AnatomyNote] = index.notes
        struct Pair: Hashable { let a: UUID; let b: UUID }
        var gathered: [Pair: [AnatomyLink]] = [:]
        for (i, note) in notes.enumerated() {
            guard let fa = note.folder, let ta = index.top[fa] else { continue }
            for j in index.outgoing[i] {
                guard let fb = notes[j].folder, let tb = index.top[fb], ta != tb,
                      let l = link(note, notes[j]) else { continue }
                gathered[Pair(a: ta, b: tb), default: []].append(l)
            }
        }
        var names: [UUID: String] = [:]
        for folder in index.folders { names[folder.id] = folder.name }
        var done: Set<Pair> = []
        var out: [AnatomyFiber] = []
        for key in gathered.keys.sorted(by: { ($0.a.uuidString, $0.b.uuidString) < ($1.a.uuidString, $1.b.uuidString) }) {
            let a: UUID = key.a < key.b ? key.a : key.b
            let b: UUID = key.a < key.b ? key.b : key.a
            let pair = Pair(a: a, b: b)
            guard done.insert(pair).inserted else { continue }
            let ab: [AnatomyLink] = gathered[Pair(a: a, b: b)] ?? []
            let ba: [AnatomyLink] = gathered[Pair(a: b, b: a)] ?? []
            let all: [AnatomyLink] = ab + ba
            guard !all.isEmpty else { continue }
            let forward: Bool = ab.count != ba.count ? ab.count > ba.count
                : (names[a] ?? "") <= (names[b] ?? "")
            let mean: Double = Double(all.map(\.strength).reduce(0, +)) / Double(all.count)
            let strength: Int = min(max(Int((mean + log2(Double(all.count))).rounded()), 1), 10)
            var weight: [Int] = [0, 0, 0]
            for l in all { weight[l.kind.rawValue] += l.strength }
            var kind: FiberKind = .excitatory
            if weight[1] > weight[0] && weight[1] >= weight[2] { kind = .inhibitory }
            else if weight[2] > weight[0] && weight[2] > weight[1] { kind = .modulatory }
            let hand: Int = all.filter(\.hand).count
            let byID: [UUID: String] = Dictionary(all.flatMap { [($0.from, ""), ($0.to, "")] },
                                                  uniquingKeysWith: { a, _ in a })
                .reduce(into: [:]) { acc, kv in acc[kv.key] = index.position[kv.key].map { notes[$0].title } ?? "" }
            let evidence: [String] = all.sorted { $0.strength > $1.strength }.prefix(3).map {
                (byID[$0.from] ?? "") + " \u{2192} " + (byID[$0.to] ?? "")
            }
            out.append(AnatomyFiber(from: forward ? a : b, to: forward ? b : a, strength: strength, kind: kind,
                                    twoWay: !ab.isEmpty && !ba.isEmpty, links: all.count,
                                    digital: hand * 2 > all.count, evidence: evidence))
        }
        return out.sorted { x, y in
            x.strength != y.strength ? x.strength > y.strength
                : (x.from.uuidString, x.to.uuidString) < (y.from.uuidString, y.to.uuidString)
        }
    }

    // MARK: the cell's shape

    /// Where each built piece of a cell goes, around the cell's centre: the
    /// seven parts on a shell round it (the core facing the camera, incoming
    /// behind, outgoing ahead...), each file further out towards its part,
    /// each bullet further out towards its file; each slides outward until
    /// clear of everything placed before it. Sizes from AnatomySizes.
    static func layout(_ cell: AnatomyCell, cellSphere: Double, page: Double, theme: AnatomyTheme,
                       spread: Double = 1) -> [AnatomyPlace] {
        let gap: Double = page * 0.4 * spread
        var placed: [AnatomyPlace] = []
        func clear(_ c: SIMD3<Double>, _ r: Double) -> Bool {
            if length(c) < cellSphere + r + gap { return false }
            for p in placed where length(p.centre - c) < p.sphere + r + gap { return false }
            return true
        }
        func put(level: Int, slot: AnatomySlot, file: Int, bullet: Int, dir: SIMD3<Double>, start: Double,
                 sphere: Double, parent: Int, label: String) {
            let d: SIMD3<Double> = normalize(dir)
            var r: Double = start
            var c: SIMD3<Double> = d * r
            var tries: Int = 0
            while !clear(c, sphere) && tries < 400 {
                r += sphere * 0.25
                c = d * r
                tries += 1
            }
            placed.append(AnatomyPlace(level: level, slot: slot, file: file, bullet: bullet, centre: c,
                                       sphere: sphere, parent: parent, label: label))
        }
        let s2: Double = AnatomySizes.sphere(level: 2, cell: cellSphere, page: page)
        let s3: Double = AnatomySizes.sphere(level: 3, cell: cellSphere, page: page)
        let s4: Double = AnatomySizes.sphere(level: 4, cell: cellSphere, page: page)
        for part in cell.parts {
            put(level: 2, slot: part.slot, file: -1, bullet: -1, dir: slotDirection(part.slot),
                start: cellSphere + s2 + gap, sphere: s2, parent: -1, label: part.label(theme))
        }
        guard cell.levels >= 3 else { return placed }
        for (p, part) in cell.parts.enumerated() {
            let home: SIMD3<Double> = placed[p].centre
            let axis: SIMD3<Double> = normalize(home)
            for (f, file) in part.files.enumerated() {
                let dir: SIMD3<Double> = fan(axis, k: f, n: part.files.count, spread: 0.45)
                put(level: 3, slot: part.slot, file: f, bullet: -1, dir: dir,
                    start: length(home) + s2 + s3 + gap, sphere: s3, parent: p, label: file.kind.name(theme))
                guard cell.levels >= 4 else { continue }
                let f3: Int = placed.count - 1
                let fileAxis: SIMD3<Double> = normalize(placed[f3].centre)
                for (b, bullet) in file.bullets.enumerated() {
                    let bd: SIMD3<Double> = fan(fileAxis, k: b, n: file.bullets.count, spread: 0.25)
                    put(level: 4, slot: part.slot, file: f, bullet: b, dir: bd,
                        start: length(placed[f3].centre) + s3 + s4 + gap, sphere: s4, parent: f3, label: bullet.text)
                }
            }
        }
        return placed
    }

    /// Where each part sits round the cell: the core towards the camera
    /// (+z), the incoming dendrites behind and up the left, the outgoing
    /// axon down the right, the reference (nucleus) on top, the energy
    /// (mitochondria) low left, the confidence (myelin) along the axon's
    /// side, the synapses out to the right.
    static func slotDirection(_ slot: AnatomySlot) -> SIMD3<Double> {
        switch slot {
        case .core: return SIMD3<Double>(0, -0.15, 1)
        case .incoming: return SIMD3<Double>(-1, 0.55, -0.35)
        case .outgoing: return SIMD3<Double>(1, -0.6, -0.2)
        case .reference: return SIMD3<Double>(0, 1, 0.1)
        case .energy: return SIMD3<Double>(-0.8, -0.8, 0.35)
        case .confidence: return SIMD3<Double>(0.25, -1, 0.45)
        case .links: return SIMD3<Double>(1, 0.45, 0.3)
        }
    }

    /// `n` directions fanned round `axis`, `spread` radians off it.
    static func fan(_ axis: SIMD3<Double>, k: Int, n: Int, spread: Double) -> SIMD3<Double> {
        guard n > 1 else { return axis }
        let helper: SIMD3<Double> = abs(axis.y) < 0.9 ? SIMD3<Double>(0, 1, 0) : SIMD3<Double>(1, 0, 0)
        let u: SIMD3<Double> = normalize(cross(axis, helper))
        let v: SIMD3<Double> = cross(axis, u)
        let a: Double = 2 * Double.pi * Double(k) / Double(n)
        return normalize(axis * cos(spread) + (u * cos(a) + v * sin(a)) * sin(spread))
    }

    static func length(_ v: SIMD3<Double>) -> Double {
        (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    }

    static func normalize(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let l: Double = length(v)
        return l > 1e-12 ? v / l : SIMD3<Double>(0, 0, 1)
    }

    static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
