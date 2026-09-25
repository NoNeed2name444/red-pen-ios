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

    /// Builds the .apkg on a background thread, so a big deck does not freeze
    /// the library while its pictures are drawn.
    static func exportInBackground(_ set: StudySet) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { try export(set) }.value
    }

    /// Picture cards whose picture is not on this phone - still a sync
    /// reference while it downloads, or never uploaded by the phone that made
    /// it. They cannot be drawn, so they are left out of the deck; this is how
    /// many, for asking before that happens rather than after.
    static func missingPictures(in set: StudySet) -> Int {
        var readable: [Int: Bool] = [:]
        func available(_ index: Int) -> Bool {
            if let known = readable[index] { return known }
            let ok = set.images.indices.contains(index) && BlobRefs.data(fromStored: set.images[index]) != nil
            readable[index] = ok
            return ok
        }
        return set.cards.filter { card in
            guard card.type == .occlusion, card.occlusion != nil else { return false }
            guard let index = card.imageIndex else { return true }
            return !available(index)
        }.count
    }

    static func export(_ set: StudySet) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("apkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("collection.anki2")

        // each picture goes to disk as it is drawn, not into memory
        var media: [(name: String, file: URL)] = []
        try buildCollection(at: dbURL, set: set, mediaFolder: dir, media: &media)

        // media manifest: {"0": "file.jpg", ...}; zipped entries are named by index
        var manifest: [String: String] = [:]
        var entries: [(name: String, file: URL)] = [("collection.anki2", dbURL)]
        for (i, m) in media.enumerated() {
            manifest[String(i)] = m.name
            entries.append((String(i), m.file))
        }
        let manifestURL = dir.appendingPathComponent("media.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        entries.append(("media", manifestURL))

        // a folder of its own, so two exports at once never write one file
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("apkg-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(safeFileName(set.name)).appendingPathExtension("apkg")
        try MiniZip.write(files: entries, to: out)
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

    private static func buildCollection(at url: URL, set: StudySet, mediaFolder: URL,
                                        media: inout [(name: String, file: URL)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw ExportError() }
        // _v2: closes once the prepared statements below are finalized,
        // whichever order their lifetimes happen to end in
        defer { sqlite3_close_v2(db) }

        // A throwaway file in the temporary folder: no journal and no fsync,
        // and every row in ONE transaction. Each INSERT used to be its own
        // committed transaction - a journal created, synced and deleted per
        // card, four thousand times for a large cloze deck.
        try exec(db, "PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;")
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
        let deckName = set.name.isEmpty ? Brand.name : set.name
        let did = deckId(for: deckName)
        let now = Int(Date().timeIntervalSince1970)

        let models: [String: Any] = [
            String(midBasic): model(id: midBasic, name: "\(Brand.name) Basic", cloze: false, fields: ["Front", "Back"],
                                   templates: [["name": "Card 1", "ord": 0, "qfmt": "{{Front}}", "afmt": "{{FrontSide}}<hr id=answer>{{Back}}", "bqfmt": "", "bafmt": "", "did": NSNull()]], did: did),
            String(midCloze): model(id: midCloze, name: "\(Brand.name) Cloze", cloze: true, fields: ["Text", "Extra"],
                                   templates: [["name": "Cloze", "ord": 0, "qfmt": "{{cloze:Text}}", "afmt": "{{cloze:Text}}{{#Extra}}<div class=\"why\"><b>Why / how</b>{{Extra}}</div>{{/Extra}}", "bqfmt": "", "bafmt": "", "did": NSNull()]], did: did),
        ]
        let decks: [String: Any] = [
            "1": ["id": 1, "name": "Default", "desc": "", "mod": now, "usn": 0, "collapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0], "dyn": 0, "extendNew": 10, "extendRev": 50, "conf": 1, "browserCollapsed": false],
            String(did): ["id": did, "name": deckName, "desc": "Exported from \(Brand.name).", "mod": now, "usn": 0, "collapsed": false, "newToday": [0, 0], "revToday": [0, 0], "lrnToday": [0, 0], "timeToday": [0, 0], "dyn": 0, "extendNew": 10, "extendRev": 50, "conf": 1, "browserCollapsed": false],
        ]
        let conf: [String: Any] = ["nextPos": 1, "estTimes": true, "activeDecks": [1], "sortType": "noteFld", "timeLim": 0, "sortBackwards": false, "addToCur": true, "curDeck": 1, "newBury": true, "newSpread": 0, "dueCounts": true, "curModel": String(midBasic), "collapseTime": 1200]
        let dconf: [String: Any] = ["1": ["id": 1, "name": "Default", "replayq": true, "lapse": ["leechFails": 8, "minInt": 1, "delays": [10], "leechAction": 0, "mult": 0], "rev": ["perDay": 200, "ivlFct": 1, "maxIvl": 36500, "ease4": 1.3, "bury": true, "minSpace": 1, "fuzz": 0.05], "timer": 0, "maxTaken": 60, "usn": 0, "new": ["perDay": 20, "delays": [1, 10], "separate": true, "ints": [1, 4, 7], "initialFactor": 2500, "bury": true, "order": 1], "mod": 0, "autoplay": true]]

        try exec(db, "BEGIN")
        let collection = try Statement(db, "INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')")
        try collection.run([.int(now), .int(now * 1000), .int(now * 1000), .text(json(conf)),
                            .text(json(models)), .text(json(decks)), .text(json(dconf))])
        let notes = try Statement(db, "INSERT INTO notes VALUES (?, ?, ?, ?, -1, '', ?, ?, ?, 0, '')")
        let cardRows = try Statement(db, "INSERT INTO cards VALUES (?, ?, ?, ?, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')")
        // the picture drawn last, since a diagram's cards sit together:
        // decoding it once per diagram rather than once per card, without
        // holding every diagram at once
        var picture: (index: Int, image: UIImage)?

        for card in set.cards {
            let why = card.why
            var mid = midBasic, fields: [String], sort: String, isCloze = false
            // The card's own id, not its text: editing a card must not create a
            // second note, which is the whole reason a GUID exists.
            let guid = guidFor(card.id.uuidString)
            switch card.type {
            case .cloze:
                mid = midCloze; isCloze = true
                let extra = why.isEmpty ? "" : AnkiFields.bold(why)
                // escaped like every other field: a cloze from a shared set
                // or a model is HTML to Anki, and runs as HTML if left raw
                fields = [AnkiFields.cloze(card.clozeText), extra]
                sort = AnkiFields.plain(card.clozeText)
            case .qa:
                let front = AnkiFields.bold(card.front)
                let items: String = card.bullets.map { "<li>\(AnkiFields.bold($0))</li>" }.joined()
                let reason: String = why.isEmpty ? "" : "<div class=\"why\"><b>Why / how</b>\(AnkiFields.esc(why))</div>"
                fields = [front, "<ul class=\"bullets\">" + items + "</ul>" + reason]
                sort = AnkiFields.plain(card.front)
            case .occlusion:
                guard let idx = card.imageIndex, let occ = card.occlusion else { continue }
                if picture?.index != idx {
                    picture = nil
                    if set.images.indices.contains(idx),
                       let data = BlobRefs.data(fromStored: set.images[idx]),
                       let decoded = UIImage(data: data) {
                        picture = (idx, decoded)
                    }
                }
                // a picture not on this phone: counted beforehand by
                // missingPictures, and asked about there
                guard let base = picture?.image else { continue }
                // named from the card's id so re-exporting overwrites the same
                // media rather than piling up a copy per export
                let short = card.id.uuidString.prefix(8)
                let f = "occ_\(short)_front.jpg", b = "occ_\(short)_back.jpg"
                let drawn: Bool = try autoreleasepool {
                    guard let pair = renderOcclusion(base, occ,
                                                     others: OcclusionCovers.others(for: card, in: set.cards))
                    else { return false }
                    let frontFile = mediaFolder.appendingPathComponent("m\(media.count)")
                    try pair.front.write(to: frontFile)
                    media.append((f, frontFile))
                    let backFile = mediaFolder.appendingPathComponent("m\(media.count)")
                    try pair.back.write(to: backFile)
                    media.append((b, backFile))
                    return true
                }
                guard drawn else { continue }
                let reason: String = why.isEmpty ? "" : "<div class=\"why\"><b>Why / how</b>\(AnkiFields.esc(why))</div>"
                fields = ["<img src=\"\(f)\">" + (card.front.isEmpty ? "" : "<div>\(AnkiFields.bold(card.front))</div>"),
                          "<img src=\"\(b)\">" + reason]
                sort = AnkiFields.plain(card.front.isEmpty ? "Image occlusion" : card.front)
            }
            let nid = nextId()
            let flds = fields.joined(separator: "\u{1f}")
            try notes.run([.int(nid), .text(guid), .int(mid), .int(now), .text(flds), .text(sort),
                           .int(checksum(fields[0]))])
            // one card per note; cloze notes get one card per distinct cN as Anki would
            let ords = isCloze ? AnkiFields.clozeOrdinals(card.clozeText) : [0]
            for ord in ords {
                try cardRows.run([.int(nextId()), .int(nid), .int(did), .int(ord), .int(now), .int(nid % 1_000_000)])
            }
        }
        try exec(db, "COMMIT")
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
        let digest = Insecure.SHA1.hash(data: Data(AnkiFields.stripped(field).utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return Int(hex, radix: 16) ?? 0
    }

    /// The longest side of a drawn occlusion picture, in pixels. The stored
    /// pictures are 1,400; older sets hold some at 4,200, which is only more
    /// memory and a bigger file for a picture Anki shows at phone size.
    private static let pictureSide: CGFloat = 2000

    /// The front and back pictures of an image occlusion note, drawn the way
    /// the app draws them: every other tested label covered in solid grey on
    /// both sides, this card's label orange with a "?" on the front and
    /// uncovered but outlined on the back. Nothing is translucent, so no text
    /// shows through a cover in either picture.
    ///
    /// Drawn at a scale of one, so the size is the picture's own pixels: a
    /// renderer left at the screen's scale drew a 1,400-pixel diagram 4,200
    /// pixels across on a 3x phone, twice per card.
    private static func renderOcclusion(_ image: UIImage, _ occ: OcclusionBox,
                                        others: [OcclusionBox]) -> (front: Data, back: Data)? {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height)
        guard longest > 0 else { return nil }
        let fit = min(1, pictureSide / longest)
        let size = CGSize(width: max(1, (pixels.width * fit).rounded()),
                          height: max(1, (pixels.height * fit).rounded()))
        let frame = CGRect(origin: .zero, size: size)
        // the stored covers are already padded, and only as far as they can
        // go without meeting another; growing them here would make them overlap
        let padding: CGFloat = OcclusionCovers.drawPadding
        let minimum: CGFloat = OcclusionCovers.drawMinimum
        let renderer = SourceIngest.pixelRenderer(size: size, opaque: true)
        func picture(revealed: Bool) -> Data? {
            renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(frame)
                image.draw(in: frame)
                PDFOcclusion.drawCovers(target: occ, others: others, revealed: revealed,
                                        in: frame, padding: padding, minimum: minimum,
                                        context: ctx.cgContext)
            }.jpegData(compressionQuality: 0.85)
        }
        guard let f = picture(revealed: false), let b = picture(revealed: true) else { return nil }
        return (f, b)
    }

    private static func json(_ obj: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: obj)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK else {
            if let err { sqlite3_free(err) }
            throw ExportError()
        }
    }
    /// One statement, prepared once and run for every row with its values
    /// bound - no SQL built out of a card's text.
    private final class Statement {
        enum Value {
            case int(Int)
            case text(String)
        }

        private let handle: OpaquePointer
        /// SQLite copies bound text rather than keeping the pointer.
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        init(_ db: OpaquePointer, _ sql: String) throws {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
                throw ExportError()
            }
            handle = prepared
        }

        deinit { sqlite3_finalize(handle) }

        func run(_ values: [Value]) throws {
            sqlite3_reset(handle)
            sqlite3_clear_bindings(handle)
            for (offset, value) in values.enumerated() {
                let slot = Int32(offset + 1)
                switch value {
                case .int(let number): sqlite3_bind_int64(handle, slot, sqlite3_int64(number))
                case .text(let text): sqlite3_bind_text(handle, slot, text, -1, Statement.transient)
                }
            }
            let stepped = sqlite3_step(handle)
            // reset straight away, so no statement is left in progress when
            // the transaction commits
            sqlite3_reset(handle)
            guard stepped == SQLITE_DONE else { throw ExportError() }
        }
    }

    private static func safeFileName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "[^A-Za-z0-9\\-_. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "red-pen-deck" : String(cleaned.prefix(80))
    }
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
