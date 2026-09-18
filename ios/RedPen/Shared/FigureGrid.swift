import Foundation
import CoreGraphics

/// Finding the diagram on a page, and making cards out of it.
///
/// The web app sent slide images to a model and asked where the figure was and
/// what to hide. That is both slow and a guess. A labelled diagram - which is
/// what almost every anatomy, histology and pathway slide is - already carries
/// its own answers: the label IS the term being tested, and its own bounding
/// box IS where to put the mask. Nothing needs to be invented, so nothing can
/// be hallucinated; the worst case is a card about a label that was really a
/// figure caption, which a person can see and delete in a second.
///
/// Everything here works on plain geometry and a boolean grid, with no
/// CoreGraphics drawing, no Vision and no UIKit, so all of it can be tested.
enum FigureGrid {

    /// A rectangle in grid cells, inclusive of both edges.
    struct Cells: Equatable {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
        var area: Int { width * height }

        mutating func absorb(x: Int, y: Int) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }

        func overlaps(_ other: Cells) -> Bool {
            !(maxX < other.minX || other.maxX < minX || maxY < other.minY || other.maxY < minY)
        }

        mutating func union(_ other: Cells) {
            minX = min(minX, other.minX); maxX = max(maxX, other.maxX)
            minY = min(minY, other.minY); maxY = max(maxY, other.maxY)
        }
    }

    /// Blobs of marked cells, as bounding boxes.
    ///
    /// Eight-way connectivity on purpose: a diagram's strokes touch at corners
    /// all the time - an arrowhead meeting a line, a dotted border - and
    /// four-way connectivity splits one drawing into a dozen pieces.
    static func blobs(in grid: [[Bool]]) -> [Cells] {
        guard let width = grid.first?.count, width > 0 else { return [] }
        let height = grid.count
        var seen = Array(repeating: Array(repeating: false, count: width), count: height)
        var found: [Cells] = []

        for y in 0..<height {
            for x in 0..<width where grid[y][x] && !seen[y][x] {
                var box = Cells(minX: x, minY: y, maxX: x, maxY: y)
                // an explicit stack rather than recursion: a full-page diagram
                // is tens of thousands of cells, and that much recursion
                // overflows the stack on a phone
                var stack = [(x, y)]
                seen[y][x] = true
                while let (cx, cy) = stack.popLast() {
                    box.absorb(x: cx, y: cy)
                    for dy in -1...1 {
                        for dx in -1...1 where !(dx == 0 && dy == 0) {
                            let nx = cx + dx, ny = cy + dy
                            guard ny >= 0, ny < height, nx >= 0, nx < width,
                                  grid[ny][nx], !seen[ny][nx] else { continue }
                            seen[ny][nx] = true
                            stack.append((nx, ny))
                        }
                    }
                }
                found.append(box)
            }
        }
        return found
    }

    /// Boxes that touch are one drawing.
    ///
    /// A figure is rarely one connected blob - a legend sits beside it, an
    /// arrow floats free of the structure it points at - so overlapping or
    /// touching boxes are merged until nothing more merges.
    static func merged(_ boxes: [Cells], padding: Int = 1) -> [Cells] {
        var working = boxes.map { box -> Cells in
            Cells(minX: box.minX - padding, minY: box.minY - padding,
                  maxX: box.maxX + padding, maxY: box.maxY + padding)
        }
        var changed = true
        while changed {
            changed = false
            outer: for i in working.indices {
                for j in working.indices where j > i {
                    if working[i].overlaps(working[j]) {
                        working[i].union(working[j])
                        working.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return working.map { box in
            Cells(minX: box.minX + padding, minY: box.minY + padding,
                  maxX: box.maxX - padding, maxY: box.maxY - padding)
        }
    }

    /// Which merged blobs are big enough to be a figure rather than a smudge.
    ///
    /// Measured as a share of the page, not in pixels, so it means the same
    /// thing whatever resolution the page was rendered at.
    static func figures(in grid: [[Bool]], minimumShare: Double = 0.04) -> [Cells] {
        guard let width = grid.first?.count, width > 0 else { return [] }
        let total = Double(width * grid.count)
        return merged(blobs(in: grid))
            .filter { Double($0.area) / total >= minimumShare }
            .sorted { $0.area > $1.area }
    }

    /// A grid rectangle as a fraction of the whole image, which is the shape
    /// an occlusion box is stored in.
    static func normalised(_ box: Cells, gridWidth: Int, gridHeight: Int) -> OcclusionBox {
        guard gridWidth > 0, gridHeight > 0 else { return OcclusionBox(x: 0, y: 0, w: 0, h: 0) }
        return OcclusionBox(x: Double(box.minX) / Double(gridWidth),
                            y: Double(box.minY) / Double(gridHeight),
                            w: Double(box.width) / Double(gridWidth),
                            h: Double(box.height) / Double(gridHeight))
    }

    /// A label found on a figure: its words, and where they sit as fractions of
    /// the image (origin top-left, the way an occlusion box is stored).
    struct Label: Equatable {
        var text: String
        var box: OcclusionBox
    }

    /// Labels worth making a card from.
    ///
    /// Three things are thrown out, each because it produces a card that
    /// teaches nothing: a label with no letters (a number on an axis), one long
    /// enough to be a caption rather than a name, and one covering so much of
    /// the picture that masking it hides the diagram itself.
    static func usableLabels(_ labels: [Label], maxWords: Int = 4,
                             maxShare: Double = 0.25) -> [Label] {
        var kept: [Label] = []
        for label in labels {
            let words = label.text.split { $0.isWhitespace }.map(String.init)
            guard !words.isEmpty, words.count <= maxWords else { continue }
            guard label.text.contains(where: { $0.isLetter }) else { continue }
            guard label.box.w * label.box.h <= maxShare else { continue }
            guard label.box.w > 0, label.box.h > 0 else { continue }
            // the same term labelled twice on one diagram is one card
            if kept.contains(where: {
                $0.text.compare(label.text, options: .caseInsensitive) == .orderedSame
            }) { continue }
            kept.append(label)
        }
        return kept
    }

    /// One occlusion card per label, masking the label itself.
    ///
    /// The mask is grown slightly, because a box drawn exactly on the glyphs
    /// leaves the tops of tall letters and the tails of descenders poking out,
    /// and a student who can read half the word has not been tested.
    static func cards(from labels: [Label], imageIndex: Int,
                      question: String = "What is labelled here?",
                      grow: Double = 0.006) -> [AnkiCard] {
        usableLabels(labels).map { label in
            let box = OcclusionBox(
                x: max(0, label.box.x - grow),
                y: max(0, label.box.y - grow),
                w: min(1 - max(0, label.box.x - grow), label.box.w + grow * 2),
                h: min(1 - max(0, label.box.y - grow), label.box.h + grow * 2))
            return AnkiCard(type: .occlusion, front: question,
                            bullets: [label.text], why: "",
                            imageIndex: imageIndex, occlusion: box)
        }
    }
}
