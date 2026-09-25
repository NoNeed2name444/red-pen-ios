import SwiftUI
import SceneKit
import UIKit
import simd

/// The space: every note as a soft point in 3D and every connection as a fine
/// thread between two, the way Obsidian's graph shows a vault - but something
/// to turn round in the hand rather than a flat picture.
///
/// It is a piece of deep space, seen through the screen as through a window:
/// it runs on under the bottom glass, and tilting the device turns it a
/// hair (see GraphSim's tilt rig), so it reads as being BEHIND the glass
/// while the controls stand out in front of it. Every note is a small black
/// hole - a black sphere, a thin photon ring hugging its rim and a tilted,
/// streaky accretion disk, tinted a little by its folder - or, by the look
/// tool, a sun, planet, gas giant, pulsar or comet (GraphNodeStyles); every
/// link a stream of plasma (see GraphLook, GraphStyleShaders). Pages are a
/// little larger than ideas, and well-linked notes larger and brighter.
///
/// Names stay out of the way: a note's name shows, on a solid dark pill just
/// the size of the words, only while the pointer hovers over it (iPad
/// trackpad, mouse or Pencil) or while it is pressed or dragged; it goes
/// when the finger lifts. Tapping it twice opens it. The only other controls
/// are three round tools: one to filter, one to choose the notes' look, one
/// to bring the view back to the middle.
///
/// It is alive rather than frozen: the notes drift gently, pop in with a small
/// bounce, and a note dragged with a finger pulls its neighbours along and
/// springs home when let go (see GraphSim). Drag empty space to turn it,
/// pinch to come closer. With Reduce Motion on the space stands still.
///
/// The Universe look (the default; GraphUniverse) maps the ideas' own
/// hierarchy onto bodies by size instead: top-level folders are black holes
/// at the hearts of galaxies, folders inside them stars, pages gas giants,
/// ideas rocky planets, short one-link ideas moons, a bridging idea its
/// galaxy's pulsar and loose notes comets - planned off the main thread,
/// with no force layout, and orbiting on GraphSim. Two taps on a star or
/// black hole fly in to its system; two more open the folder in the List.
///
/// The map has themes (GraphTheme, chosen at the top of the Look menu):
/// Space - the Universe and the single looks - Neurons, the same
/// hierarchy as a nervous system (GraphNeurons: regions, relays down the
/// pathway, neurons, glia and receptors joined by axons carrying impulses),
/// and Circuit, as a printed circuit board (GraphCircuit: processors,
/// modules on sub-boards, capacitors, resistors, LEDs and headers joined by
/// routed copper traces carrying current), each planned the same way and
/// built by the shared theme scene
/// (GraphThemeScene), so it moves, picks, filters and flies in exactly as
/// the Universe does. The Graphics setting applies to every theme.
///
/// Where each note belongs in the single looks is worked out by
/// ForceLayout3D, off the main thread, and again only when notes or links
/// change.
struct Graph3DView: View {
    @EnvironmentObject private var notes: NoteStore
    let open: (UUID) -> Void
    /// Opens a folder in the List (nil: its top level) - two double taps on
    /// a star or black hole in the Universe.
    var openFolder: (UUID?) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The sky's shared switch (SpaceQuality): at .still - Low Power Mode,
    /// a hot device - the map holds still too.
    @Environment(\.spaceQuality) private var quality
    /// The Graphics setting (GraphicsQuality.swift): a change rebuilds, so
    /// the scene is made to the new budget.
    @Environment(\.graphics) private var graphics
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.layoutDirection) private var direction
    @State private var built: GraphScene?
    @State private var filter: GraphFilter = .all
    /// Bumped by the recentre button; the view notices the change.
    @State private var recenter: Int = 0
    /// The legend ("What the bodies mean"), from the Look menu or the
    /// first-run card.
    @State private var showingLegend: Bool = false
    /// The notes' look (GraphStyleChoice), remembered; a change rebuilds.
    @AppStorage(GraphStyleChoice.key) private var nodeStyle: String = GraphStyleChoice.standard
    @AppStorage(GraphStyleChoice.foldersKey) private var folderStyles: String = ""
    /// The Universe's first-run card has been seen.
    @AppStorage("vignette.space.universeHintSeen") private var hintSeen: Bool = false
    /// The map's theme (GraphTheme: Space, Neurons, Circuit), remembered; a
    /// change rebuilds.
    @AppStorage(GraphTheme.key) private var themeRaw: String = GraphTheme.standard.rawValue
    /// The other themes whose first-run card has been seen ("neurons,...").
    @AppStorage(GraphTheme.hintsKey) private var themeHintsSeen: String = ""
    /// The empty-bench hint's "Add circuit" (or "Add folder") is naming a
    /// new folder - the same store action as the Ideas bar's + › New folder.
    @State private var addingFolder: Bool = false
    /// The owner's "Link length" (GraphLinkLength; Settings > Look and
    /// feel, and the Look menu's bar): a change rebuilds, and every body
    /// glides to its new place.
    @AppStorage(SpaceSettings.linkLengthKey) private var linkLength: Double = GraphLinkLength.standard
    /// The Look menu's Link length bar is up.
    @State private var tuningLinks: Bool = false
    /// Which themes' first-run card has shown the touch lines.
    @AppStorage(GraphMapTouch.seenKey) private var touchSeen: String = ""
    /// Touching the map (GraphTouchModel): what is chosen, whether its
    /// links are shown, what is open on top.
    @State private var selection = GraphSelection()
    /// Requests for the map from the card (a link chip, Show links, Fly in).
    @State private var command = GraphMapCommand()
    /// The note opened from the map, growing out of the peek card.
    @State private var reading: GraphReading?
    /// A body's options (held still on it, or the card's More), and what
    /// they opened.
    @State private var options: GraphOptionsTarget?
    @State private var renaming: GraphOptionsTarget?
    @State private var linkingFrom: GraphReading?
    @State private var movingNote: GraphReading?
    @State private var addingInto: GraphOptionsTarget?
    @State private var deleting: GraphOptionsTarget?
    @Namespace private var peekZoom
    @AccessibilityFocusState private var cardFocused: Bool

    init(open: @escaping (UUID) -> Void, openFolder: @escaping (UUID?) -> Void = { _ in }) {
        self.open = open
        self.openFolder = openFolder
    }

    var body: some View {
        Group {
            if notes.notes.isEmpty {
                ContentUnavailableView {
                    Label("Dump your first idea", systemImage: "cube.transparent")
                } description: {
                    Text("Every note appears here as a point in space, joined to the notes it links to. Type one in the bar below.")
                }
            } else if let built {
                space(built)
            } else {
                ProgressView()
            }
        }
        .task(id: signature) { await rebuild() }
        // a folder being filtered to was deleted: show everything again
        .onChange(of: notes.folders) { _, _ in
            if case .folder(let id) = filter, notes.folder(id) == nil { filter = .all }
        }
        .sheet(isPresented: $addingFolder) {
            NameSheet(title: "New folder", prompt: "Folder name", initial: "", confirm: "Create") { name in
                _ = notes.createFolder(name: name)
            }
        }
        .sheet(isPresented: $showingLegend) {
            GraphLegendSheet(theme: built?.theme ?? theme)
                .presentationDetents([.medium, .large])
        }
        // Open: the note, grown out of the peek card; closing it comes back
        // to the map with the same body still chosen
        .sheet(item: $reading, onDismiss: closedReading) { item in
            NoteEditorView(noteID: item.id)
                .navigationTransition(.zoom(sourceID: GraphPeekCardView.zoomID, in: peekZoom))
        }
        .sheet(item: $renaming) { target in
            renameSheet(target)
        }
        .sheet(item: $addingInto) { target in
            NameSheet(title: "New idea", prompt: "Idea", initial: "", confirm: "Add") { name in
                let folder: UUID? = target.home ? nil : target.id
                _ = notes.create(title: name, kind: .idea, folderId: folder)
            }
        }
        .sheet(item: $linkingFrom) { item in
            GraphNotePicker(from: item.id)
        }
        .sheet(item: $movingNote) { item in
            GraphFolderPicker(note: item.id)
        }
        .confirmationDialog(deleteTitle, isPresented: deletingShown, titleVisibility: .visible,
                            presenting: deleting) { target in
            Button("Delete", role: .destructive) { delete(target) }
        } message: { target in
            Text(target.folder ? "The folder goes; its notes and folders move up a level." : "This can't be undone.")
        }
        // a chosen body deleted or gone: let it go
        .onChange(of: notes.notes) { _, _ in forgetGone() }
        .onChange(of: notes.folders) { _, _ in forgetGone() }
        .task {
            // the design preview's deletions, to catch bodies dying
            guard GraphPreview.removes != nil else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            GraphPreview.remove(from: notes)
        }
        .task {
            // the design preview's taps: a body chosen (its card up), then
            // perhaps opened; or a body held (its options)
            guard GraphPreview.select != nil || GraphPreview.hold != nil else { return }
            let wait: UInt64 = GraphPreview.fly == nil ? 2_500_000_000 : 4_000_000_000
            try? await Task.sleep(nanoseconds: wait)
            if let name = GraphPreview.select, let id = previewID(name) {
                touched(id)
                if GraphPreview.opens {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    handle(.openCard)
                }
            }
            if let name = GraphPreview.hold, let id = previewID(name) {
                command.send(.previewHold(id))
            }
        }
        .task {
            // the design preview's picture of the legend
            guard GraphPreview.showsLegend else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            showingLegend = true
        }
    }

    /// The space itself, running on under the glass, with its tools in the
    /// safe area. The graph is fitted to the part of the view that is not
    /// under glass (the safe area, read here), so no note starts hidden
    /// under the bars. No SwiftUI transform ever touches the SceneKit view:
    /// its own tilt comes from inside the scene.
    private func space(_ built: GraphScene) -> some View {
        ZStack {
            GeometryReader { geo in
                let insets: GraphInsets = screenInsets(geo.safeAreaInsets)
                GraphSCNView(built: built, filter: filter, recenter: recenter,
                             insets: insets, onTap: open, openFolder: openFolder,
                             command: command, chosen: selection.selected,
                             linksFor: selection.linksShown ? selection.selected : nil,
                             labels: labelSettings, touch: touchHandlers)
            }
            .ignoresSafeArea()
        }
        .overlay {
            if filter != .all && shownCount == 0 {
                Text("Nothing here for this filter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            // a near-empty map with no folders yet: how to start a collection
            if notes.folders.isEmpty && notes.notes.count < 25 && !GraphPreview.isOn {
                GraphEmptyHint(theme: built.theme) { addingFolder = true }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if built.universe && hintShown(built.theme) && !GraphPreview.isOn && !selection.cardShown && !tuningLinks {
                // sized to what the round tools (44 points, 12 from the
                // card) leave, so it never runs under them on a phone
                GraphUniverseHint(theme: built.theme, steps: !cardSeen(built.theme),
                                  touch: !GraphMapTouch.seen(touchSeen, built.theme), more: {
                    markCardSeen(built.theme)
                    showingLegend = true
                }, done: {
                    markCardSeen(built.theme)
                })
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 16 + 44 + 12)
                .padding(.bottom, 16)
            }
        }
        .overlay(alignment: .bottom) {
            bottomPanels(built)
        }
        .overlay {
            optionsLayer(built)
        }
        .ideaTools { tools }
        // the space is always night, whatever the phone's setting
        .environment(\.colorScheme, .dark)
        // the map is opaque and fills the screen: the backdrop under it
        // stops drawing (its clocks, twinkle and tilt) while it is up
        .coversSky()
    }

    /// The peek card for the chosen body, or the Link length bar: over the
    /// bottom of the map, clear of the round tools, sliding up.
    @ViewBuilder
    private func bottomPanels(_ built: GraphScene) -> some View {
        VStack(spacing: 10) {
            if tuningLinks {
                GraphLinkLengthBar(value: linkBinding, done: { tuningLinks = false })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // it stays while its note is open over the map: the note grows
            // out of it, and shrinks back into it
            if let id = selection.selected, let content = peek(id, in: built) {
                let folder: Bool = isFolder(id, in: built)
                GraphPeekCardView(content: content, folder: folder, linksShown: selection.linksShown,
                                  zoom: peekZoom,
                                  open: { handle(.openCard) },
                                  showLinks: { handle(.showLinks) },
                                  flyIn: { command.send(.flyIn(id)) },
                                  chip: { other in handle(.chip(other)) },
                                  more: GraphPeek.menu(folder: folder, home: id == GraphUniverse.homeID),
                                  option: { item in choose(item, for: optionsTarget(id, in: built, at: nil)) })
                    .id(id)
                    .accessibilityFocused($cardFocused)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.trailing, 44 + 12)
        .padding(.bottom, 16)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: selection.selected)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: selection.cardShown)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: tuningLinks)
    }

    /// A body's options, held still on it: a glass list beside where it
    /// was held; a tap anywhere else puts it away.
    @ViewBuilder
    private func optionsLayer(_ built: GraphScene) -> some View {
        if let target = options {
            GeometryReader { geo in
                let size: CGSize = geo.size
                let at: CGPoint = target.point ?? CGPoint(x: size.width / 2, y: size.height * 0.6)
                let items: [String] = GraphPeek.menu(folder: target.folder, home: target.home)
                let tall: CGFloat = CGFloat(items.count) * 44 + 40
                let x: CGFloat = min(max(at.x, 131), max(size.width - 131, 131))
                let below: Bool = at.y + 24 + tall < size.height
                let half: CGFloat = tall / 2
                let under: CGFloat = at.y + 24 + half
                let over: CGFloat = max(at.y - 24 - half, half + 8)
                let y: CGFloat = below ? under : over
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { options = nil }
                        .accessibilityHidden(true)
                    GraphNodeMenuView(title: title(target.id), items: items) { item in
                        choose(item, for: target)
                    }
                    .position(x: x, y: y)
                }
            }
            // the same space as the map's own view, where it was held
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    static let graphHint: String =
        "Drag to turn, pinch to zoom. Tap a note to preview it, tap again to open it; hold it to move it or for options."

    /// Whether a theme's first-run card has been seen (the Universe keeps
    /// its own old key).
    private func cardSeen(_ theme: GraphTheme) -> Bool {
        if theme == .space { return hintSeen }
        return themeHintsSeen.split(separator: ",").contains { String($0) == theme.rawValue }
    }

    private func markCardSeen(_ theme: GraphTheme) {
        touchSeen = GraphMapTouch.marking(touchSeen, theme)
        if theme == .space {
            hintSeen = true
            return
        }
        guard !cardSeen(theme) else { return }
        themeHintsSeen = themeHintsSeen.isEmpty ? theme.rawValue : themeHintsSeen + "," + theme.rawValue
    }

    /// The first-run card shows until it is put away: its steps the first
    /// time in a theme, and the touch lines once per theme (for owners who
    /// saw the card before they were added).
    private func hintShown(_ theme: GraphTheme) -> Bool {
        !cardSeen(theme) || !GraphMapTouch.seen(touchSeen, theme)
    }

    // MARK: touching the map (GraphTouchModel)

    /// What the map reports back: taps, double taps, holds, VoiceOver.
    private var touchHandlers: GraphTouchHandlers {
        var out = GraphTouchHandlers()
        out.select = { id in touched(id) }
        out.double = { id in handle(.doubleTap(id)) }
        out.hold = { id, point in held(id, at: point) }
        out.voice = { id, action in voiceAction(id, action) }
        return out
    }

    /// A tap on the map: on a body (its id) or on empty space (nil).
    private func touched(_ id: UUID?) {
        if let id {
            handle(.tapBody(id))
        } else {
            handle(.tapEmpty)
        }
    }

    private func handle(_ event: GraphSelectionEvent) {
        let now: Double = CACurrentMediaTime()
        perform(selection.handle(event, at: now))
    }

    /// What the selection asks for. Choosing and Show links reach the map
    /// through `selection` itself (GraphSCNView's `chosen` and
    /// `linksFor`); the camera's move and opening happen here.
    private func perform(_ effects: [GraphSelectionEffect]) {
        for effect in effects {
            switch effect {
            case .select(let id, let glide):
                command.send(.select(id, glide: glide))
                if UIAccessibility.isVoiceOverRunning { cardFocused = true }
            case .clear:
                options = nil
            case .open(let id):
                openBody(id)
            case .links:
                break
            case .menu(let id):
                if let built { options = optionsTarget(id, in: built, at: options?.point) }
            }
        }
    }

    /// Opens a body: a note grows out of the card; a folder opens in the
    /// List (the home star: its top level), the app's own destinations.
    private func openBody(_ id: UUID) {
        options = nil
        let isHome: Bool = id == GraphUniverse.homeID
        if isHome || notes.folder(id) != nil {
            perform(selection.handle(.closed, at: CACurrentMediaTime()))
            openFolder(isHome ? nil : id)
            return
        }
        guard notes.note(id) != nil else { return }
        reading = GraphReading(id: id)
    }

    private func closedReading() {
        perform(selection.handle(.closed, at: CACurrentMediaTime()))
    }

    /// Held still on a body: its options, where it was held.
    private func held(_ id: UUID, at point: CGPoint) {
        guard let built else { return }
        options = optionsTarget(id, in: built, at: point)
        handle(.hold(id))
    }

    /// VoiceOver on a body: activate selects it; its custom actions.
    private func voiceAction(_ id: UUID, _ action: String) {
        switch action {
        case "Open", "Open folder":
            handle(.doubleTap(id))
        case "Show links":
            if selection.selected != id { handle(.tapBody(id)) }
            handle(.showLinks)
        case "Fly in":
            if selection.selected != id { handle(.tapBody(id)) }
            command.send(.flyIn(id))
        case "Delete":
            if let built { deleting = optionsTarget(id, in: built, at: nil) }
        default:
            if selection.selected != id { handle(.tapBody(id)) }
        }
    }

    /// One of a body's options.
    private func choose(_ item: String, for target: GraphOptionsTarget) {
        options = nil
        switch item {
        case "Open", "Open folder": handle(.doubleTap(target.id))
        case "Rename": renaming = target
        case "Link to\u{2026}": linkingFrom = GraphReading(id: target.id)
        case "Move to folder\u{2026}": movingNote = GraphReading(id: target.id)
        case "Add note here": addingInto = target
        case "Delete": deleting = target
        default: break
        }
    }

    @ViewBuilder
    private func renameSheet(_ target: GraphOptionsTarget) -> some View {
        let prompt: String = target.folder ? "Folder name" : "Title"
        NameSheet(title: "Rename", prompt: prompt, initial: title(target.id), confirm: "Rename") { name in
            if target.folder {
                notes.renameFolder(target.id, to: name)
            } else if var note = notes.note(target.id) {
                note.title = name
                notes.update(note)
            }
        }
    }

    private var deletingShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var deleteTitle: String {
        guard let target = deleting else { return "Delete?" }
        return "Delete \u{201C}" + title(target.id) + "\u{201D}?"
    }

    /// Deletes it; the map plays its death as it rebuilds.
    private func delete(_ target: GraphOptionsTarget) {
        if target.folder {
            notes.deleteFolder(target.id)
        } else {
            notes.delete(target.id)
        }
        perform(selection.handle(.gone(target.id), at: CACurrentMediaTime()))
        deleting = nil
    }

    /// A chosen body deleted elsewhere (or its folder gone): let it go.
    private func forgetGone() {
        guard let id = selection.selected, id != GraphUniverse.homeID else { return }
        if notes.note(id) == nil && notes.folder(id) == nil {
            perform(selection.handle(.gone(id), at: CACurrentMediaTime()))
        }
    }

    private func title(_ id: UUID) -> String {
        if let note = notes.note(id) { return note.title.isEmpty ? "Untitled" : note.title }
        if let folder = notes.folder(id) { return folder.name }
        return "Ideas"
    }

    private func isFolder(_ id: UUID, in built: GraphScene) -> Bool {
        id == GraphUniverse.homeID || notes.folder(id) != nil
    }

    private func optionsTarget(_ id: UUID, in built: GraphScene, at point: CGPoint?) -> GraphOptionsTarget {
        let home: Bool = id == GraphUniverse.homeID
        return GraphOptionsTarget(id: id, folder: isFolder(id, in: built), home: home, point: point)
    }

    /// What the peek card says about body `id`.
    private func peek(_ id: UUID, in built: GraphScene) -> GraphPeekContent? {
        let role: String = built.roles[id] ?? ""
        let themeName: String = built.theme.rawValue
        if id == GraphUniverse.homeID || notes.folder(id) != nil {
            let home: Bool = id == GraphUniverse.homeID
            let folderID: UUID? = home ? nil : id
            var input = GraphPeekInput(theme: themeName, role: role, folder: true, home: home, title: title(id))
            input.notes = home ? notes.notes.count : notes.count(in: id)
            input.subfolders = notes.subfolders(of: folderID).count
            let inside: [Note] = home ? notes.notes : notes.contents(of: folderID)
            let newest: [Note] = inside.sorted { $0.createdAt > $1.createdAt }
            input.recent = newest.prefix(3).map(\.title)
            return GraphPeek.content(input)
        }
        guard let note = notes.note(id) else { return nil }
        var input = GraphPeekInput(theme: themeName, role: role, folder: false, title: note.title,
                                   page: note.kind == .page)
        input.body = note.body
        var links: [(UUID, String)] = []
        for other in notes.connections(of: id) {
            guard let linked = notes.note(other) else { continue }
            links.append((other, linked.title))
        }
        input.links = links
        return GraphPeek.content(input)
    }

    /// A note (by title) or folder (by name) in the design preview's store.
    private func previewID(_ name: String) -> UUID? {
        if let note = notes.notes.first(where: { $0.title == name }) { return note.id }
        return notes.folders.first(where: { $0.name == name })?.id
    }

    /// Increase Contrast always takes the name pills' strongest style,
    /// Reduce Transparency an opaque pill (GraphLabelContrast.swift).
    private var labelSettings: GraphLabelSettings {
        GraphLabelSettings(increaseContrast: highContrast, reduceTransparency: reduceTransparency)
    }

    /// The link length in force (the design preview can be given one).
    private var linkValue: Double {
        if GraphPreview.isOn, let asked = GraphPreview.linkLength { return GraphLinkLength.clamped(asked) }
        return GraphLinkLength.stored(linkLength)
    }

    private var linkBinding: Binding<Double> {
        Binding<Double>(get: { linkValue }, set: { linkLength = GraphLinkLength.clamped($0) })
    }

    /// The safe area's insets, left and right as on screen.
    private func screenInsets(_ edges: EdgeInsets) -> GraphInsets {
        let rtl: Bool = direction == .rightToLeft
        let left: CGFloat = rtl ? edges.trailing : edges.leading
        let right: CGFloat = rtl ? edges.leading : edges.trailing
        return GraphInsets(top: Float(edges.top), left: Float(left),
                           bottom: Float(edges.bottom), right: Float(right))
    }

    // MARK: the tools

    private var filterSymbol: String {
        filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    }

    /// The only controls on screen: filter, the notes' look, and back to
    /// the middle.
    @ViewBuilder
    private var tools: some View {
        let filtering: Bool = filter != .all
        let ink: Color = filtering ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: filtering)
        Menu {
            filterMenu
        } label: {
            IdeaToolFace(symbol: filterSymbol)
        }
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Filter")

        GraphStyleTool(theme: themeBinding, main: lookBinding, folderRaw: folderBinding, folders: topFolders,
                       showLegend: { showingLegend = true }, linkLength: linkValue,
                       tuneLinks: tuneLinksAction)

        IdeaToolButton(symbol: "scope", label: "Recentre") {
            recenter += 1
        }
    }

    /// The Look menu's Link length: only where the map is planned (the
    /// Universe and the themes), not the single looks.
    private var tuneLinksAction: (() -> Void)? {
        guard sizedByLength else { return nil }
        return { tuningLinks = true }
    }

    /// The look in force: the owner's choice, never read or written in the
    /// design preview.
    private var lookBinding: Binding<String> {
        GraphPreview.isOn ? .constant(GraphStyleChoice.main) : $nodeStyle
    }

    private var folderBinding: Binding<String> {
        GraphPreview.isOn ? .constant("") : $folderStyles
    }

    /// The theme in force: the owner's choice, or in the design preview the
    /// one asked for (never read or written there).
    private var themeBinding: Binding<String> {
        GraphPreview.isOn ? .constant(GraphPreview.theme.rawValue) : $themeRaw
    }

    private var theme: GraphTheme {
        GraphPreview.isOn ? GraphPreview.theme : GraphTheme.stored(themeRaw)
    }

    @ViewBuilder
    private var filterMenu: some View {
        Picker("Show", selection: $filter) {
            Text("Everything").tag(GraphFilter.all)
            Text("Pages").tag(GraphFilter.pages)
            Text("Ideas").tag(GraphFilter.ideas)
            Text("Linked notes").tag(GraphFilter.linked)
        }
        .pickerStyle(.inline)
        let tops: [NoteFolder] = topFolders
        if !tops.isEmpty {
            Picker("Folder", selection: $filter) {
                ForEach(tops) { folder in
                    Text(folder.name).tag(GraphFilter.folder(folder.id))
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// The top-level folders the filter and folder looks offer: in the
    /// Universe the plan's galaxies (a folder with a missing parent, or the
    /// one where a cycle is cut, is a galaxy too), in name order; in the
    /// single looks the store's top level.
    private var topFolders: [NoteFolder] {
        guard let built, built.universe else { return notes.subfolders(of: nil) }
        let found: [NoteFolder] = built.galaxies.compactMap { notes.folder($0) }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// How many notes the current filter lets through, to say so when none do.
    private var shownCount: Int {
        var degree: [UUID: Int] = [:]
        for edge in notes.allEdges() {
            degree[edge.0, default: 0] += 1
            degree[edge.1, default: 0] += 1
        }
        var count: Int = 0
        for note in notes.notes {
            var root: UUID? = notes.rootFolder(of: note.folderId)
            if let built, built.universe { root = built.galaxyOf[note.id] }
            let links: Int = degree[note.id] ?? 0
            if filter.admits(kind: note.kind, root: root, degree: links) { count += 1 }
        }
        return count
    }

    // MARK: building

    /// The main look in force (GraphStyleChoice).
    private var mainLook: String {
        GraphPreview.isOn ? GraphStyleChoice.main : nodeStyle
    }

    /// Whether the notes are drawn as the Universe (GraphUniverse): the
    /// Space theme with any main look that is not one single style.
    private var isUniverse: Bool {
        theme == .space && GraphNodeStyle(rawValue: mainLook) == nil
    }

    /// Whether sizes come from the notes' lengths: the Universe and every
    /// other theme.
    private var sizedByLength: Bool {
        isUniverse || theme != .space
    }

    /// Everything the picture depends on. When this changes the layout is
    /// worked out again; moving a card on the board does not change it. In
    /// the Universe each note's size step counts too (GraphUniverse.level),
    /// so typing rebuilds only when a note crosses one.
    private var signature: String {
        let universe: Bool = sizedByLength
        var parts: [String] = []
        for note in notes.notes {
            let folder: String = note.folderId?.uuidString ?? ""
            var line: String = "\(note.id.uuidString)|\(note.title)|\(note.kind.rawValue)|\(folder)"
            if universe {
                let words: Int = GraphUniverse.wordCount(note.body)
                line += "|L\(GraphUniverse.level(words: words))"
            }
            parts.append(line)
        }
        for edge in notes.allEdges() {
            parts.append(edge.0.uuidString + edge.1.uuidString)
        }
        for folder in notes.folders {
            let parent: String = folder.parentId?.uuidString ?? ""
            parts.append("\(folder.id.uuidString)|\(folder.name)|\(parent)")
        }
        parts.append("\(reduceMotion)")
        parts.append(nodeStyle + "|" + folderStyles)
        parts.append("t" + theme.rawValue)
        parts.append("\(quality.rawValue)")
        parts.append("g\(graphics.tier.rawValue)")
        parts.append("\(bold)")
        parts.append("\(highContrast)")
        // the link length plans the Universe and the themes (not the single
        // looks, which the force layout places)
        if universe { parts.append(GraphLinkLength.tag(linkValue)) }
        return parts.joined(separator: "\n")
    }

    /// Reduce Transparency or Increase Contrast: brighter, solid links.
    private var bold: Bool {
        reduceTransparency || highContrast
    }

    /// Increase Contrast: black name pills with a white rim.
    private var highContrast: Bool {
        contrast == .increased
    }

    private func rebuild() async {
        if theme != .space {
            await rebuildTheme(theme)
            return
        }
        if isUniverse {
            await rebuildUniverse()
            return
        }
        let ids = notes.notes.map(\.id)
        let edges = notes.allEdges()
        var folders: [UUID: UUID] = [:]
        for note in notes.notes {
            if let folder = note.folderId { folders[note.id] = folder }
        }
        // a constant copy: a var cannot be handed to another thread
        let groups = folders
        // the layout, and (once per launch) a check that the shaders work
        // then packed into one constellation and turned to show its broadest
        // face (GraphFraming)
        let worked = await Task.detached(priority: .userInitiated) {
            let laid = ForceLayout3D.layout(nodes: ids, edges: edges, groups: groups)
            let radius: Float = GraphFraming.pageRadius(laid, edges: edges)
            let reach: Float = radius * GraphShape.diskRadius
            let positions = GraphFraming.arrange(laid, edges: edges, pad: reach)
            let support: GraphShaderSupport = GraphShaderProbe.support
            _ = GraphStyleProbe.support
            return (positions, support, radius)
        }.value
        guard !Task.isCancelled else { return }
        let lively: Bool = !reduceMotion && quality != .still && SpaceQuality.current() != .still
        var scene: GraphScene = GraphSceneBuilder.build(store: notes, positions: worked.0, edges: edges,
                                                        lively: lively, bold: bold, shaders: worked.1,
                                                        pageRadius: worked.2, contrast: highContrast)
        var names: [UUID: String] = [:]
        for note in notes.notes { names[note.id] = note.title.isEmpty ? "Untitled" : note.title }
        scene.names = names
        built = scene
    }

    /// The Universe: the plan (GraphUniverse) off the main thread, no force
    /// layout; then the scene.
    private func rebuildUniverse() async {
        let edges = notes.allEdges()
        let input: UniverseInput = universeInput(edges: edges)
        let worked = await Task.detached(priority: .userInitiated) {
            let plan: UniversePlan = GraphUniverse.plan(input)
            let support: GraphShaderSupport = GraphShaderProbe.support
            _ = GraphStyleProbe.support
            return (plan, support)
        }.value
        guard !Task.isCancelled else { return }
        let lively: Bool = !reduceMotion && quality != .still && SpaceQuality.current() != .still
        // folder looks by the plan's galaxy, not the store's top-level walk
        let looks: [UUID: GraphNodeStyle] = GraphStyleChoice.folders(GraphStyleChoice.folderRaw)
        var scene: GraphScene = GraphSceneBuilder.buildUniverse(store: notes, plan: worked.0, edges: edges,
                                                                lively: lively, bold: bold, shaders: worked.1,
                                                                contrast: highContrast, folderLooks: looks)
        var roles: [UUID: String] = [:]
        var names: [UUID: String] = [:]
        for body in worked.0.bodies {
            roles[body.id] = body.role.rawValue
            names[body.id] = body.label
        }
        scene.roles = roles
        scene.names = names
        scene.linkScale = linkValue
        built = scene
    }

    /// A theme other than Space (GraphThemes): its plan and its shaders'
    /// check off the main thread, then the shared theme scene with its
    /// look. A theme not built yet shows the Universe.
    private func rebuildTheme(_ chosen: GraphTheme) async {
        let edges = notes.allEdges()
        let input: UniverseInput = universeInput(edges: edges)
        let worked = await Task.detached(priority: .userInitiated) { () -> ThemePlan? in
            let plan: ThemePlan? = GraphThemes.plan(chosen, input)
            GraphThemes.prepare(chosen)
            return plan
        }.value
        guard !Task.isCancelled else { return }
        let lively: Bool = !reduceMotion && quality != .still && SpaceQuality.current() != .still
        guard let plan = worked, let look = GraphThemes.look(chosen, lively: lively, bold: bold) else {
            await rebuildUniverse()
            return
        }
        var scene: GraphScene = GraphSceneBuilder.buildTheme(store: notes, plan: plan, look: look, edges: edges,
                                                             lively: lively, contrast: highContrast)
        var roles: [UUID: String] = [:]
        var names: [UUID: String] = [:]
        for body in plan.bodies where body.kind != .fixture {
            roles[body.id] = String(body.role)
            names[body.id] = body.label
        }
        scene.roles = roles
        scene.names = names
        scene.linkScale = linkValue
        built = scene
    }

    /// What the plan reads from the store: notes, folders and links only.
    /// The design preview seeds by name, as its ids change every launch.
    private func universeInput(edges: [(UUID, UUID)]) -> UniverseInput {
        var list: [UniverseNote] = []
        list.reserveCapacity(notes.notes.count)
        for note in notes.notes {
            let words: Int = GraphUniverse.wordCount(note.body)
            let made: Double = note.createdAt.timeIntervalSinceReferenceDate
            list.append(UniverseNote(id: note.id, title: note.title, isPage: note.kind == .page,
                                     folder: note.folderId, words: words, created: made))
        }
        let folders: [UniverseFolder] = notes.folders.map { folder in
            UniverseFolder(id: folder.id, name: folder.name, parent: folder.parentId)
        }
        let links: [UniverseEdge] = edges.map { UniverseEdge(a: $0.0, b: $0.1) }
        return UniverseInput(notes: list, folders: folders, edges: links, seedByName: GraphPreview.isOn,
                             linkScale: linkValue)
    }
}

/// A built scene, the camera it is seen through, where that camera starts,
/// and the simulation that keeps it moving.
struct GraphScene {
    let scene: SCNScene
    let camera: SCNNode
    let sim: GraphSim
    /// Every note's home, for framing (GraphFraming.distance); in the
    /// Universe the plan's envelope.
    let homes: [SIMD3<Float>]
    /// How far a note's look reaches past its centre.
    let pad: Float
    /// The Universe (GraphUniverse): framed to fill 0.88, with folders to
    /// fly into.
    var universe: Bool = false
    /// Each folder body's system, relative to it, for its fly-in framing.
    var systems: [[SIMD3<Float>]] = []
    /// What VoiceOver reads as the space's value.
    var summary: String = ""
    /// Each folder body's index, by folder id (the home star by
    /// GraphUniverse.homeID), and by name (the design preview).
    var folders: [UUID: Int] = [:]
    var containerTitles: [String: Int] = [:]
    /// The design preview's drag in the Universe: the busiest star.
    var dragTarget: Int? = nil
    /// The Universe's galaxies (the plan's top level, which also takes in
    /// a folder whose parent is missing or that closes a cycle), and each
    /// note's galaxy - what the filter and folder looks go by.
    var galaxies: [UUID] = []
    var galaxyOf: [UUID: UUID] = [:]
    /// The theme it was built in (GraphTheme): the words VoiceOver and the
    /// first-run card use.
    var theme: GraphTheme = .space
    /// Each body's role in its theme's plan (UniverseRole's raw value, or
    /// NeuronRole's or CircuitRole's as a number), for the peek card's
    /// words; empty in the single looks.
    var roles: [UUID: String] = [:]
    /// The link length it was planned at (GraphLinkLength).
    var linkScale: Double = 1
    /// What VoiceOver calls each body (its name pill's words).
    var names: [UUID: String] = [:]
}

/// Turns notes and their positions into SceneKit nodes.
///
/// Each note's node is named "note:<id>", which is how a tap finds out which
/// note it landed on. Only the black spheres and the titles can be hit
/// (category 1); rings, disks, links and sparks are category 2.
///
/// Each note is built as:
///
///     note (black sphere)
///       disk tilt (fixed, a little different for every note)
///         disk (a flat plane, spun about its own axis by GraphSim)
///       ring holder (billboarded: always faces the camera)
///         ring stretch (lifted towards the camera; squash and stretch)
///           ring (the plane, turned back so its bright side stays right)
///       label (billboarded; hidden until hovered, pressed or chosen)
///         rim, pill, words
///
/// and the whole graph hangs from the scene as root -> tilt rig -> world:
/// the rig is turned a few hundredths of a radian by the device's tilt
/// (GraphSim), so the notes shift against the sky like things seen through
/// a window.
///
/// The ring is lifted more than a radius towards the camera, so no part of
/// its own sphere is ever in front of it and the rim shows all the way
/// round from every angle; it is still tested against depth, so another
/// note in front hides it. The disk stays a flat, tilted plane through the
/// centre, so its far half passes behind the sphere as it should.
@MainActor
enum GraphSceneBuilder {
    static func build(store: NoteStore, positions: [UUID: SIMD3<Float>], edges: [(UUID, UUID)],
                      lively: Bool, bold: Bool, shaders: GraphShaderSupport,
                      pageRadius: Float, contrast: Bool = false) -> GraphScene {
        let scene = SCNScene()
        // deep space: a sky of geometry kept round the camera (GraphSpace)
        scene.background.contents = UIColor.black
        let sky: SCNNode = GraphSpace.makeSky()
        scene.rootNode.addChildNode(sky)
        // root -> tilt rig -> world: the rig turns with the device's tilt
        let rig = SCNNode()
        rig.name = "tiltRig"
        scene.rootNode.addChildNode(rig)
        let world = SCNNode()
        rig.addChildNode(world)
        let ideaRadius: Float = pageRadius * 0.62

        let textColor = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)

        // connections: camera-facing ribbons, all in one geometry that
        // GraphSim rebuilds as the notes move; the look is in the shader,
        // which also reads each end's style (GraphStyleShaders.link)
        let styled: GraphStyleSupport = GraphStyleProbe.support
        let linkMaterial: SCNMaterial = GraphStyleKit.link(bold: bold, old: shaders.link,
                                                           styled: styled.has("link"),
                                                           lively: lively, reach: pageRadius * 2.5)
        let lines = SCNNode()
        lines.name = "links"
        lines.renderingOrder = 5
        lines.categoryBitMask = 2
        world.addChildNode(lines)

        // every note in its style (GraphNodeStyles), built by the kit from
        // shared geometry and materials; a bright pair for a chosen black
        // hole in the plain space
        let styles: [UUID: GraphNodeStyle] = GraphStyleChoice.resolve(store: store)
        // the style shaders' noise loops: only at full liveliness and High
        let detail: Float = SpaceQuality.current() == .full ? GraphQuality.current.shaderDetail : 0
        let kit = GraphStyleKit(store: store, shaders: shaders, support: styled, lively: lively, detail: detail)
        var clocked: [SCNMaterial] = []
        if shaders.link || styled.has("link") { clocked.append(linkMaterial) }
        let hotRingMaterial = GraphLook.ring(tint: .white, hot: true, shader: shaders.ring, lively: lively)
        if shaders.ring { clocked.append(hotRingMaterial) }
        let hotRing: SCNGeometry = plane(hotRingMaterial)
        let hotDisk: SCNGeometry = plane(GraphLook.disk(tint: .white, hot: true, shader: shaders.disk))
        var degree: [UUID: Int] = [:]
        for edge in edges {
            degree[edge.0, default: 0] += 1
            degree[edge.1, default: 0] += 1
        }

        var random = SplitMix64(seed: 0x6A26)
        var infos: [GraphNodeInfo] = []
        var extent: Float = 1
        var homes: [SIMD3<Float>] = []
        var suns: [(Int, Int)] = []
        for note in store.notes {
            guard let p = positions[note.id] else { continue }
            extent = max(extent, simd_length(p))
            homes.append(p)
            // a note with more links is a little bigger and brighter
            let links: Int = degree[note.id] ?? 0
            let base: Float = note.kind == .page ? pageRadius : ideaRadius
            let grown: Float = min(1 + 0.12 * log2(1 + Float(links)), 1.45)
            let radius: Float = base * grown
            let style: GraphNodeStyle = styles[note.id] ?? .blackHole
            let made: GraphStyledParts = kit.make(note: note, style: style, radius: radius, random: &random)
            let node: SCNNode = made.node
            node.simdPosition = p

            let title: String = note.title.isEmpty ? "Untitled" : note.title
            let labelHeight: Float = max(radius * 1.05, 0.17)
            let label = Self.label(title, color: textColor, height: labelHeight, contrast: contrast)
            let labelLift: Float = radius * 2.3 + 0.04
            label.simdPosition = SIMD3<Float>(0, labelLift, 0)
            node.addChildNode(label)
            world.addChildNode(node)

            if style == .sun { suns.append((infos.count, links)) }
            var info = GraphNodeInfo(id: note.id, node: node, label: label, kind: note.kind,
                                     root: store.rootFolder(of: note.folderId), home: p,
                                     radius: made.radius, ringStretch: made.ringStretch,
                                     ringLeaf: made.ringLeaf, ringGeometry: made.ringGeometry,
                                     diskLeaf: made.diskLeaf, diskGeometry: made.diskGeometry,
                                     spin: made.spin, spinRate: made.spinRate)
            info.style = style
            info.hotRing = made.hotRing
            info.hotDisk = made.hotDisk
            info.swell = made.swell
            info.stretchGain = made.stretchGain
            info.glowGain = 0.82 + 0.18 * min(Float(links) / 5, 1)
            info.deathKind = GraphDeath.kind(style: style.rawValue)
            info.shine = GraphShine.universe(Self.shineRole(style), empty: false, tier: 1)
            infos.append(info)
        }

        // the chosen note's orbit ring, and a faint gravity well round each
        // folder's notes
        let orbit: SCNNode = kit.makeOrbit()
        world.addChildNode(orbit)
        for well in kit.makeWells(homes: positions, radius: pageRadius) {
            world.addChildNode(well)
        }
        clocked.append(contentsOf: kit.clocked)
        suns.sort { $0.1 > $1.1 }
        let styler = GraphStyleAnimator(rigs: kit.rigs, suns: suns.map { $0.0 }, lit: kit.lit,
                                        orbit: orbit, extent: extent)

        // comet trails: a few emitters shared by whichever notes are moving
        // fastest; none at all with Reduce Motion
        var emitters: [SCNNode] = []
        var trails: [SCNParticleSystem] = []
        if lively {
            for _ in 0..<4 {
                let system: SCNParticleSystem = GraphLook.trail(scale: pageRadius / 0.2)
                let emitter = SCNNode()
                emitter.categoryBitMask = 2
                emitter.renderingOrder = 7
                emitter.addParticleSystem(system)
                world.addChildNode(emitter)
                emitters.append(emitter)
                trails.append(system)
            }
        }

        // the camera: placed by the view to fit the graph to the screen
        // (GraphFraming); here, a first guess for a phone held upright.
        // Everything is unlit, so there are no lights.
        // framed to the rings; the thin, tilted disks may reach a little past
        let pad: Float = pageRadius * 1.4
        let distance: Float = GraphFraming.distance(points: homes, pad: pad, aspect: 0.46)
        let camera = SCNCamera()
        camera.fieldOfView = Double(GraphFraming.fieldOfView)
        camera.zNear = 0.05
        let far: Float = distance * 4 + extent * 4 + 20
        camera.zFar = Double(far)
        // the sky sits just inside the far plane, kept round the camera
        let skyRadius: Float = far * 0.5
        sky.simdScale = SIMD3<Float>(skyRadius, skyRadius, skyRadius)
        // no HDR, bloom or glare: the glows are baked into the textures and
        // shaders, and camera bloom would put a halo round everything bright
        camera.wantsHDR = false
        camera.bloomIntensity = 0
        camera.wantsExposureAdaptation = false
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let cameraHome = SIMD3<Float>(0, 0, distance)
        cameraNode.simdPosition = cameraHome
        scene.rootNode.addChildNode(cameraNode)

        // kept for GraphSim's signature; names now show only when hovered,
        // pressed or chosen, not by distance
        let scaledReach: Float = distance * 0.55
        let labelReach: Float = max(scaledReach, 5.5)
        var simLooks = GraphSimLooks(linkMaterial: linkMaterial, hotRing: hotRing, hotDisk: hotDisk,
                                     clocked: clocked, emitters: emitters, trails: trails, sky: sky)
        simLooks.styler = styler
        // only what changed since the scene on screen pops, grows or fades
        simLooks.recall = GraphMemory.recall(ids: infos.map(\.id), edges: edges, styles: styles,
                                             lively: lively)
        // notes deleted since the scene on screen die in this one
        let key: String = "look"
        let dyingLinks = GraphDeathLinks(material: linkMaterial, halfWidth: GraphShape.linkHalfWidth)
        simLooks.dying = GraphDeathStage.make(world: world, keeping: Set(infos.map(\.id)), key: key,
                                              lively: lively, links: dyingLinks)
        let sim = GraphSim(world: world, rig: rig, infos: infos, edges: edges, lines: lines,
                           looks: simLooks, lively: lively, labelReach: labelReach)
        GraphMemory.remember(sim, edges: edges, styles: styles, key: key)
        return GraphScene(scene: scene, camera: cameraNode, sim: sim, homes: homes, pad: pad)
    }

    /// A single look's style as the Universe body it looks like, for the
    /// light it throws behind the name pills (GraphShine).
    static func shineRole(_ style: GraphNodeStyle) -> String {
        switch style {
        case .blackHole: return "galaxy"
        case .sun: return "star"
        case .gasGiant: return "gasGiant"
        case .rocky: return "rocky"
        case .pulsar: return "pulsar"
        case .comet: return "comet"
        }
    }

    /// A one-by-one square plane; each note scales it to size.
    static func plane(_ material: SCNMaterial) -> SCNGeometry {
        let plane = SCNPlane(width: 1, height: 1)
        plane.materials = [material]
        return plane
    }

    /// A small flat title that always faces the camera, on a solid dark
    /// pill just the size of the words, with a thin lighter rim round it.
    /// Everything in it is fully opaque and drawn over the whole scene
    /// without depth testing, so no link, glow or note ever shows through or
    /// hides it. It starts hidden; GraphSim shows it for the hovered,
    /// pressed or chosen note.
    /// `rim` tints the rim (a galaxy's names); `cut` shortens a long title
    /// (a folder's label comes already cut, so its count always shows).
    static func label(_ text: String, color: UIColor, height: Float, contrast: Bool,
                      rim rimTint: UIColor? = nil, cut: Bool = true) -> SCNNode {
        let long: Bool = cut && text.count > 28
        let shown: String = long ? String(text.prefix(27)) + "\u{2026}" : text
        let geometry = SCNText(string: shown, extrusionDepth: 0)
        geometry.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        geometry.flatness = 0.3
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        // always in front: a note between the camera and a name never hides it
        material.readsFromDepthBuffer = false
        geometry.materials = [material]

        let textNode = SCNNode(geometry: geometry)
        // centred over the point, sitting on it
        let (low, high) = textNode.boundingBox
        let middleX: Float = (low.x + high.x) / 2
        textNode.pivot = SCNMatrix4MakeTranslation(middleX, low.y, 0)
        // a 10-point font is about 10 units tall; shrink it to `height`
        let scale: Float = height / 10
        textNode.scale = SCNVector3(x: scale, y: scale, z: scale)

        // the pill hugs the words: a little room each side, less above and
        // below
        let textWidth: Float = (high.x - low.x) * scale
        let textHeight: Float = (high.y - low.y) * scale
        let padX: Float = height * 0.22
        let padY: Float = height * 0.10
        let pillWidth: Float = textWidth + padX * 2
        let pillHeight: Float = textHeight + padY * 2
        let pillColor: UIColor = contrast ? UIColor.black : Self.pillFill
        let pill = SCNPlane(width: CGFloat(pillWidth), height: CGFloat(pillHeight))
        pill.cornerRadius = CGFloat(pillHeight / 2)
        pill.materials = [Self.solid(pillColor)]
        let pillNode = SCNNode(geometry: pill)
        pillNode.simdPosition = SIMD3<Float>(0, textHeight / 2, -0.002)

        // the rim: one step behind the pill and a hair bigger all round
        let edge: Float = height * 0.12
        let rimWidth: Float = pillWidth + edge
        let rimHeight: Float = pillHeight + edge
        let rimColor: UIColor = contrast ? UIColor.white : (rimTint ?? Self.rimFill)
        let rim = SCNPlane(width: CGFloat(rimWidth), height: CGFloat(rimHeight))
        rim.cornerRadius = CGFloat(rimHeight / 2)
        rim.materials = [Self.solid(rimColor)]
        let rimNode = SCNNode(geometry: rim)
        rimNode.simdPosition = SIMD3<Float>(0, textHeight / 2, -0.004)

        // drawn after everything else in the space: the rim, then the pill,
        // then the words on top
        rimNode.renderingOrder = 19
        pillNode.renderingOrder = 20
        textNode.renderingOrder = 21

        let holder = SCNNode()
        holder.name = "label"
        holder.renderingOrder = 20
        holder.addChildNode(rimNode)
        holder.addChildNode(pillNode)
        holder.addChildNode(textNode)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        holder.constraints = [billboard]
        return holder
    }

    /// A solid dark slate: dark enough for the pale words, not so black it
    /// reads as a hole.
    static let pillFill = UIColor(red: 0.12, green: 0.13, blue: 0.19, alpha: 1)
    static let rimFill = UIColor(red: 0.40, green: 0.43, blue: 0.55, alpha: 1)

    /// Fully opaque, unlit, and never tested against depth: it replaces what
    /// is behind it rather than blending with it.
    static func solid(_ colour: UIColor) -> SCNMaterial {
        let look = SCNMaterial()
        look.diffuse.contents = colour
        look.lightingModel = .constant
        look.transparency = 1
        look.blendMode = .replace
        look.isDoubleSided = true
        look.writesToDepthBuffer = false
        look.readsFromDepthBuffer = false
        return look
    }
}

/// SceneKit's view, wrapped so a tap can say which note it landed on and a
/// drag on a note can move it - neither of which SwiftUI's SceneView offers.
/// Turning and zooming, when the finger is not on a note, are SceneKit's own
/// camera control.
///
/// - A finger (or Pencil, or click) down on a body shows its name for as
///   long as it is held (FramingSCNView forwards touch down and lift).
/// - One tap on a body chooses it: its ring brightens and there is a small
///   selection tick. One tap on empty space lets it go. A single tap never
///   opens anything, and never waits for a second.
/// - Two taps on a note open it. In the Universe, two taps on a star or
///   black hole fly the camera in to its system, and two more open the
///   folder in the List. Two taps on empty space are SceneKit's own (bring
///   the camera back), which wait for ours to find nothing there.
/// - The pointer (trackpad, mouse, Pencil hover) shows the name of the body
///   it is over.
///
/// A body is found by where it is on screen and how big it is drawn (see
/// `pick`), with SceneKit's own hit test as the last resort.
///
/// In the Universe the view runs at 120 frames a second from any touch,
/// press, pan, tap or hover until 3 seconds after the last one, and at 60
/// otherwise - the orbits stay smooth and idle battery use halves. A drag
/// always runs at 120.
/// What the map tells SwiftUI about touches (GraphTouchModel): a tap (on a
/// body, or nil on empty space), a double tap, a body held still (and
/// where), and VoiceOver's actions on a body ("select", "Open", "Show
/// links", "Fly in", "Delete").
struct GraphTouchHandlers {
    var select: (UUID?) -> Void = { _ in }
    var double: (UUID) -> Void = { _ in }
    var hold: (UUID, CGPoint) -> Void = { _, _ in }
    var voice: (UUID, String) -> Void = { _, _ in }
}

struct GraphSCNView: UIViewRepresentable {
    let built: GraphScene
    let filter: GraphFilter
    let recenter: Int
    /// How much of the view is under glass on each side; the graph is
    /// framed to the rest.
    let insets: GraphInsets
    let onTap: (UUID) -> Void
    var openFolder: (UUID?) -> Void = { _ in }
    /// The camera's requests from the card (GraphMapCommand), the chosen
    /// body, the body whose links alone are shown, and the name pills'
    /// accessibility settings.
    var command = GraphMapCommand()
    var chosen: UUID? = nil
    var linksFor: UUID? = nil
    var labels = GraphLabelSettings()
    var touch = GraphTouchHandlers()

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, openFolder: openFolder, recenter: recenter, insets: insets)
    }

    func makeUIView(context: Context) -> FramingSCNView {
        let view = FramingSCNView(frame: .zero)
        // the sky covers it; black until the first frame
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        // High: 4x multisampling, and every frame the screen shows (120 a
        // second on ProMotion); Smooth: 2x, and 60 (GraphQuality)
        view.antialiasingMode = Self.antialiasing()
        view.preferredFramesPerSecond = GraphQuality.frameRate
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true

        let coordinator = context.coordinator
        coordinator.view = view
        view.onResize = { [weak coordinator] size in coordinator?.resized(to: size) }
        view.onPress = { [weak coordinator] point in coordinator?.pressed(at: point) }
        view.onMove = { [weak coordinator] in coordinator?.wake() }
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = coordinator
        view.addGestureRecognizer(tap)
        coordinator.tapper = tap
        let twice = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.opened(_:)))
        twice.numberOfTapsRequired = 2
        twice.delegate = coordinator
        view.addGestureRecognizer(twice)
        coordinator.doubleTapper = twice
        let hover = UIHoverGestureRecognizer(target: coordinator, action: #selector(Coordinator.hovered(_:)))
        view.addGestureRecognizer(hover)
        // a body is moved only after it is held a quarter second; a quick
        // drag anywhere turns the camera (GraphTouchRules)
        let hold = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = GraphTouchRules.holdToDrag
        hold.allowableMovement = CGFloat(GraphTouchRules.slop)
        hold.delegate = coordinator
        view.addGestureRecognizer(hold)
        coordinator.holder = hold
        // a tap waits only for the hold to fail - at once when the finger
        // lifts before a quarter second - so a long hold never also taps
        tap.require(toFail: hold)

        coordinator.touch = touch
        coordinator.chosenID = chosen
        coordinator.linksID = linksFor
        coordinator.labels = labels
        coordinator.commandSerial = command.serial
        coordinator.attach(built, to: view)
        coordinator.apply(filter)
        return view
    }

    func updateUIView(_ view: FramingSCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.openFolder = openFolder
        coordinator.touch = touch
        coordinator.labels = labels
        let rebuilt: Bool = coordinator.sim !== built.sim
        coordinator.chosenID = chosen
        coordinator.linksID = linksFor
        if rebuilt {
            coordinator.attach(built, to: view)
        } else {
            coordinator.syncChoice()
        }
        coordinator.apply(filter)
        if coordinator.commandSerial != command.serial {
            coordinator.commandSerial = command.serial
            coordinator.run(command.kind)
        }
        if coordinator.recenterCount != recenter {
            coordinator.recenterCount = recenter
            coordinator.insets = insets
            coordinator.recentre()
        } else if coordinator.insets != insets {
            coordinator.inset(to: insets)
        }
    }

    static func dismantleUIView(_ view: FramingSCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    /// The multisampling the Graphics budget allows.
    static func antialiasing() -> SCNAntialiasingMode {
        GraphQuality.current.msaa >= 4 ? .multisampling4X : .multisampling2X
    }

    /// One body as a pick sees it: its index, where its centre is on screen,
    /// how big it is drawn there (points), how deep it is, and whether it is
    /// a folder.
    struct Seen {
        let index: Int
        let centre: CGPoint
        let size: CGFloat
        let depth: Float
        let folder: Bool
        let distance: CGFloat
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (UUID) -> Void
        var openFolder: (UUID?) -> Void
        var recenterCount: Int
        /// How much of the view is under glass; framing fits the rest.
        var insets: GraphInsets
        private(set) var sim: GraphSim?
        weak var view: SCNView?
        /// Hold a quarter second on a body, then move: it is picked up
        /// (held still longer: its options).
        weak var holder: UILongPressGestureRecognizer?
        weak var tapper: UITapGestureRecognizer?
        /// What the map tells SwiftUI (GraphTouchHandlers), and what
        /// SwiftUI has chosen: the chosen body, the body whose links alone
        /// show, the name pills' settings, the last camera request done.
        var touch = GraphTouchHandlers()
        var chosenID: UUID?
        var linksID: UUID?
        var labels = GraphLabelSettings()
        var commandSerial: Int = 0
        /// What the chosen body and Show links were last set to on the
        /// scene, so a change is made once.
        private var shownChoice: UUID?
        private var shownLinks: UUID?
        private var shownLinksSet: Bool = false
        /// A hold in progress: where it went down, and whether it has
        /// picked the body up or opened its options.
        private var holdStart: CGPoint = .zero
        private var holdMoving: Bool = false
        private var holdMenu: Bool = false
        /// Which hold the options' wait belongs to (a new hold, a move or a
        /// lift makes it stale).
        private var holdGeneration: Int = 0
        /// The pick-up tick and the light tick when a body is chosen.
        private let pickup = UIImpactFeedbackGenerator(style: .medium)
        private let light = UIImpactFeedbackGenerator(style: .light)
        /// VoiceOver: the map's summary and one element per body.
        private var voiceElements: [UIAccessibilityElement] = []
        /// The link length the scene on screen was planned at.
        private var lastLinkScale: Double = 1
        weak var doubleTapper: UITapGestureRecognizer?
        private var camera: SCNNode?
        /// The notes' homes and how far each reaches, for framing.
        private var homes: [SIMD3<Float>] = []
        private var pad: Float = 0
        /// The Universe: framing fills 0.88; folders to fly into.
        private var universe: Bool = false
        private var systems: [[SIMD3<Float>]] = []
        private var folders: [UUID: Int] = [:]
        private var titles: [String: Int] = [:]
        private var dragTarget: Int?
        /// The folder body the camera has flown in to (its index and id),
        /// or nil at the whole map.
        private var flown: Int?
        private var flownID: UUID?
        /// Whether the graph was last framed for a wide (landscape) view;
        /// nil before the first framing.
        private var framedWide: Bool?
        /// Where the last framing put the camera, to tell whether it has
        /// been turned or zoomed since.
        private var framedPose: simd_float4x4?
        private var shownFilter: GraphFilter?
        /// The note a drag is about to pick up, found when the drag begins.
        private var pending: Int?
        /// How far into the screen the dragged note sits, so it moves across
        /// the screen at that depth.
        private var dragDepth: Float = 0
        /// From the finger to the note's centre, so it does not jump.
        private var dragOffset = SIMD3<Float>(0, 0, 0)
        /// True between a drag picking a note up and letting it go.
        private var dragging: Bool = false
        /// The camera's own drags and double taps already told to wait for
        /// ours.
        private var wired: Set<ObjectIdentifier> = []
        /// The design preview's drag has been started (see GraphPreview).
        private var previewDragged: Bool = false
        /// The design preview's chosen note has been picked (see GraphPreview).
        private var previewChosen: Bool = false
        /// Where the pointer was when the hovered note was last looked for.
        private var lastHover: CGPoint?
        /// The small tick when a note is chosen.
        private let chooser = UISelectionFeedbackGenerator()
        /// The last touch, press, pan, tap or hover (the Universe's frame
        /// rate), and whether a check to slow down is already waiting.
        private var lastWake: CFTimeInterval = 0
        private var settling: Bool = false

        init(onTap: @escaping (UUID) -> Void, openFolder: @escaping (UUID?) -> Void, recenter: Int,
             insets: GraphInsets) {
            self.onTap = onTap
            self.openFolder = openFolder
            self.recenterCount = recenter
            self.insets = insets
        }

        /// Shows a newly built scene.
        func attach(_ built: GraphScene, to view: SCNView) {
            // a new link length on the same map: the camera glides to the
            // new framing while every body glides to its new place
            let glide: Bool = sim != nil && lastLinkScale != built.linkScale && built.sim.lively
            lastLinkScale = built.linkScale
            sim = built.sim
            camera = built.camera
            homes = built.homes
            pad = built.pad
            universe = built.universe
            systems = built.systems
            folders = built.folders
            titles = built.containerTitles
            dragTarget = built.dragTarget
            framedWide = nil
            framedPose = nil
            shownFilter = nil
            // the simulation steps on SceneKit's render loop, once per frame
            view.delegate = built.sim
            view.scene = built.scene
            view.pointOfView = built.camera
            view.defaultCameraController.target = SCNVector3(x: 0, y: 0, z: 0)
            view.isPlaying = true
            view.antialiasingMode = GraphSCNView.antialiasing()
            view.preferredFramesPerSecond = GraphQuality.frameRate
            built.sim.setViewHeight(Float(view.bounds.height))
            wireCameraGestures(in: view)
            // still flown in to a folder that is still there: stay on it
            if universe, let id = flownID, let slot = folders[id] {
                if glide {
                    framedWide = view.bounds.width > view.bounds.height
                } else {
                    frame(animated: false)
                }
                fly(to: slot, animated: glide)
            } else {
                flown = nil
                flownID = nil
                frame(animated: glide)
            }
            built.sim.appear()
            built.sim.setLabelSettings(labels)
            // the chosen body and Show links carry over to the new scene
            shownChoice = nil
            shownLinks = nil
            shownLinksSet = false
            syncChoice(tick: false)
            buildVoice(built, in: view)
            wake()
            if GraphPreview.drags && !previewDragged {
                previewDragged = true
                runPreviewDrag()
            } else if GraphPreview.fly != nil && !previewChosen {
                previewChosen = true
                runPreviewFly()
            } else if GraphPreview.chooses && !previewChosen {
                previewChosen = true
                runPreviewChoice()
            }
        }

        /// For the design preview (`-graphPreview` alone): a moment after
        /// the space appears, chooses the most-linked note and shows its
        /// name - not as a press, which would stop the orbits - so the
        /// picture at rest shows one name on its pill and the one two
        /// seconds later shows the Universe still turning.
        private func runPreviewChoice() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, let sim = self.sim, let i = sim.busiestNote() else { return }
                sim.select(i)
                sim.showName(i)
            }
        }

        /// For the design preview (`-graphPreviewFly <folder>`): a moment
        /// after the space appears, flies in to that folder and holds it as
        /// a press would.
        private func runPreviewFly() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, let sim = self.sim, let name = GraphPreview.fly,
                      let i = self.titles[name] else { return }
                sim.select(i)
                sim.press(i)
                self.fly(to: i, animated: true)
            }
        }

        /// For the design preview (`-graphPreviewDrag`): a second after the
        /// space appears, picks up the most-linked note (in the Universe,
        /// the busiest star), carries it along an arc across the screen for
        /// two seconds, and lets go - so a screenshot can catch the moving
        /// look.
        private func runPreviewDrag() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let sim = self.sim, let view = self.view else { return }
                let target: Int? = self.universe ? self.dragTarget : sim.busiestNote()
                guard let i = target else { return }
                let pov: simd_float4x4 = view.pointOfView?.simdWorldTransform ?? matrix_identity_float4x4
                let screenRight = SIMD3<Float>(pov.columns.0.x, pov.columns.0.y, pov.columns.0.z)
                let screenUp = SIMD3<Float>(pov.columns.1.x, pov.columns.1.y, pov.columns.1.z)
                let right: SIMD3<Float> = sim.world.simdConvertVector(screenRight, from: nil)
                let up: SIMD3<Float> = sim.world.simdConvertVector(screenUp, from: nil)
                let start: SIMD3<Float> = sim.currentPosition(i)
                sim.grab(i)
                self.wake()
                let steps: Int = 120
                for k in 1...steps {
                    try? await Task.sleep(nanoseconds: 16_666_667)
                    let s: Float = Float(k) / Float(steps)
                    let angle: Float = s * Float.pi
                    let across: Float = (1 - cos(angle)) * 1.6
                    let lift: Float = sin(angle) * 1.2
                    let moved: SIMD3<Float> = right * across + up * lift
                    sim.drag(to: start + moved)
                }
                sim.release()
            }
        }

        func apply(_ filter: GraphFilter) {
            guard let sim else { return }
            if shownFilter == filter { return }
            let before: GraphFilter? = shownFilter
            shownFilter = filter
            sim.apply(filter)
            refreshVoice()
            // the chosen body filtered away: let it go (after this update)
            if let id = chosenID, let i = sim.index[id], !sim.isVisible(i) {
                let report: (UUID?) -> Void = touch.select
                DispatchQueue.main.async { report(nil) }
            }
            // the Universe: a folder filter flies to its galaxy, and
            // Everything frames the whole map again
            guard universe, let before else { return }
            if case .folder(let id) = filter, let slot = folders[id] {
                fly(to: slot, animated: true)
            } else if filter == .all && before != .all {
                flown = nil
                flownID = nil
                frame(animated: true)
            }
        }

        /// Glides the camera back to the fitted view of the whole graph.
        func recentre() {
            flown = nil
            flownID = nil
            frame(animated: true)
        }

        /// The glass round the space changed (the switcher folded, the
        /// keyboard or the dock came or went). While the camera is still
        /// where the last framing left it, the graph glides to fit the new
        /// window; once it has been turned or zoomed, it is left alone and
        /// the next Recentre uses the new window.
        func inset(to new: GraphInsets) {
            insets = new
            guard framedWide != nil, untouched else { return }
            refit(animated: true)
        }

        /// Whether the camera is still where the last framing put it.
        private var untouched: Bool {
            guard let view, let camera, let pose = framedPose else { return false }
            guard view.pointOfView === camera else { return false }
            return Self.same(camera.simdTransform, pose)
        }

        private static func same(_ a: simd_float4x4, _ b: simd_float4x4) -> Bool {
            let gaps: [SIMD4<Float>] = [a.columns.0 - b.columns.0, a.columns.1 - b.columns.1,
                                        a.columns.2 - b.columns.2, a.columns.3 - b.columns.3]
            for gap in gaps where gap.max() > 0.001 || gap.min() < -0.001 {
                return false
            }
            return true
        }

        /// The view changed size. The first time it has a size, and whenever
        /// it turns between upright and wide, the graph is framed again.
        func resized(to size: CGSize) {
            guard size.width > 1, size.height > 1 else { return }
            sim?.setViewHeight(Float(size.height))
            let wide: Bool = size.width > size.height
            guard framedWide != wide else { return }
            refit(animated: framedWide != nil)
        }

        /// Frames again what was framed: the flown-in folder, or everything.
        private func refit(animated: Bool) {
            if let slot = flown {
                frame(animated: false)
                fly(to: slot, animated: animated)
            } else {
                frame(animated: animated)
            }
        }

        /// The world's turn for the view's shape: upright, the graph's long
        /// axis (y) runs up the screen; wide, turned a quarter so it runs
        /// across.
        private func worldTurn(wide: Bool) -> simd_quatf {
            let angle: Float = wide ? -Float.pi / 2 : 0
            return simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
        }

        /// Fits the whole graph to the screen (GraphFraming): its longest
        /// spread along the screen's long side, filling 80% of the shorter
        /// one of the part not under glass (88% of the Universe's
        /// envelope), centred in that part, seen from the front. It aims
        /// at the middle of the map's box (GraphMapBounds), not the
        /// origin: a theme's plan (the Neurons' pathway running down, the
        /// Circuit's boards) need not be centred on it.
        private func frame(animated: Bool) {
            guard let view, let camera, let sim else { return }
            let size: CGSize = view.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let wide: Bool = size.width > size.height
            framedWide = wide
            let turn: simd_quatf = worldTurn(wide: wide)
            let turned: [SIMD3<Float>] = homes.map { turn.act($0) }
            let middle: SIMD3<Float> = GraphMapBounds.centre(turned)
            let around: [SIMD3<Float>] = turned.map { $0 - middle }
            let window: GraphWindow = GraphFraming.window(width: Float(size.width),
                                                          height: Float(size.height), insets: insets)
            let fill: Float = universe ? 0.88 : GraphFraming.fill
            let distance: Float = GraphFraming.distance(points: around, pad: pad, window: window, fill: fill)
            let home: SIMD3<Float> = middle + GraphFraming.cameraHome(distance: distance, window: window)
            view.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(x: middle.x, y: middle.y, z: middle.z)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sim.world.simdOrientation = turn
            camera.simdPosition = home
            camera.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            SCNTransaction.commit()
            framedPose = camera.simdTransform
        }

        /// Flies the camera in to frame folder body `i`'s whole system - its
        /// planets, companion stars and theirs - over 0.8 s (at once with
        /// Reduce Motion, or while the space holds still: SpaceQuality
        /// .still). It centres on where the folder rests (folders never
        /// orbit), not where it is this instant: after a rebuild that is
        /// still a recalled start gliding to its new home, and after a drag
        /// a star springing back. The world keeps its turn.
        private func fly(to i: Int, animated: Bool) {
            guard let view, let camera, let sim, i >= 0, i < systems.count else { return }
            let points: [SIMD3<Float>] = systems[i]
            guard !points.isEmpty else { return }
            let size: CGSize = view.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let wide: Bool = size.width > size.height
            let turn: simd_quatf = worldTurn(wide: wide)
            let turned: [SIMD3<Float>] = points.map { turn.act($0) }
            let window: GraphWindow = GraphFraming.window(width: Float(size.width),
                                                          height: Float(size.height), insets: insets)
            let distance: Float = GraphFraming.distance(points: turned, pad: 0.25, window: window, fill: 0.88)
            let offset: SIMD3<Float> = GraphFraming.cameraHome(distance: distance, window: window)
            let local: SIMD3<Float> = sim.homePosition(i)
            let centre: SIMD3<Float> = turn.act(local)
            flown = i
            flownID = sim.ids[i]
            let still: Bool = !sim.lively || UIAccessibility.isReduceMotionEnabled
            view.pointOfView = camera
            view.defaultCameraController.target = SCNVector3(x: centre.x, y: centre.y, z: centre.z)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated && !still ? 0.8 : 0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sim.world.simdOrientation = turn
            camera.simdPosition = centre + offset
            camera.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            SCNTransaction.commit()
            framedPose = camera.simdTransform
            wake()
        }

        /// The view is going: stop drawing and let go of the simulation.
        func stop() {
            view?.isPlaying = false
            view?.delegate = nil
        }

        // MARK: the frame rate

        /// Any touch, press, pan, tap or hover: 120 frames a second, until 3
        /// seconds after the last one (the Universe; the graph look always
        /// runs at 120). A Universe that holds still (Reduce Motion, Low
        /// Power Mode, a hot device) stays at 60: nothing animates, and a
        /// drag is smooth enough there.
        func wake() {
            guard let view else { return }
            if universe, let sim, !sim.lively {
                if view.preferredFramesPerSecond != 60 { view.preferredFramesPerSecond = 60 }
                return
            }
            lastWake = CACurrentMediaTime()
            // Smooth: 60 throughout, so the rate never changes under the eye
            let fast: Int = GraphQuality.frameRate
            if view.preferredFramesPerSecond != fast { view.preferredFramesPerSecond = fast }
            guard universe, !settling else { return }
            settling = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { [weak self] in
                self?.settle()
            }
        }

        private func settle() {
            settling = false
            guard let view, universe else { return }
            let quiet: CFTimeInterval = CACurrentMediaTime() - lastWake
            if dragging || quiet < 3 {
                settling = true
                let wait: Double = dragging ? 1 : max(3.05 - quiet, 0.1)
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.settle()
                }
                return
            }
            view.preferredFramesPerSecond = 60
        }

        // MARK: gestures

        /// SceneKit's camera control brings its own gestures. Each of its
        /// drags is told to wait until ours has decided the finger is not on
        /// a note, so a drag on a note moves the note and a drag anywhere
        /// else turns the space; and each of its double taps waits for ours
        /// to find no note under the finger, so two taps on a note open it
        /// and two taps on empty space still bring the camera back.
        private func wireCameraGestures(in view: SCNView) {
            for other in view.gestureRecognizers ?? [] {
                let key = ObjectIdentifier(other)
                if wired.contains(key) { continue }
                if let holder, other !== holder, other is UIPanGestureRecognizer {
                    // a quick drag fails the hold at once (it moved), and
                    // the camera turns; a hold on a body beats it
                    other.require(toFail: holder)
                    wired.insert(key)
                } else if let doubleTapper, other !== doubleTapper,
                          let tap = other as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2 {
                    other.require(toFail: doubleTapper)
                    wired.insert(key)
                }
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view else { return true }
            if gesture === doubleTapper {
                // only on a body; on empty space SceneKit's own double tap
                // takes over
                let point: CGPoint = gesture.location(in: view)
                return pick(at: point, radius: 28, in: view) != nil
            }
            guard gesture === holder else { return true }
            let point: CGPoint = gesture.location(in: view)
            pending = dragPick(at: point, in: view)
            guard pending != nil else { return false }
            // on a note: make sure the camera does not turn as well, by
            // switching its drags off and on again, which cancels them
            wireCameraGestures(in: view)
            for other in view.gestureRecognizers ?? [] {
                guard other !== gesture, other is UIPanGestureRecognizer else { continue }
                other.isEnabled = false
                other.isEnabled = true
            }
            return true
        }

        /// A single tap never holds up a double tap - ours or SceneKit's -
        /// and is never held up by one: choosing a note is instant.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let involvesTap: Bool = gesture === tapper || other === tapper
            guard involvesTap else { return false }
            return gesture is UITapGestureRecognizer && other is UITapGestureRecognizer
        }

        /// A hold on a body (GraphTouchRules): at a quarter second it is
        /// picked up with a tick; moved, it follows the finger (its links
        /// resting, its system dragged along, as before); held still a
        /// moment longer, it is put back and its options open instead.
        /// Let go without moving: it is chosen, as a tap would.
        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            guard let view, let sim else { return }
            let point: CGPoint = gesture.location(in: view)
            wake()
            switch gesture.state {
            case .began:
                guard let i = pending else { return }
                // the depth of the note on screen is found once, here; each
                // move after that is one unprojection onto that depth
                let local: SIMD3<Float> = sim.currentPosition(i)
                let world: SIMD3<Float> = sim.world.simdConvertPosition(local, to: nil)
                let scenePoint = SCNVector3(x: world.x, y: world.y, z: world.z)
                let projected: SCNVector3 = view.projectPoint(scenePoint)
                dragDepth = projected.z
                let finger: SIMD3<Float> = fingerPoint(point, in: view, sim: sim)
                dragOffset = local - finger
                holdStart = point
                holdMoving = false
                holdMenu = false
                dragging = true
                sim.grab(i)
                pickup.impactOccurred()
                // still after a little longer: its options
                let wait: Double = GraphTouchRules.holdForMenu - GraphTouchRules.holdToDrag
                holdGeneration += 1
                let generation: Int = holdGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.holdStill(i, at: point, generation: generation)
                }
            case .changed:
                guard dragging, !holdMenu else { return }
                let dx: CGFloat = point.x - holdStart.x
                let dy: CGFloat = point.y - holdStart.y
                let moved: Double = Double((dx * dx + dy * dy).squareRoot())
                if !holdMoving && moved > GraphTouchRules.slop {
                    holdMoving = true
                    holdGeneration += 1
                }
                guard holdMoving else { return }
                let finger: SIMD3<Float> = fingerPoint(point, in: view, sim: sim)
                sim.drag(to: finger + dragOffset)
            default:
                holdGeneration += 1
                let picked: Int? = pending
                let wasStill: Bool = !holdMoving && !holdMenu
                if dragging { sim.release() }
                dragging = false
                pending = nil
                // held and let go without moving: a slow tap
                if wasStill, gesture.state == .ended, let i = picked, i < sim.ids.count {
                    touch.select(sim.ids[i])
                } else if let i = picked, !holdMenu {
                    // moved: the lit ring goes back to what SwiftUI has chosen
                    let chosenSlot: Int? = chosenID.flatMap { sim.index[$0] }
                    if chosenSlot != i {
                        if let chosenSlot { sim.select(chosenSlot) } else { sim.clearSelection() }
                    }
                }
            }
        }

        /// Held still past GraphTouchRules.holdForMenu: put it back and
        /// ask for its options, where it is.
        private func holdStill(_ i: Int, at point: CGPoint, generation: Int) {
            guard generation == holdGeneration, dragging, !holdMoving, let sim, i < sim.ids.count else { return }
            holdMenu = true
            sim.release()
            dragging = false
            light.impactOccurred()
            touch.hold(sim.ids[i], point)
        }

        /// Where the finger is, at the dragged note's depth, in the space's
        /// own coordinates.
        private func fingerPoint(_ point: CGPoint, in view: SCNView, sim: GraphSim) -> SIMD3<Float> {
            let screen = SCNVector3(x: Float(point.x), y: Float(point.y), z: dragDepth)
            let world: SCNVector3 = view.unprojectPoint(screen)
            let inScene = SIMD3<Float>(world.x, world.y, world.z)
            return sim.world.simdConvertPosition(inScene, from: nil)
        }

        /// One tap: on a body, tells SwiftUI (GraphSelection chooses it -
        /// its ring lights, its card comes up - or, when it is already
        /// chosen, opens it); on empty space, lets the chosen one go.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view, let sim else { return }
            wake()
            let point: CGPoint = gesture.location(in: view)
            guard let i = pick(at: point, radius: 28, in: view), i < sim.ids.count else {
                touch.select(nil)
                return
            }
            touch.select(sim.ids[i])
        }

        /// Two taps on a body: open it at once (a shortcut for tap, Open).
        @objc func opened(_ gesture: UITapGestureRecognizer) {
            guard let view, let sim else { return }
            wake()
            let point: CGPoint = gesture.location(in: view)
            guard let i = pick(at: point, radius: 28, in: view), i < sim.ids.count else { return }
            touch.double(sim.ids[i])
        }

        // MARK: the chosen body

        /// Makes the scene show what SwiftUI has chosen: the lit ring (and
        /// its name pill) on the chosen body, and Show links; `tick`: the
        /// light tick of a new choice.
        func syncChoice(tick: Bool = true) {
            guard let sim else { return }
            sim.setLabelSettings(labels)
            if shownChoice != chosenID {
                shownChoice = chosenID
                if let id = chosenID, let i = sim.index[id] {
                    sim.select(i)
                    if tick { light.impactOccurred() }
                } else {
                    sim.clearSelection()
                }
            }
            if !shownLinksSet || shownLinks != linksID {
                shownLinksSet = true
                shownLinks = linksID
                let slot: Int? = linksID.flatMap { sim.index[$0] }
                sim.focusLinks(on: slot)
            }
        }

        /// A request from the card.
        func run(_ kind: GraphMapCommand.Kind) {
            guard let sim else { return }
            switch kind {
            case .select(let id, let glide):
                guard let i = sim.index[id] else { return }
                ease(to: i, glide: glide)
            case .flyIn(let id):
                guard let i = sim.index[id] else { return }
                fly(to: i, animated: true)
            case .previewHold(let id):
                guard let i = sim.index[id], let point = screenPoint(i) else { return }
                touch.hold(id, point)
            case .none, .clear, .links:
                break
            }
        }

        /// The camera eases a little towards a chosen body - a third of the
        /// way to the middle of the part of the screen above the card, and
        /// a tenth closer - or, from a link chip (`glide`), all the way to
        /// that middle. Never with Reduce Motion (or while the space holds
        /// still): the body is chosen where it is, and a chip's body is
        /// brought to the middle at once.
        private func ease(to i: Int, glide: Bool) {
            guard let view, let camera, let sim else { return }
            let size: CGSize = view.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let still: Bool = !sim.lively || UIAccessibility.isReduceMotionEnabled
            if still && !glide { return }
            let local: SIMD3<Float> = sim.currentPosition(i)
            let world: SIMD3<Float> = sim.world.presentation.simdConvertPosition(local, to: nil)
            let at: SCNVector3 = view.projectPoint(SCNVector3(x: world.x, y: world.y, z: world.z))
            guard at.z > 0, at.z < 1 else { return }
            // the middle of what the card (about 40% of the height) leaves
            let goal = CGPoint(x: size.width / 2, y: size.height * 0.34)
            let share: CGFloat = glide ? 1 : 0.34
            let nx: CGFloat = CGFloat(at.x) + (goal.x - CGFloat(at.x)) * share
            let ny: CGFloat = CGFloat(at.y) + (goal.y - CGFloat(at.y)) * share
            let from: SCNVector3 = view.unprojectPoint(SCNVector3(x: at.x, y: at.y, z: at.z))
            let to: SCNVector3 = view.unprojectPoint(SCNVector3(x: Float(nx), y: Float(ny), z: at.z))
            let shift = SIMD3<Float>(from.x - to.x, from.y - to.y, from.z - to.z)
            let eye: SIMD3<Float> = camera.simdPosition + shift
            let toward: SIMD3<Float> = (world + shift) - eye
            let closer: SIMD3<Float> = glide ? SIMD3<Float>(0, 0, 0) : toward * 0.1
            let target: SCNVector3 = view.defaultCameraController.target
            let aim = SIMD3<Float>(target.x, target.y, target.z) + shift + closer
            view.defaultCameraController.target = SCNVector3(x: aim.x, y: aim.y, z: aim.z)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = still ? 0 : (glide ? 0.7 : 0.45)
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            camera.simdPosition = eye + closer
            SCNTransaction.commit()
            wake()
        }

        // MARK: VoiceOver

        /// Where body `i` is drawn on screen now; nil off screen.
        func screenPoint(_ i: Int) -> CGPoint? {
            guard let view, let sim else { return nil }
            let local: SIMD3<Float> = sim.currentPosition(i)
            let world: SIMD3<Float> = sim.world.presentation.simdConvertPosition(local, to: nil)
            let p: SCNVector3 = view.projectPoint(SCNVector3(x: world.x, y: world.y, z: world.z))
            guard p.z > 0, p.z < 1 else { return nil }
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }

        /// A body's frame for VoiceOver: 44 points round where it is drawn.
        func voiceFrame(_ i: Int) -> CGRect {
            guard let sim, sim.isVisible(i), let at = screenPoint(i) else { return .zero }
            return CGRect(x: at.x - 22, y: at.y - 22, width: 44, height: 44)
        }

        /// VoiceOver activated a body: choose it (its card comes up).
        func voiceSelect(_ i: Int) {
            guard let sim, i < sim.ids.count else { return }
            touch.voice(sim.ids[i], "select")
        }

        /// The map for VoiceOver: its summary (the map's name, the plan's
        /// counts, how to use it) and every body shown, each chosen by
        /// activating it, with Open, Show links (Fly in for a folder) and
        /// Delete as its actions; and rotors over the notes and the folders.
        private func buildVoice(_ built: GraphScene, in view: SCNView) {
            guard let sim else { return }
            let summary = GraphWholeElement(accessibilityContainer: view)
            summary.container = view
            summary.accessibilityIdentifier = "graph3D"
            summary.accessibilityLabel = built.theme.mapLabel
            summary.accessibilityValue = built.universe ? built.summary : ""
            summary.accessibilityHint = built.universe ? built.theme.hint : Graph3DView.graphHint
            var out: [UIAccessibilityElement] = [summary]
            for i in sim.ids.indices where sim.kind(of: i) != .fixture {
                let id: UUID = sim.ids[i]
                let folder: Bool = sim.kind(of: i) != .note
                let element = GraphBodyElement(accessibilityContainer: view)
                element.coordinator = self
                element.slot = i
                element.folder = folder
                element.accessibilityLabel = built.names[id] ?? "Untitled"
                let role: String = built.roles[id] ?? ""
                let word: String? = GraphPeek.roleWord(theme: built.theme.rawValue, role: role, folder: folder,
                                                       home: id == GraphUniverse.homeID)
                element.accessibilityValue = word ?? (folder ? "Folder" : "Note")
                element.accessibilityTraits = .button
                element.accessibilityHint = "Shows its card."
                var actions: [UIAccessibilityCustomAction] = []
                for name in GraphPeek.actions(folder: folder) {
                    let action = UIAccessibilityCustomAction(name: name) { [weak self] _ in
                        self?.touch.voice(id, name)
                        return true
                    }
                    actions.append(action)
                }
                element.accessibilityCustomActions = actions
                out.append(element)
            }
            voiceElements = out
            refreshVoice()
            view.accessibilityCustomRotors = [rotor("Notes", folders: false), rotor("Folders", folders: true)]
        }

        /// Only the bodies the filter shows.
        private func refreshVoice() {
            guard let view, let sim else { return }
            let shown: [UIAccessibilityElement] = voiceElements.filter { element in
                guard let body = element as? GraphBodyElement else { return true }
                return sim.isVisible(body.slot)
            }
            view.accessibilityElements = shown
        }

        /// A rotor stepping through the notes (or the folders) shown.
        private func rotor(_ name: String, folders wanted: Bool) -> UIAccessibilityCustomRotor {
            UIAccessibilityCustomRotor(name: name) { [weak self] predicate in
                guard let self, let sim = self.sim else { return nil }
                let all: [GraphBodyElement] = self.voiceElements.compactMap { $0 as? GraphBodyElement }
                let list: [GraphBodyElement] = all.filter { $0.folder == wanted && sim.isVisible($0.slot) }
                guard !list.isEmpty else { return nil }
                let current: GraphBodyElement? = predicate.currentItem.targetElement as? GraphBodyElement
                var at: Int = -1
                if let current, let found = list.firstIndex(where: { $0 === current }) { at = found }
                let forward: Bool = predicate.searchDirection == .next
                var next: Int = forward ? at + 1 : at - 1
                if at < 0 { next = forward ? 0 : list.count - 1 }
                guard next >= 0, next < list.count else { return nil }
                return UIAccessibilityCustomRotorItemResult(targetElement: list[next], targetRange: nil)
            }
        }

        /// The pointer over the space: the body under it shows its name.
        /// Looked for again only once the pointer has moved 2 points.
        @objc func hovered(_ gesture: UIHoverGestureRecognizer) {
            guard let view, let sim else { return }
            switch gesture.state {
            case .began, .changed:
                let point: CGPoint = gesture.location(in: view)
                if let last = lastHover {
                    let dx: CGFloat = point.x - last.x
                    let dy: CGFloat = point.y - last.y
                    let moved: CGFloat = dx * dx + dy * dy
                    if moved <= 4 { return }
                }
                lastHover = point
                wake()
                sim.hover(pick(at: point, radius: 16, in: view))
            default:
                lastHover = nil
                sim.hover(nil)
            }
        }

        /// A finger, Pencil or click down on the space (`point`), or lifted
        /// (nil): the body under it shows its name for as long as it is
        /// held. Taps, double taps and drags see the same touches as before.
        func pressed(at point: CGPoint?) {
            guard let sim else { return }
            wake()
            guard let point, let view else {
                sim.press(nil)
                return
            }
            sim.press(pick(at: point, radius: 28, in: view))
        }

        /// The body under `point`, by how it is drawn on screen:
        ///
        /// (a) among bodies whose drawn disc (plus 6 points) holds the
        ///     finger, the smallest - unless a nearer one's disc holds that
        ///     body's centre, so it is behind it: then the nearer one
        ///     (`pickHolding`);
        /// (b) else the nearest centre within `radius` (28 points for a
        ///     finger, 16 for the pointer); within 6 points of the best, a
        ///     note beats a folder, then the smaller;
        /// (c) else SceneKit's own hit test.
        private func pick(at point: CGPoint, radius: CGFloat = 28, in view: SCNView) -> Int? {
            let seen: [Seen] = project(at: point, in: view)
            if let held = Self.pickHolding(seen, least: 0) { return held }
            let close: [Seen] = seen.filter { $0.distance <= radius }
            if let nearest = close.min(by: { $0.distance < $1.distance }) {
                let ties: [Seen] = close.filter { $0.distance <= nearest.distance + 6 }
                let ranked: [Seen] = ties.sorted { a, b in
                    if a.folder != b.folder { return !a.folder }
                    return a.size < b.size
                }
                return ranked.first?.index ?? nearest.index
            }
            return noteIndex(at: point, in: view)
        }

        /// The body a drag starting at `point` picks up. In the Universe,
        /// rule (a) of `pick` - first by each body's drawn disc, then with
        /// every disc floored at 12 points, so a planet 4 points across at
        /// the whole-map framing can still be grabbed - and SceneKit's hit
        /// test only when neither finds one. Never rule (b): a drag on empty
        /// space still turns the camera.
        private func dragPick(at point: CGPoint, in view: SCNView) -> Int? {
            guard universe else { return noteIndex(at: point, in: view) }
            let seen: [Seen] = project(at: point, in: view)
            if let held = Self.pickHolding(seen, least: 0) { return held }
            if let near = Self.pickHolding(seen, least: 12) { return near }
            return noteIndex(at: point, in: view)
        }

        /// Rule (a): among bodies whose disc - drawn size, at least `least`
        /// points, plus 6 - holds the finger, the smallest; unless a nearer
        /// one's drawn disc holds that body's centre (it is in front of it):
        /// then the nearer one.
        private static func pickHolding(_ seen: [Seen], least: CGFloat) -> Int? {
            let holding: [Seen] = seen.filter { $0.distance <= max($0.size, least) + 6 }
            guard let smallest = holding.min(by: { $0.size < $1.size }) else { return nil }
            var best: Seen = smallest
            for other in holding where other.depth < best.depth && other.index != smallest.index {
                let dx: CGFloat = smallest.centre.x - other.centre.x
                let dy: CGFloat = smallest.centre.y - other.centre.y
                let apart: CGFloat = (dx * dx + dy * dy).squareRoot()
                if apart <= other.size { best = other }
            }
            return best.index
        }

        /// Every pickable body as it is drawn now: its centre and radius on
        /// screen, and its depth in front of the camera. The camera's and
        /// the space's matrices are read once, from their presentation
        /// nodes (so a pick follows the camera through a fly-in), and every
        /// body is projected in simd - no SceneKit call per body. The
        /// radius on screen is its pick radius over its depth, scaled by
        /// the projection's vertical focal length.
        private func project(at point: CGPoint, in view: SCNView) -> [Seen] {
            guard let sim, let pov = view.pointOfView, let lens = pov.camera else { return [] }
            let size: CGSize = view.bounds.size
            guard size.width > 1, size.height > 1 else { return [] }
            let eye: simd_float4x4 = pov.presentation.simdWorldTransform
            let lensMatrix: SCNMatrix4 = lens.projectionTransform(withViewportSize: size)
            let projection = simd_float4x4(lensMatrix)
            let toScene: simd_float4x4 = sim.world.presentation.simdWorldTransform
            let toView: simd_float4x4 = eye.inverse * toScene
            let halfWidth: Float = Float(size.width) / 2
            let halfHeight: Float = Float(size.height) / 2
            let focal: Float = projection.columns.1.y * halfHeight
            let near: Float = Float(lens.zNear)
            let far: Float = Float(lens.zFar)
            let fingerX: Float = Float(point.x)
            let fingerY: Float = Float(point.y)
            var seen: [Seen] = []
            for (i, local, reach, folder) in sim.pickables() {
                let inView: SIMD4<Float> = toView * SIMD4<Float>(local.x, local.y, local.z, 1)
                let depth: Float = -inView.z
                guard depth > near, depth < far else { continue }
                let clip: SIMD4<Float> = projection * inView
                guard abs(clip.w) > 0.000_001 else { continue }
                let x: Float = (clip.x / clip.w + 1) * halfWidth
                let y: Float = (1 - clip.y / clip.w) * halfHeight
                let radius: Float = reach * focal / depth
                let dx: Float = x - fingerX
                let dy: Float = y - fingerY
                let distance: Float = (dx * dx + dy * dy).squareRoot()
                let at = CGPoint(x: CGFloat(x), y: CGFloat(y))
                seen.append(Seen(index: i, centre: at, size: CGFloat(radius), depth: depth, folder: folder,
                                 distance: CGFloat(distance)))
            }
            return seen
        }

        /// Looks through everything under the finger for the nearest shown
        /// body, climbing from a label or a piece to the body it belongs to:
        /// a note, a folder or the home star.
        private func noteIndex(at point: CGPoint, in view: SCNView) -> Int? {
            guard let sim else { return nil }
            // only the spheres and titles (category 1): not the rings,
            // disks, links or sparks round them
            let options: [SCNHitTestOption: Any] = [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue,
                SCNHitTestOption.ignoreHiddenNodes: true,
                SCNHitTestOption.categoryBitMask: 1
            ]
            let hits = view.hitTest(point, options: options)
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let slot = Self.slot(of: current.name, in: sim), sim.isVisible(slot) {
                        return slot
                    }
                    node = current.parent
                }
            }
            return nil
        }

        /// The body a node's name stands for: "note:<id>", "folder:<id>" or
        /// "home".
        private static func slot(of name: String?, in sim: GraphSim) -> Int? {
            guard let name else { return nil }
            if name == "home" { return sim.index[GraphUniverse.homeID] }
            for prefix in ["note:", "folder:"] where name.hasPrefix(prefix) {
                let rest: String = String(name.dropFirst(prefix.count))
                guard let id = UUID(uuidString: rest) else { return nil }
                return sim.index[id]
            }
            return nil
        }
    }
}

