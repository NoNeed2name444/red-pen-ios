import SwiftUI

// Only in a Swift Playgrounds package made with `make_swiftpm.py --without graph3d`:
// stands in for Features/Notes/Graph*.swift, the 3D Ideas map (SceneKit, some
// 20,000 lines), which the iPad's build cannot take. These are the names the
// rest of the app uses from it; GraphLineStyle.swift itself stays in the package.

/// The design-preview hook (GraphPreview.swift): never on in this build.
enum GraphPreview {
    static let isOn: Bool = false
}

/// The preview's root (RedPenApp shows it when GraphPreview.isOn, so never here).
struct GraphPreviewRoot: View {
    var body: some View { NotInThisBuild(feature: "The 3D map") }
}

/// The 3D map itself, opened from the Ideas screen's third mode.
struct Graph3DView: View {
    let open: (UUID) -> Void
    let openFolder: (UUID?) -> Void

    init(open: @escaping (UUID) -> Void, openFolder: @escaping (UUID?) -> Void = { _ in }) {
        self.open = open
        self.openFolder = openFolder
    }

    var body: some View { NotInThisBuild(feature: "The 3D map") }
}

/// The map's colours (GraphLook.swift), which the photon ring on the
/// Progress screen borrows (Shared/Space/PhotonRing.swift).
nonisolated enum GraphArt {
    static let orange = SIMD3<Float>(1.0, 0.416, 0.0)
    static let gold = SIMD3<Float>(1.0, 0.753, 0.302)
    static let ember = SIMD3<Float>(0.62, 0.08, 0.0)
    static let whiteHot = SIMD3<Float>(1.0, 0.95, 0.84)
    static let violet = SIMD3<Float>(0.42, 0.26, 1.0)
}
