import SwiftUI

/// A theme's legend ("What the bodies mean" in Space, "What the cells mean"
/// in Neurons, "What the parts mean" in Circuit), from the Look menu or the first-run card: a size ladder
/// across the top, then one row per kind of body, then how to move about.
/// The words and pictures are the theme's own (GraphLegendContent).
struct GraphLegendSheet: View {
    var theme: GraphTheme = .space
    @Environment(\.dismiss) private var dismiss

    private var content: GraphLegendContent { GraphLegendContent.of(theme) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ladder
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(content.rows, id: \.name) { row in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: row.symbol)
                                .font(.title3)
                                .foregroundStyle(row.tint)
                                .frame(width: 30)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.name).font(.headline)
                                Text(row.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.name + ": " + Self.lowered(row.text))
                    }
                } footer: {
                    Text(content.footer)
                        .font(.footnote)
                        .padding(.top, 6)
                }
            }
            .navigationTitle(theme.legendTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier(theme == .space ? "universeLegend" : theme.rawValue + "Legend")
    }

    /// Five circles, biggest to smallest, captioned: what holds more is
    /// bigger.
    private var ladder: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(content.rungs, id: \.caption) { rung in
                    VStack(spacing: 8) {
                        rungCircle(rung)
                            .frame(width: 44, height: 36)
                        Text(rung.caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(content.ladderCaption)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.ladderLabel)
    }

    @ViewBuilder
    private func rungCircle(_ rung: GraphLegendRung) -> some View {
        ZStack {
            Circle()
                .fill(rung.fill)
                .frame(width: rung.size, height: rung.size)
            if rung.ringed {
                Ellipse()
                    .stroke(rung.ring, lineWidth: 1.5)
                    .frame(width: rung.size * 1.8, height: rung.size * 0.55)
            } else if rung.halo {
                Circle()
                    .stroke(rung.ring, lineWidth: 2.5)
                    .frame(width: rung.size + 3, height: rung.size + 3)
            }
        }
    }

    /// The row's text, starting lower case, for "Name: text".
    private static func lowered(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}

/// One circle of a legend's size ladder.
struct GraphLegendRung {
    let caption: String
    let size: CGFloat
    let fill: Color
    let ring: Color
    var halo: Bool = false
    var ringed: Bool = false
}

/// One row of a legend: a kind of body, in one line.
struct GraphLegendRow {
    let symbol: String
    let name: String
    let text: String
    let tint: Color
}

/// What a theme's legend says. A new theme adds its own case here.
struct GraphLegendContent {
    let rungs: [GraphLegendRung]
    let ladderCaption: String
    let ladderLabel: String
    let rows: [GraphLegendRow]
    let footer: String

    static func of(_ theme: GraphTheme) -> GraphLegendContent {
        switch theme {
        case .neurons: return neurons
        case .circuit: return circuit
        case .space: return space
        }
    }

    // Each theme's content is built from typed pieces (colours, rungs, rows,
    // footer), each its own small expression, so none of them strains the
    // type checker; the texts are single literals, no `+`.

    // MARK: Space

    private static let gold: Color = Color(red: 1.0, green: 0.68, blue: 0.28)
    private static let starFill: Color = Color(red: 1.0, green: 0.95, blue: 0.78)
    private static let pageFill: Color = Color(red: 0.82, green: 0.66, blue: 0.46)
    private static let pageRing: Color = Color(red: 0.95, green: 0.86, blue: 0.66)
    private static let ideaBlue: Color = Color(red: 0.25, green: 0.48, blue: 0.85)
    private static let detailGrey: Color = Color(white: 0.62)
    private static let gasTint: Color = Color(red: 0.86, green: 0.70, blue: 0.48)
    private static let rockTint: Color = Color(red: 0.35, green: 0.6, blue: 1.0)
    private static let moonTint: Color = Color(white: 0.7)
    private static let pulsarTint: Color = Color(red: 0.7, green: 0.8, blue: 1.0)
    private static let cometTint: Color = Color(red: 0.55, green: 1.0, blue: 0.9)
    private static let beamTint: Color = Color(red: 1.0, green: 0.78, blue: 0.5)

    private static let spaceRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Top folder", size: 30, fill: .black, ring: gold, halo: true),
        GraphLegendRung(caption: "Folder", size: 24, fill: starFill, ring: .clear),
        GraphLegendRung(caption: "Page", size: 18, fill: pageFill, ring: pageRing, ringed: true),
        GraphLegendRung(caption: "Idea", size: 13, fill: ideaBlue, ring: .clear),
        GraphLegendRung(caption: "Detail", size: 8, fill: detailGrey, ring: .clear)
    ]

    private static let spaceRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "circle.circle.fill", name: "Black hole",
                       text: "A top-level folder: the heart of a galaxy. Notes filed straight in it orbit close; its folders shine round it as stars. Bigger holds more notes.",
                       tint: gold),
        GraphLegendRow(symbol: "sun.max.fill", name: "Star",
                       text: "A folder inside a folder: yellow, orange one level deeper, red deeper still. Bigger holds more; a folder is always drawn a little smaller than the one it sits in. An empty folder is a dark star.",
                       tint: .yellow),
        GraphLegendRow(symbol: "circle.lefthalf.filled", name: "Gas giant",
                       text: "A page. Bigger is longer; rings mean over 250 words.", tint: gasTint),
        GraphLegendRow(symbol: "globe.europe.africa.fill", name: "Rocky planet",
                       text: "An idea. Brighter means more links.", tint: rockTint),
        GraphLegendRow(symbol: "moon.fill", name: "Moon",
                       text: "A short idea linked only to the note it circles.", tint: moonTint),
        GraphLegendRow(symbol: "dot.radiowaves.left.and.right", name: "Pulsar",
                       text: "An idea linking notes in two or more other folders. Its links pulse together.",
                       tint: pulsarTint),
        GraphLegendRow(symbol: "sparkle", name: "Comet",
                       text: "A note in no folder. It swings past the folder it links to most; file it and it settles into orbit. Older ones wait in the far cloud.",
                       tint: cometTint),
        GraphLegendRow(symbol: "point.3.connected.trianglepath.dotted", name: "Links",
                       text: "Straight inside a folder, arched between folders, faint between galaxies. Links never pull.",
                       tint: beamTint)
    ]

    private static let spaceFooter: String = "Inner orbits turn faster. Touch and hold for a name. Tap a note twice to open it. Tap a star or black hole twice to fly in, twice again to open the folder. Drag a star and its planets follow."

    static let space: GraphLegendContent = GraphLegendContent(
        rungs: spaceRungs, ladderCaption: "Bigger bodies hold more.",
        ladderLabel: "Size ladder: top folder, folder, page, idea, detail",
        rows: spaceRows, footer: spaceFooter)

    // MARK: Neurons

    private static let teal: Color = Color(red: 0.30, green: 0.95, blue: 0.85)
    private static let green: Color = Color(red: 0.50, green: 1.0, blue: 0.55)
    private static let amber: Color = Color(red: 1.0, green: 0.72, blue: 0.30)
    private static let tealGel: Color = teal.opacity(0.22)
    private static let greenGel: Color = green.opacity(0.22)
    private static let tealBody: Color = teal.opacity(0.3)
    private static let tealRing: Color = teal.opacity(0.8)
    private static let tealFaint: Color = teal.opacity(0.6)
    private static let gliaGel: Color = Color(white: 0.75).opacity(0.4)
    private static let interTint: Color = Color(red: 0.42, green: 0.72, blue: 1.0)
    private static let gliaTint: Color = Color(white: 0.8)
    private static let crossTint: Color = Color(red: 0.75, green: 0.58, blue: 1.0)
    private static let receptorTint: Color = Color(red: 1.0, green: 0.82, blue: 0.45)

    private static let neuronRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Region", size: 30, fill: tealGel, ring: teal, halo: true),
        GraphLegendRung(caption: "Relay", size: 24, fill: greenGel, ring: green, halo: true),
        GraphLegendRung(caption: "Page", size: 18, fill: tealBody, ring: tealRing, halo: true),
        GraphLegendRung(caption: "Idea", size: 13, fill: tealBody, ring: tealFaint, halo: true),
        GraphLegendRung(caption: "Glia", size: 8, fill: gliaGel, ring: .clear)
    ]

    private static let neuronRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "brain", name: "Region",
                       text: "A top-level folder: a brain region, its big pyramidal cell (an upper motor neuron) at the heart of a cluster of its notes. Bigger holds more.",
                       tint: teal),
        GraphLegendRow(symbol: "arrow.triangle.branch", name: "Relay",
                       text: "A folder inside a folder: the next relay down a descending pathway from the brain, a brainstem nucleus, then a spinal cord neuron, then an autonomic ganglion on the way to its organ. Always a little smaller than the one it hangs from.",
                       tint: green),
        GraphLegendRow(symbol: "circle.hexagongrid.fill", name: "Neuron",
                       text: "A page: a large neuron. Bigger and more branched is longer.", tint: teal),
        GraphLegendRow(symbol: "smallcircle.filled.circle", name: "Interneuron",
                       text: "An idea: a small neuron. Brighter means more links.", tint: interTint),
        GraphLegendRow(symbol: "allergens", name: "Glia",
                       text: "A short idea linked only to the note it hugs, like an astrocyte tending its neuron.",
                       tint: gliaTint),
        GraphLegendRow(symbol: "arrow.left.and.right.circle.fill", name: "Commissural neuron",
                       text: "An idea linking notes in two or more other folders; its fibres cross between them like the corpus callosum's.",
                       tint: crossTint),
        GraphLegendRow(symbol: "antenna.radiowaves.left.and.right", name: "Receptor",
                       text: "A note in no folder with links: a sensory cell at the edge, sending impulses in. With no links it drifts as microglia.",
                       tint: receptorTint),
        GraphLegendRow(symbol: "bolt.horizontal.fill", name: "Axons",
                       text: "Links. Impulses run from the sending cell at random times and flash at the synapse. Tracts join regions; each folder's pathway runs down to the folders inside it.",
                       tint: amber)
    ]

    private static let neuronFooter: String = "Cells drift gently in their fluid. Touch and hold for a name. Tap a cell twice to open its note. Tap a region or relay twice to fly in, twice again to open the folder. Drag a region and its whole pathway follows."

    /// The Neurons (GraphNeurons): one line per kind of cell.
    static let neurons: GraphLegendContent = GraphLegendContent(
        rungs: neuronRungs, ladderCaption: "Bigger cells hold more.",
        ladderLabel: "Size ladder: region, relay, page, idea, glia",
        rows: neuronRows, footer: neuronFooter)
}

