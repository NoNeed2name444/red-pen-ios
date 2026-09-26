import SwiftUI

/// A category's tiles: its modes above the sets (where it has more than one),
/// then every way to practise them and the tools, each under a small heading,
/// and at the very bottom the pages that belong to every category.
///
/// The tiles are what you press, so they stand a little out of the glass; the
/// rows and headings lie flat on it.
extension LibraryView {

    /// Two tiles across a phone, more on a wider window - and one across at
    /// the accessibility text sizes, where a tile's name needs the width.
    private var tileColumns: [GridItem] {
        GridItem.tiles(minimum: 150, accessibilitySize: typeSize.isAccessibilitySize)
    }

    /// One tile per kind of set here - the modes the old dock had a tab
    /// for. Only shown for a category with more than one kind; the library
    /// decides.
    var modesSection: some View {
        tileSection(.modes)
    }

    /// Ways to practise, then tools.
    @ViewBuilder
    var featureSection: some View {
        practiseSection
        tileSection(.tools)
    }

    /// The first four ways to practise, and the rest behind "More ways to
    /// practise", so the page is short enough to take in at a glance.
    @ViewBuilder
    private var practiseSection: some View {
        let features: [CategoryFeature] = category.features(in: .practise)
        let first: [CategoryFeature] = Array(features.prefix(4))
        let rest: [CategoryFeature] = Array(features.dropFirst(4))
        if !features.isEmpty {
            Section {
                tileGrid(first)
                if !rest.isEmpty {
                    DisclosureGroup(isExpanded: $morePractise) {
                        tileGrid(rest)
                    } label: {
                        Text("More ways to practise")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("morePractise")
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                CategoryHeading(title: FeatureGroup.practise.title)
            }
        }
    }

    @ViewBuilder
    private func tileSection(_ group: FeatureGroup) -> some View {
        let features: [CategoryFeature] = category.features(in: group)
        if !features.isEmpty {
            Section {
                tileGrid(features)
            } header: {
                CategoryHeading(title: group.title)
            }
        }
    }

    /// Tiles two across a phone, more on a wider window, in one clear row.
    private func tileGrid(_ features: [CategoryFeature]) -> some View {
        LazyVGrid(columns: tileColumns, spacing: 12) {
            ForEach(features) { feature in
                tileButton(feature)
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func tileButton(_ feature: CategoryFeature) -> some View {
        let line: String = tileDetail(feature)
        return Button { start(feature) } label: {
            FeatureTile(feature: feature, tint: category.tint, detail: line)
        }
        // a style of its own, so each tile in the one list row is its own
        // button rather than the row being one; it stands out of the glass
        // and sinks under the finger
        .buttonStyle(.popTile)
        // the page this tile opens zooms out of it (featurePageView)
        .skyZoomSource(Self.zoomID(feature))
        .accessibilityIdentifier("feature-\(feature.rawValue)")
    }

    /// The shared id of a tile and the page it zooms into.
    static func zoomID(_ feature: CategoryFeature) -> String {
        "tile-\(feature.rawValue)"
    }

    /// A mode tile says how many sets it holds, or that a tap makes one.
    private func tileDetail(_ feature: CategoryFeature) -> String {
        guard feature.shelfKind != nil else { return feature.detail }
        let count: Int = feature.shelfSets(store).count
        if count == 0 { return "None yet \u{2014} tap to make one" }
        return count == 1 ? "1 set" : "\(count) sets"
    }

    /// The pages about the whole app rather than one category - also in the
    /// account menu, and here so they can be found without it. (Ideas has
    /// its own place in the dock.)
    var moreSection: some View {
        let pages: [SupportPage] = [.analytics, .sources]
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
        case .analytics: return "Readiness, trends and what to do next"
        case .sources: return "Every lecture you have added"
        default: return ""
        }
    }

    /// The page a tile pushes. Turn into lists this category's sets, so it is
    /// built here, where the category is known.
    /// It zooms out of the tile that opened it (the system zoom transition;
    /// a plain push at SpaceQuality.still).
    func featurePageView(_ feature: CategoryFeature) -> some View {
        featurePageBody(feature)
            .skyZoomDestination(Self.zoomID(feature))
    }

    @ViewBuilder
    private func featurePageBody(_ feature: CategoryFeature) -> some View {
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
                .buttonStyle(.glass)
                .popOut(.raised, in: Capsule())
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
            // a session starts: the lift-off streak (WarpEffect)
            SpaceWarp.liftOff()
            featureQuiz = made
        case .due:
            let due: Int = reviews.dueAcross(store.library).count
            if due > 0 {
                SpaceWarp.liftOff()
                showingDue = true
            } else {
                nothingYet = feature
            }
        case .page:
            featurePage = feature
        case .newSet(let kind):
            newSetKind = kind
        case .shelf(let kind):
            // no sets of this kind yet: straight to making one, as the old
            // mode tab's empty page did
            // (the picture cards' page opens anyway: it is where a photo or
            // a scan becomes the first deck)
            let straightToNew: Bool = feature.shelfSets(store).isEmpty && feature != .pictures
            if straightToNew { newSetKind = kind } else { featurePage = feature }
        case .support(let page):
            // Ideas is a place in the dock, not a pushed page
            if page == .notes { goToIdeas() } else { support = page }
        case .addMaterial:
            addingKind = category.mainKind
        case .audioLecture:
            let lecture = StudySet(name: "New lecture", subject: "Lectures", kind: .narrate)
            store.addSet(lecture)
            NarrateReviewView.importOnOpen = lecture.id
            opened = [lecture]
        case .learn(let route):
            LearnRouter.shared.open(route)
        }
    }

    var nothingYetShown: Binding<Bool> {
        Binding(get: { nothingYet != nil }, set: { if !$0 { nothingYet = nil } })
    }
}
