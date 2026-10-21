import SwiftUI

/// A theme's legend ("How your universe is built", "How your network is
/// built", "How the fast map is built"), from the Look menu or the
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
                        .listRowSeparator(.hidden)
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
                                    .foregroundStyle(Color.wardInkSecondary)
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
                        .wardRowBackground()
                    }
                } footer: {
                    Text(content.footer)
                        .font(.footnote)
                        .foregroundStyle(Color.wardInkSecondary)
                        .padding(.top, 6)
                }
            }
            .wardForm()
            .navigationTitle(theme.legendTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                    .buttonStyle(.wardCompact)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .accessibilityIdentifier(theme == .space ? "universeLegend" : theme.rawValue + "Legend")
    }

    /// Five circles, biggest to smallest, captioned: what holds more is
    /// bigger.
    private var ladder: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(content.rungs, id: \.caption) { rung in
                    VStack(spacing: 8) {
                        rungCircle(rung)
                            .frame(height: 36)
                        // two lines rather than cut short or shrunk
                        Text(rung.caption)
                            .font(.caption)
                            .foregroundStyle(Color.wardInkSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 2)
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

/// How the legend sheet is presented: half or full height on a phone; on
/// a broad window (an iPad) a full page-sized sheet, never a small form
/// that cuts the ladder and the rows short.
struct GraphLegendPresentation: ViewModifier {
    var regular: Bool

    func body(content: Content) -> some View {
        if regular {
            content
                .presentationSizing(.page)
                .presentationDetents([.large])
        } else {
            content
                .presentationDetents([.medium, .large])
        }
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
        case .space: return space
        case .performance: return performance
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

    // NeuronPalette's: green, cyan, pink and amber on deep blue
    private static let teal: Color = Color(red: 0.35, green: 1.0, blue: 0.5)
    private static let green: Color = Color(red: 0.25, green: 0.92, blue: 1.0)
    private static let amber: Color = Color(red: 1.0, green: 0.72, blue: 0.30)
    private static let tealGel: Color = teal.opacity(0.22)
    private static let greenGel: Color = green.opacity(0.22)
    private static let tealBody: Color = teal.opacity(0.3)
    private static let tealRing: Color = teal.opacity(0.8)
    private static let tealFaint: Color = teal.opacity(0.6)
    private static let gliaGel: Color = Color(white: 0.75).opacity(0.4)
    private static let interTint: Color = Color(red: 1.0, green: 0.42, blue: 0.78)
    private static let stateTint: Color = Color(red: 0.82, green: 0.36, blue: 1.0)
    private static let gliaTint: Color = Color(white: 0.8)
    private static let crossTint: Color = Color(red: 0.75, green: 0.58, blue: 1.0)
    private static let receptorTint: Color = Color(red: 1.0, green: 0.82, blue: 0.45)

    private static let neuronRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Cell", size: 30, fill: tealGel, ring: teal, halo: true),
        GraphLegendRung(caption: "Part", size: 22, fill: greenGel, ring: green, halo: true),
        GraphLegendRung(caption: "Free", size: 15, fill: gliaGel, ring: .clear),
        GraphLegendRung(caption: "Page", size: 12, fill: tealBody, ring: tealRing, halo: true),
        GraphLegendRung(caption: "Idea", size: 9, fill: tealBody, ring: tealFaint, halo: true)
    ]

    private static let neuronRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "circle.hexagongrid.fill", name: "Cell",
                       text: "A top-level folder: a whole cell, glowing through its membrane round a bright nucleus. Its folders and notes float inside it. Bigger holds more.",
                       tint: teal, how: "Make a folder: + \u{203A} New folder."),
        GraphLegendRow(symbol: "smallcircle.filled.circle", name: "Cell part",
                       text: "A folder inside a folder: an organelle inside its cell, and a smaller one inside that for each folder deeper down. Each holds its own notes.",
                       tint: green, how: "A folder inside a folder: its menu in the List \u{203A} New folder inside."),
        GraphLegendRow(symbol: "circle.fill", name: "Vesicle",
                       text: "A page: a bright-rimmed vesicle floating inside the folder that holds it. Longer pages are bigger.",
                       tint: teal, how: "Add a page: + \u{203A} New page."),
        GraphLegendRow(symbol: "aqi.medium", name: "Granule",
                       text: "An idea: a small bright granule inside the folder that holds it. Brighter means more links.",
                       tint: interTint, how: "Add an idea: + \u{203A} New idea, or type it in the bar."),
        GraphLegendRow(symbol: "antenna.radiowaves.left.and.right", name: "Receptor",
                       text: "A note in no folder with links: a free cell at the edge, its leading process reaching in to the cells it links to.",
                       tint: receptorTint, how: "A note in no folder (Move \u{203A} No folder)."),
        GraphLegendRow(symbol: "allergens", name: "Drifting cell",
                       text: "A note in no folder and no links: a small glial cell drifting at the edge.",
                       tint: gliaTint, how: "A note in no folder with no links."),
        GraphLegendRow(symbol: "arrow.up.left.and.arrow.down.right", name: "Opening a cell",
                       text: "A cell shows its insides only when you open it: its parts and notes grow out from its heart one after another, and fold back in when you leave.",
                       tint: crossTint, how: "Tap a cell twice to fly in and open it."),
        GraphLegendRow(symbol: "sparkles", name: "Cell states",
                       text: "Each note shows a state, as the space\u{2019}s bodies have styles: resting, slowly breathing; firing, a burst of spikes with calcium waves spreading; releasing, a cloud of transmitter drifting out; pacemaker, a steady beat with two lobes sweeping round; migrating, crawling on behind its growth cone; engulfing, drawing debris into a dark phagosome. Left alone, a receptor migrates and a drifting cell engulfs.",
                       tint: stateTint, how: "Look \u{203A} Cells: one state for every note, or Cell by cell for one folder."),
        GraphLegendRow(symbol: "bolt.horizontal.fill", name: "Axons and synapses",
                       text: "Links. Each grows out of its cell as part of it, thick where it leaves and tapering to a synapse on the cell it reaches; impulses run along it. Inside an open cell, links between its notes run inside it.",
                       tint: amber, how: "Link two notes: type [[ and a note\u{2019}s title in a note.")
    ]

    private static let neuronFooter: String = "Cells drift gently in deep blue fluid. Touch and hold for a name. Tap a note twice to open it. Tap a cell or a part twice to fly in and open it, twice again to open the folder. Drag a cell and everything inside it follows."

    /// The Neurons (GraphNeurons): one line per kind of cell.
    static let neurons: GraphLegendContent = GraphLegendContent(
        rungs: neuronRungs, ladderCaption: "Bigger cells hold more.",
        ladderLabel: "Size ladder: cell, part, free cell, page, idea",
        rows: neuronRows, footer: neuronFooter)
}

