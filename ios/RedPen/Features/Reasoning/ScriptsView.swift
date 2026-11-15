import SwiftUI
import UIKit

/// A set's disease scripts: one card per disease with who gets it, how it
/// runs, what to look for, what settles it and what to do.
///
/// Writing more sits in the slab at the bottom; Delete is in the More menu at
/// the top, away from it.
struct ScriptsView: View {
    let set: StudySet
    @ObservedObject private var reasoning = ReasoningStore.shared
    @State private var confirmClear = false

    private var isExample: Bool { self.set.id == ReasoningExamples.setId }

    var body: some View {
        let scripts = reasoning.pack(for: set.id).scripts
        let here = Set(scripts.map { $0.disease.lowercased() })
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if scripts.isEmpty {
                        WardEmptyState(symbol: "doc.text.magnifyingglass", title: "No scripts yet",
                                       message: "Write them from this set\u{2019}s lecture below.")
                            .padding(.top, 30)
                    }
                    ForEach(scripts) { script in
                        ScriptCard(
                            script: script,
                            jumpable: here,
                            onJump: { name in
                                guard let target = scripts.first(where: { $0.disease.lowercased() == name.lowercased() })
                                else { return }
                                withAnimation(Motion.gentle(.snappy(duration: 0.25))) { reader.scrollTo(target.id, anchor: .top) }
                            })
                        .id(script.id)
                    }
                }
                .padding()
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .wardScreen()
        .navigationTitle("Disease scripts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // the ready-made examples cannot be deleted, so the menu would be empty
            if !scripts.isEmpty && !isExample {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Delete scripts", systemImage: "trash", role: .destructive) { confirmClear = true }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.wardCircle)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .confirmationDialog("Delete these scripts?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete scripts", role: .destructive) { reasoning.clear(.scripts, for: set.id) }
        }
        // the ready-made examples have nothing to write
        .studyBar(shown: !isExample) { ReasoningWriteBar(tool: .scripts, set: set) }
    }
}

/// One disease on one card.
struct ScriptCard: View {
    let script: IllnessScript
    /// Diseases with a card of their own on this screen, lowercased: their
    /// lookalike chips jump to that card.
    let jumpable: Set<String>
    let onJump: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(script.disease).font(WardType.title).foregroundStyle(Color.wardInk)
                Spacer(minLength: 8)
            }
            line("person.2", "Who gets it", script.who)
            line("clock", "Time course", script.timeCourse)
            list("list.bullet", "Key features", script.keyFeatures)
            list("stethoscope", "Examination", script.examSigns)
            line("testtube.2", "Decisive investigation", script.decisiveTest, strong: true)
            line("cross.case", "First-line management", script.firstLine)
            if !script.lookalikes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading("arrow.triangle.branch", "Lookalikes")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(script.lookalikes, id: \.self) { name in
                                lookalikeChip(name)
                            }
                        }
                        // room for a raised chip to lean without being cut
                        // off at the ends; the row still lines up with the
                        // heading above
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, -6)
                }
            }
        }
        .wardCard()
    }

    /// A lookalike with a card on this screen is a chip in the section's
    /// accent; one without is grey, since it goes nowhere.
    private func lookalikeChip(_ name: String) -> some View {
        let here: Bool = jumpable.contains(name.lowercased())
        return Button {
            onJump(name)
        } label: {
            LookalikeChipFace(name: name, here: here)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(!here)
    }

    private func heading(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(WardType.face(.caption, weight: .semibold))
            .foregroundStyle(Color.wardInkSecondary)
    }

    @ViewBuilder
    private func line(_ symbol: String, _ title: String, _ text: String, strong: Bool = false) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                heading(symbol, title)
                Text(text)
                    .font(strong ? WardType.face(.subheadline, weight: .semibold) : WardType.face(.subheadline, weight: .regular))
                    .foregroundStyle(Color.wardInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func list(_ symbol: String, _ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                heading(symbol, title)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // drawn, not read: VoiceOver reads the line alone
                        Text("\u{2022}").foregroundStyle(Color.wardInkSecondary).accessibilityHidden(true)
                        Text(item).font(WardType.face(.subheadline, weight: .regular)).foregroundStyle(Color.wardInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// One lookalike's face: raised off the base, its name in the section's
/// accent, when it jumps to a card here; pressed in and grey when it does
/// not.
private struct LookalikeChipFace: View {
    let name: String
    let here: Bool

    var body: some View {
        let words = Text(name)
            .font(WardType.face(.caption, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        if here {
            words
                .foregroundStyle(Color.wardPrimaryInk)
                .wardRaised(in: Capsule(), lift: .low)
        } else {
            words
                .foregroundStyle(Color.wardInkSecondary)
                .wardInset(in: Capsule())
        }
    }
}
