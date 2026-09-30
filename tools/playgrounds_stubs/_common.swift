import SwiftUI

// Only in a Swift Playgrounds package made with `make_swiftpm.py --without ...`:
// the screen a left-out feature shows in its place. The full app never has it.

/// "This part is not in this build": what stands where a feature that this
/// package leaves out would open, so the rest of the app is unchanged.
struct NotInThisBuild: View {
    let feature: String

    var body: some View {
        ContentUnavailableView(
            "\(feature) is not in this build",
            systemImage: "shippingbox",
            description: Text("This copy of Stethoscore leaves it out so Swift Playgrounds can build the app on the iPad. The full app has it.")
        )
    }
}
