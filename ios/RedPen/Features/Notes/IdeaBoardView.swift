import SwiftUI

/// The idea board: every note as a card on a flat canvas that goes on for
/// ever, joined by curved lines where two notes are connected.
///
/// It is the noding system for idea points - the place to lay thoughts out
/// next to each other and draw the lines between them by hand:
/// - drag the background to move around, pinch to zoom;
/// - drag a card to put it somewhere else (where it lands is kept);
/// - long-press a card, then tap another, to connect the two - or to part
///   them if they were already connected. "Connect" in the toolbar does the
///   same with plain taps, for joining up a lot at once;
/// - double-tap empty space to put a new idea exactly there.
///
/// Cards are tinted, faintly, by the folder they belong to.
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
        GeometryReader { geo in
            let size = geo.size
            let points = positions(in: size)
            let edges = notes.allEdges()
            let lineWidth = max(1, 1.5 * scale)
            ZStack {
                // the board itself: moved by dragging, added to by double-tap
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .onTapGesture(count: 2) { location in
                        ask(at: location, in: size)
                    }

                Canvas { context, _ in
                    for (a, b) in edges {
                        guard let p = points[a], let q = points[b] else { continue }
                        context.stroke(Self.curve(from: p, to: q),
                                       with: .color(Color.primary.opacity(0.28)),
                                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
                .allowsHitTesting(false)

                ForEach(notes.notes) { note in
                    card(note)
                        .scaleEffect(scale)
                        .position(points[note.id] ?? .zero)
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
                }
            }
            .coordinateSpace(.named(Self.space))
            .simultaneousGesture(pinchGesture)
            .clipped()
        }
        .overlay(alignment: .bottom) {
            if source != nil || connecting {
                hint
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { pan = .zero; zoom = 1 }
                } label: {
                    Image(systemName: "scope")
                }
                .accessibilityLabel("Back to the middle")
                Button {
                    connecting.toggle()
                    source = nil
                } label: {
                    Image(systemName: connecting ? "link.circle.fill" : "link")
                }
                .accessibilityLabel(connecting ? "Stop connecting" : "Connect")
            }
        }
        .sensoryFeedback(.selection, trigger: source)
        .sheet(item: $adding) { spot in
            NameSheet(title: "New idea", prompt: "The idea", initial: "", confirm: "Add") { text in
                _ = notes.create(title: text, kind: .idea, at: (x: spot.x, y: spot.y))
            }
        }
    }

    // MARK: cards

    private func card(_ note: Note) -> some View {
        let tone = NoteTone.color(for: note.folderId, in: notes)
        let chosen = source == note.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: note.kind.symbol)
                Text(notes.folder(note.folderId)?.name ?? note.kind.label)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text(note.title.isEmpty ? "Untitled" : note.title)
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
                shape.fill(tone.opacity(0.14))
            }
        }
        .overlay {
            shape.strokeBorder(chosen ? Color.accentColor : tone.opacity(0.4),
                               lineWidth: chosen ? 2 : 1)
        }
        .shadow(color: .black.opacity(dragged == note.id ? 0.18 : 0.07),
                radius: dragged == note.id ? 10 : 5, y: 2)
        .contentShape(shape)
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

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            Text(source == nil ? "Tap a card to start a connection."
                               : "Tap another card to connect them, or to part them.")
                .font(.footnote)
            if source != nil {
                Button("Cancel") { source = nil }
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
    }

    // MARK: where things are

    /// Every card's centre on screen.
    private func positions(in size: CGSize) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for note in notes.notes {
            var x = CGFloat(note.boardX)
            var y = CGFloat(note.boardY)
            if note.id == dragged {
                x += dragOffset.width / scale
                y += dragOffset.height / scale
            }
            let screenX: CGFloat = size.width / 2 + offset.width + x * scale
            let screenY: CGFloat = size.height / 2 + offset.height + y * scale
            result[note.id] = CGPoint(x: screenX, y: screenY)
        }
        return result
    }

    /// A double-tap on empty board: ask for the idea, to put it there.
    private func ask(at location: CGPoint, in size: CGSize) {
        let x = (location.x - size.width / 2 - offset.width) / scale
        let y = (location.y - size.height / 2 - offset.height) / scale
        adding = BoardSpot(x: Double(x), y: Double(y))
    }

    /// A gentle bow rather than a straight line, so two lines between nearby
    /// cards do not lie on top of each other.
    private static func curve(from p: CGPoint, to q: CGPoint) -> Path {
        var path = Path()
        path.move(to: p)
        let dx = q.x - p.x
        let dy = q.y - p.y
        let midX: CGFloat = (p.x + q.x) / 2
        let midY: CGFloat = (p.y + q.y) / 2
        let control = CGPoint(x: midX - dy * 0.18, y: midY + dx * 0.18)
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
