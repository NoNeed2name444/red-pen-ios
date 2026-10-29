import Charts
import SwiftUI

// The pathology, pharmacology and biostatistics tools, on Shared/Sciences
// (Pathology, Pharmacokinetics, Biostatistics).

// MARK: - Shock

struct ShockTool: View {
    @State private var output: ShockTrend = .down
    @State private var resistance: ShockTrend = .up
    @State private var wedge: ShockTrend = .down

    private static let choices: [ShockTrend] = [.down, .normal, .up]

    private func word(_ t: ShockTrend) -> String {
        switch t {
        case .up: return "\(t.arrow) High"
        case .down: return "\(t.arrow) Low"
        case .normal: return "\(t.arrow) Normal"
        case .varies: return "\(t.arrow) Either"
        }
    }

    var body: some View {
        let fits: [ShockProfile.Kind] = Pathology.readShock(cardiacOutput: output, resistance: resistance, wedge: wedge)
        ScienceToolPage(tool: .shock) {
            Section("Values") {
                trendRow("Cardiac output", $output)
                trendRow("Systemic resistance", $resistance)
                trendRow("Wedge pressure", $wedge)
            }
            .wardRowBackground()

            Section("Result") {
                if fits.isEmpty {
                    ScienceVerdict(text: "No kind of shock gives this picture. Check the numbers, or think of a mixed shock (septic shock with a failing heart).")
                }
                ForEach(fits, id: \.self) { kind in
                    if let p = Pathology.shock(kind) {
                        ScienceFact(title: p.name, lines: [(label: "Why", text: p.note),
                                                           (label: "Causes", text: p.causes.joined(separator: "; "))])
                    }
                }
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section {
                Grid(alignment: .leading, horizontalSpacing: WardSpace.m, verticalSpacing: WardSpace.s) {
                    GridRow {
                        Text("")
                        ForEach(["CO", "SVR", "PCWP", "CVP", "HR"], id: \.self) { h in
                            Text(h).font(.caption.weight(.semibold)).foregroundStyle(Color.wardInkSecondary)
                        }
                    }
                    ForEach(Pathology.shock) { p in
                        GridRow {
                            Text(p.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.wardInk)
                            ForEach(Array([p.cardiacOutput, p.resistance, p.wedge, p.cvp, p.heartRate].enumerated()),
                                    id: \.offset) { _, t in
                                Text(t.arrow)
                                    .font(WardType.obs)
                                    .foregroundStyle(t == .up ? Color.wardEcg : t == .down ? Color.wardPrimaryInk : Color.wardInkSecondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, WardSpace.xs)
            } header: {
                Text("The five profiles")
            } footer: {
                Text("CO cardiac output, SVR systemic vascular resistance, PCWP wedge pressure (the left heart's filling), CVP central venous pressure (the right's), HR heart rate. \u{2195} means either way.")
            }
            .wardRowBackground()
        }
    }

    private func trendRow(_ name: String, _ value: Binding<ShockTrend>) -> some View {
        VStack(alignment: .leading, spacing: WardSpace.s) {
            Text(name)
            WardSegmented(selection: value, options: Self.choices) { t in
                Text(word(t))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
        }
        .padding(.vertical, WardSpace.xs)
    }
}

// MARK: - Infarct by age

struct InfarctTool: View {
    /// log10 of the hours since the ischaemia began.
    @State private var age = log10(48.0)

    var body: some View {
        let hours: Double = pow(10, age)
        let stage: InfarctStage? = Pathology.infarctStage(hours: hours)
        ScienceToolPage(tool: .infarct) {
            Section("Values") {
                ScienceSlider(name: "Since it began", value: $age, range: -1...log10(24 * 120), step: 0.01,
                              shown: Self.spoken(hours))
            }
            .wardRowBackground()

            if let stage {
                Section(stage.span) {
                    ScienceFact(title: "What it looks like",
                                lines: [(label: "By eye", text: stage.gross), (label: "Microscope", text: stage.micro)]
                                    + (stage.risk.map { [(label: "Risk", text: $0)] } ?? []))
                }
                .wardRowBackground()
            }

            Section("Every stage") {
                ForEach(Pathology.infarct) { s in
                    ScienceFact(title: s == stage ? s.span + " (now)" : s.span, lines: [(label: "Microscope", text: s.micro)])
                }
            }
            .wardRowBackground()

            ScienceTextSection(title: "Keep in mind",
                               text: "Troponin rises from about 3 hours, peaks at a day and stays up for a week or two; CK-MB returns to normal in 2 to 3 days, so it can time a reinfarction. Rupture (free wall, septum, papillary muscle) belongs to days 3 to 10, when macrophages have cleared the dead muscle and no scar has formed. Dressler syndrome, an autoimmune pericarditis, comes weeks later.")
        }
    }

    /// "48 hours", "5 days", "3 weeks".
    private static func spoken(_ hours: Double) -> String {
        if hours < 1 { return scienceNumber(hours * 60) + " minutes" }
        if hours < 48 { return scienceNumber(hours) + " hours" }
        if hours < 24 * 21 { return scienceNumber(hours / 24) + " days" }
        return scienceNumber(hours / 24 / 7) + " weeks"
    }
}

// MARK: - Necrosis

struct NecrosisTool: View {
    var body: some View {
        ScienceToolPage(tool: .necrosis) {
            Section {
                ForEach(Pathology.necrosis) { n in
                    ScienceFact(title: n.name, lines: [(label: "Looks", text: n.looks), (label: "Where", text: n.sites)])
                }
            }
            .wardRowBackground()
            ScienceTextSection(title: "Keep in mind",
                               text: "Necrosis is death that spills: the cell swells, bursts and inflames. Apoptosis is death kept tidy: the cell shrinks, its chromatin condenses, it breaks into membrane-bound bodies and is eaten without inflammation.")
        }
    }
}

// MARK: - Nephrotic or nephritic

struct GlomerularTool: View {
    @State private var protein = 1.0
    @State private var casts = true

    var body: some View {
        let picture: Pathology.Glomerular = Pathology.glomerular(proteinGramsPerDay: protein, redCellCasts: casts)
        let diseases: [GlomerularDisease] = Pathology.glomerularDiseases.filter {
            picture == .neither || $0.picture == picture || $0.picture == .mixed || picture == .mixed
        }
        ScienceToolPage(tool: .glomerular) {
            Section("Values") {
                ScienceSlider(name: "Protein in the urine", value: $protein, range: 0...12, step: 0.1,
                              shown: scienceNumber(protein, 1) + " g/day")
                Toggle("Red cell casts", isOn: $casts)
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Picture", value: picture.name)
                ScienceVerdict(text: picture == .neither ? "Neither: protein at or under 3.5 g a day and no red cell casts."
                                                         : "Over 3.5 g a day is the nephrotic line; red cell casts mean glomerular bleeding, the nephritic sign.")
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Nephrotic") {
                ForEach(Pathology.nephroticFeatures, id: \.self) { f in Text(f).font(.subheadline) }
            }
            .wardRowBackground()
            Section("Nephritic") {
                ForEach(Pathology.nephriticFeatures, id: \.self) { f in Text(f).font(.subheadline) }
            }
            .wardRowBackground()

            Section(picture == .neither ? "The diseases" : "Diseases that fit") {
                ForEach(diseases) { d in
                    ScienceFact(title: d.name, subtitle: d.picture.name,
                                lines: [(label: "Who", text: d.who), (label: "Clues", text: d.clues)])
                }
            }
            .wardRowBackground()
        }
    }
}

// MARK: - Naming tumours

struct TumourNamesTool: View {
    @State private var tissue: String = Pathology.tumourTissues.first?.tissue ?? ""
    @State private var malignant = false

    var body: some View {
        let name: String? = Pathology.tumourName(tissue: tissue, malignant: malignant)
        ScienceToolPage(tool: .tumourNames) {
            Section("Values") {
                Picker("Tissue", selection: $tissue) {
                    ForEach(Pathology.tumourTissues) { t in
                        Text(t.tissue).tag(t.tissue)
                    }
                }
                .pickerStyle(.menu)
                WardSegmented(selection: $malignant, options: [false, true]) { m in
                    Text(m ? "Malignant" : "Benign")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Behaviour")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Name", value: name ?? "None")
                if name == nil {
                    ScienceVerdict(text: "This tissue has no benign tumour of its own.")
                }
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Names that break the rule") {
                ForEach(Pathology.misleadingNames, id: \.name) { m in
                    ScienceFact(title: m.name, lines: [(label: "Really", text: m.truth)])
                }
            }
            .wardRowBackground()

            Section("Benign or malignant") {
                ForEach(Pathology.benignAgainstMalignant, id: \.feature) { f in
                    ScienceFact(title: f.feature, lines: [(label: "Benign", text: f.benign), (label: "Malignant", text: f.malignant)])
                }
            }
            .wardRowBackground()

            ScienceTextSection(title: "Keep in mind",
                               text: "The rule: benign tumours end in -oma; malignant ones of epithelium are carcinomas and of mesenchyme sarcomas. Lymphoma, melanoma, mesothelioma and seminoma end in -oma but are malignant; a hamartoma and a choristoma are not tumours at all.")
        }
    }
}

// MARK: - Drug levels

struct PharmacokineticsTool: View {
    @State private var drug = Pharmacokinetics.Drug()
    @State private var regimen = Pharmacokinetics.Regimen()
    @State private var doses = 10.0

    private struct Point: Identifiable {
        let id: Int
        let t: Double
        let c: Double
    }

    /// The regimen with the slider's count of doses.
    private var plan: Pharmacokinetics.Regimen {
        var r: Pharmacokinetics.Regimen = regimen
        r.doses = Int(doses)
        return r
    }

    var body: some View {
        let r: Pharmacokinetics.Regimen = plan
        let hours: Double = max(48, Double(r.doses) * r.interval + 24)
        let points: [Point] = Pharmacokinetics.curve(drug, r, hours: hours).enumerated().map { Point(id: $0, t: $1.t, c: $1.c) }
        let average: Double = Pharmacokinetics.averageSteadyState(drug, r)
        let accumulation: Double = Pharmacokinetics.accumulation(drug, interval: r.interval)
        let f: Double = r.route == .oral ? drug.bioavailability : 1
        let loading: Double = Pharmacokinetics.loadingDose(target: average, volume: drug.volume, bioavailability: f)
        ScienceToolPage(tool: .pharmacokinetics) {
            Section {
                ScienceFigure(title: "Concentration over time",
                              caption: "Each dose adds to what is left of the last, until as much leaves in an interval as is given: steady state, in about five half-lives.",
                              spoken: "Half-life \(scienceNumber(drug.halfLife, 1)) hours; average steady state \(scienceNumber(average, 1)) milligrams per litre.") {
                    Chart {
                        ForEach(points) { p in
                            LineMark(x: .value("Hours", p.t), y: .value("mg/L", p.c))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                        RuleMark(y: .value("Average at steady state", average))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.wardBeam)
                    }
                    .chartXAxisLabel("hours")
                    .chartYAxisLabel("mg/L")
                }
            }
            .wardRowBackground()

            Section("Values") {
                WardSegmented(selection: $regimen.route, options: Pharmacokinetics.Route.allCases) { route in
                    Text(route.name)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Route")
                ScienceSlider(name: "Dose", value: $regimen.dose, range: 50...2000, step: 50,
                              shown: scienceNumber(regimen.dose) + " mg")
                ScienceSlider(name: "Every", value: $regimen.interval, range: 2...48, step: 1,
                              shown: scienceNumber(regimen.interval) + " h")
                ScienceSlider(name: "Doses", value: $doses, range: 1...20, step: 1, shown: scienceNumber(doses))
                ScienceSlider(name: "Volume of distribution", value: $drug.volume, range: 5...500, step: 5,
                              shown: scienceNumber(drug.volume) + " L")
                ScienceSlider(name: "Clearance", value: $drug.clearance, range: 0.5...20, step: 0.5,
                              shown: scienceNumber(drug.clearance, 1) + " L/h")
                if regimen.route == .oral {
                    ScienceSlider(name: "Bioavailability", value: $drug.bioavailability, range: 0.05...1, step: 0.05,
                                  shown: sciencePercent(drug.bioavailability))
                }
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Half-life", value: scienceNumber(drug.halfLife, 1) + " h")
                ScienceReading(label: "Steady state, average", value: scienceNumber(average, 1) + " mg/L")
                ScienceReading(label: "Accumulation", value: "\u{00D7}" + scienceNumber(accumulation, 1))
                ScienceReading(label: "Steady state in", value: scienceNumber(drug.halfLife * 5) + " h")
                ScienceReading(label: "Loading dose", value: scienceNumber(loading) + " mg")
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "One compartment, first-order elimination: k = clearance / volume and half-life = 0.693 / k. By mouth, absorption is first order too, scaled by bioavailability. Average steady state = F \u{00D7} dose / (clearance \u{00D7} interval); a loading dose = target \u{00D7} volume / F reaches it at once.")
            ScienceTextSection(title: "Keep in mind",
                               text: "The half-life depends on both volume and clearance: a drug spread widely in tissue (large volume) lingers even when cleared well. The time to steady state depends only on the half-life, not on the dose; a loading dose is what shortens the wait (digoxin, amiodarone, vancomycin).")
        }
    }
}

// MARK: - Tests and trials

struct DiagnosticTestsTool: View {
    @State private var sensitivity = 0.9
    @State private var specificity = 0.8
    @State private var prevalence = 0.1
    @State private var controlRate = 0.2
    @State private var treatedRate = 0.15

    private struct Point: Identifiable {
        let id: String
        let prevalence: Double
        let value: Double
        let name: String
    }

    var body: some View {
        let table = Biostatistics.TwoByTwo.from(sensitivity: sensitivity, specificity: specificity, prevalence: prevalence)
        let curve: [Point] = (1...99).flatMap { i -> [Point] in
            let p: Double = Double(i) / 100
            let t = Biostatistics.TwoByTwo.from(sensitivity: sensitivity, specificity: specificity, prevalence: p)
            return [Point(id: "p\(i)", prevalence: Double(i), value: (t.positivePredictive ?? 0) * 100, name: "Positive predictive value"),
                    Point(id: "n\(i)", prevalence: Double(i), value: (t.negativePredictive ?? 0) * 100, name: "Negative predictive value")]
        }
        let trial = Biostatistics.Trial(treatedEvents: treatedRate * 1000, treatedTotal: 1000,
                                        controlEvents: controlRate * 1000, controlTotal: 1000)
        ScienceToolPage(tool: .diagnosticTests) {
            Section {
                ScienceFigure(title: "Predictive values against prevalence",
                              caption: "The same test: in a rare disease most positives are false; in a common one, most negatives need a second look.",
                              spoken: "At \(sciencePercent(prevalence)) prevalence a positive is right \(sciencePercent(table.positivePredictive ?? 0)) of the time.") {
                    Chart {
                        ForEach(curve) { p in
                            LineMark(x: .value("Prevalence", p.prevalence), y: .value("%", p.value), series: .value("Value", p.name))
                                .foregroundStyle(by: .value("Value", p.name))
                                .lineStyle(p.name == "Positive predictive value" ? StrokeStyle(lineWidth: 2) : StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                        RuleMark(x: .value("Now", prevalence * 100))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                    .chartForegroundStyleScale(["Positive predictive value": Color.wardPrimaryInk,
                                                "Negative predictive value": Color.wardInkSecondary])
                    .chartYScale(domain: 0.0...100.0)
                    .chartXAxisLabel("prevalence, %")
                    .chartYAxisLabel("%")
                }
            }
            .wardRowBackground()

            Section("A test") {
                ScienceSlider(name: "Sensitivity", value: $sensitivity, range: 0.5...1, step: 0.01, shown: sciencePercent(sensitivity))
                ScienceSlider(name: "Specificity", value: $specificity, range: 0.5...1, step: 0.01, shown: sciencePercent(specificity))
                ScienceSlider(name: "Prevalence", value: $prevalence, range: 0.01...0.9, step: 0.01, shown: sciencePercent(prevalence))
            }
            .wardRowBackground()

            Section {
                Grid(alignment: .trailing, horizontalSpacing: WardSpace.l, verticalSpacing: WardSpace.s) {
                    GridRow {
                        Text("")
                        Text("Disease").font(.caption.weight(.semibold)).foregroundStyle(Color.wardInkSecondary)
                        Text("No disease").font(.caption.weight(.semibold)).foregroundStyle(Color.wardInkSecondary)
                    }
                    GridRow {
                        Text("Test +").font(.subheadline.weight(.semibold))
                        cell(table.truePositive, good: true)
                        cell(table.falsePositive, good: false)
                    }
                    GridRow {
                        Text("Test \u{2212}").font(.subheadline.weight(.semibold))
                        cell(table.falseNegative, good: false)
                        cell(table.trueNegative, good: true)
                    }
                }
                .padding(.vertical, WardSpace.xs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Of 1,000 people: \(scienceNumber(table.truePositive)) true positives, \(scienceNumber(table.falsePositive)) false positives, \(scienceNumber(table.falseNegative)) false negatives, \(scienceNumber(table.trueNegative)) true negatives.")
            } header: {
                Text("In 1,000 people")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Positive predictive value", value: sciencePercent(table.positivePredictive ?? 0))
                ScienceReading(label: "Negative predictive value", value: sciencePercent(table.negativePredictive ?? 0))
                ScienceReading(label: "Likelihood ratio +", value: scienceNumber(table.positiveLikelihood ?? .nan, 1))
                ScienceReading(label: "Likelihood ratio \u{2212}", value: scienceNumber(table.negativeLikelihood ?? .nan, 2))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("A trial") {
                ScienceSlider(name: "Events without treatment", value: $controlRate, range: 0.01...0.6, step: 0.01,
                              shown: sciencePercent(controlRate))
                ScienceSlider(name: "Events with treatment", value: $treatedRate, range: 0.01...0.6, step: 0.01,
                              shown: sciencePercent(treatedRate))
            }
            .wardRowBackground()

            Section("The trial's result") {
                ScienceReading(label: "Relative risk", value: scienceNumber(trial.relativeRisk ?? .nan, 2))
                ScienceReading(label: "Absolute risk reduction", value: sciencePercent(trial.absoluteRiskReduction ?? .nan, 1))
                ScienceReading(label: "Relative risk reduction", value: sciencePercent(trial.relativeRiskReduction ?? .nan))
                ScienceReading(label: "Number needed to treat", value: nnt(trial.numberNeededToTreat))
                ScienceReading(label: "Odds ratio", value: scienceNumber(trial.oddsRatio ?? .nan, 2))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "Sensitivity = TP / (TP + FN); specificity = TN / (TN + FP). PPV = TP / (TP + FP); NPV = TN / (TN + FN). LR+ = sensitivity / (1 \u{2212} specificity); LR\u{2212} = (1 \u{2212} sensitivity) / specificity. ARR = control rate \u{2212} treated rate; NNT = 1 / ARR, rounded up; RR = treated rate / control rate.")
        }
    }

    private func cell(_ n: Double, good: Bool) -> some View {
        Text(scienceNumber(n))
            .font(WardType.obs)
            .foregroundStyle(good ? Color.wardInk : Color.wardDanger)
    }

    private func nnt(_ value: Double?) -> String {
        guard let value, value.isFinite, value > 0 else { return "\u{2014}" }
        return scienceNumber(value.rounded(.up))
    }
}
