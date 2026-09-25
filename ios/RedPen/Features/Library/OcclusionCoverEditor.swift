import SwiftUI
import UIKit

/// The picture with its covers, to adjust with a finger or the Pencil.
///
/// - Tap a cover to choose it; drag it to move it.
/// - Drag a chosen cover's corner to stretch it.
/// - Drag across an empty part of the picture to draw a new cover.
/// - Tap an empty part to choose nothing.
///
/// Covers are drawn see-through while they are edited, so the label under
/// each can be checked; the review screen draws them solid. Nothing moves on
/// its own: the only motion is the student's own drag.
struct OcclusionCoverEditor: View {
    let image: UIImage?
    /// Width over height of the picture.
    let aspect: Double
    @Binding var covers: [PhotoOcclusion.Cover]
    @Binding var selected: UUID?
    var tint: Color = StudySetKind.anki.tint

    /// What the drag under way is doing, decided where it started.
    private enum Edit {
        case move(UUID, OcclusionBox)
        case stretch(UUID, PhotoOcclusion.Handle, OcclusionBox)
        case draw(Double, Double)
    }

    @State private var edit: Edit?
    @State private var drawing: OcclusionBox?

    /// A fingertip, in points: how near a corner counts as on it.
    private static let reach: CGFloat = 24
    private static let handleSize: CGFloat = 16

    var body: some View {
        let ratio: CGFloat = CGFloat(aspect > 0 ? aspect : 1)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        picture
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    canvas(geo.size)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Picture with \(covers.count) covers")
            .accessibilityHint("Drag across the picture to draw a cover. Each cover's answer can also be edited in the list below.")
    }

    @ViewBuilder
    private var picture: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
        } else {
            Rectangle().fill(Color.white)
        }
    }

    private func canvas(_ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
            ForEach(covers) { cover in
                coverView(cover, size: size)
            }
            if let drawing {
                band(drawing, size: size)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .gesture(dragGesture(size))
    }

    // MARK: drawing

    private func coverView(_ cover: PhotoOcclusion.Cover, size: CGSize) -> some View {
        let rect: CGRect = cover.box.rect(in: size)
        let chosen: Bool = cover.id == selected
        let answered: Bool = !PhotoOcclusion.tidied(cover.answer).isEmpty
        let fill: Color = chosen ? tint.opacity(0.35) : Color.orange.opacity(answered ? 0.35 : 0.15)
        let edge: Color = chosen ? tint : Color.orange
        let dash: [CGFloat] = answered ? [] : [5, 4]
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(fill)
                .overlay(Rectangle().strokeBorder(edge, style: StrokeStyle(lineWidth: chosen ? 2.5 : 1.5, dash: dash)))
                .frame(width: rect.width, height: rect.height)
            if chosen {
                handles(rect.size)
            }
        }
        .offset(x: rect.minX, y: rect.minY)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(answered ? cover.answer : "Cover with no answer")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func handles(_ size: CGSize) -> some View {
        let s: CGFloat = Self.handleSize
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
                    .frame(width: s, height: s)
                    .offset(x: points[index].x - s / 2, y: points[index].y - s / 2)
            }
        }
    }

    private func band(_ box: OcclusionBox, size: CGSize) -> some View {
        let rect: CGRect = box.rect(in: size)
        return Rectangle()
            .fill(tint.opacity(0.2))
            .overlay(Rectangle().strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    // MARK: the one gesture

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in changed(value, size: size) }
            .onEnded { value in ended(value, size: size) }
    }

    private func fraction(_ point: CGPoint, _ size: CGSize) -> (x: Double, y: Double) {
        let w: CGFloat = max(size.width, 1)
        let h: CGFloat = max(size.height, 1)
        return (Double(point.x / w), Double(point.y / h))
    }

    private func begin(at start: CGPoint, size: CGSize) -> Edit {
        let at = fraction(start, size)
        let tx: Double = Double(Self.reach / max(size.width, 1))
        let ty: Double = Double(Self.reach / max(size.height, 1))
        // the chosen cover's corners first: they sit on its edge, where a
        // neighbouring cover may also be
        if let id = selected, let cover = covers.first(where: { $0.id == id }),
           let corner = PhotoOcclusion.handle(atX: at.x, y: at.y, of: cover.box,
                                              toleranceX: tx, toleranceY: ty) {
            return .stretch(id, corner, cover.box)
        }
        let slack: Double = Double(6 / max(size.width, 1))
        if let index = PhotoOcclusion.hit(x: at.x, y: at.y, in: covers, slack: slack) {
            let cover = covers[index]
            selected = cover.id
            return .move(cover.id, cover.box)
        }
        return .draw(at.x, at.y)
    }

    private func changed(_ value: DragGesture.Value, size: CGSize) {
        let current: Edit = edit ?? begin(at: value.startLocation, size: size)
        edit = current
        let dx: Double = Double(value.translation.width / max(size.width, 1))
        let dy: Double = Double(value.translation.height / max(size.height, 1))
        switch current {
        case .move(let id, let from):
            set(id, PhotoOcclusion.moved(from, dx: dx, dy: dy))
        case .stretch(let id, let corner, let from):
            set(id, PhotoOcclusion.resized(from, handle: corner, dx: dx, dy: dy))
        case .draw(let x, let y):
            let end = fraction(value.location, size)
            drawing = PhotoOcclusion.drawn(fromX: x, y: y, toX: end.x, y: end.y)
        }
    }

    private func ended(_ value: DragGesture.Value, size: CGSize) {
        let finished: Edit? = edit
        edit = nil
        guard case .draw = finished else { return }
        if let box = drawing {
            let made = PhotoOcclusion.Cover(box: box, answer: "")
            covers.append(made)
            selected = made.id
        } else {
            // a tap on the picture itself
            selected = nil
        }
        drawing = nil
    }

    private func set(_ id: UUID, _ box: OcclusionBox) {
        guard let index = covers.firstIndex(where: { $0.id == id }) else { return }
        covers[index].box = box
    }
}