extension GraphLegendContent {
    // MARK: Circuit

    private static let copper: Color = Color(red: 0.98, green: 0.64, blue: 0.32)
    private static let boardGreen: Color = Color(red: 0.10, green: 0.42, blue: 0.26)
    private static let lid: Color = Color(red: 0.72, green: 0.74, blue: 0.77)
    private static let ledAmber: Color = Color(red: 1.0, green: 0.72, blue: 0.22)
    private static let epoxy: Color = Color(white: 0.12)
    private static let pinGrey: Color = Color(white: 0.7)
    private static let canNavy: Color = Color(red: 0.10, green: 0.16, blue: 0.42)
    private static let canSleeve: Color = Color(red: 0.62, green: 0.68, blue: 0.78)
    private static let resistorBeige: Color = Color(red: 0.80, green: 0.68, blue: 0.48)
    private static let smdGrey: Color = Color(white: 0.3)
    private static let moduleTint: Color = Color(white: 0.75)
    private static let capTint: Color = Color(red: 0.45, green: 0.55, blue: 0.95)
    private static let diodeTint: Color = Color(white: 0.85)
    private static let smdTint: Color = Color(white: 0.55)
    private static let headerTint: Color = Color(red: 1.0, green: 0.78, blue: 0.36)
    private static let fingerTint: Color = Color(red: 1.0, green: 0.8, blue: 0.4)

