import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// How the phone is held, and where its fold is: one flat screen, or two
/// halves either side of a hinge, in portrait or on either side.
///
/// Every layout decision reads the window (WindowSpan, and this), never the
/// kind of device. A phone that does not fold reads as `.folded` with no
/// band: one panel, as every iPhone was.
///
/// The band is where the hinge crosses the window, in window points. Nothing
/// that is read or touched sits in it; the page colour runs across it. On
/// 23 Oct 2026 no Xcode on GitHub's macOS images ships a foldable iPhone
/// simulator or a hinge API in its headers (T0138, item 0), so a real scene
/// reports no band; the screenshot launches (`-uiPreviewPosture`) draw one,
/// `previewThickness` wide, across the window's longer side.
struct DevicePosture: Equatable {
    enum Posture: String, CaseIterable {
        /// Closed, or a phone that does not fold: one panel.
        case folded
        /// Opened flat: the hinge crosses the window.
        case open
        /// Part open, as a tent or a book: one half to read, one to touch.
        case half
    }

    enum Orientation: String, CaseIterable {
        case portrait, landscapeLeft, landscapeRight

        var isLandscape: Bool { self != .portrait }

        /// A launch argument's word: "portrait", "landscapeLeft",
        /// "landscapeRight", or any other "land..." (the iPad job's
        /// "landscape") as landscapeRight, the side it always turned to.
        init?(word: String) {
            let w = word.lowercased()
            switch w {
            case "portrait": self = .portrait
            case "landscapeleft", "left": self = .landscapeLeft
            case "landscaperight", "right": self = .landscapeRight
            default:
                guard w.hasPrefix("land") else { return nil }
                self = .landscapeRight
            }
        }
    }

    var posture: Posture
    var orientation: Orientation
    /// Where the hinge crosses the window (window points); nil on one flat
    /// screen.
    var band: CGRect?

    static let flat = DevicePosture(posture: .folded, orientation: .portrait, band: nil)

    /// The width of the screenshot launches' stand-in band. A guess, flagged:
    /// no SDK on the CI images gives a hinge's width yet.
    static let previewThickness: CGFloat = 24

    /// The smallest pane worth having: one 44 pt target across.
    static let minPane: CGFloat = 44

    /// The screenshot launches' band: across the window's longer side, at its
    /// middle (a book fold splits the inner screen into two phone-shaped
    /// halves), so it stands upright in a wide window and lies flat in a tall
    /// one. None when folded.
    static func previewBand(window: CGSize, posture: Posture,
                            thickness: CGFloat = previewThickness) -> CGRect? {
        guard posture != .folded, window.width > 4 * thickness, window.height > 4 * thickness else { return nil }
        if window.width >= window.height {
            return CGRect(x: (window.width - thickness) / 2, y: 0, width: thickness, height: window.height)
        }
        return CGRect(x: 0, y: (window.height - thickness) / 2, width: window.width, height: thickness)
    }

    /// The posture for a window: a stand-in band when a screenshot launch
    /// names a posture, otherwise the scene's own (none, until the SDK has one).
    static func current(window: CGSize, orientation: Orientation, preview: Posture?) -> DevicePosture {
        guard let preview else { return DevicePosture(posture: .folded, orientation: orientation, band: nil) }
        return DevicePosture(posture: preview, orientation: orientation,
                             band: previewBand(window: window, posture: preview))
    }

    /// The two sides of the band within `container` (window points).
    struct Panes: Equatable {
        /// Leading or top: the stem, the card's face, the page.
        var reading: CGRect
        /// Trailing or bottom: the options, the rating row, the pen tray,
        /// the dock. Nil when the band leaves room on one side only.
        var controls: CGRect?
        /// Side by side (an upright band) or one over the other.
        var sideBySide: Bool
    }

    /// Whether the band stands upright (panes side by side).
    var upright: Bool { (band?.height ?? 0) >= (band?.width ?? 0) }

    /// The panes either side of the band within `container`, or nil when the
    /// band does not cross it (or there is none). A side narrower than one
    /// 44 pt target is not a pane.
    func panes(in container: CGRect) -> Panes? {
        guard posture != .folded, let band, container.width > 0, container.height > 0 else { return nil }
        let cut = container.intersection(band)
        guard !cut.isNull, cut.width > 0, cut.height > 0 else { return nil }
        var first: CGRect, second: CGRect
        if upright {
            first = CGRect(x: container.minX, y: container.minY,
                           width: max(0, band.minX - container.minX), height: container.height)
            second = CGRect(x: band.maxX, y: container.minY,
                            width: max(0, container.maxX - band.maxX), height: container.height)
        } else {
            first = CGRect(x: container.minX, y: container.minY,
                           width: container.width, height: max(0, band.minY - container.minY))
            second = CGRect(x: container.minX, y: band.maxY,
                            width: container.width, height: max(0, container.maxY - band.maxY))
        }
        let roomy: (CGRect) -> Bool = { min($0.width, $0.height) >= DevicePosture.minPane }
        switch (roomy(first), roomy(second)) {
        case (true, true): return Panes(reading: first, controls: second, sideBySide: upright)
        case (true, false): return Panes(reading: first, controls: nil, sideBySide: upright)
        case (false, true): return Panes(reading: second, controls: nil, sideBySide: upright)
        default: return nil
        }
    }

