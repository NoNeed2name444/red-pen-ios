// Turning a rendered slide into occlusion cards.
//
// FigureGrid holds the decisions and is testable; this file holds the two
// things that can only happen on a device - reading pixels and running Vision -
// and does no deciding of its own.
//
// The route is short on purpose:
//     page image  ->  coarse ink grid  ->  biggest figure
//                 ->  the text sitting inside that figure  ->  one card each
//
// Nothing is asked of a model, so nothing can be invented. The worst outcome is
// a card about a word that was really part of a caption, which is visible at a
// glance and gone in one tap.
import Foundation
import CoreGraphics

public enum FigureFinder {

    /// How coarse the grid is. Eighty cells across a slide is about a
    /// centimetre each: fine enough to separate a diagram from a paragraph,
    /// coarse enough that a whole page is a few thousand cells rather than a
    /// few million.
    public static let gridWidth = 80

    /// A page reduced to "is there ink here", with the text taken out.
    ///
    /// Text has to be removed before the blobs are found, or the body of the
    /// slide - which is a dense, well-connected mass of ink - becomes the
    /// biggest "figure" on every page.
    public static func inkGrid(_ image: CGImage,
                               ignoring textBoxes: [CGRect] = [],
                               width: Int = gridWidth) -> [[Bool]] {
        let height = max(1, Int((Double(image.height) / Double(image.width)
                                * Double(width)).rounded()))
        guard width > 0,
              let space = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }

        // white, so a page with an alpha channel does not read as all ink
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return [] }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height)

        // The page's own background, whatever colour it is: a dark slide theme
        // is just as common as a white one, and a fixed threshold would call
        // every pixel of a dark slide ink.
        var histogram = [Int](repeating: 0, count: 256)
        for i in 0..<(width * height) { histogram[Int(pixels[i])] += 1 }
        let background = histogram.enumerated().max { $0.element < $1.element }?.offset ?? 255
        let margin = 40

        // Vision's boxes have their origin at the bottom left; the grid's is at
        // the top left, like every other box Red Pen stores.
        let blocked = textBoxes.map { box in
            CGRect(x: box.minX * CGFloat(width),
                   y: (1 - box.maxY) * CGFloat(height),
                   width: box.width * CGFloat(width),
                   height: box.height * CGFloat(height)).insetBy(dx: -1, dy: -1)
        }

        var grid = Array(repeating: Array(repeating: false, count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                // the bitmap's first row is the bottom of the image
                let value = Int(pixels[(height - 1 - y) * width + x])
                guard abs(value - background) > margin else { continue }
                let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                if blocked.contains(where: { $0.contains(point) }) { continue }
                grid[y][x] = true
            }
        }
        return grid
    }

    /// The labels sitting on a figure, in the form FigureGrid wants them:
    /// fractions of the whole image, origin top-left.
    public static func labels(_ lines: [OCRLine], on figure: OcclusionBox)
        -> [FigureGrid.Label] {
        lines.compactMap { line in
            let box = OcclusionBox(x: Double(line.box.minX),
                                   y: Double(1 - line.box.maxY),
                                   w: Double(line.box.width),
                                   h: Double(line.box.height))
            // a label belongs to the figure it sits on; the slide's title and
            // its bullet points are somewhere else on the page
            let cx = box.x + box.w / 2, cy = box.y + box.h / 2
            guard cx >= figure.x, cx <= figure.x + figure.w,
                  cy >= figure.y, cy <= figure.y + figure.h else { return nil }
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : FigureGrid.Label(text: text, box: box)
        }
    }

    /// What a page offers: the figure on it, and the cards its labels make.
    public struct Found {
        public var figure: OcclusionBox
        public var cards: [AnkiCard]
    }

    /// Everything above, for one page image.
    ///
    /// The OCR pass happens first because its boxes are what keep the page's
    /// text out of the ink grid. A page with no figure - a wall of bullet
    /// points - returns nil rather than a card about its own heading.
    public static func read(_ image: CGImage, imageIndex: Int,
                            question: String = "What is labelled here?") -> Found? {
        let lines = (try? RedPenOCR.read(image)) ?? []
        let grid = inkGrid(image, ignoring: lines.map(\.box))
        guard let width = grid.first?.count,
              let box = FigureGrid.figures(in: grid).first else { return nil }

        let figure = FigureGrid.normalised(box, gridWidth: width, gridHeight: grid.count)
        let cards = FigureGrid.cards(from: labels(lines, on: figure),
                                     imageIndex: imageIndex, question: question)
        return cards.isEmpty ? nil : Found(figure: figure, cards: cards)
    }
}
