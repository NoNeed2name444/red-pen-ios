import Foundation
import CoreGraphics

/// Which words on a slide are worth hiding.
///
/// OCR reads everything on a page: the lecture title, the college crest, the
/// lecturer's name, "Slide 12 of 45", the copyright line. Every one of those
/// used to become a mask, so a deck about the inguinal canal quizzed the
/// student on the name of their own university. Only a label a student could
/// be examined on should be hidden.
///
/// The rules are plain text and geometry, no Vision and no UIKit, so all of
/// them can be tested:
///   - the header and footer bands of a page are the slide template, not the
///     diagram; a word there survives only if it sits on the figure AND reads
///     as an anatomical or clinical term
///   - when the figure is known, anything off it is the slide's own text
///   - the slide's title (the tallest line near the top) is never a label
///   - branding, people, dates, page numbers, captions and references are
///     dropped by what they say
///   - what is left passes if it reads as a medical term, or sits on the
///     figure
enum OcclusionFilter {

    /// One line of text on the page, as fractions of the whole image with the
    /// origin at the top left - the way an occlusion box is stored.
    struct Line: Equatable {
        var text: String
        var box: OcclusionBox
    }

    /// The top of a page where the template puts its title bar and logos.
    static let headerBand = 0.12
    /// The bottom of a page where the template puts its footer and page number.
    static let footerBand = 0.08

    /// The lines worth masking, in their original order.
    ///
    /// `figure` is the diagram's box when one was found. `pageBands` is off for
    /// a picture that is itself the diagram (an image pulled out of a slide
    /// deck), where the top of the picture is not a page header.
    static func testable(_ lines: [Line], figure: OcclusionBox?,
                         pageBands: Bool = true) -> [Line] {
        let title = titleIndex(lines)
        var kept: [Line] = []
        for (index, line) in lines.enumerated() {
            if index == title { continue }
            let text = tidy(line.text)
            guard looksLikeALabel(text) else { continue }
            guard !isBoilerplate(text) else { continue }

            let cx = line.box.x + line.box.w / 2
            let cy = line.box.y + line.box.h / 2
            let onFigure = figure.map { isInside($0, x: cx, y: cy) } ?? false
            // the slide's own text, not the diagram's
            if figure != nil && !onFigure { continue }

            let medical = isMedicalTerm(text)
            let inBand = pageBands && (cy < headerBand || cy > 1 - footerBand)
            if inBand && !(onFigure && medical) { continue }

            if medical || onFigure {
                var cleaned = line
                cleaned.text = text
                kept.append(cleaned)
            }
        }
        return kept
    }

    /// The slide's title: the tallest line in the top part of the page, when
    /// it is clearly taller than the text around it.
    static func titleIndex(_ lines: [Line]) -> Int? {
        guard lines.count >= 2 else { return nil }
        let heights = lines.map(\.box.h).sorted()
        let median = heights[heights.count / 2]
        var best: Int?
        for (index, line) in lines.enumerated() where line.box.y + line.box.h / 2 < 0.3 {
            if let current = best, lines[current].box.h >= line.box.h { continue }
            best = index
        }
        guard let found = best, lines[found].box.h >= median * 1.25 else { return nil }
        return found
    }

