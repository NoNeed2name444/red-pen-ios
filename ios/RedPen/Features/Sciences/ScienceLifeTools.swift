import Charts
import SwiftUI

// The biochemistry, microbiology, immunology and genetics tools, on the
// engines in Shared/Sciences (Biochemistry, Microbiology, Immunology,
// Genetics).

// MARK: - Enzyme kinetics

struct EnzymeKineticsTool: View {
    @State private var vmax = 100.0
    @State private var km = 5.0
    @State private var inhibition: EnzymeKinetics.Inhibition = .competitive
    @State private var inhibitor = 4.0
    @State private var ki = 2.0

    private struct Point: Identifiable {
        let id: String
        let x: Double
        let y: Double
        let line: String
    }

    var body: some View {
        let plain = EnzymeKinetics.Constants(vmax: vmax, km: km)
        let inhibited: EnzymeKinetics.Constants = EnzymeKinetics.apparent(plain, inhibition, inhibitor: inhibitor, ki: ki)
        let substrates: [Double] = (0...60).map { Double($0) * 0.5 }
        let curves: [Point] = substrates.map { Point(id: "a\($0)", x: $0, y: EnzymeKinetics.rate(substrate: $0, plain), line: "No inhibitor") }
            + (inhibition == .none ? [] : substrates.map {
                Point(id: "b\($0)", x: $0, y: EnzymeKinetics.rate(substrate: $0, inhibited), line: "With inhibitor")
            })
        let lowest: Double = min(-1 / plain.km, -1 / inhibited.km) * 1.2
        let reciprocals: [Double] = (0...40).map { lowest + (1 - lowest) * Double($0) / 40 }
        let lines: [Point] = reciprocals.map { x in
            let lb = EnzymeKinetics.lineweaverBurk(plain)
            return Point(id: "c\(x)", x: x, y: lb.yIntercept + lb.slope * x, line: "No inhibitor")
        } + (inhibition == .none ? [] : reciprocals.map { x in
            let lb = EnzymeKinetics.lineweaverBurk(inhibited)
            return Point(id: "d\(x)", x: x, y: lb.yIntercept + lb.slope * x, line: "With inhibitor")
        })
        let colours: KeyValuePairs<String, Color> = inhibition == .none
            ? ["No inhibitor": Color.wardPrimaryInk, "With inhibitor": Color.wardPrimaryInk]
            : ["No inhibitor": Color.wardInkSecondary, "With inhibitor": Color.wardPrimaryInk]
        let comparison: Bool = inhibition != .none
        ScienceToolPage(tool: .enzymeKinetics) {
            Section {
                ScienceFigure(title: "Rate against substrate (Michaelis-Menten)",
                              caption: "The rate climbs towards Vmax; at [S] = Km it is half of Vmax.",
                              spoken: "Vmax \(scienceNumber(inhibited.vmax)), Km \(scienceNumber(inhibited.km, 1)) with the inhibitor; \(scienceNumber(vmax)) and \(scienceNumber(km, 1)) without.") {
                    Chart(curves) { p in
                        LineMark(x: .value("[S]", p.x), y: .value("Rate", p.y), series: .value("Line", p.line))
                            .foregroundStyle(by: .value("Line", p.line))
                            .lineStyle(comparison && p.line == "No inhibitor" ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 2))
                    }
                    .chartForegroundStyleScale(colours)
                    .chartXAxisLabel("[S], mmol/L")
                    .chartYAxisLabel("rate")
                }
            }
            .wardRowBackground()

            Section {
                ScienceFigure(title: "Double reciprocal (Lineweaver-Burk)",
                              caption: "The line meets the y-axis at 1/Vmax and the x-axis at \u{2212}1/Km.",
                              spoken: inhibition.effect) {
                    Chart {
                        ForEach(lines) { p in
                            LineMark(x: .value("1/[S]", p.x), y: .value("1/rate", p.y), series: .value("Line", p.line))
                                .foregroundStyle(by: .value("Line", p.line))
                                .lineStyle(comparison && p.line == "No inhibitor" ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 2))
                        }
                        RuleMark(x: .value("Zero", 0.0)).foregroundStyle(Color.wardInkSecondary)
                        RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Color.wardInkSecondary)
                    }
                    .chartForegroundStyleScale(colours)
                    .chartXAxisLabel("1/[S]")
                    .chartYAxisLabel("1/rate")
                }
            }
            .wardRowBackground()

            Section("Values") {
                Picker("Inhibitor", selection: $inhibition) {
                    ForEach(EnzymeKinetics.Inhibition.allCases) { i in
                        Text(i.name).tag(i)
                    }
                }
                .pickerStyle(.menu)
                ScienceSlider(name: "Vmax", value: $vmax, range: 10...200, step: 1, shown: scienceNumber(vmax))
                ScienceSlider(name: "Km", value: $km, range: 0.5...20, step: 0.5, shown: scienceNumber(km, 1) + " mmol/L")
                if inhibition != .none {
                    ScienceSlider(name: "Inhibitor", value: $inhibitor, range: 0...20, step: 0.5,
                                  shown: scienceNumber(inhibitor, 1) + " mmol/L")
                    ScienceSlider(name: "Its Ki", value: $ki, range: 0.5...10, step: 0.5, shown: scienceNumber(ki, 1) + " mmol/L")
                }
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Apparent Vmax", value: scienceNumber(inhibited.vmax, 1))
                ScienceReading(label: "Apparent Km", value: scienceNumber(inhibited.km, 1) + " mmol/L")
                ScienceVerdict(text: inhibition.effect)
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "v = Vmax[S] / (Km + [S]). An inhibitor at [I] with constant Ki multiplies by \u{03B1} = 1 + [I]/Ki: Km for a competitive one, 1/Vmax for a non-competitive one, and both (dividing Km and Vmax) for an uncompetitive one.")
            ScienceTextSection(title: "Keep in mind",
                               text: "Methotrexate (dihydrofolate reductase) and statins (HMG-CoA reductase) are competitive; ethanol is given against methanol poisoning to compete for alcohol dehydrogenase. Irreversible inhibitors such as aspirin on cyclooxygenase lower Vmax for the life of the enzyme.")
        }
    }
}

