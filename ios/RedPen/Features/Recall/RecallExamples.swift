import UIKit
import PencilKit

/// A figure and a finished attempt at it, for the personal build, so Draw from
/// memory - and Compare especially - can be tried without drawing first.
///
/// The figure is a simple labelled sketch of the inguinal canal drawn in code;
/// the attempt is a rough freehand version of it built from PencilKit strokes,
/// a little off in the places a student's would be.
enum RecallExamples {
    static let key = "example-inguinal-canal"
    /// The size both the figure and the example drawing are made at.
    static let size = CGSize(width: 600, height: 400)

    static let labels = [
        "Anterior superior iliac spine",
        "Inguinal ligament",
        "Deep inguinal ring",
        "Superficial inguinal ring",
        "Pubic tubercle",
        "Spermatic cord",
    ]

    static var figure: RecallFigure {
        RecallFigure(key: key, image: image, title: "The inguinal canal", labels: labels)
    }

    /// Saves the example attempt the first time, and returns the kept one to
    /// open with.
    static func seedIfNeeded() -> RecallAttempt {
        if let kept = RecallAttempts.load(key).first { return kept }
        let attempt = RecallAttempt(date: Date().addingTimeInterval(-86_400),
                                    drawing: drawing.dataRepresentation(),
                                    width: Double(size.width), height: Double(size.height),
                                    got: Array(labels.prefix(3)), labelCount: labels.count)
        RecallAttempts.save(attempt, for: key)
        return attempt
    }

    // MARK: - The figure

    static let image: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: RecallExamples.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: RecallExamples.size))
            let ink = UIColor(red: 0.12, green: 0.2, blue: 0.45, alpha: 1)
            ink.setStroke()

            // inguinal ligament: ASIS down to the pubic tubercle
            let ligament = UIBezierPath()
            ligament.move(to: CGPoint(x: 80, y: 110))
            ligament.addQuadCurve(to: CGPoint(x: 500, y: 320), controlPoint: CGPoint(x: 260, y: 300))
            ligament.lineWidth = 5
            ligament.stroke()

            // the canal, running above and parallel to the ligament
            let canal = UIBezierPath()
            canal.move(to: CGPoint(x: 205, y: 165))
            canal.addQuadCurve(to: CGPoint(x: 445, y: 255), controlPoint: CGPoint(x: 330, y: 245))
            canal.lineWidth = 3
            canal.setLineDash([10, 6], count: 2, phase: 0)
            canal.stroke()

            // deep ring, superficial ring
            let deep = UIBezierPath(ovalIn: CGRect(x: 185, y: 145, width: 40, height: 40))
            deep.lineWidth = 3
            deep.stroke()
            let superficial = UIBezierPath(ovalIn: CGRect(x: 430, y: 240, width: 44, height: 30))
            superficial.lineWidth = 3
            superficial.stroke()

            // the spermatic cord leaving the superficial ring
            let cord = UIBezierPath()
            cord.move(to: CGPoint(x: 452, y: 270))
            cord.addQuadCurve(to: CGPoint(x: 470, y: 385), controlPoint: CGPoint(x: 440, y: 330))
            cord.lineWidth = 6
            cord.stroke()

            // ASIS and pubic tubercle as dots
            ink.setFill()
            UIBezierPath(ovalIn: CGRect(x: 72, y: 102, width: 16, height: 16)).fill()
            UIBezierPath(ovalIn: CGRect(x: 492, y: 312, width: 16, height: 16)).fill()

            let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            func label(_ text: String, _ x: CGFloat, _ y: CGFloat) {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }
            label("ASIS", 40, 70)
            label("Inguinal ligament", 150, 300)
            label("Deep ring", 150, 110)
            label("Superficial ring", 360, 205)
            label("Pubic tubercle", 470, 335)
            label("Spermatic cord", 330, 360)
        }
    }()

    // MARK: - The example attempt

    /// A freehand version: the same parts, wobbling a little, the canal
    /// drawn a touch too low and the labels left off.
    static let drawing: PKDrawing = {
        var strokes: [PKStroke] = []
        // ligament
        strokes.append(RecallExamples.stroke(RecallExamples.curve(from: CGPoint(x: 85, y: 118), to: CGPoint(x: 495, y: 330),
                                    control: CGPoint(x: 250, y: 310))))
        // canal
        strokes.append(RecallExamples.stroke(RecallExamples.curve(from: CGPoint(x: 215, y: 180), to: CGPoint(x: 440, y: 272),
                                    control: CGPoint(x: 320, y: 265))))
        // deep and superficial rings
        strokes.append(RecallExamples.stroke(RecallExamples.circle(CGPoint(x: 212, y: 175), radius: 22)))
        strokes.append(RecallExamples.stroke(RecallExamples.circle(CGPoint(x: 445, y: 268), radius: 18)))
        // cord
        strokes.append(RecallExamples.stroke(RecallExamples.curve(from: CGPoint(x: 447, y: 285), to: CGPoint(x: 460, y: 390),
                                    control: CGPoint(x: 432, y: 340))))
        // the two bony points, as small scribbled circles
        strokes.append(RecallExamples.stroke(RecallExamples.circle(CGPoint(x: 84, y: 114), radius: 6)))
        strokes.append(RecallExamples.stroke(RecallExamples.circle(CGPoint(x: 497, y: 326), radius: 6)))
        return PKDrawing(strokes: strokes)
    }()

    private static func stroke(_ points: [CGPoint]) -> PKStroke {
        let ink = PKInk(.pen, color: .black)
        var controls: [PKStrokePoint] = []
        for i in points.indices {
            let offset: TimeInterval = TimeInterval(i) * 0.01
            let upright: CGFloat = CGFloat.pi / 2
            controls.append(PKStrokePoint(location: points[i], timeOffset: offset,
                                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1,
                                          azimuth: 0, altitude: upright))
        }
        let path = PKStrokePath(controlPoints: controls, creationDate: Date())
        return PKStroke(ink: ink, path: path, transform: .identity, mask: nil)
    }

    /// Points along a quadratic curve, with a small hand-drawn wobble.
    private static func curve(from a: CGPoint, to b: CGPoint, control c: CGPoint, steps: Int = 40) -> [CGPoint] {
        // written out step by step: as one long expression it takes the
        // Swift Playgrounds compiler too long to work out the types
        var points: [CGPoint] = []
        for i in 0...steps {
            let t: CGFloat = CGFloat(i) / CGFloat(steps)
            let u: CGFloat = 1 - t
            let wA: CGFloat = u * u
            let wC: CGFloat = 2 * u * t
            let wB: CGFloat = t * t
            let wobble: CGFloat = sin(t * 17) * 2
            let x: CGFloat = wA * a.x + wC * c.x + wB * b.x
            let y: CGFloat = wA * a.y + wC * c.y + wB * b.y + wobble
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }

    private static func circle(_ centre: CGPoint, radius: CGFloat, steps: Int = 30) -> [CGPoint] {
        var points: [CGPoint] = []
        for i in 0...steps {
            let fraction: CGFloat = CGFloat(i) / CGFloat(steps)
            let angle: CGFloat = fraction * 2 * CGFloat.pi
            let r: CGFloat = radius + sin(angle * 3)
            let x: CGFloat = centre.x + cos(angle) * r
            let y: CGFloat = centre.y + sin(angle) * r
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}
