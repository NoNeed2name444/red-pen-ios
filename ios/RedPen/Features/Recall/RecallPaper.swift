import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where draw from memory's paper stands and how Compare lays the original on
/// it, with no view in it, so it is tested off the device (the recallpaper
/// suite). DrawRecallView draws what this decides.
enum RecallPaper {
    /// How far the paper's foot must rise to stand just above a tool picker
    /// docked along the bottom: the room's foot less the picker's top, and
    /// `space`. Both frames are in window points; nothing while the picker
    /// floats, hides or is clear of the room.
    static func trayGap(room: CGRect, picker: CGRect, space: CGFloat) -> CGFloat {
        guard !picker.isNull, !picker.isEmpty, room.width > 0, room.height > 0 else { return 0 }
        guard picker.intersects(room) else { return 0 }
        return max(0, room.maxY - picker.minY + space)
    }

    /// The paper's fixed size, or nil while it fills its room. While
    /// comparing it keeps the size it was drawn at: the compare panel floats
    /// over the foot and the tool picker's going does not move it, so
    /// turning Compare on or off never resizes the paper and the comparison
    /// stands on exactly the space that was drawn on.
    static func size(comparing: Bool, drawnOn: CGSize?) -> CGSize? {
        guard comparing, let drawnOn, drawnOn.width.isFinite, drawnOn.height.isFinite,
              drawnOn.width > 0, drawnOn.height > 0 else { return nil }
        return drawnOn
    }

    /// How the original is laid over the drawing. A figure is a picture on
    /// white: in light mode it is multiplied, so its white is the page's own
    /// colour; in dark mode it is inverted with its hues turned back and
    /// screened, so its white goes dark like the page and there is no white
    /// block on the dark paper. No colour of its own either way.
    enum Original: Equatable {
        case multiply
        case invertedScreen
    }

    static func original(dark: Bool) -> Original { dark ? .invertedScreen : .multiply }
}