/// An SCNView that says when its size changes, so the graph can be framed
/// once it has a size and again when the phone turns; and when one finger
/// goes down on it and lifts, so a pressed note can show its name while it
/// is held; and when a finger moves (the Universe's frame rate). The
/// touches still reach every gesture recogniser as before.
final class FramingSCNView: SCNView {
    var onResize: ((CGSize) -> Void)?
    /// Where a single finger went down, or nil when it lifts, is cancelled
    /// or a second finger joins it.
    var onPress: ((CGPoint?) -> Void)?
    var onMove: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let down: Int = event?.allTouches?.count ?? touches.count
        guard down == 1, let touch = touches.first else {
            onPress?(nil)
            return
        }
        onPress?(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        onMove?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onPress?(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        onPress?(nil)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGSize = bounds.size
        guard size != lastSize else { return }
        lastSize = size
        onResize?(size)
    }
}

/// One body for VoiceOver: its frame follows it on screen; activating it
/// chooses it.
final class GraphBodyElement: UIAccessibilityElement {
    weak var coordinator: GraphSCNView.Coordinator?
    var slot: Int = 0
    var folder: Bool = false

    override var accessibilityFrameInContainerSpace: CGRect {
        get { coordinator?.voiceFrame(slot) ?? .zero }
        set { _ = newValue }
    }

    override func accessibilityActivate() -> Bool {
        coordinator?.voiceSelect(slot)
        return true
    }
}

/// The whole map for VoiceOver (its name, the plan's summary, the hint):
/// the view's whole frame.
final class GraphWholeElement: UIAccessibilityElement {
    weak var container: UIView?

    override var accessibilityFrameInContainerSpace: CGRect {
        get { container?.bounds ?? .zero }
        set { _ = newValue }
    }
}
