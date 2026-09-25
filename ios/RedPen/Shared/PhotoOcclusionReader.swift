// Picture cards from your own photo, screenshot or scan: the device half.
//
// A picture comes in from Photos, Files or the document camera, is shrunk to
// 2,048 pixels on its long side, flattened onto white, and read by the same
// route the heart example and the lecture diagrams use: Vision reads the
// words (RedPenOCR), OcclusionPhrases groups them into whole labels,
// OcclusionFilter keeps the testable ones, and each gets one cover. The
// student then moves, stretches, adds or deletes covers before saving.
//
// Everything here is slow (decoding, OCR) and is only ever called off the
// main thread. The decisions live in PhotoOcclusion, which is tested.
import Foundation
import UIKit
import ImageIO
import CoreGraphics

/// One picture being turned into cards.
struct PhotoPage: Identifiable {
    let id: UUID = UUID()
    /// The picture as it will be kept: a JPEG, at most 2,048 pixels across.
    var jpeg: Data
    /// Decoded lazily from `jpeg` when drawn, so ten pages waiting in the
    /// strip are not ten bitmaps in memory.
    var preview: UIImage?
    var pixelWidth: Int
    var pixelHeight: Int
    /// What Vision read, kept so the covers can be placed again another way
    /// without reading the picture twice.
    var lines: [OCRLine]
    var covers: [PhotoOcclusion.Cover]
    /// A page from the document camera: a whole page, with a title and a
    /// footer that are not labels.
    var scanned: Bool

    /// Width over height, for drawing and for a new cover's shape.
    var aspect: Double {
        pixelHeight > 0 ? Double(pixelWidth) / Double(pixelHeight) : 1
    }

    /// The page's words, one line each, for the lecture it can become.
    var text: String {
        PhotoOcclusion.pageText(lines.map(\.text))
    }
}

enum PhotoOcclusionReader {

    /// Where the covers are looked for.
    enum Placement {
        /// Every label anywhere on the picture - a photo or screenshot of a
        /// diagram, where the picture is the figure.
        case wholePicture
        /// Only the labels on the page's biggest drawing, leaving out its
        /// title, body text and footer - a scanned page or a whole slide.
        case diagramOnly
    }

    // MARK: - In

    /// A picture's bytes (Photos, Files): decoded straight to its kept size
    /// and turned upright, then read. Nil when it is not a picture.
    static func read(data: Data, scanned: Bool) -> PhotoPage? {
        guard let small = thumbnail(data) else { return nil }
        return read(small, scanned: scanned)
    }

    /// A picture file picked in Files, borrowed for as long as it is read.
    static func read(fileAt url: URL) -> PhotoPage? {
        let scoped: Bool = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return read(data: data, scanned: false)
    }

    /// A page from the document camera, already upright.
    static func read(image: UIImage, scanned: Bool) -> PhotoPage? {
        if image.imageOrientation == .up, let cg = image.cgImage {
            return read(cg, scanned: scanned)
        }
        // turned: let ImageIO apply the turn on the way through
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
        return read(data: data, scanned: scanned)
    }

    /// The shared route once a picture is decoded.
    private static func read(_ image: CGImage, scanned: Bool) -> PhotoPage? {
        guard let flat = flattened(image),
              let jpeg = UIImage(cgImage: flat).jpegData(compressionQuality: 0.85) else { return nil }
        let lines: [OCRLine] = FigureFinder.plausible(width: flat.width, height: flat.height)
            ? ((try? RedPenOCR.read(flat)) ?? []) : []
        let placement: Placement = scanned ? .diagramOnly : .wholePicture
        let covers: [PhotoOcclusion.Cover] = place(lines, on: flat, placement)
        return PhotoPage(jpeg: jpeg, preview: UIImage(data: jpeg),
                         pixelWidth: flat.width, pixelHeight: flat.height,
                         lines: lines, covers: covers, scanned: scanned)
    }

    /// The covers placed again, another way, from what was already read.
    static func replaced(_ page: PhotoPage, _ placement: Placement) -> [PhotoOcclusion.Cover] {
        guard let image = UIImage(data: page.jpeg)?.cgImage else { return page.covers }
        return place(page.lines, on: image, placement)
    }

    // MARK: - Covers

