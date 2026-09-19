import SwiftUI

// MARK: - Visual identity
//
// Every mode has its own colour (the same tints the web app uses for its
// mode chips), an SF Symbol, and a soft gradient. Screens set `.tint(kind.tint)`
// so the glass buttons, progress bars and chips all pick it up, and sit on a
// `ModeBackdrop` — a faint wash of that colour — so Liquid Glass has
// something to refract instead of a flat white sheet.

extension StudySetKind {
    var tint: Color {
        switch self {
        case .mcq: return Color(red: 0.78, green: 0.16, blue: 0.16)     // pen red
        case .anki: return Color(red: 0.31, green: 0.36, blue: 0.86)    // indigo
        case .book: return Color(red: 0.10, green: 0.55, blue: 0.50)    // teal
        case .qa: return Color(red: 0.90, green: 0.49, blue: 0.13)      // amber
        case .osce: return Color(red: 0.20, green: 0.62, blue: 0.35)    // green
        case .narrate: return Color(red: 0.55, green: 0.32, blue: 0.80) // violet
        }
    }

    var symbol: String {
        switch self {
        case .mcq: return "checklist.checked"
        case .anki: return "rectangle.on.rectangle.angled"
        case .book: return "book.pages"
        case .qa: return "stethoscope"
        case .osce: return "list.clipboard"
        case .narrate: return "waveform"
        }
    }

    /// Steps inside the mode's OWN hue, for controls that must be told apart
    /// from one another.
    ///
    /// The four Anki rating buttons used to be red, orange, green and blue -
    /// a traffic light borrowed wholesale from three other modes' identities,
    /// sitting inside an indigo screen. Distinguishing four buttons does not
    /// require four unrelated colours: depth inside one hue does it, and the
    /// screen stays one colour. Anything that carries real meaning of its own
    /// (a right answer, an error) keeps its own colour; this is for controls
    /// that are merely different from each other.
    func step(_ i: Int, of n: Int = 4) -> Color {
        guard n > 1 else { return tint }
        let t = Double(min(max(i, 0), n - 1)) / Double(n - 1)   // 0 ... 1
        return shifted(brightness: 0.34 * (1 - t) - 0.16 * t,
                       saturation: -0.30 * (1 - t))
    }

    /// The same hue, lighter or darker, for washes and quiet states.
    func shifted(brightness: Double, saturation: Double = 0) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(tint).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return tint }
        return Color(hue: Double(h),
                     saturation: min(1, max(0, Double(s) + saturation)),
                     brightness: min(1, max(0, Double(b) + brightness)),
                     opacity: Double(a))
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [tint, tint.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The tinted icon tile used on library rows and screen headers.
struct ModeTile: View {
    let kind: StudySetKind
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(
                // a glossy top-edge highlight so the tile reads as a lit object
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .padding(1)
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
            .shadow(color: kind.tint.opacity(0.42), radius: 9, y: 5)
            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
    }
}

/// A faint wash of the mode's colour behind a whole screen. Two soft blobs
/// top-right and bottom-left, over the system grouped background, so it
/// stays quiet in both light and dark mode.
struct ModeBackdrop: View {
    let kind: StudySetKind
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            // two soft blobs that drift very slowly, so the glass above them
            // has something living to refract
            RadialGradient(colors: [kind.tint.opacity(scheme == .dark ? 0.30 : 0.22), .clear],
                           center: .init(x: drift ? 0.85 : 0.98, y: drift ? 0.08 : -0.02), startRadius: 0, endRadius: 440)
            RadialGradient(colors: [kind.tint.opacity(scheme == .dark ? 0.20 : 0.13), .clear],
                           center: .init(x: drift ? 0.12 : 0.02, y: drift ? 0.92 : 1.04), startRadius: 0, endRadius: 400)
            RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.0 : 0.35), .clear],
                           center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// A content card: the reading surface each mode places its question, card
/// or page on. Rounded, elevated a touch off the backdrop.
struct ContentCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
                    .blendMode(.plusLighter)
            )
            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)   // contact shadow
            .shadow(color: .black.opacity(0.07), radius: 16, y: 8)    // ambient lift
    }
}

extension View {
    func contentCard() -> some View { modifier(ContentCard()) }

    /// Standard chrome for a mode screen: mode tint + tinted backdrop.
    func modeScreen(_ kind: StudySetKind) -> some View {
        self
            .background(ModeBackdrop(kind: kind))
            .tint(kind.tint)
    }

    /// Slides up and fades in on first appearance, staggered by `index` so
    /// a list of rows arrives as a cascade rather than all at once.
    func riseIn(index: Int = 0) -> some View { modifier(RiseIn(index: index)) }
}

/// A tappable row that squashes a touch under the finger — the tactile
/// feedback Liquid Glass buttons have, for our custom rows.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
extension ButtonStyle where Self == PressableRowStyle {
    static var pressableRow: PressableRowStyle { PressableRowStyle() }
}

struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

/// A thin, rounded, tinted progress bar — replaces the stock `ProgressView`
/// so every mode's progress reads the same way.
struct ThinProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(.tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// The animated score ring on the MCQ results screen.
struct ScoreRing: View {
    let fraction: Double
    let label: String
    let sublabel: String
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle()
                .trim(from: 0, to: shown)
                // `.tint` rather than the app accent: the ring belongs to the
                // screen it is on, and the accent is whatever mode happens to
                // be the app's default.
                .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            VStack(spacing: 2) {
                Text(label).font(.system(size: 38, weight: .bold, design: .rounded))
                Text(sublabel).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 168, height: 168)
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.72)) { shown = fraction } }
    }
}
