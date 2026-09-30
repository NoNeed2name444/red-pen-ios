import SwiftUI

/// "How to reach it": the differential behind an answer, shown once the
/// student has answered. Three tiers, each with a coloured chip - most likely
/// green, expanded grey, can't miss red - and every diagnosis opens on a tap
/// to the findings for and against it and the test that settles it. Under
/// them, the sources: the lecture page, and any evidence the accuracy check
/// looked up. Nothing is cited that neither of those returned.
struct HowToReachCard: View {
    let differential: DifferentialTiers
    /// The lecture page this item was matched to ("Hernia, p. 4"), if known.
    var lecture: String? = nil
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to reach it", systemImage: "signpost.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(DifferentialTier.allCases) { tier in
                let items: [DifferentialEntry] = differential.entries(tier)
                if !items.isEmpty {
                    tierBlock(tier, items: items)
                }
            }
            sources
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("howToReach")
    }

    static func color(_ tier: DifferentialTier) -> Color {
        switch tier {
        case .mostLikely: return .green
        case .expanded: return .gray
        case .cantMiss: return .red
        }
    }

    private func tierBlock(_ tier: DifferentialTier, items: [DifferentialEntry]) -> some View {
        let tint: Color = Self.color(tier)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tier.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(tint.opacity(0.15), in: Capsule())
            ForEach(items, id: \.name) { entry in
                entryRow(entry, key: tier.rawValue + "|" + entry.name)
            }
        }
    }

    private func entryRow(_ entry: DifferentialEntry, key: String) -> some View {
        let isOpen: Bool = open.contains(key)
        return VStack(alignment: .leading, spacing: 6) {
            if entry.hasDetail {
                Button {
                    withAnimation(.snappy) {
                        if isOpen { open.remove(key) } else { open.insert(key) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(isOpen ? "Hides the findings" : "Shows the findings for and against"))
            } else {
                Text(entry.name).font(.body.weight(.medium))
            }
            if isOpen {
                detail(entry)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(_ entry: DifferentialEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !entry.supporting.isEmpty {
                findingLine("For", entry.supporting.joined(separator: ", "), symbol: "plus.circle.fill", tint: .green)
            }
            if !entry.against.isEmpty {
                findingLine("Against", entry.against.joined(separator: ", "), symbol: "minus.circle.fill", tint: .red)
            }
            if !entry.test.isEmpty {
                findingLine("Test", entry.test, symbol: "testtube.2", tint: .secondary)
            }
        }
        .font(.subheadline)
        .padding(.leading, 4)
    }

    private func findingLine(_ title: String, _ text: String, symbol: String, tint: Color) -> some View {
        var line = AttributedString(title + ": ")
        line.font = Font.subheadline.weight(.semibold)
        line += AttributedString(text)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).font(.caption)
            Text(line)
        }
    }

    // MARK: sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let lecture, !lecture.isEmpty {
                Label(lecture, systemImage: "doc.text").font(.caption)
            } else {
                Text("From the lecture").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(differential.evidence, id: \.self) { ref in
                evidenceLink(ref)
            }
        }
    }

    @ViewBuilder
    private func evidenceLink(_ ref: EvidenceRef) -> some View {
        if let url = URL(string: ref.url), !ref.url.isEmpty {
            Link(destination: url) {
                Label(ref.label, systemImage: "link").font(.caption).lineLimit(2)
            }
        } else {
            Label(ref.label, systemImage: "link").font(.caption).lineLimit(2)
        }
    }

    // MARK: which lecture page

    /// The lecture page a card's text shares the most words with, as
    /// Provenance cites a question - matched, never asked of the model.
    static func lectureLabel(for text: String, in set: StudySet) -> String? {
        for doc in set.sources {
            let pages: [SourceText.Page] = doc.pages.map {
                SourceText.Page(number: $0.number, text: $0.text, recognised: $0.recognised)
            }
            if let number = Provenance.page(for: text, in: pages) {
                return Provenance.label(doc.name, page: number)
            }
        }
        return nil
    }
}