// MARK: - Metabolic pathways

struct PathwaysTool: View {
    var body: some View {
        ScienceToolPage(tool: .pathways) {
            Section {
                ForEach(MetabolicPathways.all) { pathway in
                    NavigationLink {
                        PathwayView(pathway: pathway)
                    } label: {
                        WardRow(symbol: ScienceTool.pathways.symbol, title: pathway.name,
                                detail: pathway.location, chevron: false)
                    }
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier("sciencePathway-\(pathway.id)")
                }
            } footer: {
                Text("Each pathway links to its curated diagram in Reactome (data CC0, diagrams CC BY 4.0).")
            }
            .wardRowBackground()
        }
    }
}

/// One pathway, step by step: the reaction, the enzyme, what it makes or
/// spends, how it is controlled and the disease it is known for.
struct PathwayView: View {
    let pathway: MetabolicPathway

    var body: some View {
        List {
            Section {
                ScienceVerdict(text: pathway.summary)
                LabeledContent("Where", value: pathway.location)
            }
            .wardRowBackground()

            Section("Steps") {
                ForEach(pathway.steps) { step in
                    VStack(alignment: .leading, spacing: WardSpace.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: WardSpace.s) {
                            Text("\(step.number)")
                                .font(WardType.obs)
                                .foregroundStyle(Color.wardInkSecondary)
                            Text(step.reaction)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.wardInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(step.enzyme)
                            .font(.subheadline)
                            .foregroundStyle(Color.wardPrimaryInk)
                        if step.rateLimiting || step.irreversible || !step.yield.isEmpty {
                            HStack(spacing: WardSpace.xs) {
                                if step.rateLimiting { WardChip(text: "Rate-limiting", tone: .amber) }
                                if step.irreversible && !step.rateLimiting { WardChip(text: "Irreversible", tone: .grey) }
                                ForEach(step.yield, id: \.self) { y in WardChip(text: y, tone: .blue) }
                            }
                        }
                        if let control = step.control {
                            ScienceVerdict(text: control)
                        }
                        if let clinical = step.clinical {
                            Label {
                                Text(clinical)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.wardInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "stethoscope").foregroundStyle(Color.wardEcg)
                            }
                        }
                    }
                    .padding(.vertical, WardSpace.xs)
                    .accessibilityElement(children: .combine)
                }
            }
            .wardRowBackground()

            Section("Net") {
                ForEach(pathway.net, id: \.self) { line in
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .wardRowBackground()

            if let url = URL(string: pathway.reactomeURL) {
                Section {
                    Link(destination: url) {
                        Label("The diagram in Reactome (\(pathway.reactome))", systemImage: "link")
                            .font(.footnote)
                    }
                }
                .wardRowBackground()
            }
        }
        .wardForm()
        .navigationTitle(pathway.name)
        .navigationBarTitleDisplayMode(.inline)
        .wardDisclaimer()
        .accessibilityIdentifier("sciencePathwayPage-\(pathway.id)")
    }
}

// MARK: - Bacteria key

struct MicrobeKeyTool: View {
    /// The answers chosen so far, each with the question it answered.
    @State private var trail: [(question: String, answer: String)] = []
    @State private var node: String = Microbiology.root
    @State private var found: [String]?

