import Foundation

/// The app icon's layers, back to front: the base and the stethoscope (with
/// its shadow), cut from the icon's light and dark pictures by
/// tools/icon_layers.py into design/icon/layers. Foundation only, so the
/// "iconlayers" suite can check the files on Linux.
enum IconLayer: String, CaseIterable {
    case background, stethoscope

    /// The PNG's name, numbered back to front; the dark picture's has "-dark".
    func asset(dark: Bool = false) -> String {
        "\(IconLayer.allCases.firstIndex(of: self)!)-\(rawValue)\(dark ? "-dark" : "").png"
    }

    /// Every PNG the layers folder holds: each layer, light then dark.
    static var assets: [String] { [false, true].flatMap { d in allCases.map { $0.asset(dark: d) } } }
}
