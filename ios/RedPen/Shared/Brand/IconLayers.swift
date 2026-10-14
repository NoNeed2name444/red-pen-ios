// The app icon in the app, in layers: design/icon/layers (the icon's light
// and dark pictures, cut by tools/icon_layers.py into the base and the
// stethoscope), copied into the app as the folder "layers". It follows the
// app's light or dark, as the home screen's icon follows the phone's.
#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// `IconLayersView()` is the whole icon; `layers:` picks some of them, so a
/// screen can move or light them apart. Without the PNGs (the Playgrounds
/// package has none) it draws nothing.
struct IconLayersView: View {
    var layers: [IconLayer] = IconLayer.allCases
    var body: some View {
        ZStack { ForEach(layers, id: \.self) { IconLayerView(layer: $0) } }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(IconTile())
    }
}

/// The rounded tile iOS cuts every icon to.
struct IconTile: Shape {
    func path(in r: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 0.2237 * min(r.width, r.height), style: .continuous).path(in: r)
    }
}

struct IconLayerView: View {
    let layer: IconLayer
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: layer.asset(dark: scheme == .dark), withExtension: nil,
                                         subdirectory: "layers"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
#endif