    var body: some View {
        ScienceToolPage(tool: .microbeKey) {
            if !trail.isEmpty {
                Section("So far") {
                    ForEach(Array(trail.enumerated()), id: \.offset) { _, step in
                        LabeledContent(step.question, value: step.answer)
                    }
                    Button("Start again") {
                        trail = []; node = Microbiology.root; found = nil
                    }
                    .accessibilityIdentifier("microbeKeyRestart")
                }
                .wardRowBackground()
            }
            if let found {
                Section("It is") {
                    ForEach(found.compactMap(Microbiology.organism)) { microbe in
                        NavigationLink {
                            MicrobeView(microbe: microbe)
                        } label: {
                            WardRow(symbol: "microbe", title: microbe.name, detail: microbe.diseases.first, chevron: false)
                        }
                        .hoverEffect(.highlight)
                        .accessibilityIdentifier("microbeKeyFound-\(microbe.id)")
                    }
                }
                .wardRowBackground()
            } else if let current = Microbiology.node(node) {
                Section(current.question) {
                    ForEach(current.answers, id: \.label) { answer in
                        Button {
                            choose(answer, of: current)
                        } label: {
                            Text(answer.label).foregroundStyle(Color.wardPrimaryInk)
                        }
                        .accessibilityIdentifier("microbeKeyAnswer-\(answer.label)")
                    }
                }
                .wardRowBackground()
            }
            ScienceTextSection(title: "Keep in mind",
                               text: "A key like this is how a laboratory narrows a culture down before identifying it by MALDI-TOF or sequencing. Some organisms are named by more than one route; atypical organisms that do not Gram stain are reached through \u{201C}stains poorly\u{201D}.")
        }
    }

    private func choose(_ answer: MicrobeKeyNode.Answer, of current: MicrobeKeyNode) {
        trail.append((current.question, answer.label))
        switch answer.next {
        case .node(let next): node = next
        case .organisms(let ids): found = ids
        }
    }
}

struct MicrobesTool: View {
    @State private var query = ""

