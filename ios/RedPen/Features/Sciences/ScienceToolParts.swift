import SwiftUI

// The parts every Sciences tool is built from, written the way the ward
// pocket's calculators write theirs (WardCalcView): a list in the soft UI,
// the values to change, the result, how it is worked out, and the
// learning-only line at the foot. The plots are Swift Charts in a list row,
// as Vitals has them.

/// A tool's page: the list, its inline title and the learning-only line.
struct ScienceToolPage<Content: View>: View {
    let tool: ScienceTool
    @ViewBuilder let content: () -> Content

    var body: some View {
        List {
            content()
        }
        .wardForm()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tool.name)
        .navigationBarTitleDisplayMode(.inline)
        .wardDisclaimer()
        .accessibilityIdentifier("scienceToolPage-\(tool.rawValue)")
    }
}

/// A plot with its name above and what to read from it below. The plot is
/// read aloud as one sentence (`spoken`), as Vitals' charts are.
struct ScienceFigure<Plot: View>: View {
    let title: String
    var caption: String?
    let spoken: String
    @ViewBuilder let plot: () -> Plot

    /// Taller than Vitals' 150: here the plot is the page.
    static var height: CGFloat { 220 }

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.wardInk)
            plot()
                .frame(height: Self.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.wardInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, WardSpace.xs)
    }
}

/// A value to change: its name, what it is now, and the slider under them
/// (as Settings writes its link-length slider).
struct ScienceSlider: View {
    let name: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// What it is now, with its unit: "4.0 mmol/L".
    let shown: String

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            HStack {
                Text(name)
                Spacer()
                Text(shown)
                    .monospacedDigit()
                    .foregroundStyle(Color.wardInkSecondary)
            }
            Slider(value: $value, in: range, step: step) {
                Text(name)
            }
            .accessibilityValue(shown)
        }
    }
}

/// One figure of a result, as the ward pocket shows one.
struct ScienceReading: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(WardType.obsLarge)
                .monospacedDigit()
                .foregroundStyle(Color.wardInk)
        }
    }
}

/// What a result means, under its figures.
struct ScienceVerdict: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.wardInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A block of text under a heading: how it is worked out, what to keep in
/// mind (the ward pocket's text sections).
struct ScienceTextSection: View {
    let title: String
    let text: String

    var body: some View {
        if !text.isEmpty {
            Section(title) {
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .wardRowBackground()
        }
    }
}

/// An entry in a table of facts: a name, and a line or more under it, each
/// with its label ("Looks", "Where").
struct ScienceFact: View {
    let title: String
    var subtitle: String?
    let lines: [(label: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.wardInk)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let label = Text(line.label).font(.caption.weight(.semibold)).foregroundColor(Color.wardInkSecondary)
                Text("\(label)  \(line.text)")
                    .font(.subheadline)
                    .foregroundStyle(Color.wardInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, WardSpace.xs)
        .accessibilityElement(children: .combine)
    }
}

/// A ready-made case to load: a row that sets the values.
struct SciencePresetButton: View {
    let title: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WardSpace.xs) {
                Text(title).foregroundStyle(Color.wardPrimaryInk)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Color.wardInkSecondary)
                }
            }
        }
        .accessibilityIdentifier("sciencePreset-\(title)")
    }
}

/// A number with a fixed count of decimals: "4.0", "-90".
func scienceNumber(_ x: Double, _ digits: Int = 0) -> String {
    guard x.isFinite else { return "\u{2014}" }
    return x.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
}

/// A share as a percentage: "62%".
func sciencePercent(_ x: Double, _ digits: Int = 0) -> String {
    scienceNumber(x * 100, digits) + "%"
}