    private static let circuitRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Processor", size: 30, fill: lid, ring: boardGreen, halo: true),
        GraphLegendRung(caption: "Module", size: 24, fill: epoxy, ring: pinGrey, halo: true),
        GraphLegendRung(caption: "Page", size: 18, fill: canNavy, ring: canSleeve, halo: true),
        GraphLegendRung(caption: "Idea", size: 13, fill: resistorBeige, ring: .clear),
        GraphLegendRung(caption: "SMD", size: 8, fill: smdGrey, ring: .clear)
    ]

    private static let circuitRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "cpu", name: "Processor",
                       text: "A top-level folder: a big chip under a metal lid, its name silkscreened on it, at the heart of its own zone of the board. Bigger holds more.",
                       tint: lid),
        GraphLegendRow(symbol: "memorychip", name: "Module",
                       text: "A folder inside a folder: a smaller chip on its own sub-board beside its parent's, wired to it by a bus. Always a little smaller than the chip above it.",
                       tint: moduleTint),
        GraphLegendRow(symbol: "cylinder.fill", name: "Capacitor",
                       text: "A page. Bigger is longer; from 250 words it is a copper inductor coil.", tint: capTint),
        GraphLegendRow(symbol: "capsule.fill", name: "Resistor",
                       text: "An idea. With two or more links it is an LED that lights as current arrives.",
                       tint: ledAmber),
        GraphLegendRow(symbol: "arrow.right.to.line", name: "Diode",
                       text: "An idea whose links all run out into one other folder: current one way out.",
                       tint: diodeTint),
        GraphLegendRow(symbol: "square.fill", name: "Surface-mount part",
                       text: "A short idea linked only to the note it is soldered beside.", tint: smdTint),
        GraphLegendRow(symbol: "rectangle.split.3x1.fill", name: "Bus header",
                       text: "An idea linking notes in two or more other folders: a row of pins the traces between zones run through.",
                       tint: headerTint),
        GraphLegendRow(symbol: "rectangle.bottomthird.inset.filled", name: "Edge finger",
                       text: "A note in no folder with links, on the board's bottom edge where current comes in. With no links it is a bare pad on the top edge.",
                       tint: fingerTint),
        GraphLegendRow(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", name: "Traces",
                       text: "Links: copper routed square with 45° corners. Current flows along them and packets run at random times; buses join zones and each chip to its modules.",
                       tint: copper)
    ]

    private static let circuitFooter: String = "Touch and hold for a name. Tap a part twice to open its note. Tap a processor or module twice to fly in, twice again to open the folder. Drag a chip and its parts and sub-board come with it; the traces re-route as it moves."

    /// The Circuit (GraphCircuit): one line per kind of part.
    static let circuit: GraphLegendContent = GraphLegendContent(
        rungs: circuitRungs, ladderCaption: "Bigger parts hold more.",
        ladderLabel: "Size ladder: processor, module, page, idea, surface-mount part",
        rows: circuitRows, footer: circuitFooter)
}

/// A theme's one-time card (the Universe's first): what the bodies are, in
/// two lines, with the legend a tap away. Shown once, never in the design preview; it sits
/// at the bottom leading corner, clear of the round tools.
struct GraphUniverseHint: View {
    var theme: GraphTheme = .space
    let more: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(theme.cardTitle)
                .font(.headline)
            Text(theme.cardText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("What else?", action: more)
                    .buttonStyle(.glass)
                Button("Got it", action: done)
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("universeHint")
    }
}
