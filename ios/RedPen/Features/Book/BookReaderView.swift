import SwiftUI

/// The reader — matches `#bookView`: title + word count, the page, a
/// Previous / Next bar with "Page X of Y — title", and a table of contents.
struct BookReaderView: View {
    let studySet: StudySet
    private let pages: [BookPage]
    @State private var index = 0
    @State private var showToc = false
    @EnvironmentObject private var store: Store

    init(set studySet: StudySet, page: Int = 0) {
        self.studySet = studySet
        self.pages = BookPages.split(studySet.bookMarkdown)
        _index = State(initialValue: min(max(0, page), max(0, pages.count - 1)))
    }

    private var page: BookPage? { pages.indices.contains(index) ? pages[index] : nil }
    private var wordCount: Int { studySet.bookMarkdown.split { $0.isWhitespace || $0.isNewline }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(wordCount.formatted()) words · \(pages.count) page\(pages.count == 1 ? "" : "s")")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if pages.count > 1 {
                    Button { showToc = true } label: { Label("Contents", systemImage: "list.bullet").font(.footnote.weight(.semibold)) }
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let page {
                        ForEach(Array(BookPages.blocks(page.markdown).enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                    } else {
                        Text("This textbook is empty.").foregroundStyle(.secondary)
                    }
                }
                .contentCard()
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .readableColumn()
            }
            .id(index)
            if pages.count > 1 { footer }
        }
        .onAppear {
            if index == 0 { index = store.reading(for: studySet.id, count: pages.count) }
        }
        .onChange(of: index) { _, now in store.saveReading(at: now, for: studySet.id) }
        .modeScreen(.book)
        .turnIntoButton(studySet)
        .accuracyCheck(set: studySet,
                       instruction: "Write a textbook page for medical students from the source.") {
            page.map { $0.title + "\n" + $0.markdown }
        }
        .navigationTitle(studySet.subject.isEmpty ? "Textbook" : studySet.subject)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showToc) {
            NavigationStack {
                List(pages) { p in
                    Button {
                        index = p.id; showToc = false
                    } label: {
                        HStack {
                            Text("\(p.id + 1).").font(.subheadline.monospaced()).foregroundStyle(.secondary)
                            Text(p.title).foregroundStyle(.primary)
                            Spacer()
                            if p.id == index { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func blockView(_ block: BookPages.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(md(text))
                .font(level == 1 ? .title2.weight(.bold) : level == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 6)
        case .bullet(let text, let marker):
            HStack(alignment: .top, spacing: 8) {
                Text(marker ?? "\u{2022}")
                    .font(marker == nil ? .body : .body.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(md(text))
            }
        case .row(let cells, let header):
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                    Text(md(cell))
                        .font(header ? .subheadline.weight(.bold) : i == 0 ? .subheadline.weight(.semibold) : .subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(header ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .paragraph(let text):
            Text(md(text)).font(.body).lineSpacing(3)
        case .callout(let kind, let text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: Self.calloutSymbol(kind))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Self.calloutColor(kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind).font(.caption.weight(.bold)).textCase(.uppercase)
                        .foregroundStyle(Self.calloutColor(kind))
                    Text(md(text)).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Self.calloutColor(kind).opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle().fill(Self.calloutColor(kind)).frame(width: 3).padding(.vertical, 6)
            }
        case .flow(let steps):
            FlowchartView(steps: steps)
        case .image(let index, let caption):
            if let picture = picture(index) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(uiImage: picture)
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
                        .accessibilityLabel(caption.isEmpty ? "Figure" : caption)
                    if !caption.isEmpty {
                        Text(md(caption)).font(.caption).foregroundStyle(.secondary)
                    }
                    DrawFromMemoryButton(set: studySet, imageIndex: index, caption: caption)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func picture(_ index: Int) -> UIImage? {
        guard studySet.images.indices.contains(index),
              let data = Data(base64Encoded: studySet.images[index]) else { return nil }
        return UIImage(data: data)
    }

    static func calloutSymbol(_ kind: String) -> String {
        switch kind.lowercased() {
        case let k where k.contains("red flag") || k.contains("warning"): return "exclamationmark.triangle.fill"
        case let k where k.contains("exam"): return "graduationcap.fill"
        case let k where k.contains("mnemonic"): return "brain.head.profile"
        default: return "lightbulb.fill"
        }
    }

    static func calloutColor(_ kind: String) -> Color {
        switch kind.lowercased() {
        case let k where k.contains("red flag") || k.contains("warning"): return .red
        case let k where k.contains("exam"): return .indigo
        case let k where k.contains("mnemonic"): return .purple
        default: return .orange
        }
    }

    private func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    private var footer: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button("Previous") { index = max(0, index - 1) }.buttonStyle(.glass).disabled(index == 0)
                Spacer()
                Text("Page \(index + 1) of \(pages.count)").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button("Next") { index = min(pages.count - 1, index + 1) }.buttonStyle(.glassProminent).disabled(index >= pages.count - 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

/// A pathway as boxes joined by arrows: one box per step, a branch ("If X →
/// do Y") drawn with its condition above its action, so a work-up or a
/// management algorithm reads the way it is taught.
struct FlowchartView: View {
    let steps: [String]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 {
                    Image(systemName: "arrow.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                box(step)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func box(_ step: String) -> some View {
        let parts = step.components(separatedBy: CharacterSet(charactersIn: "\u{2192}")).map { $0.trimmingCharacters(in: .whitespaces) }
        let branch = parts.count > 1 || step.contains("->")
        let pieces = parts.count > 1 ? parts : step.components(separatedBy: "->").map { $0.trimmingCharacters(in: .whitespaces) }
        VStack(spacing: 2) {
            if branch, pieces.count > 1 {
                Text(pieces[0]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(pieces.dropFirst().joined(separator: " \u{2192} ")).font(.subheadline.weight(.semibold))
            } else {
                Text(step).font(.subheadline.weight(.semibold))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(Color.accentColor.opacity(branch ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
    }
}
