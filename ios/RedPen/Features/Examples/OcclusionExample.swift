import SwiftUI
import UIKit

/// The image occlusion example: a labelled schematic of the heart, drawn in
/// code so no picture or licence has to ship, and turned into cards by the
/// app's real route - Vision reads the labels, OcclusionPhrases groups the
/// words into whole labels, OcclusionFilter keeps the testable ones, and each
/// label gets one cover whose answer is exactly the words under it.
///
/// Some labels are several words ("Right atrium") and some wrap onto two
/// lines ("Superior vena" / "cava"), so one cover per label can be seen doing
/// its job. It replaces the inguinal canal diagram from the bundled lecture,
/// whose labels were not in English.
enum OcclusionExample {

    static let setName = "Example: The heart - image occlusion"
    static let title = "The heart"
    /// The drawing's size in points; it is rendered at twice this.
    static let size = CGSize(width: 900, height: 640)

    /// A label drawn on the diagram: its lines, where its first line starts
    /// (the right edge for the left-hand column), and the point its leader
    /// line reaches on the drawing.
    struct DrawnLabel {
        var lines: [String]
        var x: CGFloat
        var y: CGFloat
        var rightAligned: Bool
        var target: CGPoint
    }

    static let fontSize: CGFloat = 22
    /// Line pitch for a label that wraps: tight, as a label is set.
    static let linePitch: CGFloat = 25

    static let labels: [DrawnLabel] = [
        // the patient's right, on the left of the picture
        DrawnLabel(lines: ["Superior vena", "cava"], x: 190, y: 70, rightAligned: true,
              target: CGPoint(x: 296, y: 120)),
        DrawnLabel(lines: ["Right atrium"], x: 190, y: 245, rightAligned: true,
              target: CGPoint(x: 262, y: 262)),
        DrawnLabel(lines: ["Tricuspid valve"], x: 190, y: 345, rightAligned: true,
              target: CGPoint(x: 330, y: 364)),
        DrawnLabel(lines: ["Right ventricle"], x: 190, y: 440, rightAligned: true,
              target: CGPoint(x: 340, y: 452)),
        DrawnLabel(lines: ["Inferior vena", "cava"], x: 190, y: 548, rightAligned: true,
              target: CGPoint(x: 272, y: 572)),
        // the patient's left, on the right of the picture
        DrawnLabel(lines: ["Aorta"], x: 700, y: 58, rightAligned: false,
              target: CGPoint(x: 560, y: 84)),
        DrawnLabel(lines: ["Pulmonary", "trunk"], x: 700, y: 150, rightAligned: false,
              target: CGPoint(x: 494, y: 214)),
        DrawnLabel(lines: ["Left atrium"], x: 700, y: 255, rightAligned: false,
              target: CGPoint(x: 590, y: 268)),
        DrawnLabel(lines: ["Mitral valve"], x: 700, y: 335, rightAligned: false,
              target: CGPoint(x: 560, y: 334)),
        DrawnLabel(lines: ["Left ventricle"], x: 700, y: 430, rightAligned: false,
              target: CGPoint(x: 585, y: 440)),
        DrawnLabel(lines: ["Interventricular", "septum"], x: 700, y: 540, rightAligned: false,
              target: CGPoint(x: 450, y: 500)),
    ]

    // MARK: - The drawing

