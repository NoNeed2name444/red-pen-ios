import SwiftUI

/// The app's own identity, kept in one place.
///
/// The name is CramDown, and it is about compression rather than panic: a
/// term's worth of lectures pressed down into the few hundred things that
/// actually fit in a head on the morning of a final. The app's whole method -
/// spacing the work so it peaks on the day - is the opposite of an all-nighter,
/// and the identity should say "compressed", not "frantic".
///
/// Which is why the brand itself is quiet. The six modes already carry strong
/// colours, and a seventh strong colour competing with them is what made the
/// old identity feel scattered: the app's own red sat on top of a green OSCE
/// station. So the brand is graphite and paper, and the colour on any given
/// screen belongs to the mode you are in. The one exception is `signal`, used
/// for the count-down to exam day - the only thing that should ever shout.
enum Brand {
    static let name = "CramDown"

    /// The tagline, where there is room for one.
    static let line = "Everything, pressed down to what fits."

    /// Near-black with a trace of blue: ink on paper, not a pure grey.
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)

    /// The page. Warm rather than white, so long reading is easy on the eye.
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    /// Used for exactly one thing: how long is left.
    static let signal = Color(red: 0.90, green: 0.33, blue: 0.17)

    /// The mark: three stacked rules pressed down into one.
    ///
    /// Drawn rather than shipped as an image so it stays sharp at any size and
    /// picks up whatever colour the screen it sits on is using.
    struct Mark: View {
        var size: CGFloat = 28
        var tint: Color = Brand.ink

        var body: some View {
            Canvas { context, canvasSize in
                let w = canvasSize.width, h = canvasSize.height
                // Three bars, each shorter and closer to the one below it:
                // material being compressed towards a single line.
                let widths: [CGFloat] = [1.0, 0.74, 0.48]
                let tops: [CGFloat] = [0.10, 0.34, 0.54]
                for (i, ratio) in widths.enumerated() {
                    let bar = CGRect(x: (w - w * ratio) / 2, y: h * tops[i],
                                     width: w * ratio, height: h * 0.11)
                    context.fill(Path(roundedRect: bar, cornerRadius: h * 0.055),
                                 with: .color(tint.opacity(1 - Double(i) * 0.22)))
                }
                // and the point they are pressed into
                var arrow = Path()
                arrow.move(to: CGPoint(x: w * 0.30, y: h * 0.74))
                arrow.addLine(to: CGPoint(x: w * 0.50, y: h * 0.94))
                arrow.addLine(to: CGPoint(x: w * 0.70, y: h * 0.74))
                context.stroke(arrow, with: .color(tint),
                               style: StrokeStyle(lineWidth: h * 0.11,
                                                  lineCap: .round, lineJoin: .round))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