    /// The one pane a screen that does not split is kept to: the larger side
    /// (the reading side on a tie). Nil when the band misses `container`.
    func clearPane(in container: CGRect) -> CGRect? {
        guard let p = panes(in: container) else { return nil }
        guard let controls = p.controls else { return p.reading }
        let area: (CGRect) -> CGFloat = { $0.width * $0.height }
        return area(controls) > area(p.reading) ? controls : p.reading
    }

    /// Whether a target (window points) keeps clear of the band.
    func clear(_ target: CGRect) -> Bool {
        guard let band, posture != .folded else { return true }
        // touching the band's edge is clear; only an overlap is not
        let overlap = band.intersection(target)
        return overlap.isNull || overlap.width <= 0 || overlap.height <= 0
    }

    /// The posture and orientation a screenshot launch names
    /// (`-uiPreviewPosture folded|open|half`, `-uiPreviewOrientation
    /// portrait|landscapeLeft|landscapeRight`).
    static func preview(arguments: [String]) -> (posture: Posture?, orientation: Orientation?) {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        let posture: Posture? = value("-uiPreviewPosture").flatMap { word -> Posture? in
            let w = word.lowercased()
            if w.hasPrefix("half") || w == "tent" || w == "book" { return .half }
            return Posture(rawValue: w)
        }
        return (posture, value("-uiPreviewOrientation").flatMap { Orientation(word: $0) })
    }
}

#if canImport(SwiftUI)
private struct DevicePostureKey: EnvironmentKey {
    static let defaultValue = DevicePosture.flat
}

private struct PostureRootedKey: EnvironmentKey {
    static let defaultValue = false
}

/// A screen that splits itself across the band (StudyBarHost) says so, and
/// the screen round it then leaves it the whole window.
struct PostureClaimKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension EnvironmentValues {
    var devicePosture: DevicePosture {
        get { self[DevicePostureKey.self] }
        set { self[DevicePostureKey.self] = newValue }
    }

    fileprivate var postureRooted: Bool {
        get { self[PostureRootedKey.self] }
        set { self[PostureRootedKey.self] = newValue }
    }
}

#if canImport(UIKit)
/// The display the window is on, for the frame's corner: the large-screen
/// corner on a display whose shorter side is a tablet's, whatever the device.
enum WindowDisplay {
    @MainActor static var roundsLikePad: Bool {
        let screen: UIScreen? = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        guard let size = screen?.bounds.size else { return false }
        return WardPaper.roundsLikePad(displayWidth: Double(size.width), displayHeight: Double(size.height))
    }

    @MainActor static var orientation: DevicePosture.Orientation {
        let scene: UIWindowScene? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        switch scene?.interfaceOrientation {
        case .landscapeLeft?: return .landscapeLeft
        case .landscapeRight?: return .landscapeRight
        default: return .portrait
        }
    }
}

#endif

/// Measures the window once, at the outermost screen, and hands the posture
/// down; any inner one passes straight through.
struct DevicePostureRoot: ViewModifier {
    @Environment(\.postureRooted) private var rooted

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(UIKit)
        if rooted {
            content
        } else {
            content.modifier(DevicePostureMeasure())
        }
        #else
        content
        #endif
    }
}

#if canImport(UIKit)
private struct DevicePostureMeasure: ViewModifier {
    @State private var window: CGSize = .zero
    @State private var orientation: DevicePosture.Orientation = .portrait

    func body(content: Content) -> some View {
        content
            .environment(\.postureRooted, true)
            .environment(\.devicePosture,
                         DevicePosture.current(window: window, orientation: orientation,
                                               preview: PreviewLaunch.posture))
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        if size != window { window = size }
                        Task { @MainActor in
                            let now = WindowDisplay.orientation
                            if now != orientation { orientation = now }
                        }
                    }
            }
            .task {
                // after the first layout, so there is a scene to turn; the
                // screens PreviewRoot does not draw are turned here too
                await PreviewLaunch.applyOrientation()
                orientation = WindowDisplay.orientation
            }
    }
}
#endif

/// Keeps a screen to one side of the band, the page colour running across
/// it; nothing changes where there is no band.
struct ClearOfBand: ViewModifier {
    @Environment(\.devicePosture) private var posture

    @ViewBuilder
    func body(content: Content) -> some View {
        if posture.band == nil {
            content
        } else {
            content.modifier(ClearOfBandPane(posture: posture))
        }
    }
}

private struct ClearOfBandPane: ViewModifier {
    let posture: DevicePosture
    @Environment(\.layoutDirection) private var direction
    @State private var frame: CGRect = .zero
    @State private var claimed = false

    func body(content: Content) -> some View {
        let pane: CGRect? = claimed ? nil : posture.clearPane(in: frame)
        let left: CGFloat = pane.map { $0.minX - frame.minX } ?? 0
        let right: CGFloat = pane.map { frame.maxX - $0.maxX } ?? 0
        let insets = EdgeInsets(top: pane.map { $0.minY - frame.minY } ?? 0,
                                leading: direction == .rightToLeft ? right : left,
                                bottom: pane.map { frame.maxY - $0.maxY } ?? 0,
                                trailing: direction == .rightToLeft ? left : right)
        return content
            .onPreferenceChange(PostureClaimKey.self) { claimed = $0 }
            .padding(insets)
            .background {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { now in
                        if now != frame { frame = now }
                    }
            }
    }
}

extension View {
    /// The posture, measured once at the root (wardControls).
    func devicePostureRoot() -> some View { modifier(DevicePostureRoot()) }

    /// Kept to one side of the band (open or half-open), the page colour
    /// across it.
    func clearOfBand() -> some View { modifier(ClearOfBand()) }
}
#endif
