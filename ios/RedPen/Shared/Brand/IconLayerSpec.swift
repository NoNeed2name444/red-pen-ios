import Foundation

/// The app icon's layers, back to front - the order iOS 26 stacks them in and
/// the order tools/icon_layers.py cuts them from the render. Foundation only,
/// so the "iconlayers" suite can check design/icon/layers and AppIcon.icon on Linux.
enum IconLayer: String, CaseIterable {
    case background, metal, tubing, earpieces
    case chestPiece = "chest-piece"
    case aPlus = "a-plus"

    /// The PNG's name, numbered back to front as Apple asks.
    var asset: String { "\(IconLayer.allCases.firstIndex(of: self)!)-\(rawValue).png" }

    /// Its Icon Composer group (iOS lights and moves a group as one piece; at
    /// most four). The tube sleeves over the metal, so they move together.
    var group: String {
        switch self {
        case .background: return "Background"
        case .metal, .tubing: return "Tubing"
        case .earpieces: return "Earpieces"
        case .chestPiece, .aPlus: return "Chest piece"
        }
    }
}