    /// One to six words, mostly letters: the shape of a label rather than a
    /// sentence, a number or a stray mark.
    static func looksLikeALabel(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace }
        guard (1...6).contains(words.count) else { return false }
        let visible = text.filter { !$0.isWhitespace }
        let letters = visible.filter { $0.isLetter }.count
        guard letters >= 2 else { return false }
        return Double(letters) / Double(max(visible.count, 1)) >= 0.6
    }

    /// Words that belong to the slide template, the people or the paperwork
    /// rather than to the body.
    static func isBoilerplate(_ text: String) -> Bool {
        let lower = text.lowercased()
        for fragment in fragments where lower.contains(fragment) { return true }
        for pattern in patterns where lower.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        let words = tokens(lower)
        return words.contains { dropWords.contains($0) }
    }

    /// Whether any word in the label reads as anatomy or medicine: a known
    /// root, or a Latin-looking ending on a word long enough to carry one.
    static func isMedicalTerm(_ text: String) -> Bool {
        for word in tokens(text.lowercased()) {
            if medicalWords.contains(word) { return true }
            if word.count >= 5, medicalEndings.contains(where: { word.hasSuffix($0) }) { return true }
        }
        return false
    }

    // MARK: word lists

    /// Pieces that give a line away wherever they appear in it.
    static let fragments = [
        "©", "(c)", "copyright", "all rights reserved", "www", "http", ".com", ".edu",
        ".ac.uk", ".org", ".net", ".gov", "@", "universit", "et al", "adapted from",
        "reproduced", "permission", "learning outcome", "learning objective",
    ]

    /// Shapes of text that are dates, page counts and figure numbers.
    static let patterns = [
        #"\b(19|20)\d{2}\b"#,                   // a year
        #"\b\d{1,2}\s*[/.\-]\s*\d{1,3}\b"#,     // 12/45, 03.10
        #"\b(slide|page|fig|figure|table)\.?\s*\d"#,
        #"^\s*(source|ref|refs|reference|references|credit|image)\s*:"#,
        #"\b(dr|prof)\.?\s"#,                   // Dr Smith, Prof. Jones
    ]

    /// Whole words that mark a line as branding, a person, a date or admin.
    static let dropWords: Set<String> = [
        // institutions and branding
        "university", "college", "faculty", "department", "dept", "school", "hospital",
        "hospitals", "nhs", "trust", "institute", "foundation", "ltd", "inc", "campus",
        "medicine", "academy", "copyright",
        // people and their letters
        "dr", "prof", "professor", "mbbs", "mbchb", "md", "frcs", "frcp", "mrcs", "mrcp",
        "phd", "bsc", "msc", "lecturer", "consultant", "registrar", "mr", "mrs", "miss",
        // the slide as a document
        "slide", "slides", "page", "figure", "fig", "table", "source", "sources", "reference",
        "references", "ref", "refs", "courtesy", "credit", "credits", "doi", "journal",
        "lecture", "objectives", "outcomes", "outline", "contents", "agenda", "overview",
        "summary", "introduction", "questions", "thanks", "thank", "module", "semester",
        "week", "session", "date", "click", "video", "animation",
        // months
        "january", "february", "march", "april", "june", "july", "august", "september",
        "october", "november", "december", "jan", "feb", "apr", "jun", "jul", "aug",
        "sep", "sept", "oct", "nov", "dec",
    ]

    /// Roots of the words anatomy and clinical diagrams are labelled with.
    static let medicalWords: Set<String> = [
        "artery", "arteries", "vein", "veins", "nerve", "nerves", "ligament", "ligaments",
        "muscle", "muscles", "canal", "ring", "fascia", "duct", "lobe", "node", "nodes",
        "gland", "bone", "cortex", "valve", "sinus", "tract", "plexus", "sac", "tendon",
        "membrane", "process", "fossa", "foramen", "epigastric", "inguinal", "femoral",
        "spermatic", "cord", "vessel", "vessels", "aorta", "atrium", "ventricle", "septum",
        "cartilage", "joint", "capsule", "bursa", "ramus", "trunk", "branch", "root",
        "ganglion", "lymph", "vertebra", "rib", "skull", "pelvis", "femur", "tibia",
        "fibula", "humerus", "radius", "ulna", "scapula", "clavicle", "sternum", "kidney",
        "liver", "lung", "heart", "spleen", "pancreas", "stomach", "bladder", "ureter",
        "urethra", "uterus", "ovary", "testis", "colon", "ileum", "jejunum", "duodenum",
        "caecum", "cecum", "rectum", "anus", "oesophagus", "esophagus", "trachea",
        "bronchus", "larynx", "pharynx", "tongue", "brain", "cerebellum", "thalamus",
        "pons", "medulla", "cell", "cells", "tubule", "glomerulus", "alveolus", "villi",
        "epithelium", "mucosa", "submucosa", "serosa", "layer", "wall", "triangle",
        "hiatus", "orifice", "notch", "tubercle", "tuberosity", "crest", "spine",
        "condyle", "epicondyle", "aponeurosis", "retinaculum", "sheath", "fold", "recess",
        "pouch", "peritoneum", "omentum", "mesentery", "diaphragm", "abdominis", "oblique",
        "rectus", "transversus", "superficial", "deep", "anterior", "posterior",
        "superior", "inferior", "medial", "lateral", "proximal", "distal", "hernia",
        "tissue", "fibres", "fibers", "nucleus", "ducts", "lobule", "cavity",
        "floor", "roof", "apex", "hilum", "hilus", "pedicle", "lamina",
    ]

    /// Endings that anatomical Latin and clinical adjectives share.
    static let medicalEndings = [
        "us", "is", "al", "ary", "ic", "oid", "ous", "ior", "eal", "ial", "ar", "ae",
        "um", "ium", "itis", "oma", "osis",
    ]

    // MARK: helpers

    /// Whitespace collapsed and the ends trimmed.
    static func tidy(_ text: String) -> String {
        text.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// Words as runs of letters, so "Dr." and "(MBBS)" both read as words.
    static func tokens(_ text: String) -> [String] {
        text.split { !$0.isLetter }.map(String.init)
    }

    static func isInside(_ box: OcclusionBox, x: Double, y: Double) -> Bool {
        x >= box.x && x <= box.x + box.w && y >= box.y && y <= box.y + box.h
    }
}

