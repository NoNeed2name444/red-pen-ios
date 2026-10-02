import Foundation

/// The app icon's layers, back to front - the order iOS 26 stacks them in and
/// the order tools/icon_layers.py draws them. Foundation only, so the
/// "iconlayers" suite can check design/icon/layers and AppIcon.icon on Linux.
enum IconLayer: String, CaseIterable {
    case background, metal, tubing, earpieces
    case chestPiece = "chest-piece"
    case aPlus = "a-plus"

    /// The SVG's name, numbered back to front as Apple asks.
    var asset: String { "\(IconLayer.allCases.firstIndex(of: self)!)-\(rawValue).svg" }

    /// Its Icon Composer group (iOS lights and moves a group as one piece);
    /// nil for the background, which is the icon's fill rather than artwork.
    var group: String? {
        switch self {
        case .background: return nil
        case .metal: return "Metal"
        case .tubing: return "Tubing"
        case .earpieces: return "Earpieces"
        case .chestPiece, .aPlus: return "Chest piece"
        }
    }
}
