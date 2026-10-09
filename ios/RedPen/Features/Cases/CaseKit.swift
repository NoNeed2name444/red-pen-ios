import SwiftUI

// What the Cases screens add to the Ward kit (Shared/Ward, the chart's views
// in ChartQuizViews): the case's own names for the kit's tokens, the patient's
// avatar, the clock in minutes, and the case's observations and results
// handed to the chart's vitals grid and results table.

/// The Ward Round tokens as the Cases screens use them.
enum CaseInk {
    static let theatre: Color = .wardPrimaryInk
    static let resus: Color = .wardDanger
    static let discharge: Color = .wardSuccess
    static let caution: Color = .wardWarning
    static let biro: Color = .wardInkSecondary
    static let surface: Color = .wardSurface
    static let ward: Color = .wardBackground
    static let hairline: Color = .wardHairline
}

extension View {
    /// A Clean Sheet card (WardCardStyle), full width.
    func caseCard(padding: CGFloat = WardSpace.gutter) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .wardCard(padding: padding)
    }
}

/// A small heading in the kit's small capitals, read as a heading.
struct CaseLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .wardSmallCaps()
            .accessibilityAddTraits(.isHeader)
    }
}

/// The initials in a circle pressed into the card, for the patient.
struct CaseAvatar: View {
    let initials: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.wardPrimaryInk)
            .frame(width: size, height: size)
            .wardInset(in: Circle())
            .accessibilityHidden(true)
    }
}

/// The case's clock: minutes used of the budget, in SF Mono, drawn like the
/// kit's timer pill. Resus Red once past the budget, which the student may go
/// beyond (the debrief counts it).
struct CaseClockPill: View {
    let used: Int
    let budget: Int

    private var over: Bool { used > budget }

    var body: some View {
        Label(used == 0 ? "\(budget) min" : "\(used) / \(budget) min", systemImage: over ? "exclamationmark.circle.fill" : "clock")
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .monospacedDigit()
            .contentTransition(.identity)
            .foregroundStyle(over ? Color.wardDanger : Color.wardInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // pressed in, like the kit's timer pill: read, not touched
            .wardInset(in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    private var spoken: String {
        if used == 0 { return "Time allowed: \(budget) minutes" }
        if over { return "Clock: \(used) minutes used, \(used - budget) over the \(budget) allowed" }
        return "Clock: \(used) of \(budget) minutes used"
    }
}

/// The arrival observations in the chart's vitals grid, flagged H or L.
struct CaseVitalsGrid: View {
    let obs: [CaseFile.Obs]

    var body: some View {
        ChartVitalsGrid(vitals: obs.map(\.chartVital))
    }
}

/// Test values in the chart's results table, flagged H or L.
struct CaseResultsTable: View {
    let results: [CaseStep.LabResult]

    var body: some View {
        ChartLabsTable(labs: results.map(\.chartLab))
    }
}

extension CaseFile.Obs {
    /// The observation as the chart shows one.
    var chartVital: PatientChart.Vital {
        let unit: String = sign == .temp ? " \u{00B0}C" : (sign == .spo2 ? "%" : "")
        return PatientChart.Vital(label: sign.label, value: shown + unit, flag: CaseChart.flag(self).map(\.chart))
    }
}

extension CaseStep.LabResult {
    /// The result as the chart's table shows one.
    var chartLab: PatientChart.Lab {
        PatientChart.Lab(name: name, value: CaseFile.Obs.number(value), unit: unit, flag: CaseChart.flag(self).map(\.chart))
    }
}

extension CaseChart.Flag {
    var chart: PatientChart.Flag { self == .high ? .high : .low }
}

/// The state chip on a patient's card.
struct CaseStateChip: View {
    let state: CaseRun.State

    var body: some View {
        switch state {
        case .new: WardChip(text: "New", tone: .blue)
        case .seen: WardChip(text: "Seen", tone: .warning)
        case .discharged(let score): WardChip(text: "Discharged \u{00B7} \(score)", tone: .green)
        }
    }
}
