import SwiftUI

/// The lower half of a category's page: every way to practise, as big tiles.
extension LibraryView {

    /// Two tiles across a phone, more on a wider window.
    private var tileColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    var featureSection: some View {
        Section {
            LazyVGrid(columns: tileColumns, spacing: 12) {
                ForEach(category.features) { feature in
                    Button { start(feature) } label: {
                        FeatureTile(feature: feature, tint: category.tint)
                    }
                    // a style of its own, so each tile in the one list row
                    // is its own button rather than the row being one
                    .buttonStyle(.pressableRow)
                    .accessibilityIdentifier("feature-\(feature.rawValue)")
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } header: {
            CategoryHeading(title: "Ways to practise")
        }
    }

    /// Said in place of the sets when the category has none yet, with the
    /// one button that makes one.
    var emptyCategoryRow: some View {
        HStack(spacing: 14) {
            Image(systemName: category.symbol)
                .font(.title2)
                .foregroundStyle(category.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            Text(category.emptySets)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Make one") { newSetKind = category.mainKind }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 56)
        .frostedListRow()
    }

    /// Whatever the tile does: a quiz built now, the due cards, a page of its
    /// own, or New set on the right kind.
    func start(_ feature: CategoryFeature) {
        switch feature.action {
        case .quiz:
            guard let made = feature.quiz(from: store), !made.set.questions.isEmpty else {
                nothingYet = feature
                return
            }
            featureQuiz = made
        case .due:
            let due: Int = reviews.dueAcross(store.library).count
            if due > 0 { showingDue = true } else { nothingYet = feature }
        case .page:
            featurePage = feature
        case .newSet(let kind):
            newSetKind = kind
        }
    }

    var nothingYetShown: Binding<Bool> {
        Binding(get: { nothingYet != nil }, set: { if !$0 { nothingYet = nil } })
    }
}
