import SwiftUI

/// "Add to…": keep a captured question in a study mode - a question set, a
/// deck, an OSCE station or a narration - in a set the student picks, or in
/// "Lens captures".
///
/// Whatever is made carries the Lens tag and "Study Lens" as its source, and
/// joins the library like any new content, so the accuracy engine checks it
/// as it checks everything else.
struct LensAddSheet: View {
    let question: DetectedQuestion
    let answer: LensAnswer
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// Where in the chosen mode.
    enum Target: Hashable {
        case lensCaptures
        case existing(UUID)
        case new
    }

    @State private var destination: LensDestination
    @State private var target: Target = .lensCaptures
    @State private var newName: String = ""
    @State private var added: String?
    @State private var problem: String?

    init(question: DetectedQuestion, answer: LensAnswer) {
        self.question = question
        self.answer = answer
        let suggested: LensDestination = LensDestination.suggested(for: question.type)
        // the suggested mode when it can be made, else the first that can
        let fallback: LensDestination? = LensDestination.allCases.first {
            LensConversion.can(question, answer, goTo: $0)
        }
        let usable: Bool = LensConversion.can(question, answer, goTo: suggested)
        _destination = State(initialValue: usable ? suggested : (fallback ?? suggested))
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                    .wardRowBackground()
                placeSection
                    .wardRowBackground()
                if let added {
                    Section {
                        Label(added, systemImage: "checkmark.circle.fill")
                            .labelStyle(WardGlyphLabelStyle(glyph: Color.wardSuccess)).foregroundStyle(Color.wardInk)
                    }
                    .wardRowBackground()
                }
                if let problem {
                    Section {
                        WardBanner(tone: .danger, symbol: "exclamationmark.triangle.fill", text: problem)
                    }
                    .wardWellRow()
                }
            }
            .wardForm()
            .navigationTitle("Add to\u{2026}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added == nil ? "Cancel" : "Done") { dismiss() }
                    .buttonStyle(WardButtonStyle(kind: added == nil ? .quiet : .compact))
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                    .buttonStyle(.wardCompact)
                        .disabled(!canSave)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .onChange(of: destination) { _, _ in
                target = .lensCaptures
                added = nil
                problem = nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: choosing

    private var modeSection: some View {
        Section("Add as") {
            ForEach(LensDestination.allCases) { d in
                let usable: Bool = LensConversion.can(question, answer, goTo: d)
                Button {
                    destination = d
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.symbol)
                            .foregroundStyle(LensStyle.tint(d))
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).foregroundStyle(Color.wardInk)
                            Text(usable ? d.detail : "Not enough in this answer to make one")
                                .font(WardType.caption)
                                .foregroundStyle(Color.wardInkSecondary)
                        }
                        Spacer(minLength: 0)
                        if d == destination {
                            Image(systemName: "checkmark").foregroundStyle(Color.wardPrimaryInk)
                        }
                    }
                }
                .disabled(!usable)
                .accessibilityAddTraits(d == destination ? .isSelected : [])
            }
        }
        .wardRowBackground()
    }

    private var placeSection: some View {
        Section("Set") {
            Picker("Set", selection: $target) {
                Text(LensConversion.defaultName).tag(Target.lensCaptures)
                ForEach(places) { place in
                    Text(place.name).tag(Target.existing(place.id))
                }
                Text("New set\u{2026}").tag(Target.new)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if target == .new {
                TextField("Set name", text: $newName)
                    .textInputAutocapitalization(.words)
            }
        }
        .wardRowBackground()
    }

    /// The sets of the chosen mode (newest first), less the one called "Lens
    /// captures", which has its own row.
    private var places: [LensPlace] {
        let kind: StudySetKind = destination.kind
        let sets: [StudySet] = store.library.filter { $0.kind == kind && $0.name != LensConversion.defaultName }
        let newest: [StudySet] = sets.sorted { $0.updatedAt > $1.updatedAt }
        return newest.map { LensPlace(id: $0.id, name: $0.name) }
    }

    private var canSave: Bool {
        guard added == nil else { return false }
        if target == .new { return !newName.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    // MARK: saving

    private func save() {
        problem = nil
        let kind: StudySetKind = destination.kind
        let name: String = newName.trimmingCharacters(in: .whitespaces)
        var base: StudySet? = nil
        switch target {
        case .existing(let id):
            base = store.library.first { $0.id == id }
        case .lensCaptures:
            base = store.library.first { $0.kind == kind && $0.name == LensConversion.defaultName }
        case .new:
            base = nil
        }
        let isNew: Bool = base == nil
        let fresh: StudySet? = LensConversion.newSet(for: destination, name: name.isEmpty ? LensConversion.defaultName : name)
        guard let start = base ?? fresh,
              let updated = LensConversion.adding(question, answer, to: start) else {
            problem = "This answer can\u{2019}t be made into that mode."
            return
        }
        if isNew { store.addSet(updated) } else { store.update(updated) }
        added = "Added to \u{201C}" + updated.name + "\u{201D} in " + destination.title + "."
    }
}

/// A set to add to.
struct LensPlace: Identifiable, Hashable {
    let id: UUID
    let name: String
}
