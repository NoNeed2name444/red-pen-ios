import SwiftUI

/// A theme's legend ("How your universe is built", "How your network is
/// built", "How your circuits are built"), from the Look menu or the
/// first-run card: a size ladder across the top, then one row per kind of
/// body - what it is, and how to make one with the app's own controls (the
/// + button in the Ideas bar, a folder's menu in the List, [[ ]] in a note)
/// - then how to move about. The words and pictures are the theme's own
/// (GraphLegendContent).
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
                                if !row.how.isEmpty {
                                    Label(row.how, systemImage: "plus.circle")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(row.tint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Self.spoken(row))
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

    /// What VoiceOver reads for a row: "Name: text. To add one: how".
    private static func spoken(_ row: GraphLegendRow) -> String {
        let said: String = row.name + ": " + lowered(row.text)
        guard !row.how.isEmpty else { return said }
        let how: String = " To add one: " + row.how
        return said + how
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

/// One row of a legend: a kind of body, in one line, and how to make one.
struct GraphLegendRow {
    let symbol: String
    let name: String
    let text: String
    let tint: Color
    var how: String = ""
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
                       tint: gold, how: "Make a folder: + \u{203A} New folder."),
        GraphLegendRow(symbol: "sun.max.fill", name: "Star",
                       text: "A folder inside a folder: yellow, orange one level deeper, red deeper still. Bigger holds more; a folder is always drawn a little smaller than the one it sits in. An empty folder is a dark star.",
                       tint: .yellow, how: "A folder inside a folder: its menu in the List \u{203A} New folder inside."),
        GraphLegendRow(symbol: "circle.lefthalf.filled", name: "Gas giant",
                       text: "A page. Bigger is longer; rings mean over 250 words.", tint: gasTint,
                       how: "Add a page: + \u{203A} New page."),
        GraphLegendRow(symbol: "globe.europe.africa.fill", name: "Rocky planet",
                       text: "An idea. Brighter means more links.", tint: rockTint,
                       how: "Add an idea: + \u{203A} New idea, or type it in the bar."),
        GraphLegendRow(symbol: "moon.fill", name: "Moon",
                       text: "A short idea linked only to the note it circles.", tint: moonTint,
                       how: "A short idea linked to one note."),
        GraphLegendRow(symbol: "dot.radiowaves.left.and.right", name: "Pulsar",
                       text: "An idea linking notes in two or more other folders. Its links pulse together.",
                       tint: pulsarTint, how: "Link an idea to notes in two other folders."),
        GraphLegendRow(symbol: "sparkle", name: "Comet",
                       text: "A note in no folder. It swings past the folder it links to most; file it and it settles into orbit. Older ones wait in the far cloud.",
                       tint: cometTint, how: "A note in no folder (Move \u{203A} No folder)."),
        GraphLegendRow(symbol: "point.3.connected.trianglepath.dotted", name: "Links",
                       text: "Straight inside a folder, arched between folders, faint between galaxies. Links never pull.",
                       tint: beamTint, how: "Link two notes: type [[ and a note\u{2019}s title in a note.")
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
                       tint: teal, how: "Make a folder: + \u{203A} New folder."),
        GraphLegendRow(symbol: "arrow.triangle.branch", name: "Relay",
                       text: "A folder inside a folder: the next relay down a descending pathway from the brain, a brainstem nucleus, then a spinal cord neuron, then an autonomic ganglion on the way to its organ. Always a little smaller than the one it hangs from.",
                       tint: green, how: "A folder inside a folder: its menu in the List \u{203A} New folder inside."),
        GraphLegendRow(symbol: "circle.hexagongrid.fill", name: "Neuron",
                       text: "A page: a large neuron. Bigger and more branched is longer.", tint: teal,
                       how: "Add a page: + \u{203A} New page."),
        GraphLegendRow(symbol: "smallcircle.filled.circle", name: "Interneuron",
                       text: "An idea: a small neuron. Brighter means more links.", tint: interTint,
                       how: "Add an idea: + \u{203A} New idea, or type it in the bar."),
        GraphLegendRow(symbol: "allergens", name: "Glia",
                       text: "A short idea linked only to the note it hugs, like an astrocyte tending its neuron.",
                       tint: gliaTint, how: "A short idea linked to one note."),
        GraphLegendRow(symbol: "arrow.left.and.right.circle.fill", name: "Commissural neuron",
                       text: "An idea linking notes in two or more other folders; its fibres cross between them like the corpus callosum's.",
                       tint: crossTint, how: "Link an idea to notes in two other folders."),
        GraphLegendRow(symbol: "antenna.radiowaves.left.and.right", name: "Receptor",
                       text: "A note in no folder with links: a sensory cell at the edge, sending impulses in. With no links it drifts as microglia.",
                       tint: receptorTint, how: "A note in no folder (Move \u{203A} No folder)."),
        GraphLegendRow(symbol: "bolt.horizontal.fill", name: "Axons and synapses",
                       text: "Links. Impulses run from the sending cell at random times; near its target each axon branches into fine twigs whose swollen tips press on the next cell, and the impulse crosses there. Tracts join regions; each folder's pathway runs down to the folders inside it.",
                       tint: amber, how: "Link two notes: type [[ and a note\u{2019}s title in a note.")
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

    private static let copper: Color = Color(red: 0.92, green: 0.60, blue: 0.32)
    private static let boardGreen: Color = Color(red: 0.10, green: 0.42, blue: 0.26)
    private static let chipBlack: Color = Color(white: 0.1)
    private static let chipEdge: Color = Color(white: 0.8)
    private static let canDark: Color = Color(red: 0.16, green: 0.18, blue: 0.2)
    private static let canStripe: Color = Color(white: 0.8)
    private static let ledAmber: Color = Color(red: 1.0, green: 0.70, blue: 0.22)
    private static let padGold: Color = Color(red: 1.0, green: 0.78, blue: 0.36)
    private static let current: Color = Color(red: 0.55, green: 0.95, blue: 1.0)
    private static let silkWhite: Color = Color(white: 0.85)

    private static let circuitRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Board chip", size: 30, fill: chipBlack, ring: chipEdge, halo: true),
        GraphLegendRung(caption: "Sub-chip", size: 24, fill: chipBlack, ring: chipEdge, halo: true),
        GraphLegendRung(caption: "Page", size: 18, fill: canDark, ring: canStripe, halo: true),
        GraphLegendRung(caption: "Idea", size: 13, fill: ledAmber, ring: .clear),
        GraphLegendRung(caption: "Pad", size: 10, fill: padGold, ring: .clear)
    ]

    private static let circuitRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "cpu", name: "Chip",
                       text: "A collection (a top-level folder): its own circuit board, the chip its controller. Bigger holds more.",
                       tint: silkWhite, how: "Make a folder: + \u{203A} New folder \u{2192} a new circuit board."),
        GraphLegendRow(symbol: "memorychip", name: "Smaller chip",
                       text: "A folder inside a folder: a smaller chip on its own sub-board, on a branch of its chip's bus.",
                       tint: silkWhite, how: "In the List, a folder\u{2019}s menu \u{203A} New folder inside."),
        GraphLegendRow(symbol: "cylinder.fill", name: "Capacitor",
                       text: "A page, on its chip's bus. Bigger is longer.", tint: canStripe,
                       how: "Add a page: + \u{203A} New page."),
        GraphLegendRow(symbol: "lightbulb.fill", name: "LED",
                       text: "An idea, on a branch off the page it links to; its linked ideas follow it in a row. Lit when it has links.",
                       tint: ledAmber, how: "Add an idea: + \u{203A} New idea, or type it in the bar."),
        GraphLegendRow(symbol: "bolt.fill", name: "Rails",
                       text: "Power (VCC) along each board's top, ground (GND) along its bottom: every part sits on a loop from one to the other.",
                       tint: copper),
        GraphLegendRow(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", name: "Traces",
                       text: "Links inside a board: copper, now and then carrying a packet of current down from the power rail. The LED it reaches lights.",
                       tint: current, how: "Link two notes: type [[ and a note\u{2019}s title in a note."),
        GraphLegendRow(symbol: "rectangle.connected.to.line.below", name: "Connectors",
                       text: "A link to another collection leaves its board at a gold edge connector and runs as a thin bus to the other board.",
                       tint: padGold, how: "Link notes in two different folders."),
        GraphLegendRow(symbol: "circle.fill", name: "Gold pad",
                       text: "A note in no folder, on the edge of the board it links to most.",
                       tint: padGold, how: "Move a note \u{203A} No folder.")
    ]

    private static let circuitFooter: String = "Touch and hold a part for its name; chips show theirs. Tap a part twice to open its note. Tap a chip twice to fly in to its board, twice again to open the folder. Drag a chip and its whole circuit comes with it."

    /// The Circuit (GraphCircuit): how the boards are built, and how to
    /// add to them.
    static let circuit: GraphLegendContent = GraphLegendContent(
        rungs: circuitRungs, ladderCaption: "Bigger parts hold more.",
        ladderLabel: "Size ladder: board chip, sub-chip, page, idea, pad",
        rows: circuitRows, footer: circuitFooter)
}

