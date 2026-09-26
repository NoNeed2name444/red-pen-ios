import SwiftUI

/// The idea board: every note as a card on a flat canvas that goes on for
/// ever, joined by lines where two notes are connected: gently bowed, or
/// straight, as "Lines" is set (the Look tool here, the 3D map's Look menu,
/// or Settings > Look and feel - GraphLineStyle).
///
/// It is the noding system for idea points - the place to lay thoughts out
/// next to each other and draw the lines between them by hand:
/// - drag the background to move around, pinch to zoom;
/// - drag a card to put it somewhere else (where it lands is kept);
/// - long-press a card, then tap another, to connect the two - or to part
///   them if they were already connected. "Connect", in the round tools at
///   the bottom corner, does the same with plain taps, for joining up a lot
///   at once;
/// - double-tap empty space to put a new idea exactly there.
///
/// Cards are tinted, faintly, by the folder they belong to. They lie flat on
/// the glass; the one being dragged, or starting a connection, rises off it
/// to the floating plane, over every other card.
///
/// The canvas runs on under the bottom glass, but its middle - where the
/// board's origin sits, and where "Back to the middle" returns to - is the
/// middle of the part that is not under glass.
struct IdeaBoardView: View {
    @EnvironmentObject private var notes: NoteStore
    let open: (UUID) -> Void

    /// How far the board has been moved, and the move in progress.
    @State private var pan: CGSize = .zero
    @GestureState private var panning: CGSize = .zero
    /// How far it is zoomed, and the pinch in progress.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinching: CGFloat = 1
    /// The card being dragged, and how far, in screen points.
    @State private var dragged: UUID?
    @State private var dragOffset: CGSize = .zero
    /// With Connect on, a tap picks a card instead of opening it.
    @State private var connecting = false
    /// The card a connection starts from, waiting for a second.
    @State private var source: UUID?
    @State private var adding: BoardSpot?
    /// "Lines": Curved (false, a gentle bow) or Straight (GraphLineStyle).
    @AppStorage(SpaceSettings.straightLinesKey) private var straightLines: Bool = false

    /// Where a new idea was asked for, in board points.
    struct BoardSpot: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    private static let cardWidth: CGFloat = 150
    private static let space = "idea-board"

    private var scale: CGFloat { min(max(zoom * pinching, 0.3), 2.5) }
    private var offset: CGSize {
        CGSize(width: pan.width + panning.width, height: pan.height + panning.height)
    }

    var body: some View {
        // The canvas runs on under the bottom glass (the capture row and the
        // Library's dock); the tools and the hint stay in the safe area.
        ZStack {
            canvas
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            if source != nil || connecting {
                hint
            }
        }
        .ideaTools {
            IdeaToolButton(symbol: "scope", label: "Back to the middle") {
                withAnimation(.snappy) { pan = .zero; zoom = 1 }
            }
            IdeaToolButton(symbol: connectSymbol, label: connectLabel, active: connecting) {
                connecting.toggle()
                source = nil
            }
            IdeaBoardLookTool()
        }
        .sensoryFeedback(.selection, trigger: source)
        .sheet(item: $adding) { spot in
            NameSheet(title: "New idea", prompt: "The idea", initial: "", confirm: "Add") { text in
                _ = notes.create(title: text, kind: .idea, at: (x: spot.x, y: spot.y))
            }
        }
    }

    private var connectSymbol: String { connecting ? "link.circle.fill" : "link" }
    private var connectLabel: String { connecting ? "Stop connecting" : "Connect" }

