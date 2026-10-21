import UIKit
import XCTest

/// A picture of the whole screen, the right way up.
///
/// An iPad on its side gives `app.screenshot()` back turned a quarter and
/// cut short, and the screen's own picture keeps the upright tablet's pixels,
/// with the app drawn across them on its side. The picture may say which way
/// up it goes (its image's orientation, which the saved pixels ignore), so on
/// an iPad held on its side it is drawn the way it says; if that leaves it
/// standing, it is turned by the device's side. A tablet is told by its
/// screen, nearer square than a phone's, not by what the test runner calls
/// itself. An iPhone app stays upright while the phone is turned, so its
/// picture is left alone.
func uprightShot() -> XCTAttachment {
    let screen: XCUIScreenshot = XCUIScreen.main.screenshot()
    let image: UIImage = screen.image
    let side: UIDeviceOrientation = XCUIDevice.shared.orientation
    let across = CGFloat(image.cgImage?.width ?? 0)
    let down = CGFloat(image.cgImage?.height ?? 0)
    let tablet: Bool = min(across, down) > 0 && max(across, down) / min(across, down) < 1.6
    guard tablet, side.isLandscape else {
        return XCTAttachment(screenshot: screen)
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    // drawn as the picture says it goes
    var upright: UIImage = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    if upright.size.height > upright.size.width {
        let standing: UIImage = upright
        let size = CGSize(width: standing.size.height, height: standing.size.width)
        upright = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg: CGContext = context.cgContext
            if side == .landscapeRight {
                // the app's top is at the picture's left: a quarter turn right
                cg.translateBy(x: size.width, y: 0)
                cg.rotate(by: .pi / 2)
            } else {
                // the app's top is at the picture's right: a quarter turn left
                cg.translateBy(x: 0, y: size.height)
                cg.rotate(by: -.pi / 2)
            }
            standing.draw(in: CGRect(origin: .zero, size: standing.size))
        }
    }
    if upright.size.height > upright.size.width {
        // still standing: what the picture and the device said, to find out why
        let said = "side \(side.rawValue), image \(image.size) at \(image.scale)x, orientation "
            + "\(image.imageOrientation.rawValue), pixels \(across)x\(down), "
            + "idiom \(UIDevice.current.userInterfaceIdiom.rawValue), drawn \(upright.size)"
        XCTContext.runActivity(named: "upright-check") { activity in
            let note = XCTAttachment(string: said)
            note.name = "upright-check"
            note.lifetime = .keepAlways
            activity.add(note)
        }
    }
    return XCTAttachment(image: upright)
}
