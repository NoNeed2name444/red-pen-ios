import CryptoKit
import Foundation
import SQLite3
import UIKit

/// Ports the web app's `exportCardsToApkg()` / `assembleApkgZip()`: writes a
/// real Anki package — a SQLite `collection.anki2` plus a `media` manifest,
/// zipped — that the Anki desktop and mobile apps import directly. Same two
/// note types as the web app ("Red Pen Basic", "Red Pen Cloze"), same card
/// CSS. Image-occlusion cards are rendered to front (masked) / back
/// (unmasked) JPEGs and shipped as media, exactly as the web version does.
///
/// This stays the real exporter: it runs on the phone, offline, in a moment,
/// with nothing to upload and nobody's account involved. genanki — the Python
/// library that is the community's reference for this file format — was
/// measured against it rather than replacing it, and it turned out to get four
/// things right that this did not. All four are about IDENTITY, which is the
/// part of the format that decides what happens on the SECOND export.
///
///   * the note types now have FIXED ids. They were minted from the clock, so
///     every export introduced a brand new "Red Pen Basic" note type: import
///     twice and Anki shows two, import ten times and your card browser is
///     unusable. A note type id is a name, not a timestamp;
///   * the deck id is derived from the deck's NAME, so re-exporting the same
///     subject lands in the same deck instead of creating a sibling;
///   * a note's GUID comes from the card's own `id`. It used to be hashed from
///     the card's CONTENT, which meant the comment promising that re-export
///     "updates notes instead of duplicating them" was true only while you
///     never edited anything — fix a typo and Anki imported a second copy of
///     the card, and the copy you had been reviewing kept its schedule while
///     the corrected one started from zero. Keying on the id is what makes an
///     edit an edit;
///   * the field checksum is the real one: the first eight hex digits of the
///     SHA-1 of the stripped sort field. It was a different hash, which Anki
///     accepts silently and then cannot use to find duplicates.
///
/// One consequence worth knowing: because the GUIDs change, the FIRST import
/// after this lands brings your existing Red Pen notes in as new notes. That
/// happens once. Afterwards, editing a card and exporting updates it in place.
enum ApkgExporter {
    struct ExportError: Error {}

    /// Fixed for the life of the app. Changing either of these orphans every
    /// note anybody has already imported, so they are constants, not values.
    private static let midBasic = 1_607_392_319
    private static let midCloze = 1_607_392_320

    static func export(_ set: StudySet) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("collection.anki2")

        var media: [(name: String, data: Data)] = []
        try buildCollection(at: dbURL, set: set, media: &media)

        // media manifest: {"0": "file.jpg", ...}; zipped entries are named by index
        var manifest: [String: String] = [:]
        var entries: [(name: String, data: Data)] = []
        entries.append(("collection.anki2", try Data(contentsOf: dbURL)))
        for (i, m) in media.enumerated() {
            manifest[String(i)] = m.name
            entries.append((String(i), m.data))
        }
        entries.append(("media", try JSONSerialization.data(withJSONObject: manifest)))