    private var canvas: some View {
        GeometryReader { geo in
            let size = geo.size
            // the reader runs on under the bottom glass; this much is hidden
            let hidden: CGFloat = geo.safeAreaInsets.bottom
            let midY: CGFloat = Self.middle(of: size, hidden: hidden)
            let points = positions(in: size, midY: midY)
            let edges = notes.allEdges()
            let lineWidth: CGFloat = max(1, 1.5 * scale)
            let style: GraphLineStyle = GraphLineStyle.inForce(straightLines)
            let lanes: [(lane: Int, lanes: Int)] = Self.lanes(edges)
            ZStack {
                // the board itself: moved by dragging, added to by double-tap
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(count: 2) { location in
                        ask(at: location, in: size, midY: midY)
                    }

                Canvas { context, _ in
                    let ink: Color = Color.primary.opacity(0.28)
                    let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    for (k, edge) in edges.enumerated() {
                        guard let p = points[edge.0], let q = points[edge.1] else { continue }
                        let line: Path = Self.line(style, from: p, to: q, lane: lanes[k].lane, lanes: lanes[k].lanes)
                        context.stroke(line, with: .color(ink), style: stroke)
                    }
                }
                .allowsHitTesting(false)

                ForEach(notes.notes) { note in
                    // a lifted card is drawn over the flat ones it passes
                    let lifted: Bool = dragged == note.id || source == note.id
                    let layer: Double = lifted ? 1 : 0
                    card(note)
                        .scaleEffect(scale)
                        .position(points[note.id] ?? .zero)
                        .zIndex(layer)
                }

                if notes.notes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.title2)
                        Text("Double-tap anywhere to put an idea there.")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                    .position(x: size.width / 2, y: midY)
                }
            }
            .coordinateSpace(.named(Self.space))
            .simultaneousGesture(pinchGesture)
            .clipped()
        }
    }

    // MARK: cards

    private func card(_ note: Note) -> some View {
        let tone = NoteTone.color(for: note.folderId, in: notes)
        let chosen: Bool = source == note.id
        // a card being dragged or starting a connection rises off the board
        let lifted: Bool = dragged == note.id || chosen
        let plane: PopOutPlane = lifted ? .floating : .screen
        let grow: CGFloat = lifted ? 1.04 : 1
        let ring: Color = chosen ? Color.accentColor : tone.opacity(0.4)
        let ringWidth: CGFloat = chosen ? 2 : 1
        let wash: Color = tone.opacity(0.14)
        let place: String = notes.folder(note.folderId)?.name ?? note.kind.label
        let title: String = note.title.isEmpty ? "Untitled" : note.title
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: note.kind.symbol)
                Text(place)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(width: Self.cardWidth, alignment: .leading)
        .background {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(wash)
            }
        }
        .overlay {
            shape.strokeBorder(ring, lineWidth: ringWidth)
        }
        .scaleEffect(grow)
        .popOut(plane, in: shape)
        .animation(.snappy(duration: 0.2), value: lifted)
        .contentShape(shape)
        .contentShape(.hoverEffect, shape)
        .hoverEffect(.lift)
        .onTapGesture { tapped(note.id) }
        .onLongPressGesture(minimumDuration: 0.4) { source = note.id }
        .gesture(cardDrag(note))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Connect from here") { source = note.id }
    }

    /// A tap opens the card - unless a connection is being made, when it is
    /// the first or second end of one.
    private func tapped(_ id: UUID) {
        if let from = source {
            if from != id {
                if notes.isLinked(from, id) { notes.unlink(from, id) } else { notes.link(from, id) }
            }
            source = nil
        } else if connecting {
            source = id
        } else {
            open(id)
        }
    }

    /// Up at the top while connecting, out of the way of the cards and the
    /// thumb.
    private var hint: some View {
        let words: String = source == nil ? "Tap a card to start a connection."
                                          : "Tap another card to connect them, or to part them."
        return HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .accessibilityHidden(true)
            Text(words)
                .font(.footnote)
            if source != nil {
                Button("Cancel") { source = nil }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .popOut(.raised, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: where things are

    /// The height of the board's middle: the middle of the part of the
    /// canvas not under the bottom glass.
    private static func middle(of size: CGSize, hidden: CGFloat) -> CGFloat {
        let seen: CGFloat = max(size.height - hidden, 0)
        return seen / 2
    }

    /// Every card's centre on screen; the board's origin is at the middle
    /// across, and `midY` down.
    private func positions(in size: CGSize, midY: CGFloat) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for note in notes.notes {
            var x = CGFloat(note.boardX)
            var y = CGFloat(note.boardY)
            if note.id == dragged {
                x += dragOffset.width / scale
                y += dragOffset.height / scale
            }
            let screenX: CGFloat = size.width / 2 + offset.width + x * scale
            let screenY: CGFloat = midY + offset.height + y * scale
            result[note.id] = CGPoint(x: screenX, y: screenY)
        }
        return result
    }

    /// A double-tap on empty board: ask for the idea, to put it there.
    private func ask(at location: CGPoint, in size: CGSize, midY: CGFloat) {
        let x = (location.x - size.width / 2 - offset.width) / scale
        let y = (location.y - midY - offset.height) / scale
        adding = BoardSpot(x: Double(x), y: Double(y))
    }

    /// Each link's lane among those joining the same two cards.
    private static func lanes(_ edges: [(UUID, UUID)]) -> [(lane: Int, lanes: Int)] {
        let keys: [String] = edges.map { edge in edge.0.uuidString + edge.1.uuidString }
        return IdeaLinkShape.lanes(for: keys)
    }

    /// One connector, as "Lines" is set (IdeaLinkShape): Curved, a gentle
    /// bow - always to the same side of the pair's first card to its second
    /// (allEdges orders each pair), so lines between nearby cards run side
    /// by side instead of on top of each other, and several between one
    /// pair fan out; Straight, card centre to card centre.
    private static func line(_ style: GraphLineStyle, from p: CGPoint, to q: CGPoint,
                             lane: Int, lanes: Int) -> Path {
        var path = Path()
        if style.isStraight {
            let ends: (CGPoint, CGPoint) = IdeaLinkShape.straightEnds(from: p, to: q, lane: lane, lanes: lanes)
            path.move(to: ends.0)
            path.addLine(to: ends.1)
            return path
        }
        let control: CGPoint = IdeaLinkShape.control(from: p, to: q, lane: lane, lanes: lanes)
        path.move(to: p)
        path.addQuadCurve(to: q, control: control)
        return path
    }

    // MARK: gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($panning) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                pan.width += value.translation.width
                pan.height += value.translation.height
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinching) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                zoom = min(max(zoom * value.magnification, 0.3), 2.5)
            }
    }

    /// Moves a card; where it is let go is saved. The distance is measured in
    /// the board's own space, so it is right at any zoom.
    private func cardDrag(_ note: Note) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                dragged = note.id
                dragOffset = value.translation
            }
            .onEnded { value in
                notes.setPosition(note.id,
                                  x: note.boardX + Double(value.translation.width / scale),
                                  y: note.boardY + Double(value.translation.height / scale))
                dragged = nil
                dragOffset = .zero
            }
    }
}
