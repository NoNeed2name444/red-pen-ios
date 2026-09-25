import Foundation

/// Turning an Anki note's fields into this app's cards.
///
/// Everything here is text in and text out - the HTML of a field made plain,
/// the fields a card template shows, an image-occlusion shape made a box, a
/// deck tree made a handful of sets - so the whole of the mapping is tested
/// on the runner. Reading the package itself (zip, zstd, SQLite) is
/// ApkgImport.
///
/// Foundation only, so it is tested.
enum AnkiNoteText {

    // MARK: - HTML to plain text

    /// A field as text the app shows: tags gone, `<b>` as `**bold**`, line
    /// breaks kept, entities decoded, `[sound:...]` dropped. The pictures it
    /// showed are handed back by file name, in order.
    ///
    /// Worked on the UTF-8 bytes - every character HTML gives meaning to is
    /// ASCII - because it runs on every field of every note, and a deck of
    /// thirty-five thousand notes is a quarter of a million fields.
    static func plain(_ html: String) -> (text: String, images: [String]) {
        let bytes = Array(html.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var images: [String] = []
        var i = 0
        let count = bytes.count
        while i < count {
            let c = bytes[i]
            if c == 0x3C {
                // <
                guard let close = find(0x3E, in: bytes, from: i + 1, limit: 4_000) else {
                    out.append(c)
                    i += 1
                    continue
                }
                let tag = TagBytes(bytes, from: i + 1, to: close)
                i = close + 1
                switch tag.name {
                case "br":
                    out.append(0x0A)
                case "div", "p", "li", "tr", "ul", "ol", "table", "blockquote",
                     "h1", "h2", "h3", "h4", "h5", "h6", "hr", "section", "article":
                    if let last = out.last, last != 0x0A { out.append(0x0A) }
                case "td", "th":
                    if tag.closing { out.append(0x20) }
                case "b", "strong":
                    out.append(0x2A)
                    out.append(0x2A)
                case "img":
                    let inside = String(decoding: bytes[tag.bodyStart..<close], as: UTF8.self)
                    if let src = Tag("img" + inside).attribute("src") {
                        let name = decodeEntities(src).trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { images.append(name) }
                    }
                case "script", "style":
                    if !tag.closing { i = skip(pastClosing: tag.name, in: bytes, from: i) }
                default:
                    break
                }
            } else if c == 0x26 {
                // &
                if let semi = find(0x3B, in: bytes, from: i + 1, limit: 12) {
                    let name = String(decoding: bytes[(i + 1)..<semi], as: UTF8.self)
                    if let decoded = entity(name) {
                        out.append(contentsOf: Array(decoded.utf8))
                        i = semi + 1
                        continue
                    }
                }
                out.append(c)
                i += 1
            } else if c == 0x5B, startsWith(soundTag, bytes, at: i),
                      let close = find(0x5D, in: bytes, from: i + 1, limit: 400) {
                // [sound:...]
                i = close + 1
            } else {
                out.append(c)
                i += 1
            }
        }
        return (tidy(bytes: out), images)
    }

    private static let soundTag: [UInt8] = Array("[sound:".utf8)

    /// Runs of spaces made one, every line trimmed, blank lines gone, and
    /// the empty bold pairs markup leaves behind taken out.
    static func tidy(_ text: String) -> String {
        tidy(bytes: Array(text.utf8))
    }

    static func tidy(bytes: [UInt8]) -> String {
        var lines: [[UInt8]] = []
        var line: [UInt8] = []
        var space = false
        func close() {
            var done = line
            // "<b></b>" and "</b><b>" both leave four stars
            while let at = fourStars(done) { done.removeSubrange(at..<(at + 4)) }
            while done.last == 0x20 { done.removeLast() }
            while done.first == 0x20 { done.removeFirst() }
            if !done.isEmpty && done != [0x2A, 0x2A] { lines.append(done) }
            line.removeAll(keepingCapacity: true)
            space = false
        }
        var i = 0
        let count = bytes.count
        while i < count {
            let c = bytes[i]
            if c == 0x0A || c == 0x0D {
                close()
                i += 1
                continue
            }
            // a space, a tab, a no-break space (C2 A0), an em or en space or
            // a zero-width space (E2 80 83 / 82 / 8B)
            var blank = 0
            if c == 0x20 || c == 0x09 {
                blank = 1
            } else if c == 0xC2, i + 1 < count, bytes[i + 1] == 0xA0 {
                blank = 2
            } else if c == 0xE2, i + 2 < count, bytes[i + 1] == 0x80,
                      bytes[i + 2] == 0x83 || bytes[i + 2] == 0x82 || bytes[i + 2] == 0x8B {
                blank = 3
            }
            if blank > 0 {
                space = !line.isEmpty
                i += blank
                continue
            }
            if space { line.append(0x20); space = false }
            line.append(c)
            i += 1
        }
        close()
        var joined: [UInt8] = []
        for (index, done) in lines.enumerated() {
            if index > 0 { joined.append(0x0A) }
            joined.append(contentsOf: done)
        }
        return String(decoding: joined, as: UTF8.self)
    }

    private static func fourStars(_ line: [UInt8]) -> Int? {
        guard line.count >= 4 else { return nil }
        var i = 0
        while i + 3 < line.count {
            if line[i] == 0x2A && line[i + 1] == 0x2A && line[i + 2] == 0x2A && line[i + 3] == 0x2A { return i }
            i += 1
        }
        return nil
    }

    /// A tag's name, read from its bytes.
    struct TagBytes {
        var name: String
        var closing: Bool
        var bodyStart: Int

        init(_ bytes: [UInt8], from start: Int, to end: Int) {
            var i = start
            while i < end, bytes[i] == 0x20 { i += 1 }
            closing = i < end && bytes[i] == 0x2F
            if closing { i += 1 }
            var letters: [UInt8] = []
            while i < end, letters.count < 12 {
                let b = bytes[i]
                let isLetter = (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39)
                if !isLetter { break }
                letters.append(b | ((b >= 0x41 && b <= 0x5A) ? 0x20 : 0))
                i += 1
            }
            name = String(decoding: letters, as: UTF8.self)
            bodyStart = i
        }
    }

    /// An entity's character, or nil when it is not one this knows.
    static func entity(_ name: String) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            guard let value = UInt32(name.dropFirst(2), radix: 16), let s = Unicode.Scalar(value) else { return nil }
            return String(Character(s))
        }
        if name.hasPrefix("#") {
            guard let value = UInt32(name.dropFirst()), let s = Unicode.Scalar(value) else { return nil }
            return String(Character(s))
        }
        return named[name]
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "bull": "\u{2022}",
        "middot": "\u{00b7}", "rarr": "\u{2192}", "larr": "\u{2190}", "uarr": "\u{2191}",
        "darr": "\u{2193}", "harr": "\u{2194}", "rArr": "\u{21d2}", "deg": "\u{00b0}",
        "plusmn": "\u{00b1}", "times": "\u{00d7}", "divide": "\u{00f7}", "micro": "\u{00b5}",
        "le": "\u{2264}", "ge": "\u{2265}", "ne": "\u{2260}", "asymp": "\u{2248}",
        "alpha": "\u{03b1}", "beta": "\u{03b2}", "gamma": "\u{03b3}", "delta": "\u{03b4}",
        "Delta": "\u{0394}", "mu": "\u{03bc}", "kappa": "\u{03ba}", "lambda": "\u{03bb}",
        "sigma": "\u{03c3}", "tau": "\u{03c4}", "omega": "\u{03c9}", "pi": "\u{03c0}",
        "theta": "\u{03b8}", "epsilon": "\u{03b5}", "eta": "\u{03b7}", "zeta": "\u{03b6}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201c}", "rdquo": "\u{201d}",
        "shy": "", "zwj": "", "zwnj": "", "trade": "\u{2122}", "copy": "\u{00a9}",
        "reg": "\u{00ae}", "sup2": "\u{00b2}", "sup3": "\u{00b3}", "frac12": "\u{00bd}",
        "frac14": "\u{00bc}", "frac34": "\u{00be}", "uparrow": "\u{2191}", "downarrow": "\u{2193}",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return plain(text).text
    }

    /// One tag's name and attributes.
    struct Tag {
        var name: String
        var closing: Bool
        var body: String

        init(_ inside: String) {
            var text = inside.trimmingCharacters(in: .whitespaces)
            closing = text.hasPrefix("/")
            if closing { text.removeFirst() }
            let letters = text.prefix { $0.isLetter || $0.isNumber }
            name = letters.lowercased()
            body = String(text.dropFirst(letters.count))
        }

        /// An attribute's value, quoted or not.
        func attribute(_ wanted: String) -> String? {
            let lower = body.lowercased()
            var search = lower.startIndex
            while let hit = lower.range(of: wanted, range: search..<lower.endIndex) {
                search = hit.upperBound
                // a whole attribute name, not the end of another
                if hit.lowerBound > lower.startIndex {
                    let before = lower[lower.index(before: hit.lowerBound)]
                    if before.isLetter || before == "-" { continue }
                }
                var at = hit.upperBound
                while at < lower.endIndex, lower[at] == " " { at = lower.index(after: at) }
                guard at < lower.endIndex, lower[at] == "=" else { continue }
                at = lower.index(after: at)
                while at < lower.endIndex, lower[at] == " " { at = lower.index(after: at) }
                guard at < lower.endIndex else { return nil }
                // read from the original, whose case the value keeps
                let offset = lower.distance(from: lower.startIndex, to: at)
                let original = body.dropFirst(offset)
                guard let first = original.first else { return nil }
                if first == "\"" || first == "'" {
                    let rest = original.dropFirst()
                    guard let end = rest.firstIndex(of: first) else { return String(rest) }
                    return String(rest[..<end])
                }
                let value = original.prefix { $0 != " " && $0 != ">" && $0 != "/" }
                return String(value)
            }
            return nil
        }
    }

    private static func find(_ wanted: UInt8, in bytes: [UInt8], from start: Int, limit: Int) -> Int? {
        var i = start
        let stop = min(bytes.count, start + limit)
        while i < stop {
            if bytes[i] == wanted { return i }
            i += 1
        }
        return nil
    }

    private static func startsWith(_ prefix: [UInt8], _ bytes: [UInt8], at start: Int) -> Bool {
        guard start + prefix.count <= bytes.count else { return false }
        for (k, p) in prefix.enumerated() where bytes[start + k] != p { return false }
        return true
    }

    /// Past `</name ...>`, whatever its case; the end when there is none.
    private static func skip(pastClosing name: String, in bytes: [UInt8], from start: Int) -> Int {
        let wanted: [UInt8] = Array("</\(name)".utf8)
        var i = start
        while i + wanted.count <= bytes.count {
            var match = true
            for (k, w) in wanted.enumerated() {
                let b = bytes[i + k]
                let lower: UInt8 = (b >= 0x41 && b <= 0x5A) ? b | 0x20 : b
                if lower != w { match = false; break }
            }
            if match { return (find(0x3E, in: bytes, from: i, limit: 64) ?? i) + 1 }
            i += 1
        }
        return bytes.count
    }

    // MARK: - templates

    /// The fields a card template shows, in order, as `{{Name}}`,
    /// `{{text:Name}}`, `{{cloze:Name}}` and the like - without `FrontSide`,
    /// conditionals or special fields. On the `front`, a `{{type:Name}}`
    /// answer box is left out: it asks for that field, it does not show it.
    static func fieldsShown(in template: String, front: Bool = false) -> [String] {
        var found: [String] = []
        var rest = template[...]
        while let open = rest.range(of: "{{") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { break }
            var name = after[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            rest = after[close.upperBound...]
            if name.hasPrefix("#") || name.hasPrefix("^") || name.hasPrefix("/") || name.hasPrefix("!") { continue }
            if front && name.hasPrefix("type:") { continue }
            if let colon = name.lastIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
            let special: Set<String> = ["FrontSide", "Tags", "Deck", "Subdeck", "Card", "CardFlag", "Type"]
            if name.isEmpty || special.contains(name) || found.contains(name) { continue }
            found.append(name)
        }
        return found
    }

    /// The field a cloze template hides words in: `{{cloze:Text}}`.
    static func clozeField(in template: String) -> String? {
        guard let hit = template.range(of: "{{cloze:") else { return nil }
        let after = template[hit.upperBound...]
        guard let close = after.range(of: "}}") else { return nil }
        let name = after[..<close.lowerBound].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    // MARK: - tags and decks

    /// A note's tags: Anki keeps them space-separated with a space either side.
    static func tags(_ field: String, limit: Int = 20) -> [String] {
        let parts = field.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
        var kept: [String] = []
        for part in parts {
            let tag = String(part.prefix(120))
            if !tag.isEmpty && !kept.contains(tag) { kept.append(tag) }
            if kept.count == limit { break }
        }
        return kept
    }

    /// A deck's place in the tree, from either way Anki writes one:
    /// "A::B" in a JSON collection, "A\u{1f}B" in a newer one.
    static func deckPath(_ name: String) -> [String] {
        let separator: String = name.contains("\u{1f}") ? "\u{1f}" : "::"
        return name.components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - cards

    /// A plain field made into answer bullets: one per line, and after the
    /// first `maxBullets` the rest kept as "why" rather than lost.
    static func bullets(_ text: String, maxBullets: Int = 6) -> (bullets: [String], rest: String) {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        let kept = Array(lines.prefix(maxBullets))
        let rest = lines.dropFirst(maxBullets).joined(separator: "\n")
        return (kept, rest)
    }

    /// Longer than this, a "why" is cut at a sentence or word and marked.
    static func clipped(_ text: String, limit: Int = 900) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let cut = head.range(of: " ", options: .backwards) {
            return String(head[..<cut.lowerBound]) + "\u{2026}"
        }
        return head + "\u{2026}"
    }

    // MARK: - image occlusion

    /// One cloze number's covers, from Anki's own image occlusion (23.10+):
    /// `{{c1::image-occlusion:rect:left=.1:top=.2:width=.3:height=.1:oi=1}}`.
    /// Several shapes under one number are one card; its box is their union.
    /// Values are fractions of the picture, or pixels in the earliest
    /// versions - `pixelSize` turns those into fractions when it is known.
    static func occlusions(_ field: String, pixelSize: (w: Double, h: Double)? = nil) -> [Int: [OcclusionBox]] {
        var found: [Int: [OcclusionBox]] = [:]
        var rest = field[...]
        while let open = rest.range(of: "{{c") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else { break }
            let body = after[..<close.lowerBound]
            rest = after[close.upperBound...]
            guard let sep = body.range(of: "::") else { continue }
            guard let number = Int(body[..<sep.lowerBound]) else { continue }
            let shape = String(body[sep.upperBound...])
            guard let box = occlusionBox(shape, pixelSize: pixelSize) else { continue }
            found[number, default: []].append(box)
        }
        return found
    }

    /// One `image-occlusion:` shape as a box.
    static func occlusionBox(_ shape: String, pixelSize: (w: Double, h: Double)?) -> OcclusionBox? {
        guard shape.hasPrefix("image-occlusion:") else { return nil }
        let parts = shape.dropFirst("image-occlusion:".count).components(separatedBy: ":")
        guard let kind = parts.first else { return nil }
        var values: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "=") else { continue }
            values[String(part[..<eq])] = String(part[part.index(after: eq)...])
        }
        func number(_ key: String) -> Double? { values[key].flatMap { Double($0) } }
        var box: OcclusionBox?
        switch kind {
        case "rect":
            if let l = number("left"), let t = number("top"), let w = number("width"), let h = number("height") {
                box = OcclusionBox(x: l, y: t, w: w, h: h)
            }
        case "ellipse":
            if let l = number("left"), let t = number("top"), let rx = number("rx"), let ry = number("ry") {
                box = OcclusionBox(x: l, y: t, w: rx * 2, h: ry * 2)
            }
        case "polygon":
            let points = (values["points"] ?? "").split(separator: " ").compactMap { pair -> (Double, Double)? in
                let xy = pair.split(separator: ",")
                guard xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) else { return nil }
                return (x, y)
            }
            if let minX = points.map({ $0.0 }).min(), let maxX = points.map({ $0.0 }).max(),
               let minY = points.map({ $0.1 }).min(), let maxY = points.map({ $0.1 }).max() {
                box = OcclusionBox(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
            }
        default:
            return nil
        }
        guard var made = box else { return nil }
        // pixels, from before the values were fractions
        if made.x + made.w > 1.001 || made.y + made.h > 1.001 {
            guard let size = pixelSize, size.w > 0, size.h > 0 else { return nil }
            made = OcclusionBox(x: made.x / size.w, y: made.y / size.h, w: made.w / size.w, h: made.h / size.h)
        }
        return clamped(made)
    }

    /// Covers from the Image Occlusion Enhanced add-on: its mask is an SVG
    /// the size of the picture, the card's own shape marked `qshape`.
    static func svgMask(_ svg: String) -> (target: OcclusionBox, others: [OcclusionBox])? {
        guard let open = svg.range(of: "<svg") else { return nil }
        let head = svg[open.upperBound...].prefix { $0 != ">" }
        let root = Tag("svg" + head)
        var width = root.attribute("width").flatMap(length)
        var height = root.attribute("height").flatMap(length)
        if width == nil || height == nil, let box = root.attribute("viewbox") ?? root.attribute("viewBox") {
            let parts = box.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if parts.count == 4 { width = parts[2]; height = parts[3] }
        }
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        var target: OcclusionBox?
        var others: [OcclusionBox] = []
        var rest = svg[...]
        while let hit = rest.range(of: "<rect") {
            let after = rest[hit.upperBound...]
            let inside = after.prefix { $0 != ">" }
            rest = after.dropFirst(inside.count)
            let tag = Tag("rect" + inside)
            guard let x = tag.attribute("x").flatMap(length), let y = tag.attribute("y").flatMap(length),
                  let rw = tag.attribute("width").flatMap(length), let rh = tag.attribute("height").flatMap(length)
            else { continue }
            let box = clamped(OcclusionBox(x: x / w, y: y / h, w: rw / w, h: rh / h))
            let classes = (tag.attribute("class") ?? "").lowercased()
            if classes.contains("qshape") { target = target ?? box } else { others.append(box) }
        }
        guard let target else { return nil }
        return (target, others)
    }

    private static func length(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: ""))
    }

    /// Several shapes as the one box that holds them all.
    static func union(_ boxes: [OcclusionBox]) -> OcclusionBox? {
        guard let first = boxes.first else { return nil }
        var minX = first.x, minY = first.y
        var maxX = first.x + first.w, maxY = first.y + first.h
        for b in boxes.dropFirst() {
            minX = min(minX, b.x)
            minY = min(minY, b.y)
            maxX = max(maxX, b.x + b.w)
            maxY = max(maxY, b.y + b.h)
        }
        return OcclusionBox(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    static func clamped(_ box: OcclusionBox) -> OcclusionBox {
        let x = min(max(box.x, 0), 1)
        let y = min(max(box.y, 0), 1)
        let w = min(max(box.w, 0), 1 - x)
        let h = min(max(box.h, 0), 1 - y)
        return OcclusionBox(x: x, y: y, w: w, h: h)
    }

    /// A picture's pixel size from its first bytes - PNG, JPEG or GIF -
    /// for old occlusion shapes written in pixels.
    static func pixelSize(of data: Data) -> (w: Double, h: Double)? {
        let b = [UInt8](data.prefix(64 * 1024))
        guard b.count > 24 else { return nil }
        if b[0] == 0x89, b[1] == 0x50 {
            let w = Int(b[16]) << 24 | Int(b[17]) << 16 | Int(b[18]) << 8 | Int(b[19])
            let h = Int(b[20]) << 24 | Int(b[21]) << 16 | Int(b[22]) << 8 | Int(b[23])
            return (Double(w), Double(h))
        }
        if b[0] == 0x47, b[1] == 0x49 {
            let w = Int(b[6]) | Int(b[7]) << 8
            let h = Int(b[8]) | Int(b[9]) << 8
            return (Double(w), Double(h))
        }
        if b[0] == 0xFF, b[1] == 0xD8 {
            var i = 2
            while i + 9 < b.count {
                guard b[i] == 0xFF else { i += 1; continue }
                let marker = b[i + 1]
                let size = Int(b[i + 2]) << 8 | Int(b[i + 3])
                if (0xC0...0xCF).contains(marker) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC {
                    let h = Int(b[i + 5]) << 8 | Int(b[i + 6])
                    let w = Int(b[i + 7]) << 8 | Int(b[i + 8])
                    return (Double(w), Double(h))
                }
                i += 2 + size
            }
        }
        return nil
    }

    // MARK: - decks into sets

    /// One deck of cards on its way to becoming a set.
    struct Deck {
        var path: [String]
        var cards: [AnkiCard]
        /// Media file names; a card's `imageIndex` points in here.
        var pictures: [String]
        /// Schedules brought over from Anki, by the card's new id.
        var progress: [UUID: AnkiProgress]

        init(path: [String], cards: [AnkiCard] = [], pictures: [String] = [], progress: [UUID: AnkiProgress] = [:]) {
            self.path = path
            self.cards = cards
            self.pictures = pictures
            self.progress = progress
        }
    }

    /// A set to be made: its name, the folder it goes in (by name), and what
    /// is in it.
    struct PlannedSet {
        var name: String
        var folder: String?
        var deck: Deck
    }

    /// Decks as sets. A deep tree is cut at the level that keeps the set
    /// count at `maxSets` or under, deeper decks joining the deck above them;
    /// a set over `maxCards` is split into parts so no one screen has to hold
    /// thirty thousand cards. With more than one set, each top-level deck
    /// becomes a folder.
    static func plan(_ decks: [Deck], maxSets: Int = 60, maxCards: Int = 3_000) -> [PlannedSet] {
        let filled = decks.filter { !$0.cards.isEmpty }
        guard !filled.isEmpty else { return [] }
        let deepest = filled.map { $0.path.count }.max() ?? 1
        var depth = max(deepest, 1)
        while depth > 1 {
            let keys = Set(filled.map { Array($0.path.prefix(depth)) })
            if keys.count <= maxSets { break }
            depth -= 1
        }
        // merged in first-seen order, so the sets keep the package's order
        var order: [[String]] = []
        var merged: [[String]: Deck] = [:]
        for deck in filled {
            let key = Array(deck.path.prefix(depth))
            if var existing = merged[key] {
                append(deck, to: &existing)
                merged[key] = existing
            } else {
                order.append(key)
                merged[key] = Deck(path: key, cards: deck.cards, pictures: deck.pictures, progress: deck.progress)
            }
        }
        let many: Bool = order.count > 1
        var sets: [PlannedSet] = []
        for key in order {
            guard let deck = merged[key] else { continue }
            let top = key.first ?? "Anki"
            let below = key.dropFirst()
            let name: String = below.isEmpty ? top : below.joined(separator: " \u{203a} ")
            let folder: String? = many ? top : nil
            let parts = split(deck, maxCards: maxCards)
            for (index, part) in parts.enumerated() {
                let suffix: String = parts.count > 1 ? " (\(index + 1) of \(parts.count))" : ""
                sets.append(PlannedSet(name: name + suffix, folder: folder, deck: part))
            }
        }
        return sets
    }

    /// A planned set made a StudySet. `picture` gives each picture's stored
    /// form (base64) by its Anki name, or nil when it could not be read: an
    /// occlusion card whose picture is missing is left out, any other card
    /// just loses its picture. The deck's place in Anki becomes the set's
    /// tag, so a search for `tag:AnKing` still finds it.
    static func studySet(_ planned: PlannedSet, subject: String, folderId: UUID?, now: Date = Date(),
                         picture: (String) -> String?) -> StudySet {
        var set = StudySet(name: planned.name, subject: subject, kind: .anki)
        set.folderId = folderId
        set.createdAt = now
        set.updatedAt = now
        var moved: [Int: Int] = [:]
        for (index, name) in planned.deck.pictures.enumerated() {
            guard let stored = picture(name) else { continue }
            moved[index] = set.images.count
            set.images.append(stored)
        }
        set.cards = planned.deck.cards.compactMap { card -> AnkiCard? in
            var copy = card
            if let old = card.imageIndex { copy.imageIndex = moved[old] }
            if card.type == .occlusion && copy.imageIndex == nil { return nil }
            return copy
        }
        let path = planned.deck.path.joined(separator: "::")
        if let tag = CardTags.normalized(path) { set.tags = [tag] }
        return set
    }

    /// One deck's cards, pictures renumbered, added to another's.
    static func append(_ deck: Deck, to target: inout Deck) {
        var moved: [Int: Int] = [:]
        for (index, name) in deck.pictures.enumerated() {
            if let at = target.pictures.firstIndex(of: name) {
                moved[index] = at
            } else {
                moved[index] = target.pictures.count
                target.pictures.append(name)
            }
        }
        for card in deck.cards {
            var copy = card
            if let old = card.imageIndex { copy.imageIndex = moved[old] }
            target.cards.append(copy)
        }
        target.progress.merge(deck.progress) { first, _ in first }
    }

    /// A deck in parts of at most `maxCards`, each with only its own pictures.
    /// Cards on one picture stay in one part where they can, since an
    /// occlusion card's neighbours are its covers.
    static func split(_ deck: Deck, maxCards: Int) -> [Deck] {
        guard maxCards > 0, deck.cards.count > maxCards else { return [deck] }
        var parts: [Deck] = []
        var current = Deck(path: deck.path)
        var map: [Int: Int] = [:]
        var index = 0
        while index < deck.cards.count {
            // a run of cards on the same picture moves as one
            var end = index + 1
            if let picture = deck.cards[index].imageIndex {
                while end < deck.cards.count, deck.cards[end].imageIndex == picture { end += 1 }
            }
            let run = deck.cards[index..<end]
            if !current.cards.isEmpty && current.cards.count + run.count > maxCards {
                parts.append(current)
                current = Deck(path: deck.path)
                map = [:]
            }
            for card in run {
                var copy = card
                if let old = card.imageIndex {
                    if let now = map[old] {
                        copy.imageIndex = now
                    } else if deck.pictures.indices.contains(old) {
                        map[old] = current.pictures.count
                        copy.imageIndex = current.pictures.count
                        current.pictures.append(deck.pictures[old])
                    } else {
                        copy.imageIndex = nil
                    }
                }
                current.cards.append(copy)
                if let progress = deck.progress[card.id] { current.progress[card.id] = progress }
            }
            index = end
        }
        if !current.cards.isEmpty { parts.append(current) }
        return parts
    }
}

/// Where one card stood in Anki: brought over so a student switching apps
/// does not start thirty thousand cards from zero. Plain values - turned into
/// the app's own schedule record where it is saved (ReviewPlan is not needed
/// to read a package).
struct AnkiProgress: Equatable {
    var due: Date
    /// Days between reviews; under a day for a card still being learned.
    var intervalDays: Double
    var reviews: Int
    var lapses: Int
    var suspended: Bool

    /// From a row of Anki's `cards` table.
    ///
    /// `type` 0 is new (no progress), 1 learning, 2 review, 3 relearning.
    /// A review card's `due` is a day number counted from the collection's
    /// creation; a learning card's is a moment in epoch seconds.
    static func from(type: Int, queue: Int, due: Int, interval: Int, reps: Int, lapses: Int,
                     created: Date, now: Date = Date()) -> AnkiProgress? {
        guard type != 0, reps > 0 || type == 2 else { return nil }
        var when: Date
        if due > 1_000_000_000 {
            when = Date(timeIntervalSince1970: TimeInterval(due))
        } else {
            // the collection's creation is already the start of Anki's day
            when = created.addingTimeInterval(TimeInterval(due) * 86_400)
        }
        // a due date years out is a corrupt row, not a plan
        if when.timeIntervalSince(now) > 3_650 * 86_400 { when = now }
        let days: Double = interval >= 0 ? Double(interval) : Double(-interval) / 86_400
        return AnkiProgress(due: when, intervalDays: max(days, 0), reviews: max(reps, 0),
                            lapses: max(lapses, 0), suspended: queue == -1)
    }
}
