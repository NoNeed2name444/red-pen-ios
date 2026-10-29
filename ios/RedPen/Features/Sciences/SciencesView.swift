import SwiftUI

/// The core sciences (SupportPage.sciences): the 3D atlas first, then the
/// nine subjects and the ten body systems of ScienceCatalog, each opening its
/// tools and topics. A search over the topics and tools sits on top.
///
/// A list on a phone. On a wide iPad the same links are tiles, a few across,
/// the way the tour of examples lays them out, with the same identifiers.
struct SciencesView: View {
    @Environment(\.windowSpan) private var span
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""

    /// Tiles rather than rows: only with the room of a wide iPad window.
    private var tiles: Bool { span == .broad }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if searching {
                results
            } else if tiles {
                grid
            } else {
                list
            }
        }
        .navigationTitle("Sciences")
        // inline, as the examples hub's title shows pushed from the library;
        // a large one went unseen on a stack of its own (the screenshots)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find a topic or tool")
        .accessibilityIdentifier("sciencesHub")
    }

    // MARK: - A phone: one list

    private var list: some View {
        List {
            Section {
                atlasLink
            } header: { Text("Anatomy in 3D") }
            .wardRowBackground()

            Section {
                subjectLinks
            } header: { Text("Subjects") }
            .wardRowBackground()

            Section {
                systemLinks
            } header: { Text("Body systems") }
            .wardRowBackground()
        }
        .wardForm()
    }

    // MARK: - A wide iPad: tiles

    private var grid: some View {
        let columns: [GridItem] = GridItem.tiles(minimum: 220, accessibilitySize: typeSize.isAccessibilitySize)
        return ScrollView {
            VStack(alignment: .leading, spacing: WardSpace.section) {
                gridSection("Anatomy in 3D", columns: columns) { atlasLink }
                gridSection("Subjects", columns: columns) { subjectLinks }
                gridSection("Body systems", columns: columns) { systemLinks }
            }
            .padding(WardSpace.gutter)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .wardScreen()
    }

    private func gridSection<Content: View>(_ title: String, columns: [GridItem],
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: WardSpace.m) {
            WardSectionLabel(title)
                .padding(.horizontal, WardSpace.xs)
            LazyVGrid(columns: columns, alignment: .leading, spacing: WardSpace.m) {
                content()
            }
        }
    }

    // MARK: - The links, the same in both

    private var atlasLink: some View {
        ScienceLink(title: ScienceTool.atlas.name, symbol: ScienceTool.atlas.symbol,
                    detail: ScienceTool.atlas.blurb, id: "scienceAtlas", tile: tiles) {
            AnatomyAtlasView()
        }
    }

    @ViewBuilder
    private var subjectLinks: some View {
        ForEach(ScienceSubject.allCases) { subject in
            ScienceLink(title: subject.name, symbol: subject.symbol, detail: subject.blurb,
                        id: "scienceSubject-\(subject.rawValue)", tile: tiles) {
                ScienceSubjectView(subject: subject)
            }
        }
    }

    @ViewBuilder
    private var systemLinks: some View {
        ForEach(BodySystem.allCases) { system in
            ScienceLink(title: system.name, symbol: system.symbol, detail: system.blurb,
                        id: "scienceSystem-\(system.rawValue)", tile: tiles) {
                BodySystemView(system: system)
            }
        }
    }

    // MARK: - Search

    private var matchingTools: [ScienceTool] {
        let words: [String] = query.lowercased().split(separator: " ").map(String.init)
        return ScienceTool.allCases.filter { tool in
            let text: String = (tool.name + " " + tool.blurb).lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    private var results: some View {
        let topics: [ScienceTopic] = ScienceCatalog.search(query)
        let tools: [ScienceTool] = matchingTools
        return List {
            if topics.isEmpty && tools.isEmpty {
                WardEmptyState(symbol: "magnifyingglass", title: "No results",
                               message: "Try a structure, a disease or a word from a topic, such as \u{201C}shock\u{201D} or \u{201C}glycolysis\u{201D}.")
                    .listRowBackground(Color.clear)
            }
            if !tools.isEmpty {
                Section {
                    ForEach(tools) { tool in
                        ScienceLink(title: tool.name, symbol: tool.symbol, detail: tool.blurb,
                                    id: "scienceTool-\(tool.rawValue)", tile: false) {
                            tool.page
                        }
                    }
                } header: { Text("Tools") }
                .wardRowBackground()
            }
            if !topics.isEmpty {
                Section {
                    ForEach(topics) { topic in
                        ScienceTopicLink(topic: topic)
                    }
                } header: { Text("Topics") }
                .wardRowBackground()
            }
        }
        .wardForm()
    }
}

/// One link in the Sciences: a row in a list, or a raised tile on a wide
/// iPad. The row is the shared WardRow, without its chevron since the list
/// draws its own.
struct ScienceLink<Destination: View>: View {
    let title: String
    let symbol: String
    let detail: String
    let id: String
    var tile: Bool = false
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        if tile {
            NavigationLink {
                destination()
            } label: {
                ScienceTile(title: title, symbol: symbol, detail: detail)
            }
            .buttonStyle(.popTile)
            .accessibilityIdentifier(id)
        } else {
            NavigationLink {
                destination()
            } label: {
                WardRow(symbol: symbol, title: title, detail: detail, chevron: false)
            }
            .hoverEffect(.highlight)
            .accessibilityIdentifier(id)
        }
    }
}

