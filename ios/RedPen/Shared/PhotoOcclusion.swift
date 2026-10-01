// Picture cards from your own photo, screenshot or scan: the decisions.
//
// The device half - reading the picture, shrinking it, running Vision - lives
// in PhotoOcclusionReader. This file holds everything that can be decided
// without a device, so it is tested on Linux: how small a picture is kept,
// where a cover goes when it is dragged or stretched, which cover a finger
// landed on, and which covers become cards.
//
// Every box is a fraction of the picture with the origin at the top left, the
// same OcclusionBox the review screen, the PDF export and the Anki export
// already draw, so a card made here looks like every other picture card.
import Foundation

enum PhotoOcclusion {

    /// The longest side a picture is kept at. A phone photo is 4,000 pixels
    /// or more; 2,048 is plenty for Vision to read a label and for a cover to
    /// sit on it, and a quarter of the memory and of the library file.
    static let maxSide: Int = 2048

    /// The smallest a cover may be made, as a fraction of the picture: small
    /// enough for a one-letter label, big enough to find again with a finger.
    static let minSide: Double = 0.015

    /// The size a picture is shrunk to so its longest side is at most
    /// `maxSide`, keeping its proportions. A picture already small enough is
    /// kept as it is; nothing is ever enlarged.
    static func fitted(width: Int, height: Int, maxSide: Int = maxSide) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxSide > 0 else { return (0, 0) }
        let longest: Int = max(width, height)
        guard longest > maxSide else { return (width, height) }
        let scale: Double = Double(maxSide) / Double(longest)
        let w: Int = max(1, Int((Double(width) * scale).rounded()))
        let h: Int = max(1, Int((Double(height) * scale).rounded()))
        return (min(w, maxSide), min(h, maxSide))
    }

    // MARK: - Covers being edited

    /// One cover on the picture and the answer under it, while the student
    /// is still adjusting them.
    struct Cover: Identifiable, Equatable {
        var id: UUID = UUID()
        var box: OcclusionBox
        var answer: String
    }

    /// The corner a cover is stretched from.
    enum Handle: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// A box kept inside the picture and no smaller than `minSide` each way.
    static func clamped(_ box: OcclusionBox, minSide: Double = minSide) -> OcclusionBox {
        let side: Double = min(max(minSide, 0), 1)
        let w: Double = min(max(box.w, side), 1)
        let h: Double = min(max(box.h, side), 1)
        let x: Double = min(max(box.x, 0), 1 - w)
        let y: Double = min(max(box.y, 0), 1 - h)
        return OcclusionBox(x: x, y: y, w: w, h: h)
    }

    /// A box dragged by a finger: the same size, as far as the picture's
    /// edge allows.
    static func moved(_ box: OcclusionBox, dx: Double, dy: Double) -> OcclusionBox {
        let w: Double = min(box.w, 1)
        let h: Double = min(box.h, 1)
        let x: Double = min(max(box.x + dx, 0), 1 - w)
        let y: Double = min(max(box.y + dy, 0), 1 - h)
        return OcclusionBox(x: x, y: y, w: w, h: h)
    }

    /// A box stretched from one corner. The opposite corner stays where it
    /// is; the dragged corner stops at the picture's edge and never crosses
    /// the fixed one, so a cover cannot be turned inside out.
    static func resized(_ box: OcclusionBox, handle: Handle, dx: Double, dy: Double,
                        minSide: Double = minSide) -> OcclusionBox {
        var left: Double = box.x
        var top: Double = box.y
        var right: Double = box.x + box.w
        var bottom: Double = box.y + box.h
        switch handle {
        case .topLeft:
            left = min(max(left + dx, 0), right - minSide)
            top = min(max(top + dy, 0), bottom - minSide)
        case .topRight:
            right = max(min(right + dx, 1), left + minSide)
            top = min(max(top + dy, 0), bottom - minSide)
        case .bottomLeft:
            left = min(max(left + dx, 0), right - minSide)
            bottom = max(min(bottom + dy, 1), top + minSide)
        case .bottomRight:
            right = max(min(right + dx, 1), left + minSide)
            bottom = max(min(bottom + dy, 1), top + minSide)
        }
        return clamped(OcclusionBox(x: left, y: top, w: right - left, h: bottom - top), minSide: minSide)
    }

    /// A new cover drawn by dragging across the picture, whichever way the
    /// drag went; nil for a drag too short to mean a box (a tap, or a slip).
    static func drawn(fromX x0: Double, y y0: Double, toX x1: Double, y y1: Double,
                      minSide: Double = minSide) -> OcclusionBox? {
        let a: Double = min(max(x0, 0), 1)
        let b: Double = min(max(x1, 0), 1)
        let c: Double = min(max(y0, 0), 1)
        let d: Double = min(max(y1, 0), 1)
        let w: Double = abs(b - a)
        let h: Double = abs(d - c)
        guard w >= minSide || h >= minSide else { return nil }
        return clamped(OcclusionBox(x: min(a, b), y: min(c, d), w: w, h: h), minSide: minSide)
    }

    /// A cover put in the middle of what is on screen, for "Add a cover": about
    /// the size of a short label, in the picture's own proportions.
    static func added(centreX: Double = 0.5, centreY: Double = 0.5, aspect: Double = 1) -> OcclusionBox {
        let ratio: Double = aspect > 0 ? aspect : 1
        let w: Double = 0.22
        let h: Double = min(0.9, max(minSide, 0.06 * ratio))
        return clamped(OcclusionBox(x: centreX - w / 2, y: centreY - h / 2, w: w, h: h))
    }

    /// The cover under a point: of all the covers holding it, the smallest,
    /// since a small cover lying on a bigger one can only be reached that way.
    static func hit(x: Double, y: Double, in covers: [Cover], slack: Double = 0) -> Int? {
        var best: Int? = nil
        var bestArea: Double = .greatestFiniteMagnitude
        for (index, cover) in covers.enumerated() {
            let box: OcclusionBox = cover.box
            let inX: Bool = x >= box.x - slack && x <= box.x + box.w + slack
            let inY: Bool = y >= box.y - slack && y <= box.y + box.h + slack
            guard inX && inY else { continue }
            let area: Double = box.w * box.h
            if area < bestArea {
                bestArea = area
                best = index
            }
        }
        return best
    }

    /// The corner of a box a point is on, within `toleranceX` across and
    /// `toleranceY` down (a finger is the same size both ways on screen,
    /// which is a different fraction of a wide picture each way).
    static func handle(atX x: Double, y: Double, of box: OcclusionBox,
                       toleranceX: Double, toleranceY: Double) -> Handle? {
        let corners: [(Handle, Double, Double)] = [
            (.topLeft, box.x, box.y),
            (.topRight, box.x + box.w, box.y),
            (.bottomLeft, box.x, box.y + box.h),
            (.bottomRight, box.x + box.w, box.y + box.h),
        ]
        var best: Handle? = nil
        var bestDistance: Double = .greatestFiniteMagnitude
        for corner in corners {
            let across: Double = abs(x - corner.1)
            let down: Double = abs(y - corner.2)
            guard across <= toleranceX, down <= toleranceY else { continue }
            let distance: Double = across / max(toleranceX, 1e-9) + down / max(toleranceY, 1e-9)
            if distance < bestDistance {
                bestDistance = distance
                best = corner.0
            }
        }
        return best
    }

    // MARK: - From the labels OCR found, and back to cards

    /// The covers OcclusionPhrases placed, as covers to edit.
    static func covers(from found: [OcclusionPhrases.Cover]) -> [Cover] {
        found.map { (cover: OcclusionPhrases.Cover) -> Cover in
            Cover(box: clamped(cover.box), answer: cover.answer)
        }
    }

    /// A cover's answer as it will be kept: trimmed, one line.
    static func tidied(_ answer: String) -> String {
        let parts: [Substring] = answer.split(whereSeparator: { $0.isWhitespace })
        return parts.joined(separator: " ")
    }

    /// The covers that will make cards: those with an answer typed or read.
    /// A cover with no answer still hides its place on every other card
    /// (it is a sibling) but asks nothing itself.
    static func answered(_ covers: [Cover]) -> [Cover] {
        covers.filter { !tidied($0.answer).isEmpty }
    }

    /// One picture card per answered cover, through the same builder the
    /// lecture diagrams and the heart example use: every other cover on the
    /// picture stays grey after reveal, and a term labelled twice is asked
    /// once. A photo of one label is still a card, so one is enough.
    static func cards(from covers: [Cover], imageIndex: Int,
                      question: String = "What is labelled here?",
                      source: String? = nil) -> [AnkiCard] {
        let asked: [Cover] = answered(covers)
        guard !asked.isEmpty else { return [] }
        let unasked: [OcclusionBox] = covers.filter { tidied($0.answer).isEmpty }.map(\.box)
        let phrased: [OcclusionPhrases.Cover] = asked.map { (cover: Cover) -> OcclusionPhrases.Cover in
            OcclusionPhrases.Cover(box: cover.box, answer: tidied(cover.answer), lines: [])
        }
        var made: [AnkiCard] = OcclusionPhrases.cards(from: phrased, imageIndex: imageIndex,
                                                      question: question, minimumLabels: 1)
        for i in made.indices {
            made[i].siblings += unasked
            made[i].source = source
        }
        return made
    }

    // MARK: - Naming and the lecture

    /// A deck's name when the student gives none: what it is and the day.
    static func defaultName(on date: Date, scanned: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM"
        let day: String = formatter.string(from: date)
        return scanned ? "Scanned pages, \(day)" : "Picture cards, \(day)"
    }

    /// Where a card says it came from: the deck, and the page when there are
    /// several, so a card that looks wrong can be checked against its page.
    static func source(name: String, page: Int, of pages: Int) -> String {
        pages > 1 ? "\(name), p. \(page)" : name
    }

    /// A page's words, top to bottom, one line each, blanks dropped - the
    /// text a scanned page brings to the lecture it becomes.
    static func pageText(_ lines: [String]) -> String {
        let kept: [String] = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return kept.joined(separator: "\n")
    }
}
