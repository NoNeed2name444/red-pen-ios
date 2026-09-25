import SwiftUI

/// "What the bodies mean": the Universe look's legend (GraphUniverse),
/// from the Look menu or the first-run card. A size ladder across the top,
/// then one row per kind of body, then how to move about.
struct GraphLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ladder
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(Self.rows, id: \.name) { row in
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
                    Text(Self.footer)
                        .font(.footnote)
                        .padding(.top, 6)
                }
            }
            .navigationTitle("What the bodies mean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("universeLegend")
    }

    /// Five circles, biggest to smallest, captioned: what holds more is
    /// bigger.
    private var ladder: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Self.rungs, id: \.caption) { rung in
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
            Text("Bigger bodies hold more.")
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Size ladder: top folder, folder, page, idea, detail")
    }

    @ViewBuilder
    private func rungCircle(_ rung: Rung) -> some View {
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

    private struct Rung {
        let caption: String
        let size: CGFloat
        let fill: Color
        let ring: Color
        var halo: Bool = false
        var ringed: Bool = false
    }

    private static let gold = Color(red: 1.0, green: 0.68, blue: 0.28)

    private static let rungs: [Rung] = [
        Rung(caption: "Top folder", size: 30, fill: .black, ring: gold, halo: true),
        Rung(caption: "Folder", size: 24, fill: Color(red: 1.0, green: 0.95, blue: 0.78), ring: .clear),
        Rung(caption: "Page", size: 18, fill: Color(red: 0.82, green: 0.66, blue: 0.46),
             ring: Color(red: 0.95, green: 0.86, blue: 0.66), ringed: true),
        Rung(caption: "Idea", size: 13, fill: Color(red: 0.25, green: 0.48, blue: 0.85), ring: .clear),
        Rung(caption: "Detail", size: 8, fill: Color(white: 0.62), ring: .clear)
    ]

    private struct Row {
        let symbol: String
        let name: String
        let text: String
        let tint: Color
    }

    private static let rows: [Row] = [
        Row(symbol: "circle.circle.fill", name: "Black hole",
            text: "A top-level folder: the heart of a galaxy. Notes filed straight in it orbit close; "
                + "its folders shine round it as stars. Bigger holds more notes.", tint: gold),
        Row(symbol: "sun.max.fill", name: "Star",
            text: "A folder inside a folder: yellow, orange one level deeper, red deeper still. "
                + "Bigger holds more; a folder is always drawn a little smaller than the one it sits in. "
                + "An empty folder is a dark star.", tint: .yellow),
        Row(symbol: "circle.lefthalf.filled", name: "Gas giant",
            text: "A page. Bigger is longer; rings mean over 250 words.",
            tint: Color(red: 0.86, green: 0.70, blue: 0.48)),
        Row(symbol: "globe.europe.africa.fill", name: "Rocky planet",
            text: "An idea. Brighter means more links.", tint: Color(red: 0.35, green: 0.6, blue: 1.0)),
        Row(symbol: "moon.fill", name: "Moon",
            text: "A short idea linked only to the note it circles.", tint: Color(white: 0.7)),
        Row(symbol: "dot.radiowaves.left.and.right", name: "Pulsar",
            text: "An idea linking notes in two or more other folders. Its links pulse together.",
            tint: Color(red: 0.7, green: 0.8, blue: 1.0)),
        Row(symbol: "sparkle", name: "Comet",
            text: "A note in no folder. It swings past the folder it links to most; file it and it settles "
                + "into orbit. Older ones wait in the far cloud.", tint: Color(red: 0.55, green: 1.0, blue: 0.9)),
        Row(symbol: "point.3.connected.trianglepath.dotted", name: "Links",
            text: "Straight inside a folder, arched between folders, faint between galaxies. Links never pull.",
            tint: Color(red: 1.0, green: 0.78, blue: 0.5))
    ]

    private static let footer: String = "Inner orbits turn faster. Touch and hold for a name. "
        + "Tap a note twice to open it. Tap a star or black hole twice to fly in, twice again to open the folder. "
        + "Drag a star and its planets follow."

    /// The row's text, starting lower case, for "Name: text".
    private static func lowered(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}

/// The Universe's one-time card: what the bodies are, in two lines, with
/// the legend a tap away. Shown once, never in the design preview; it sits
/// at the bottom leading corner, clear of the round tools.
struct GraphUniverseHint: View {
    let more: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your notes as a universe")
                .font(.headline)
            Text("Top-level folders are black holes, folders are stars, pages are gas giants and ideas are rocky planets. Bigger holds more.")
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