        let out = FileManager.default.temporaryDirectory.appendingPathComponent(safeFileName(set.name)).appendingPathExtension("apkg")
        try MiniZip.write(entries: entries, to: out)
        try? FileManager.default.removeItem(at: dir)
        return out
    }

    // MARK: collection.anki2 — the Anki 2 schema genanki writes

    private static let cardCSS = """
    .card { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 20px; text-align: left; color: #1e1c19; background: #fbfaf7; padding: 12px 18px; }
    .bullets { padding-left: 1.2em; margin: .5em 0; } .bullets li { margin: .3em 0; }
    .why { margin-top: 1em; padding: .7em 1em; background: #f4ece6; border-left: 3px solid #c02828; border-radius: 6px; font-size: .9em; }
    .why b { display: block; margin-bottom: .25em; color: #c02828; font-size: .8em; letter-spacing: .04em; text-transform: uppercase; }
    .cloze { font-weight: bold; color: #c02828; }
    img { max-width: 100%; border-radius: 8px; }
    """

    private static func buildCollection(at url: URL, set: StudySet, media: inout [(name: String, data: Data)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw ExportError() }
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE col (id integer primary key, crt integer not null, mod integer not null, scm integer not null, ver integer not null, dty integer not null, usn integer not null, ls integer not null, conf text not null, models text not null, decks text not null, dconf text not null, tags text not null);
        CREATE TABLE notes (id integer primary key, guid text not null, mid integer not null, mod integer not null, usn integer not null, tags text not null, flds text not null, sfld integer not null, csum integer not null, flags integer not null, data text not null);
        CREATE TABLE cards (id integer primary key, nid integer not null, did integer not null, ord integer not null, mod integer not null, usn integer not null, type integer not null, queue integer not null, due integer not null, ivl integer not null, factor integer not null, reps integer not null, lapses integer not null, left integer not null, odue integer not null, odid integer not null, flags integer not null, data text not null);
        CREATE TABLE revlog (id integer primary key, cid integer not null, usn integer not null, ease integer not null, ivl integer not null, lastIvl integer not null, factor integer not null, time integer not null, type integer not null);
        CREATE TABLE graves (usn integer not null, oid integer not null, type integer not null);
        CREATE INDEX ix_notes_usn on notes (usn); CREATE INDEX ix_cards_usn on cards (usn); CREATE INDEX ix_revlog_usn on revlog (usn);
        CREATE INDEX ix_cards_nid on cards (nid); CREATE INDEX ix_cards_sched on cards (did, queue, due); CREATE INDEX ix_revlog_cid on revlog (cid); CREATE INDEX ix_notes_csum on notes (csum);
        """)

        var idc = Int(Date().timeIntervalSince1970 * 1000)
        func nextId() -> Int { idc += 1; return idc }
        let deckName = set.name.isEmpty ? "Red Pen" : set.name
        let did = deckId(for: deckName)
        let now = Int(Date().timeIntervalSince1970)

        let models: [String: Any] = [
            String(midBasic): model(id: midBasic, name: "Red Pen Basic", cloze: false, fields: ["Front", "Back"],
                                   templates: [["name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr id=answer>{{Back}}", "bqfmt": "", "bafmt": "", "did": NSNull()]], did: did),
            String(midCloze): model(id: midCloze, name: "Red Pen Cloze", cloze: true, fields: ["Text", "Extra"],
                                   templates: [["name": "Cloze", "ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}{{#Extra}}<div class=\"why\"><b>Why / how</b>{{Extra}}</div>{{/Extra}}", "bqfmt": "", "bafmt": "", "did": NSNull()]], did: did),
        ]
        let decks: [String: Any] = [
            "1": ["id": 1, "name": "Default", "desc": "", "mod": now, "usn": 0, "collapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0], "dyn": 0, "extendNew": 10, "extendRev": 50, "conf": 1, "browserCollapsed": false],
            String(did): ["id": did, "name": deckName, "desc": "Exported from Red Pen.", "mod": now, "usn": 0, "collapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0], "dyn": 0, "extendNew": 10, "extendRev": 50, "conf": 1, "browserCollapsed": false],
        ]
        let conf: [String: Any] = ["nextPos": 1, "estTimes": true, "activeDecks": [1], "sortType": "noteFld", "timeLim": 0, "sortBackwards": false, "addToCur": true, "curDeck": 1, "newBury": true, "newSpread": 0, "dueCounts": true, "curModel": String(midBasic), "collapseTime": 1200]
        let dconf: [String: Any] = ["1": ["id": 1, "name": "Default", "replayq": true, "lapse": ["leechFails": 8, "minInt": 1, "delays": [10], "leechAction": 0, "mult": 0], "rev": ["perDay": 200, "ivlFct": 1, "maxIvl": 36500, "ease4": 1.3, "bury": true, "minSpace": 1, "fuzz": 0.05], "timer": 0, "maxTaken": 60, "usn": 0, "new": ["perDay": 20, "delays": [1, 10], "separate": true, "ints": [1, 4, 7], "initialFactor": 2500, "bury": true, "order": 1], "mod": 0, "autoplay": true]]

        try exec(db, "INSERT INTO col VALUES (1, \(now), \(now * 1000), \(now * 1000), 11, 0, 0, 0, \(q(json(conf))), \(q(json(models))), \(q(json(decks))), \(q(json(dconf))), '{}')")

        for card in set.cards {
            let why = card.why
            var mid = midBasic, fields: [String], sort: String, isCloze = false
            // The card's own id, not its text: editing a card must not create a
            // second note, which is the whole reason a GUID exists.
            let guid = guidFor(card.id.uuidString)
            switch card.type {
            case .cloze:
                mid = midCloze; isCloze = true
                let extra = why.isEmpty ? "" : bold(why)
                fields = [card.clozeText, extra]
                sort = plain(card.clozeText)
            case .qa:
                let front = bold(card.front)
                let back = "<ul class=\"bullets\">" + card.bullets.map { "<li>\(bold($0))</li>" }.joined() + "</ul>" + (why.isEmpty ? "" : "<div class=\"why\"><b>Why / how</b>\(esc(why))</div>")
                fields = [front, back]
                sort = plain(card.front)
            case .occlusion:
                guard let idx = card.imageIndex, set.images.indices.contains(idx), let occ = card.occlusion,
                      let pair = renderOcclusion(set.images[idx], occ) else { continue }
                let (frontJPEG, backJPEG) = pair
                // named from the card's id so re-exporting overwrites the same
                // media rather than piling up a copy per export
                let short = card.id.uuidString.prefix(8)
                let f = "occ_\(short)_front.jpg", b = "occ_\(short)_back.jpg"
                media.append((f, frontJPEG)); media.append((b, backJPEG))
                fields = ["<img src=\"\(f)\">" + (card.front.isEmpty ? "" : "<div>\(bold(card.front))</div>"),
                          "<img src=\"\(b)\">" + (why.isEmpty ? "" : "<div class=\"why\"><b>Why / how</b>\(esc(why))</div>")]
                sort = plain(card.front.isEmpty ? "Image occlusion" : card.front)
            }
            let nid = nextId()
            let flds = fields.joined(separator: "\u{1f}")
            try exec(db, "INSERT INTO notes VALUES (\(nid), \(q(guid)), \(mid), \(now), -1, '', \(q(flds)), \(q(sort)), \(checksum(fields[0])), 0, '')")
            // one card per note; cloze notes get one card per distinct cN as Anki would
            let ords = isCloze ? clozeOrdinals(card.clozeText) : [0]
            for ord in ords {
                try exec(db, "INSERT INTO cards VALUES (\(nextId()), \(nid), \(did), \(ord), \(now), -1, 0, 0, \(nid % 1_000_000), 0, 0, 0, 0, 0, 0, 0, 0, '')")
            }
        }
    }

    private static func model(id: Int, name: String, cloze: Bool, fields: [String], templates: [[String: Any]], did: Int) -> [String: Any] {
        [
            "id": id, "name": name, "type": cloze ? 1 : 0, "mod": 0, "usn": 0, "sortf": 0, "did": did,
            "tmpls": templates,
            "flds": fields.enumerated().map { ["name": $1, "ord": $0, "sticky": false, "rtl": false, "font": "Arial", "size": 20, "media": []] as [String: Any] },
            "css": cardCSS, "latexPre": "\\documentclass[12pt]{article}\\special{papersize=3in,5in}\\usepackage[utf8]{inputenc}\\usepackage{amssymb,amsmath}\\pagestyle{empty}\\setlength{\\parindent}{0in}\\begin{document}",
            "latexPost": "\\end{document}", "latexsvg": false, "req": [[0, "any", [0]]], "tags": [], "vers": [],
        ]
    }

    // MARK: identity

    /// The same subject must land in the same deck every time, so the id comes
    /// from the name. Anki treats a deck id as opaque; it only has to be stable
    /// and not collide with the Default deck's 1.
    static func deckId(for name: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in name.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        // keep it inside the range Anki's own ids occupy, and clear of 1
        return Int(h % 900_000_000_000) + 1_000_000_000_000
    }

    /// A stable 10-character GUID, base91 like genanki's.
    static func guidFor(_ content: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in content.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        let table = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-./:;<=>?@[]^_`{|}~")
        var out = "", v = h
        for _ in 0..<10 { out.append(table[Int(v % UInt64(table.count))]); v /= UInt64(table.count) }
        return out
    }

    /// Anki's field checksum: the first 8 hex digits of the SHA-1 of the
    /// stripped first field, as an integer. Anki uses this and only this to
    /// find duplicate notes, so a different hash is not a private detail —
    /// it silently disables the duplicate warning in the card browser.
    static func checksum(_ field: String) -> Int {
        let stripped = field.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let digest = Insecure.SHA1.hash(data: Data(stripped.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return Int(hex, radix: 16) ?? 0
    }

    // MARK: helpers ported from the web app's ankiFieldBold / plainTextForSort

    /// `**term**` → <b>term</b>, everything else HTML-escaped.
    private static func bold(_ s: String) -> String {
        var out = "", rest = Substring(s), on = false
        while let r = rest.range(of: "**") {
            out += esc(String(rest[..<r.lowerBound])) + (on ? "</b>" : "<b>")
            on.toggle(); rest = rest[r.upperBound...]
        }
        out += esc(String(rest))
        return on ? out + "</b>" : out
    }
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    private static func plain(_ s: String) -> String { s.replacingOccurrences(of: "**", with: "") }

    static func clozeOrdinals(_ text: String) -> [Int] {
        let re = try? NSRegularExpression(pattern: #"\{\{c(\d+)::"#)
        let ns = text as NSString
        let nums = re?.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range(at: 1))) } ?? []
        let ords = Set(nums.map { $0 - 1 }).sorted()
        return ords.isEmpty ? [0] : ords
    }

    /// Draws the occlusion box over the image for the front, leaves the
    /// back clean — the web app's `renderOcclusionImages()`.
    private static func renderOcclusion(_ base64: String, _ occ: OcclusionBox) -> (Data, Data)? {
        let payload = base64.hasPrefix("data:") ? String(base64[(base64.firstIndex(of: ",").map { base64.index(after: $0) } ?? base64.startIndex)...]) : base64
        guard let data = Data(base64Encoded: payload), let image = UIImage(data: data) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let front = renderer.image { ctx in
            image.draw(at: .zero)
            UIColor.black.withAlphaComponent(0.92).setFill()
            ctx.fill(CGRect(x: occ.x * image.size.width, y: occ.y * image.size.height, width: occ.w * image.size.width, height: occ.h * image.size.height))
        }
        guard let f = front.jpegData(compressionQuality: 0.85), let b = image.jpegData(compressionQuality: 0.85) else { return nil }
        return (f, b)
    }

    private static func json(_ obj: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: obj)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            if let err { sqlite3_free(err) }
            throw ExportError()
        }
    }
    private static func safeFileName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "[^A-Za-z0-9\\-_. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "red-pen-deck" : String(cleaned.prefix(80))
    }
}

/// The smallest possible ZIP writer: STORE (no compression), CRC-32,
/// local headers + central directory. Anki only needs a valid archive;
/// the SQLite file compresses poorly anyway.
enum MiniZip {
    static func write(entries: [(name: String, data: Data)], to url: URL) throws {
        var out = Data(), central = Data()
        for (name, data) in entries {
            let nameBytes = Array(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            // local file header
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0)); out.append(le16(0))
            out.append(le16(0)); out.append(le16(0x21)) // time/date: fixed
            out.append(le32(crc)); out.append(le32(UInt32(data.count))); out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(nameBytes.count))); out.append(le16(0))
            out.append(contentsOf: nameBytes); out.append(data)
            // central directory entry
            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20)); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0x21))
            central.append(le32(crc)); central.append(le32(UInt32(data.count))); central.append(le32(UInt32(data.count)))
            central.append(le16(UInt16(nameBytes.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset))
            central.append(contentsOf: nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset)); out.append(le16(0))
        try out.write(to: url, options: .atomic)
    }

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}

/// The set as JSON — the same `StudySet` Codable shape `NewSetView`
/// imports, so a set can be sent phone-to-phone or into the web app.
enum JSONExporter {
    static func export(_ set: StudySet) -> URL? {
        guard let data = try? JSONEncoder.redPen.encode(set) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(set.name.replacingOccurrences(of: "[^A-Za-z0-9\\-_ ]", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces).isEmpty ? "red-pen-set" : set.name.replacingOccurrences(of: "[^A-Za-z0-9\\-_ ]", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
            .appendingPathExtension("json")
        try? data.write(to: url, options: .atomic)
        return url
    }
}