extension GraphLegendContent {
    // MARK: Performance

    private static let hubWhite: Color = Color(red: 0.86, green: 0.9, blue: 1.0)
    private static let pointBlue: Color = Color(red: 0.36, green: 0.61, blue: 1.0)
    private static let pointRose: Color = Color(red: 1.0, green: 0.37, blue: 0.49)
    private static let glowAmber: Color = Color(red: 1.0, green: 0.71, blue: 0.26)
    private static let lineGrey: Color = Color(white: 0.75)
    private static let glowSoft: Color = glowAmber.opacity(0.35)

    private static let performanceRungs: [GraphLegendRung] = [
        GraphLegendRung(caption: "Far folder", size: 30, fill: glowSoft, ring: .clear),
        GraphLegendRung(caption: "Folder", size: 22, fill: hubWhite, ring: .clear),
        GraphLegendRung(caption: "Page", size: 16, fill: pointRose, ring: .clear),
        GraphLegendRung(caption: "Idea", size: 11, fill: pointBlue, ring: .clear),
        GraphLegendRung(caption: "Far note", size: 5, fill: lineGrey, ring: .clear)
    ]

    private static let performanceRows: [GraphLegendRow] = [
        GraphLegendRow(symbol: "circle.hexagongrid.fill", name: "Folder",
                       text: "A bright hub with its notes round it in a ball. Each top-level folder and everything in it has its own colour; a folder inside a folder is a lighter shade.",
                       tint: hubWhite, how: "Make a folder: + \u{203A} New folder."),
        GraphLegendRow(symbol: "circle.fill", name: "Page",
                       text: "A larger point. Brighter means more links.", tint: pointRose,
                       how: "Add a page: + \u{203A} New page."),
        GraphLegendRow(symbol: "smallcircle.filled.circle", name: "Idea",
                       text: "A smaller point. Brighter means more links.", tint: pointBlue,
                       how: "Add an idea: + \u{203A} New idea, or type it in the bar."),
        GraphLegendRow(symbol: "sun.min.fill", name: "Glow",
                       text: "A folder too far away to show its notes one by one: one soft light stands for all of them, and links into it end at its middle. Come closer and it opens into its points.",
                       tint: glowAmber),
        GraphLegendRow(symbol: "line.diagonal", name: "Lines",
                       text: "Links, coloured by the notes at their ends, fainter between folders and in the distance. Thin grey lines join each folder to the one it sits in.",
                       tint: lineGrey, how: "Link two notes: type [[ and a note\u{2019}s title in a note."),
        GraphLegendRow(symbol: "speedometer", name: "Speed",
                       text: "The readout at the top counts the notes, the links and the frames a second. Its menu shows a demo map of 100,000 or 300,000 made-up notes; your own notes are never touched.",
                       tint: lineGrey)
    ]

    private static let performanceFooter: String = "Drag to turn, two fingers to slide, pinch to zoom. Tap a point to preview it; tap a glow to fly in. Tap a point twice to open it, empty space twice to see the whole map."

    /// The Performance theme (GraphPerf*): what the points, glows and lines are.
    static let performance: GraphLegendContent = GraphLegendContent(
        rungs: performanceRungs, ladderCaption: "Nearer things show more detail.",
        ladderLabel: "Size ladder: far folder, folder, page, idea, far note",
        rows: performanceRows, footer: performanceFooter)
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
                            .foregroundStyle(Color.wardInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Full list", action: more)
                    .buttonStyle(.wardQuiet)
                Button("Got it", action: done)
                    .buttonStyle(.wardCompact)
            }
        }
        .foregroundStyle(Color.wardInk)
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .wardRaised(in: RoundedRectangle(cornerRadius: 22, style: .continuous), lift: .high)
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
        case .neurons: return "No cells yet. Add a folder to grow your first one."
        case .performance: return "No folders yet: every note shares one cluster. Add a folder to start a cluster of its own."
        }
    }

    private var button: String { "Add folder" }

    var body: some View {
        VStack(spacing: 8) {
            Text(words)
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(button, systemImage: "folder.badge.plus", action: add)
                .buttonStyle(.wardQuiet)
                .accessibilityIdentifier("graphAddFolder")
        }
        .padding(14)
        .frame(maxWidth: 340)
        .wardRaised(in: RoundedRectangle(cornerRadius: 20, style: .continuous), lift: .high)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphEmptyHint")
    }
}