/// A theme's one-time card (the Universe's first): the three most useful
/// ways to add to the map (GraphTheme.cardSteps), with the full list a tap
/// away. Shown once, never in the design preview; it sits
/// at the bottom leading corner, clear of the round tools.
struct GraphUniverseHint: View {
    var theme: GraphTheme = .space
    /// The theme's three ways to add (the first time in a theme).
    var steps: Bool = true
    /// How to touch the map (GraphPeek.coachLines), once per theme.
    var touch: Bool = true
    let more: () -> Void
    let done: () -> Void

    private static let touchSymbols: [String] = ["hand.tap", "doc.text", "hand.draw"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(steps ? theme.cardTitle : "Touching the map")
                .font(.headline)
            if touch {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(GraphPeek.coachLines.enumerated()), id: \.offset) { k, line in
                        Label(line, systemImage: Self.touchSymbols[k % Self.touchSymbols.count])
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("touchHint")
            }
            if steps {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(theme.cardSteps, id: \.self) { step in
                        Label(step, systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Full list", action: more)
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

/// A gentle hint over a map with no folders yet: what a folder becomes in
/// this theme, and a button that makes one (the same action as the Ideas
/// bar's + › New folder).
struct GraphEmptyHint: View {
    var theme: GraphTheme = .space
    let add: () -> Void

    private var words: String {
        switch theme {
        case .space: return "No galaxies yet: your notes orbit one star. Add a folder to light your first black hole."
        case .neurons: return "No brain regions yet. Add a folder to grow your first one."
        case .circuit: return "No collections yet: every note sits on one board. Add a folder to place your first circuit of its own."
        }
    }

    private var button: String {
        theme == .circuit ? "Add circuit" : "Add folder"
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(words)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, systemImage: "folder.badge.plus", action: add)
                .buttonStyle(.glass)
                .accessibilityIdentifier("graphAddFolder")
        }
        .padding(14)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphEmptyHint")
    }
}
