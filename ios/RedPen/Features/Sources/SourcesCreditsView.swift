import SwiftUI

/// Where one set's content came from, with each part's licence and credit.
///
/// Reached from the set's menu in the library. What it lists is
/// ContentCredits': the lectures the set was made from and how many of its
/// items cite each, the openly licensed style examples its exam's questions
/// were written beside, and the public sources its checks read. A set with
/// none of these (typed in, imported, or made before sources were kept)
/// says so rather than showing an empty list.
struct SetCreditsView: View {
    let set: StudySet
    @State private var reading: SourceDoc?

    private var credits: SetCredits {
        let exam: TargetExam? = ExamCatalog.exam(set.exam)
        return SetCredits.make(set, exam: exam.map { (name: $0.name, bank: $0.exemplars.rawValue) })
    }

    var body: some View {
        let credits: SetCredits = self.credits
        return List {
            if credits.isEmpty {
                Section {
                    WardEmptyState(symbol: "questionmark.folder", title: "Nothing recorded for this set",
                                   message: "It was typed in, imported from a file, or made before \(Brand.name) kept where a set came from. Whatever is in it is yours, or came with the file you imported.",
                                   tone: .grey)
                }
                .wardRowBackground()
            }
            if !credits.lectures.isEmpty || !credits.citedElsewhere.isEmpty {
                lecturesSection(credits)
            }
            if let style = credits.style {
                styleSection(style, exam: credits.examName ?? "your exam")
            }
            if !credits.evidence.isEmpty || !credits.otherEvidence.isEmpty {
                evidenceSection(credits)
            }
            Section {
                NavigationLink {
                    ContentLicencesView()
                } label: {
                    Label("Every source and licence", systemImage: "books.vertical")
                }
            }
            .wardRowBackground()
        }
        .wardForm()
        .navigationTitle("Sources and licences")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading) { source in
            SourcePreviewView(source: source, set: set, openAt: 1)
        }
    }

    // MARK: Made from

    private func lecturesSection(_ credits: SetCredits) -> some View {
        Section {
            ForEach(credits.lectures) { lecture in
                Button { reading = lecture.source } label: {
                    HStack(spacing: 12) {
                        WardIconSquare(symbol: lecture.source.kind.symbol, tone: .blue, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lecture.source.name.isEmpty ? "Untitled lecture" : lecture.source.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.wardInk)
                            Text(lecture.detail)
                                .font(.caption)
                                .foregroundStyle(Color.wardInkSecondary)
                            if lecture.cited > 0 {
                                Text("Cited by \(lecture.cited) \(lecture.cited == 1 ? set.itemNoun : set.itemNoun + "s")")
                                    .font(.caption)
                                    .foregroundStyle(Color.wardInkSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.wardInkSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the lecture")
            }
            ForEach(credits.citedElsewhere, id: \.self) { name in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.body.weight(.medium))
                        Text("Cited, but not kept with this set")
                            .font(.caption)
                            .foregroundStyle(Color.wardInkSecondary)
                    }
                } icon: {
                    Image(systemName: "doc").foregroundStyle(Color.wardInkSecondary)
                }
            }
        } header: {
            Text("Made from")
        } footer: {
            Text("Your own material. \(Brand.name) keeps it so you can read it again, and claims nothing over it.")
        }
        .wardRowBackground()
    }

    // MARK: Question style

    private func styleSection(_ style: ContentSource, exam: String) -> some View {
        Section {
            ContentSourceDetail(source: style)
        } header: {
            Text("Question style")
        } footer: {
            Text("When questions are written for \(exam), the writer is shown a few real \(style.name) questions as examples of the exam\u{2019}s style. They are examples only: the writer is told never to copy them, and a question written on this device that copies one is dropped.")
        }
        .wardRowBackground()
    }

    // MARK: Checked against

    private func evidenceSection(_ credits: SetCredits) -> some View {
        Section {
            ForEach(credits.evidence) { group in
                DisclosureGroup {
                    ForEach(group.refs, id: \.self) { ref in
                        refLink(ref)
                    }
                    ContentSourceDetail(source: group.source, showsUse: false)
                } label: {
                    LabeledContent(group.source.name) {
                        Text("\(group.refs.count)").font(WardType.obs).monospacedDigit()
                    }
                }
            }
            if !credits.otherEvidence.isEmpty {
                DisclosureGroup {
                    ForEach(credits.otherEvidence, id: \.self) { ref in
                        refLink(ref)
                    }
                } label: {
                    LabeledContent("Other sources") {
                        Text("\(credits.otherEvidence.count)").font(WardType.obs).monospacedDigit()
                    }
                }
            }
        } header: {
            Text("Checked against")
        } footer: {
            Text("What the accuracy checks read for this set. Titles and links only: each page stays with its publisher, under its own terms.")
        }
        .wardRowBackground()
    }

    @ViewBuilder
    private func refLink(_ ref: EvidenceRef) -> some View {
        if let url = URL(string: ref.url), url.scheme == "https" {
            Link(destination: url) {
                Label(ref.title.isEmpty ? ref.url : ref.title, systemImage: "link")
                    .font(.footnote)
            }
        } else {
            Label(ref.label, systemImage: "doc.text")
                .font(.footnote)
        }
    }
}

/// Every source of content the app itself brings, with its licence and
/// credit line. In Settings, under About.
struct ContentLicencesView: View {
    var body: some View {
        List {
            Section {
                Text("Lectures, notes and decks you add are yours. \(Brand.name) keeps them on your devices and in your own sync so you can study from them, and claims nothing over them.")
                    .font(.footnote)
            } header: {
                Text("Your material")
            }
            .wardRowBackground()
            ForEach(ContentSources.all) { source in
                Section {
                    ContentSourceDetail(source: source)
                } header: {
                    Text(source.name)
                }
                .wardRowBackground()
            }
        }
        .wardForm()
        .navigationTitle("Sources and licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One source's use, credit line, changes and licence links.
struct ContentSourceDetail: View {
    let source: ContentSource
    var showsUse: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsUse {
                Text(source.use)
                    .font(.subheadline.weight(.semibold))
            }
            Text(source.attribution)
                .font(.footnote)
            if let changes = source.changes {
                Text("Changes: " + changes)
                    .font(.footnote)
                    .foregroundStyle(Color.wardInkSecondary)
            }
        }
        .padding(.vertical, 2)
        ForEach(source.licences, id: \.self) { licence in
            if let url = URL(string: licence.url) {
                Link(destination: url) {
                    Label(licence.name, systemImage: "checkmark.seal")
                        .font(.footnote)
                }
            }
        }
        if let home = URL(string: source.home) {
            Link(destination: home) {
                Label(home.host() ?? source.home, systemImage: "safari")
                    .font(.footnote)
            }
        }
    }
}