    private var shown: [Microbe] {
        let q: String = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Microbiology.organisms }
        return Microbiology.organisms.filter { m in
            ([m.name, m.shape] + m.diseases + m.features).contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        let groups: [(title: String, gram: Microbe.Gram)] = [("Gram positive", .positive), ("Gram negative", .negative),
                                                              ("Does not Gram stain", .none)]
        ScienceToolPage(tool: .microbes) {
            if shown.isEmpty {
                WardEmptyState(symbol: "magnifyingglass", title: "No results",
                               message: "Try a disease, a shape or a test, such as \u{201C}meningitis\u{201D} or \u{201C}catalase\u{201D}.")
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.title) { group in
                let members: [Microbe] = shown.filter { $0.gram == group.gram }
                if !members.isEmpty {
                    Section(group.title) {
                        ForEach(members) { microbe in
                            NavigationLink {
                                MicrobeView(microbe: microbe)
                            } label: {
                                WardRow(symbol: "microbe", title: microbe.name, detail: microbe.shape, chevron: false)
                            }
                            .hoverEffect(.highlight)
                            .accessibilityIdentifier("microbe-\(microbe.id)")
                        }
                    }
                    .wardRowBackground()
                }
            }
        }
        .searchable(text: $query, prompt: "Find an organism, disease or test")
    }
}

/// One organism: how it looks and grows, how it is told apart, and what it
/// causes, with its NCBI Taxonomy entry.
struct MicrobeView: View {
    let microbe: Microbe

    var body: some View {
        List {
            Section {
                LabeledContent("Gram stain", value: microbe.gram == .none ? "Does not Gram stain" : microbe.gram.rawValue.capitalized)
                LabeledContent("Shape", value: microbe.shape)
                LabeledContent("Oxygen", value: microbe.oxygen)
            }
            .wardRowBackground()
            Section("Told apart by") {
                ForEach(microbe.features, id: \.self) { f in Text(f).font(.subheadline) }
            }
            .wardRowBackground()
            Section("Causes") {
                ForEach(microbe.diseases, id: \.self) { d in Text(d).font(.subheadline) }
            }
            .wardRowBackground()
            if let path = Microbiology.path(to: microbe.id) {
                Section("In the key") {
                    ForEach(Array(path.enumerated()), id: \.offset) { i, step in
                        Label(step, systemImage: "\(min(i + 1, 50)).circle")
                            .font(.subheadline)
                    }
                }
                .wardRowBackground()
            }
            if let url = URL(string: microbe.taxonomyURL) {
                Section {
                    Link(destination: url) {
                        Label("NCBI Taxonomy \(microbe.taxonomy)", systemImage: "link")
                            .font(.footnote)
                    }
                }
                .wardRowBackground()
            }
        }
        .wardForm()
        .navigationTitle(microbe.name)
        .navigationBarTitleDisplayMode(.inline)
        .wardDisclaimer()
        .accessibilityIdentifier("microbePage-\(microbe.id)")
    }
}

// MARK: - Bacterial growth

struct GrowthCurveTool: View {
    @State private var culture = Microbiology.Culture()

    private struct Point: Identifiable {
        let id: Int
        let hours: Double
        let log10: Double
    }

    var body: some View {
        let points: [Point] = (0...120).map { i in
            let h: Double = Double(i) * 0.25
            return Point(id: i, hours: h, log10: Microbiology.cultureLog10(culture, hours: h))
        }
        let rate: Double = log(2) / (culture.generationMinutes / 60)
        let n0: Double = pow(10, culture.startLog10), k: Double = pow(10, culture.capacityLog10)
        let reach: Double = culture.lagHours + log((k / n0 - 1) / (1 / 0.99 - 1)) / rate
        ScienceToolPage(tool: .growthCurve) {
            Section {
                ScienceFigure(title: "A batch culture, log of the count",
                              caption: "Lag, then exponential growth (a straight line on a log scale), then stationary as the medium runs out, then death.",
                              spoken: "From 10 to the \(scienceNumber(culture.startLog10)) to 10 to the \(scienceNumber(culture.capacityLog10)) cells, reached at \(scienceNumber(reach, 1)) hours.") {
                    Chart {
                        ForEach(points) { p in
                            LineMark(x: .value("Hours", p.hours), y: .value("log10 cells", p.log10))
                                .foregroundStyle(Color.wardPrimaryInk)
                        }
                        RuleMark(x: .value("Lag ends", culture.lagHours))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.wardInkSecondary)
                        RuleMark(x: .value("Stationary", reach))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.wardBeam)
                    }
                    .chartYScale(domain: 0.0...11.0)
                    .chartXAxisLabel("hours")
                    .chartYAxisLabel("log10 cells/mL")
                }
            }
            .wardRowBackground()

