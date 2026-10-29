import SwiftUI

/// A subject's page: its tools first, then its topics.
struct ScienceSubjectView: View {
    let subject: ScienceSubject

    var body: some View {
        List {
            Section {
                ForEach(ScienceCatalog.tools(subject)) { tool in
                    ScienceLink(title: tool.name, symbol: tool.symbol, detail: tool.blurb,
                                id: "scienceTool-\(tool.rawValue)") {
                        tool.page
                    }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text(subject.blurb + ".")
            }
            .wardRowBackground()

            Section {
                ForEach(ScienceCatalog.topics(subject)) { topic in
                    ScienceTopicLink(topic: topic)
                }
            } header: { Text("Topics") }
            .wardRowBackground()
        }
        .wardForm()
        .navigationTitle(subject.name)
        .accessibilityIdentifier("scienceSubjectPage")
    }
}

/// A body system's page: the system in the 3D atlas, then its topics under
/// each subject that has them, anatomy first.
struct BodySystemView: View {
    let system: BodySystem

    private var topics: [ScienceTopic] { ScienceCatalog.topics(system) }

    /// Every atlas part the system's topics name, in the order first named.
    private var parts: [String] {
        var seen: Set<String> = []
        return topics.flatMap(\.atlas).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            if !parts.isEmpty {
                Section {
                    ScienceLink(title: "See it in 3D", symbol: ScienceTool.atlas.symbol,
                                detail: AtlasLibrary.names(of: parts), id: "scienceSystemAtlas") {
                        AnatomyAtlasView(focus: parts, title: system.name)
                    }
                }
                .wardRowBackground()
            }
            ForEach(ScienceSubject.allCases) { subject in
                let mine: [ScienceTopic] = topics.filter { $0.subject == subject }
                if !mine.isEmpty {
                    Section {
                        ForEach(mine) { topic in
                            ScienceTopicLink(topic: topic)
                        }
                    } header: { Text(subject.name) }
                    .wardRowBackground()
                }
            }
        }
        .wardForm()
        .navigationTitle(system.name)
        .accessibilityIdentifier("scienceSystemPage")
    }
}

/// A topic: its note, the points to remember, the tools that try it, and
/// the parts of the atlas that show it.
struct ScienceTopicView: View {
    let topic: ScienceTopic

    var body: some View {
        List {
            Section {
                Text(topic.note)
                    .font(.body)
                    .foregroundStyle(Color.wardInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, WardSpace.xs)
            } header: {
                Text(topic.byline)
            }
            .wardRowBackground()

            Section {
                ForEach(topic.points, id: \.self) { point in
                    Label {
                        Text(point)
                            .font(.subheadline)
                            .foregroundStyle(Color.wardInk)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.wardPrimaryInk)
                    }
                    .padding(.vertical, WardSpace.xs)
                }
            } header: { Text("To remember") }
            .wardRowBackground()

            if !topic.tools.isEmpty {
                Section {
                    ForEach(topic.tools) { tool in
                        ScienceLink(title: tool.name, symbol: tool.symbol, detail: tool.blurb,
                                    id: "scienceTool-\(tool.rawValue)") {
                            tool.page
                        }
                    }
                } header: { Text("Tools") }
                .wardRowBackground()
            }

            if !topic.atlas.isEmpty {
                Section {
                    ScienceLink(title: "See it in 3D", symbol: ScienceTool.atlas.symbol,
                                detail: AtlasLibrary.names(of: topic.atlas), id: "scienceTopicAtlas") {
                        AnatomyAtlasView(focus: topic.atlas, title: topic.title)
                    }
                }
                .wardRowBackground()
            }
        }
        .wardForm()
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("scienceTopicPage")
    }
}

/// A topic's link, the same wherever it is listed: its title, the first
/// system's symbol, and where it belongs.
struct ScienceTopicLink: View {
    let topic: ScienceTopic
    var tile = false

    var body: some View {
        ScienceLink(title: topic.title, symbol: topic.symbol, detail: topic.byline,
                    id: "scienceTopic-\(topic.id)", tile: tile) {
            ScienceTopicView(topic: topic)
        }
    }
}

extension ScienceTopic {
    /// The subject and the systems, for a topic's row and header:
    /// "Physiology · Cardiovascular".
    var byline: String {
        let systems: [String] = systems.map(\.name)
        return ([subject.name] + systems).joined(separator: " \u{00B7} ")
    }

    /// The first system's symbol, or the subject's for a general topic.
    var symbol: String { systems.first?.symbol ?? subject.symbol }
}