/// How the masks on an image occlusion card are drawn, the same way on screen,
/// in a printed PDF and in an Anki export.
///
/// Every tested label on the picture is covered, so reading a neighbouring
/// label cannot give the answer away; the one this card asks about is covered
/// in a different colour with a "?", and only that one comes off when the card
/// is turned over. Covers are solid - never translucent - and grown outward to
/// whole pixels so no edge of a letter shows round them.
enum OcclusionCovers {

    /// The label this card asks about: a strong orange.
    static let targetRGB: (red: Double, green: Double, blue: Double) = (0.93, 0.45, 0.09)
    /// Every other label on the picture: a flat, neutral grey.
    static let otherRGB: (red: Double, green: Double, blue: Double) = (0.56, 0.58, 0.62)

    /// The other labels on this card's picture.
    ///
    /// A card made since the masks were all stored carries them itself. An
    /// older card does not, so they are taken from the other cards in its set
    /// that point at the same picture. Anything sitting on top of the card's
    /// own label is left out, or the grey would hide the answer after reveal.
    static func others(for card: AnkiCard, in deck: [AnkiCard]) -> [OcclusionBox] {
        var found: [OcclusionBox] = card.siblings
        if found.isEmpty, let index = card.imageIndex {
            for other in deck where other.id != card.id && other.type == .occlusion
                && other.imageIndex == index {
                if let box = other.occlusion { found.append(box) }
            }
        }
        var kept: [OcclusionBox] = []
        for box in found {
            if let target = card.occlusion, overlapShare(box, target) > 0.5 { continue }
            if kept.contains(box) { continue }
            kept.append(box)
        }
        return kept
    }

    /// How much of the smaller box the two share, 0...1.
    static func overlapShare(_ a: OcclusionBox, _ b: OcclusionBox) -> Double {
        let w = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
        let h = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
        guard w > 0, h > 0 else { return 0 }
        let smaller = min(a.w * a.h, b.w * b.h)
        return smaller > 0 ? (w * h) / smaller : 0
    }

    /// Where a cover goes on a picture drawn in `frame`: the stored box grown
    /// by `padding` on every side, at least `minimum` across, kept on the
    /// picture, and rounded OUTWARD to whole pixels at `pixelScale` so its
    /// edges are never a half-covered, see-through pixel.
    static func rect(for box: OcclusionBox, in frame: CGRect, padding: CGFloat,
                     minimum: CGFloat, pixelScale: CGFloat = 1) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        var r = CGRect(x: frame.minX + CGFloat(box.x) * frame.width,
                       y: frame.minY + CGFloat(box.y) * frame.height,
                       width: CGFloat(box.w) * frame.width,
                       height: CGFloat(box.h) * frame.height)
        r = r.insetBy(dx: -padding, dy: -padding)
        if r.width < minimum { r = r.insetBy(dx: -(minimum - r.width) / 2, dy: 0) }
        if r.height < minimum { r = r.insetBy(dx: 0, dy: -(minimum - r.height) / 2) }
        r = r.intersection(frame)
        guard !r.isNull, r.width > 0, r.height > 0 else { return .zero }
        let s = max(pixelScale, 1)
        let minX = (r.minX * s).rounded(.down) / s
        let minY = (r.minY * s).rounded(.down) / s
        let maxX = (r.maxX * s).rounded(.up) / s
        let maxY = (r.maxY * s).rounded(.up) / s
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