            Section("Values") {
                ScienceSlider(name: "Lag", value: $culture.lagHours, range: 0...8, step: 0.5,
                              shown: scienceNumber(culture.lagHours, 1) + " h")
                ScienceSlider(name: "Doubling time", value: $culture.generationMinutes, range: 15...180, step: 5,
                              shown: scienceNumber(culture.generationMinutes) + " min")
                ScienceSlider(name: "Stationary phase", value: $culture.stationaryHours, range: 0...15, step: 0.5,
                              shown: scienceNumber(culture.stationaryHours, 1) + " h")
                ScienceSlider(name: "Death rate", value: $culture.deathPerHour, range: 0...1, step: 0.05,
                              shown: scienceNumber(culture.deathPerHour, 2) + " log/h")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Stationary from", value: scienceNumber(reach, 1) + " h")
                ScienceReading(label: "Doublings per hour", value: scienceNumber(60 / culture.generationMinutes, 1))
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            ScienceTextSection(title: "How it is worked out",
                               text: "Growth is logistic towards the medium's capacity: N = K / (1 + (K/N0 \u{2212} 1)e^(\u{2212}rt)), with r = ln 2 / doubling time. Once within 1% of capacity the culture holds, then loses a fixed number of log units an hour. Illustrative rates; the shape is what is examined.")
            ScienceTextSection(title: "Keep in mind",
                               text: "Beta-lactams and other cell-wall antibiotics kill only growing bacteria, in the log phase. Spores form as nutrients run out. E. coli doubles in about 20 minutes at its best; Mycobacterium tuberculosis takes 15 to 20 hours, which is why its cultures take weeks.")
        }
    }
}

// MARK: - Immunology

struct ImmuneCellsTool: View {
    var body: some View {
        ScienceToolPage(tool: .immuneCells) {
            ForEach([ImmuneCell.Arm.innate, .adaptive], id: \.self) { arm in
                Section(arm == .innate ? "Innate" : "Adaptive") {
                    ForEach(Immunology.cells.filter { $0.arm == arm }) { cell in
                        ScienceFact(title: cell.name, subtitle: cell.cellOntology,
                                    lines: Self.lines(cell))
                    }
                }
                .wardRowBackground()
            }
            Section("Antibodies") {
                ForEach(Immunology.antibodies) { ab in
                    ScienceFact(title: ab.name, subtitle: ab.form + " \u{00B7} " + ab.serumShare + " of serum antibody",
                                lines: ab.roles.map { (label: "\u{2022}", text: $0) })
                }
            }
            .wardRowBackground()
            ScienceTextSection(title: "Source",
                               text: "Cell names follow the Cell Ontology (CC BY 4.0); each cell's CL identifier is under its name.")
        }
    }

    private static func lines(_ cell: ImmuneCell) -> [(label: String, text: String)] {
        var out: [(label: String, text: String)] = [(label: "Does", text: cell.role)]
        if let markers = cell.markers { out.append((label: "Markers", text: markers)) }
        return out
    }
}

struct AntibodyResponseTool: View {
    @State private var secondDay = 40.0

    private struct Point: Identifiable {
        let id: String
        let day: Double
        let level: Double
        let kind: String
    }

