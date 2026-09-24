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

enum FigureFinder {

    /// How coarse the grid is. Eighty cells across a slide is about a
    /// centimetre each: fine enough to separate a diagram from a paragraph,
    /// coarse enough that a whole page is a few thousand cells rather than a
    /// few million.
    static let gridWidth = 80

    /// A page reduced to "is there ink here", with the text taken out.
    ///
    /// Text has to be removed before the blobs are found, or the body of the
    /// slide - which is a dense, well-connected mass of ink - becomes the
    /// biggest "figure" on every page.
    static func inkGrid(_ image: CGImage,
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
        let pixelWidth = CGFloat(width)
        let pixelHeight = CGFloat(height)
        let blocked: [CGRect] = textBoxes.map { (box: CGRect) -> CGRect in
            let x: CGFloat = box.minX * pixelWidth
            let y: CGFloat = (1 - box.maxY) * pixelHeight
            let w: CGFloat = box.width * pixelWidth
            let h: CGFloat = box.height * pixelHeight
            return CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -1, dy: -1)
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
    static func labels(_ lines: [OCRLine], on figure: OcclusionBox)
        -> [FigureGrid.Label] {
        lines.compactMap { (line: OCRLine) -> FigureGrid.Label? in
            // an unsure reading is as likely a smudge as a word
            guard Double(line.confidence) >= OcclusionFilter.minimumConfidence else { return nil }
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

    /// The labels on a figure worth hiding: every line OCR read on the page,
    /// put through OcclusionFilter so the slide's title, its header and footer,
    /// the college crest and the lecturer's name never become masks.
    ///
    /// OCR's own confidence goes along with each line, so a guess at a smudge
    /// is thrown out. When the picture is given, a line with no ink under it -
    /// OCR "reading" a texture or a blank patch - is thrown out too, so no
    /// cover ever sits over nothing.
    static func testableLabels(_ lines: [OCRLine], on figure: OcclusionBox,
                               pageBands: Bool = true,
                               image: CGImage? = nil) -> [FigureGrid.Label] {
        let all: [OcclusionFilter.Line] = lines.compactMap { (line: OCRLine) -> OcclusionFilter.Line? in
            // Vision's origin is the bottom left; a stored box's is the top left
            let box = OcclusionBox(x: Double(line.box.minX),
                                   y: Double(1 - line.box.maxY),
                                   w: Double(line.box.width),
                                   h: Double(line.box.height))
            if let image, !hasInk(image, under: box) { return nil }
            return OcclusionFilter.Line(text: line.text, box: box,
                                        confidence: Double(line.confidence))
        }
        var aspect: Double = 1
        if let image, image.width > 0, image.height > 0 {
            aspect = Double(image.width) / Double(image.height)
        }
        return OcclusionFilter.testable(all, figure: figure, pageBands: pageBands, aspect: aspect)
            .map { FigureGrid.Label(text: $0.text, box: $0.box) }
    }

    /// Whether there is really writing under a box: the box's patch of the
    /// picture, shrunk to a small grey bitmap, has enough pixels that differ
    /// from its own background. When the patch cannot be read at all the
    /// answer is yes, so a failure to look never throws a real label away.
    static func hasInk(_ image: CGImage, under box: OcclusionBox) -> Bool {
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)
        guard imageWidth > 0, imageHeight > 0 else { return true }
        let left: Double = max(0, box.x) * imageWidth
        let top: Double = max(0, box.y) * imageHeight
        let across: Double = box.w * imageWidth
        let down: Double = box.h * imageHeight
        let region = CGRect(x: left, y: top, width: across, height: down).integral
        guard region.width >= 1, region.height >= 1 else { return false }
        guard let patch = image.cropping(to: region) else { return true }

        let width = max(1, min(patch.width, 128))
        let height = max(1, min(patch.height, 40))
        guard let space = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return true }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return true }
        let count = width * height
        let pixels = raw.bindMemory(to: UInt8.self, capacity: count)

        var histogram = [Int](repeating: 0, count: 256)
        for i in 0..<count { histogram[Int(pixels[i])] += 1 }
        let background = histogram.enumerated().max { $0.element < $1.element }?.offset ?? 255
        var inked = 0
        for i in 0..<count where abs(Int(pixels[i]) - background) > 30 { inked += 1 }
        let share: Double = Double(inked) / Double(count)
        return OcclusionFilter.hasInk(share: share)
    }

    /// What a page offers: the figure on it, and the cards its labels make.
    struct Found {
        var figure: OcclusionBox
        var cards: [AnkiCard]
    }

    /// Everything above, for one page image.
    ///
    /// The OCR pass happens first because its boxes are what keep the page's
    /// text out of the ink grid. A page with no figure - a wall of bullet
    /// points - returns nil rather than a card about its own heading.
    /// `pageBands` is off for a picture that is itself the diagram rather than
    /// a whole slide, where the top of the picture is not a page header.
    static func read(_ image: CGImage, imageIndex: Int,
                     question: String = "What is labelled here?",
                     pageBands: Bool = true) -> Found? {
        let lines = (try? RedPenOCR.read(image)) ?? []
        let grid = inkGrid(image, ignoring: lines.map(\.box))
        guard let width = grid.first?.count,
              let box = FigureGrid.figures(in: grid).first else { return nil }

        let figure = FigureGrid.normalised(box, gridWidth: width, gridHeight: grid.count)
        let labels = testableLabels(lines, on: figure, pageBands: pageBands, image: image)
        // fewer than two labels that survive is not a labelled diagram
        let cards = FigureGrid.cards(from: labels, imageIndex: imageIndex,
                                     question: question, minimumLabels: 2)
        return cards.isEmpty ? nil : Found(figure: figure, cards: cards)
    }
}