    /// One cover per testable label, as the heart example places them.
    /// Asked for the diagram only, the page's biggest drawing is found first
    /// (as for a lecture slide); when there is none, or it carries no labels,
    /// the whole picture is used rather than giving nothing.
    static func place(_ lines: [OCRLine], on image: CGImage,
                      _ placement: Placement) -> [PhotoOcclusion.Cover] {
        guard !lines.isEmpty else { return [] }
        if placement == .diagramOnly, let figure = figure(on: image, lines: lines) {
            let found: [OcclusionPhrases.Cover] = FigureFinder.covers(lines, on: figure,
                                                                      pageBands: true, image: image)
            if !found.isEmpty { return PhotoOcclusion.covers(from: found) }
        }
        let whole = OcclusionBox(x: 0, y: 0, w: 1, h: 1)
        let found: [OcclusionPhrases.Cover] = FigureFinder.covers(lines, on: whole,
                                                                  pageBands: false, image: image)
        return PhotoOcclusion.covers(from: found)
    }

    /// The page's biggest drawing, with its text taken out first so the body
    /// of a page is not taken for a figure.
    private static func figure(on image: CGImage, lines: [OCRLine]) -> OcclusionBox? {
        let grid: [[Bool]] = FigureFinder.inkGrid(image, ignoring: lines.map(\.box))
        guard let width = grid.first?.count, let cells = FigureGrid.figures(in: grid).first
        else { return nil }
        return FigureGrid.normalised(cells, gridWidth: width, gridHeight: grid.count)
    }

    // MARK: - Pixels

    /// Decoded at no more than the kept size, never the full 12 or 48
    /// megapixels, and turned by its EXIF orientation.
    static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var longest: Int = PhotoOcclusion.maxSide
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w: Int = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let h: Int = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0
            let fit = PhotoOcclusion.fitted(width: w, height: h)
            let side: Int = max(fit.width, fit.height)
            if side > 0 { longest = side }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The picture at its kept size, on white: a JPEG has no transparency,
    /// and a screenshot or a diagram saved as a transparent PNG otherwise
    /// comes out black on black.
    static func flattened(_ image: CGImage) -> CGImage? {
        let fit = PhotoOcclusion.fitted(width: image.width, height: image.height)
        guard fit.width > 0, fit.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: fit.width, height: fit.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let frame = CGRect(x: 0, y: 0, width: fit.width, height: fit.height)
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(frame)
        context.interpolationQuality = .high
        context.draw(image, in: frame)
        return context.makeImage()
    }
}

// MARK: - Scanned pages as a lecture

extension SourceIngest {

    /// Scanned pages kept as a lecture, like any lecture file: a PDF of the
    /// pages, kept on this device (SourceFiles) so the Sources page can show
    /// them, and the words Vision already read as the lecture's text, put
    /// through the same clean-up an imported PDF's pages get (SourceText),
    /// so nothing is read twice. Nil when no page had any words.
    static func lecture(fromScans pages: [(jpeg: Data, text: String)], name: String) async -> SourceDoc? {
        let raw: [(number: Int, text: String, recognised: Bool)] = pages.enumerated().map {
            (number: $0.offset + 1, text: $0.element.text, recognised: true)
        }
        let document: SourceText.Document = SourceText.document(from: raw)
        guard !document.isEmpty else { return nil }
        let jpegs: [Data] = pages.map(\.jpeg)
        let blob: String? = await Task.detached(priority: .userInitiated) { () -> String? in
            guard let url = scanPDF(jpegs, name: name) else { return nil }
            defer { try? FileManager.default.removeItem(at: url) }
            return SourceFiles.keep(url, kind: .pdf)
        }.value
        let read = ReadSource(name: name, document: document, kind: .pdf, fileBlob: blob)
        return read.doc()
    }

    /// The pages as one PDF in the temporary folder, each page the picture's
    /// own shape, about A4 on its long side.
    static func scanPDF(_ jpegs: [Data], name: String) -> URL? {
        let pictures: [UIImage] = jpegs.compactMap { UIImage(data: $0) }
        guard let first = pictures.first else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect(first))
        do {
            try renderer.writePDF(to: url) { context in
                for picture in pictures {
                    let rect: CGRect = pageRect(picture)
                    context.beginPage(withBounds: rect, pageInfo: [:])
                    picture.draw(in: rect)
                }
            }
        } catch {
            return nil
        }
        return url
    }

    private static func pageRect(_ picture: UIImage) -> CGRect {
        let long: CGFloat = 842
        let w: CGFloat = max(picture.size.width, 1)
        let h: CGFloat = max(picture.size.height, 1)
        let scale: CGFloat = long / max(w, h)
        return CGRect(x: 0, y: 0, width: (w * scale).rounded(), height: (h * scale).rounded())
    }
}