    var body: some View {
        let points: [Point] = (0...100).flatMap { d -> [Point] in
            let day: Double = Double(d)
            let first = Immunology.antibody(day: day, secondary: false)
            let second = Immunology.antibody(day: day - secondDay, secondary: true)
            return [Point(id: "m\(d)", day: day, level: max(0.1, first.igm + second.igm), kind: "IgM"),
                    Point(id: "g\(d)", day: day, level: max(0.1, first.igg + second.igg), kind: "IgG")]
        }
        ScienceToolPage(tool: .antibodyResponse) {
            Section {
                ScienceFigure(title: "Antibody after a first and a second exposure",
                              caption: "On a log scale. The first response is late, low and mostly IgM; the second is quick, about a hundred times higher and mostly IgG.",
                              spoken: "A first exposure on day 0 and a second on day \(scienceNumber(secondDay)).") {
                    Chart {
                        ForEach(points) { p in
                            LineMark(x: .value("Day", p.day), y: .value("Level", p.level), series: .value("Class", p.kind))
                                .foregroundStyle(by: .value("Class", p.kind))
                                .lineStyle(p.kind == "IgM" ? StrokeStyle(lineWidth: 1.5, dash: [4, 3]) : StrokeStyle(lineWidth: 2))
                        }
                        RuleMark(x: .value("First exposure", 0.0)).foregroundStyle(Color.wardInkSecondary)
                        RuleMark(x: .value("Second exposure", secondDay))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                    .chartForegroundStyleScale(["IgM": Color.wardInkSecondary, "IgG": Color.wardPrimaryInk])
                    .chartYScale(domain: 0.1...2000.0, type: .log)
                    .chartXAxisLabel("days")
                    .chartYAxisLabel("relative level")
                }
                ScienceSlider(name: "Second exposure on day", value: $secondDay, range: 20...80, step: 1,
                              shown: scienceNumber(secondDay))
            }
            .wardRowBackground()

            ScienceTextSection(title: "Keep in mind",
                               text: "IgM points to a recent first infection; IgG alone to an old one or to immunisation. The second response is faster because memory B cells have already switched class and matured their affinity in germinal centres. Illustrative curves, not measurements.")
        }
    }
}

struct HypersensitivityTool: View {
    var body: some View {
        ScienceToolPage(tool: .hypersensitivity) {
            ForEach(Immunology.hypersensitivities) { h in
                Section("Type \(h.type)") {
                    ScienceFact(title: h.name, subtitle: h.timing,
                                lines: [(label: "How", text: h.mechanism), (label: "Examples", text: h.examples.joined(separator: "; "))])
                }
                .wardRowBackground()
            }
        }
    }
}

struct ComplementTool: View {
    var body: some View {
        ScienceToolPage(tool: .complement) {
            Section("Three ways in") {
                ForEach(Immunology.complementPathways) { p in
                    ScienceFact(title: p.name, lines: [(label: "Started by", text: p.trigger), (label: "Steps", text: p.steps)])
                }
            }
            .wardRowBackground()
            Section("What it does") {
                ForEach(Immunology.complementEffects, id: \.self) { e in
                    Text(e).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .wardRowBackground()
            Section("When a part is missing") {
                ForEach(Immunology.complementDeficiencies) { d in
                    ScienceFact(title: d.missing, lines: [(label: "Leads to", text: d.result)])
                }
            }
            .wardRowBackground()
        }
    }
}

// MARK: - Genetics

struct PunnettTool: View {
    @State private var first = "Aa"
    @State private var second = "Aa"
    @State private var pattern: Genetics.Pattern = .autosomalRecessive

    var body: some View {
        let cross: Genetics.Cross? = Genetics.cross(first, second)
        ScienceToolPage(tool: .punnett) {
            Section {
                genotypeField("First parent", text: $first, id: "punnettFirst")
                genotypeField("Second parent", text: $second, id: "punnettSecond")
            } header: {
                Text("Parents")
            } footer: {
                Text("One letter pair per gene, upper case dominant: Aa, AaBb. Up to three genes.")
            }
            .wardRowBackground()

            if let cross, cross.rows.count <= 8 {
                Section("The square") {
                    ScrollView(.horizontal) {
                        square(cross)
                            .padding(.vertical, WardSpace.xs)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(cross.total) children: genotypes " + Genetics.ratio(cross.genotypes))
                }
                .wardRowBackground()

                Section("Result") {
                    ScienceReading(label: "Genotypes", value: Genetics.ratio(cross.genotypes))
                    ScienceReading(label: "Phenotypes", value: Genetics.ratio(cross.phenotypes))
                    ScienceVerdict(text: cross.genotypes.sorted { $0.value > $1.value }
                        .map { "\($0.key) \($0.value) in \(cross.total)" }
                        .joined(separator: " \u{00B7} "))
                }
                .wardRowBackground()
                .accessibilityElement(children: .combine)
            } else {
                WardEmptyState(symbol: "square.grid.2x2", title: "Not a cross yet",
                               message: "Write both parents with the same genes, as letter pairs, such as Aa \u{00D7} aa or AaBb \u{00D7} AaBb.")
                    .listRowBackground(Color.clear)
            }

            Section("Try") {
                SciencePresetButton(title: "Two carriers", detail: "Aa \u{00D7} Aa: 1 in 4 affected") { first = "Aa"; second = "Aa" }
                SciencePresetButton(title: "A test cross", detail: "Aa \u{00D7} aa: 1 to 1") { first = "Aa"; second = "aa" }
                SciencePresetButton(title: "Two genes", detail: "AaBb \u{00D7} AaBb: 9:3:3:1") { first = "AaBb"; second = "AaBb" }
            }
            .wardRowBackground()

            Section("Family patterns") {
                Picker("Pattern", selection: $pattern) {
                    ForEach(Genetics.Pattern.allCases) { p in
                        Text(p.name).tag(p)
                    }
                }
                .pickerStyle(.menu)
                ForEach(pattern.risks, id: \.self) { line in
                    Text(line).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .wardRowBackground()
        }
    }

    private func genotypeField(_ label: String, text: Binding<String>, id: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: WardSpace.s)
            TextField("Aa", text: text)
                .font(WardType.obs)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, WardSpace.m)
                .padding(.vertical, WardSpace.s)
                .frame(maxWidth: 140)
                .wardInset(in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous), control: true)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private func square(_ cross: Genetics.Cross) -> some View {
        Grid(horizontalSpacing: WardSpace.s, verticalSpacing: WardSpace.s) {
            GridRow {
                Text("")
                ForEach(cross.columns, id: \.self) { c in
                    Text(c).font(WardType.obs.weight(.semibold)).foregroundStyle(Color.wardPrimaryInk)
                }
            }
            ForEach(Array(cross.rows.enumerated()), id: \.offset) { i, r in
                GridRow {
                    Text(r).font(WardType.obs.weight(.semibold)).foregroundStyle(Color.wardPrimaryInk)
                    ForEach(Array(cross.cells[i].enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(WardType.obs)
                            .foregroundStyle(Genetics.phenotype(cell) == Genetics.phenotype(cell).lowercased() ? Color.wardEcg : Color.wardInk)
                            .padding(WardSpace.xs)
                            .wardInset(in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous))
                    }
                }
            }
        }
    }
}

struct HardyWeinbergTool: View {
    /// log10 of "1 in N" births affected.
    @State private var rarity = log10(2500.0)

    var body: some View {
        let oneIn: Double = pow(10, rarity)
        let hw: Genetics.HardyWeinberg = Genetics.hardyWeinberg(incidence: 1 / oneIn)
        let siblings: Double = Genetics.siblingsChildRisk(incidence: 1 / oneIn)
        ScienceToolPage(tool: .hardyWeinberg) {
            Section("Values") {
                ScienceSlider(name: "Affected births", value: $rarity, range: 2...5, step: 0.01,
                              shown: "1 in " + scienceNumber(oneIn.rounded()))
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Allele (q)", value: scienceNumber(hw.q, 4))
                ScienceReading(label: "Carriers (2pq)", value: "1 in " + scienceNumber(1 / hw.carriers))
                ScienceReading(label: "Sibling's child", value: "1 in " + scienceNumber(1 / siblings))
                ScienceVerdict(text: "An unaffected sibling of an affected child is a carrier 2 times in 3; with a partner from the general population, their child is affected 1 time in \(scienceNumber(1 / siblings)).")
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Try") {
                SciencePresetButton(title: "Cystic fibrosis", detail: "About 1 in 2,500 births of northern European descent") { rarity = log10(2500) }
                SciencePresetButton(title: "Phenylketonuria", detail: "About 1 in 10,000") { rarity = log10(10000) }
                SciencePresetButton(title: "Sickle cell disease", detail: "About 1 in 400 births of West African descent") { rarity = log10(400) }
            }
            .wardRowBackground()

            ScienceTextSection(title: "How it is worked out",
                               text: "For an autosomal recessive disease in a population at equilibrium, affected births are q\u{00B2}, so q = \u{221A}incidence, p = 1 \u{2212} q and carriers are 2pq (about 2q when q is small). The sibling's child: 2/3 \u{00D7} 2pq \u{00D7} 1/4.")
        }
    }
}

struct GeneticCodeTool: View {
    @State private var reference = "ATGGTGCACCTGACTCCTGAGGAGAAGTCTGCC"
    @State private var variant = "ATGGTGCACCTGACTCCTGTGGAGAAGTCTGCC"

    private func threeLetter(_ protein: String) -> String {
        protein.map { Genetics.threeLetter[$0] ?? String($0) }.joined(separator: "-")
    }

    var body: some View {
        let mRNA: String = Genetics.transcribe(coding: reference)
        let protein: String = Genetics.translate(mRNA: mRNA)
        let changed: String = Genetics.translate(mRNA: Genetics.transcribe(coding: variant))
        let kind: Genetics.Mutation = Genetics.classify(reference: reference, variant: variant)
        ScienceToolPage(tool: .geneticCode) {
            Section {
                strandField("Reference", text: $reference, id: "codeReference")
                strandField("Variant", text: $variant, id: "codeVariant")
            } header: {
                Text("Coding strand, 5\u{2032} to 3\u{2032}")
            } footer: {
                Text("A, C, G and T. Translation starts at the first ATG.")
            }
            .wardRowBackground()

            Section("Result") {
                ScienceReading(label: "Change", value: kind.name)
                strand("mRNA", mRNA)
                strand("Protein", threeLetter(protein))
                if kind != .none {
                    strand("Variant protein", threeLetter(changed))
                }
            }
            .wardRowBackground()
            .accessibilityElement(children: .combine)

            Section("Try") {
                SciencePresetButton(title: "Sickle cell", detail: "\u{03B2}-globin GAG \u{2192} GTG: glutamate to valine") {
                    variant = "ATGGTGCACCTGACTCCTGTGGAGAAGTCTGCC"
                }
                SciencePresetButton(title: "Silent", detail: "GAG \u{2192} GAA: still glutamate") {
                    variant = "ATGGTGCACCTGACTCCTGAAGAGAAGTCTGCC"
                }
                SciencePresetButton(title: "Nonsense", detail: "AAG \u{2192} TAG: a stop codon") {
                    variant = "ATGGTGCACCTGACTCCTGAGGAGTAGTCTGCC"
                }
                SciencePresetButton(title: "Frameshift", detail: "One base lost") {
                    variant = "ATGGTGCACCTGACTCCTGAGAGAAGTCTGCC"
                }
            }
            .wardRowBackground()
        }
    }

    private func strandField(_ label: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(label).font(.caption).foregroundStyle(Color.wardInkSecondary)
            TextField(label, text: text, axis: .vertical)
                .font(WardType.obs)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, WardSpace.m)
                .padding(.vertical, WardSpace.s)
                .wardInset(in: RoundedRectangle(cornerRadius: WardRadius.field, style: .continuous), control: true)
                .accessibilityIdentifier(id)
        }
    }

    private func strand(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: WardSpace.xs) {
            Text(label).font(.caption).foregroundStyle(Color.wardInkSecondary)
            Text(text.isEmpty ? "\u{2014}" : text)
                .font(WardType.obs)
                .foregroundStyle(Color.wardInk)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
