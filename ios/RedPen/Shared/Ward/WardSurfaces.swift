#if canImport(SwiftUI)
import SwiftUI

/// Ward White with ECG grid paper over it: 8-point minor lines, 40-point
/// major ones, drawn once by Canvas. Decoration only, so VoiceOver skips it.
struct WardBackground: View {
    var grid = true

    var body: some View {
        ZStack {
            Color.wardBackground
            if grid {
                Canvas { context, size in
                    var minor = Path(), major = Path()
                    var x: CGFloat = 0
                    var i = 0
                    while x <= size.width {
                        let line = Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }
                        if i % 5 == 0 { major.addPath(line) } else { minor.addPath(line) }
                        x += 8; i += 1
                    }
                    var y: CGFloat = 0
                    i = 0
                    while y <= size.height {
                        let line = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }
                        if i % 5 == 0 { major.addPath(line) } else { minor.addPath(line) }
                        y += 8; i += 1
                    }
                    context.stroke(minor, with: .color(.wardGridMinor), lineWidth: 0.5)
                    context.stroke(major, with: .color(.wardGridMajor), lineWidth: 0.75)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A card: Clean Sheet, a hairline edge, the one shadow.
struct WardCardStyle: ViewModifier {
    var padding: CGFloat = WardSpace.gutter

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wardSurface, in: shape)
            .overlay(shape.strokeBorder(Color.wardHairline, lineWidth: 1))
            .wardShadow()
    }
}

/// The vitals monitor: Chart Ink in both modes, light text on it.
struct MonitorCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        content
            .padding(WardSpace.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.white)
            .background(Color.wardMonitor, in: shape)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func wardCard(padding: CGFloat = WardSpace.gutter) -> some View { modifier(WardCardStyle(padding: padding)) }

    /// A screen in the Ward Round language: the grid ground, Theatre Blue
    /// controls.
    func wardScreen() -> some View {
        self
            .background(WardBackground())
            .tint(Color.wardPrimary)
    }

    /// A Form or List in the language: its own ground hidden for the grid,
    /// white rows, Theatre Blue controls.
    func wardForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(WardBackground())
            .tint(Color.wardPrimary)
    }

    /// A List or Form row on Clean Sheet.
    func wardRowBackground() -> some View {
        listRowBackground(Color.wardSurface)
    }
}
#endif
