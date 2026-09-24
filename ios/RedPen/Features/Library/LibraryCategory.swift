import SwiftUI

/// A category's tiles: its modes above the sets, then every way to practise
/// them and the tools, each under a small heading, and at the very bottom the
/// pages that belong to every category.
extension LibraryView {

    /// Two tiles across a phone, more on a wider window.
    private var tileColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: 12)]
    }

    /// One tile per kind of set here - the modes the old dock had a tab for.
    var modesSection: some View {
        tileSection(.modes)
    }

    /// Ways to practise, then tools.
    @ViewBuilder
    var featureSection: some View {
        tileSection(.practise)
        tileSection(.tools)
    }

    @ViewBuilder
    private func tileSection(_ group: FeatureGroup) -> some View {
        let features: [CategoryFeature] = category.features(in: group)
        if !features.isEmpty {
            Section {
                LazyVGrid(columns: tileColumns, spacing: 12) {
                    ForEach(features) { feature in
                        tileButton(feature)
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } header: {
                CategoryHeading(title: group.title)
            }
        }
    }

    private func tileButton(_ feature: CategoryFeature) -> some View {
        let line: String = tileDetail(feature)
        return Button { start(feature) } label: {
            FeatureTile(feature: feature, tint: category.tint, detail: line)
        }
        // a style of its own, so each tile in the one list row
        // is its own button rather than the row being one
        .buttonStyle(.pressableRow)
        .accessibilityIdentifier("feature-\(feature.rawValue)")
    }

    /// A mode tile says how many sets it holds, or that a tap makes one.
    private func tileDetail(_ feature: CategoryFeature) -> String {
        guard feature.shelfKind != nil else { return feature.detail }
        let count: Int = feature.shelfSets(store).count
        if count == 0 { return "None yet \u{2014} tap to make one" }
        return count == 1 ? "1 set" : "\(count) sets"
    }

    /// The pages about the whole app rather than one category - also behind
    /// the gear, and here so they can be found without it.
    var moreSection: some View {
        let pages: [SupportPage] = [.notes, .analytics, .sources]
        return Section {
            ForEach(pages) { page in
                Button { support = page } label: {
                    CategoryRowLabel(title: page.title, symbol: page.symbol,
                                     detail: Self.moreDetail(page), tint: category.tint)
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("more-\(page.rawValue)")
                .frostedListRow()
            }
        } header: {
            CategoryHeading(title: "Across the app")
        }
    }

    private static func moreDetail(_ page: SupportPage) -> String {
        switch page {
        case .notes: return "Idea dump, board and 3D map"
        case .analytics: return "Readiness, trends and what to do next"
        case .sources: return "Every lecture you have added"
        default: return ""
        }
    }

    /// The page a tile pushes. Turn into lists this category's sets, so it is
    /// built here, where the category is known.
    @ViewBuilder
    func featurePageView(_ feature: CategoryFeature) -> some View {
        if feature == .turn {
            TurnIntoListView(kinds: category.kinds)
        } else {
            feature.page
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

    /// Whatever the tile does: a mode's sets, a quiz built now, the due cards,
    /// a page of its own, or New set on the right kind.
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
        case .shelf(let kind):
            // no sets of this kind yet: straight to making one, as the old
            // mode tab's empty page did
            if feature.shelfSets(store).isEmpty { newSetKind = kind } else { featurePage = feature }
        case .support(let page):
            support = page
        case .addMaterial:
            addingKind = category.mainKind
        case .audioLecture:
            let lecture = StudySet(name: "New lecture", subject: "Lectures", kind: .narrate)
            store.addSet(lecture)
            NarrateReviewView.importOnOpen = lecture.id
            opened = [lecture]
        }
    }

    var nothingYetShown: Binding<Bool> {
        Binding(get: { nothingYet != nil }, set: { if !$0 { nothingYet = nil } })
    }
}