/// A link as a tile: the symbol, the title and a line. The tile style raises
/// it, so it draws no card of its own (as the tour's tiles).
private struct ScienceTile: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: WardSpace.m) {
            WardIconSquare(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: WardSpace.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.wardInkSecondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(WardSpace.gutter)
    }
}

// MARK: - Symbols (the catalog is Foundation only; the screens choose these)

extension ScienceSubject {
    var symbol: String {
        switch self {
        case .anatomy: return "figure.stand"
        case .physiology: return "waveform.path.ecg"
        case .biochemistry: return "flask"
        case .pathology: return "bandage"
        case .microbiology: return "microbe"
        case .immunology: return "shield.lefthalf.filled"
        case .genetics: return "square.grid.2x2"
        case .pharmacology: return "pills"
        case .biostatistics: return "percent"
        }
    }
}

extension BodySystem {
    var symbol: String {
        switch self {
        case .cardiovascular: return "heart"
        case .respiratory: return "lungs"
        case .renal: return "drop"
        case .digestive: return "fork.knife"
        case .endocrine: return "bolt.horizontal.circle"
        case .reproductive: return "person.2"
        case .nervous: return "brain"
        case .musculoskeletal: return "figure.strengthtraining.traditional"
        case .blood: return "cross.vial"
        case .skin: return "hand.raised"
        }
    }

    /// How many topics the system gathers, for its row.
    var blurb: String {
        let count: Int = ScienceCatalog.topics(self).count
        return count == 1 ? "1 topic" : "\(count) topics"
    }
}

extension ScienceTool {
    var symbol: String {
        switch self {
        case .atlas: return "rotate.3d"
        case .membranePotential: return "bolt"
        case .actionPotential: return "waveform"
        case .cardiacCycle: return "heart.circle"
        case .haemodynamics: return "gauge.with.dots.needle.50percent"
        case .starling: return "arrow.left.and.right"
        case .oxygenCurve: return "lungs"
        case .alveolarGas: return "wind"
        case .renalClearance: return "drop"
        case .acidBase: return "testtube.2"
        case .enzymeKinetics: return "function"
        case .pathways: return "arrow.triangle.branch"
        case .shock: return "exclamationmark.triangle"
        case .infarct: return "heart.slash"
        case .necrosis: return "aqi.low"
        case .glomerular: return "circle.grid.cross"
        case .tumourNames: return "textformat.abc"
        case .microbeKey: return "list.bullet.indent"
        case .microbes: return "microbe"
        case .growthCurve: return "chart.line.uptrend.xyaxis"
        case .immuneCells: return "circle.hexagonpath"
        case .antibodyResponse: return "chart.xyaxis.line"
        case .hypersensitivity: return "allergens"
        case .complement: return "puzzlepiece"
        case .punnett: return "square.grid.2x2"
        case .hardyWeinberg: return "person.3"
        case .geneticCode: return "character.textbox"
        case .pharmacokinetics: return "pills"
        case .diagnosticTests: return "percent"
        }
    }

    /// The page the tool opens.
    @ViewBuilder
    var page: some View {
        switch self {
        case .atlas: AnatomyAtlasView()
        case .membranePotential: MembranePotentialTool()
        case .actionPotential: ActionPotentialTool()
        case .cardiacCycle: CardiacCycleTool()
        case .haemodynamics: HaemodynamicsTool()
        case .starling: StarlingTool()
        case .oxygenCurve: OxygenCurveTool()
        case .alveolarGas: AlveolarGasTool()
        case .renalClearance: RenalClearanceTool()
        case .acidBase: AcidBaseTool()
        case .enzymeKinetics: EnzymeKineticsTool()
        case .pathways: PathwaysTool()
        case .shock: ShockTool()
        case .infarct: InfarctTool()
        case .necrosis: NecrosisTool()
        case .glomerular: GlomerularTool()
        case .tumourNames: TumourNamesTool()
        case .microbeKey: MicrobeKeyTool()
        case .microbes: MicrobesTool()
        case .growthCurve: GrowthCurveTool()
        case .immuneCells: ImmuneCellsTool()
        case .antibodyResponse: AntibodyResponseTool()
        case .hypersensitivity: HypersensitivityTool()
        case .complement: ComplementTool()
        case .punnett: PunnettTool()
        case .hardyWeinberg: HardyWeinbergTool()
        case .geneticCode: GeneticCodeTool()
        case .pharmacokinetics: PharmacokineticsTool()
        case .diagnosticTests: DiagnosticTestsTool()
        }
    }
}