    /// The schematic, drawn with Core Graphics. Anterior view: the right
    /// side of the heart (blue) on the left of the picture.
    static func image() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg: CGContext = context.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: size))
            drawHeart(cg)
            for label in labels { draw(label, in: cg) }
        }
    }

    static let blue = UIColor(red: 0.16, green: 0.33, blue: 0.62, alpha: 1)
    static let paleBlue = UIColor(red: 0.80, green: 0.87, blue: 0.97, alpha: 1)
    static let red = UIColor(red: 0.70, green: 0.15, blue: 0.15, alpha: 1)
    static let paleRed = UIColor(red: 0.98, green: 0.84, blue: 0.83, alpha: 1)
    static let ink = UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1)
    static let leader = UIColor(red: 0.35, green: 0.37, blue: 0.42, alpha: 1)

    private static func drawHeart(_ cg: CGContext) {
        cg.setLineJoin(.round)
        cg.setLineCap(.round)

        // right pulmonary artery, behind the ascending aorta
        tube(cg, from: CGPoint(x: 488, y: 196), to: CGPoint(x: 360, y: 186),
             control: CGPoint(x: 430, y: 176), width: 22, fill: paleBlue, edge: blue)

        // aorta: up from the left ventricle, to the patient's right of the
        // pulmonary trunk, arching over it to the left and down behind
        let aorta = CGMutablePath()
        aorta.move(to: CGPoint(x: 462, y: 350))
        aorta.addCurve(to: CGPoint(x: 430, y: 130), control1: CGPoint(x: 440, y: 290),
                       control2: CGPoint(x: 420, y: 190))
        aorta.addCurve(to: CGPoint(x: 590, y: 120), control1: CGPoint(x: 450, y: 50),
                       control2: CGPoint(x: 570, y: 50))
        aorta.addCurve(to: CGPoint(x: 612, y: 330), control1: CGPoint(x: 612, y: 190),
                       control2: CGPoint(x: 612, y: 260))
        stroke(cg, aorta, width: 40, fill: paleRed, edge: red)

        // superior and inferior vena cava, into the right atrium
        roundedTube(cg, CGRect(x: 276, y: 60, width: 44, height: 180), fill: paleBlue, edge: blue)
        roundedTube(cg, CGRect(x: 250, y: 340, width: 44, height: 270), fill: paleBlue, edge: blue)

        // the atria
        chamber(cg, CGPath(roundedRect: CGRect(x: 232, y: 214, width: 172, height: 142),
                           cornerWidth: 54, cornerHeight: 54, transform: nil),
                fill: paleBlue, edge: blue)
        chamber(cg, CGPath(roundedRect: CGRect(x: 476, y: 206, width: 150, height: 124),
                           cornerWidth: 48, cornerHeight: 48, transform: nil),
                fill: paleRed, edge: red)

        // the ventricles, the septum between them
        let right = CGMutablePath()
        right.move(to: CGPoint(x: 300, y: 372))
        right.addLine(to: CGPoint(x: 444, y: 372))
        right.addLine(to: CGPoint(x: 444, y: 556))
        right.addQuadCurve(to: CGPoint(x: 300, y: 420), control: CGPoint(x: 330, y: 540))
        right.closeSubpath()
        chamber(cg, right, fill: paleBlue, edge: blue)
        let left = CGMutablePath()
        left.move(to: CGPoint(x: 456, y: 344))
        left.addLine(to: CGPoint(x: 626, y: 344))
        left.addQuadCurve(to: CGPoint(x: 470, y: 594), control: CGPoint(x: 646, y: 540))
        left.addLine(to: CGPoint(x: 456, y: 566))
        left.closeSubpath()
        chamber(cg, left, fill: paleRed, edge: red)
        cg.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor)
        cg.fill(CGRect(x: 444, y: 372, width: 12, height: 190))

        // pulmonary trunk: up out of the right ventricle, in front
        tube(cg, from: CGPoint(x: 420, y: 378), to: CGPoint(x: 490, y: 200),
             control: CGPoint(x: 470, y: 300), width: 34, fill: paleBlue, edge: blue)
        // left pulmonary artery
        tube(cg, from: CGPoint(x: 490, y: 202), to: CGPoint(x: 640, y: 176),
             control: CGPoint(x: 560, y: 176), width: 22, fill: paleBlue, edge: blue)

        // tricuspid valve: three cusps between right atrium and ventricle
        leaflets(cg, from: 316, to: 412, y: 364, count: 3, colour: blue)
        // mitral valve: two cusps between left atrium and ventricle
        leaflets(cg, from: 512, to: 596, y: 337, count: 2, colour: red)
    }

    private static func chamber(_ cg: CGContext, _ path: CGPath, fill: UIColor, edge: UIColor) {
        cg.addPath(path)
        cg.setFillColor(fill.cgColor)
        cg.fillPath()
        cg.addPath(path)
        cg.setStrokeColor(edge.cgColor)
        cg.setLineWidth(3)
        cg.strokePath()
    }

    /// A vessel: a thick outlined stroke along a path.
    private static func stroke(_ cg: CGContext, _ path: CGPath, width: CGFloat,
                               fill: UIColor, edge: UIColor) {
        cg.addPath(path)
        cg.setStrokeColor(edge.cgColor)
        cg.setLineWidth(width + 6)
        cg.strokePath()
        cg.addPath(path)
        cg.setStrokeColor(fill.cgColor)
        cg.setLineWidth(width)
        cg.strokePath()
    }

    private static func tube(_ cg: CGContext, from: CGPoint, to: CGPoint, control: CGPoint,
                             width: CGFloat, fill: UIColor, edge: UIColor) {
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)
        stroke(cg, path, width: width, fill: fill, edge: edge)
    }

    private static func roundedTube(_ cg: CGContext, _ rect: CGRect, fill: UIColor, edge: UIColor) {
        let radius: CGFloat = rect.width / 2
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        chamber(cg, path, fill: fill, edge: edge)
    }

    /// Valve cusps: small arcs hanging from the line between two chambers.
    private static func leaflets(_ cg: CGContext, from: CGFloat, to: CGFloat, y: CGFloat,
                                 count: Int, colour: UIColor) {
        cg.setStrokeColor(colour.cgColor)
        cg.setLineWidth(4)
        let step: CGFloat = (to - from) / CGFloat(count)
        for i in 0..<count {
            let start: CGFloat = from + step * CGFloat(i)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: start + 4, y: y - 6))
            path.addQuadCurve(to: CGPoint(x: start + step - 4, y: y - 6),
                              control: CGPoint(x: start + step / 2, y: y + 16))
            cg.addPath(path)
            cg.strokePath()
        }
    }

    private static func draw(_ label: DrawnLabel, in cg: CGContext) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        var widest: CGFloat = 0
        for (i, line) in label.lines.enumerated() {
            let text = line as NSString
            let width: CGFloat = text.size(withAttributes: attributes).width
            widest = max(widest, width)
            let left: CGFloat = label.rightAligned ? label.x - width : label.x
            let top: CGFloat = label.y + linePitch * CGFloat(i)
            text.draw(at: CGPoint(x: left, y: top), withAttributes: attributes)
        }
        // the leader line leaves from beside the first line, away from the text
        let middle: CGFloat = label.y + linePitch / 2
        let start = CGPoint(x: label.rightAligned ? label.x + 10 : label.x - 10, y: middle)
        cg.setStrokeColor(leader.cgColor)
        cg.setLineWidth(1.5)
        cg.move(to: start)
        cg.addLine(to: label.target)
        cg.strokePath()
        cg.setFillColor(leader.cgColor)
        cg.fillEllipse(in: CGRect(x: label.target.x - 3.5, y: label.target.y - 3.5, width: 7, height: 7))
    }

    // MARK: - The real route

    /// The example set, made the way any picture becomes cards: OCR, whole
    /// labels, the testable ones kept, one cover each. Seconds of work, so it
    /// is called off the main thread.
    static func make() -> StudySet? {
        let picture: UIImage = image()
        guard let cg = picture.cgImage,
              let lines = try? RedPenOCR.read(cg) else { return nil }
        // the picture is the diagram itself: no page header, no search for a
        // figure on a slide
        let whole = OcclusionBox(x: 0, y: 0, w: 1, h: 1)
        let covers: [OcclusionPhrases.Cover] = FigureFinder.covers(lines, on: whole,
                                                                   pageBands: false, image: cg)
        var cards: [AnkiCard] = OcclusionPhrases.cards(from: covers, imageIndex: 0)
        guard !cards.isEmpty, let data = picture.pngData() else { return nil }
        for i in cards.indices { cards[i].source = "Heart schematic (drawn in the app)" }
        var set = StudySet(name: setName, subject: "Cardiology", kind: .anki)
        set.cards = cards
        set.images = [data.base64EncodedString()]
        return set
    }

    /// Puts the example in a personal build's Examples folder, once, in place
    /// of the image occlusion set the bundled lecture used to make.
    @MainActor
    static func seed(into store: Store) async {
        let flag = "occlusionExample.heart.v1"
        guard PersonalBuild.isOn, !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        guard let made = await Task.detached(priority: .background, operation: { () -> StudySet? in
            make()
        }).value else { return }
        keep(made, in: store)
    }

    /// Stores a freshly made example: over the kept one when there is one
    /// (so it keeps its place and id), otherwise new in the Examples folder.
    /// The lecture's old occlusion example goes, since this replaces it.
    @MainActor
    static func keep(_ made: StudySet, in store: Store) {
        let replaced: [UUID] = store.library.filter {
            $0.name.hasPrefix("Example: ") && $0.name.hasSuffix(" - image occlusion") && $0.name != setName
        }.map(\.id)
        for id in replaced { store.deleteSet(id) }
        if var kept = store.library.first(where: { $0.name == setName }) {
            kept.cards = made.cards
            kept.images = made.images
            store.update(kept)
            return
        }
        let folder = store.folders.first { $0.name.hasPrefix("Examples") }
            ?? { () -> StudyFolder in
                let fresh = StudyFolder(name: "Examples - try every mode")
                store.folders.append(fresh)
                return fresh
            }()
        var copy = made
        copy.folderId = folder.id
        store.addSet(copy)
    }
}

/// Opens the heart example: runs the whole route on the drawing each time,
/// so what is shown is what the app really does, then reviews the cards.
struct OcclusionExampleView: View {
    @EnvironmentObject private var store: Store
    @State private var made: StudySet?
    @State private var failed = false

    var body: some View {
        Group {
            if let made {
                AnkiReviewView(set: made)
            } else if failed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("The diagram's labels could not be read on this device.")
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading the heart diagram\u{2019}s labels\u{2026}")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(OcclusionExample.title)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard made == nil else { return }
        let result: StudySet? = await Task.detached(priority: .userInitiated, operation: { () -> StudySet? in
            OcclusionExample.make()
        }).value
        guard let result else {
            failed = true
            return
        }
        if PersonalBuild.isOn {
            OcclusionExample.keep(result, in: store)
        }
        made = store.library.first { $0.name == OcclusionExample.setName } ?? result
    }
}
