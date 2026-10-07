import UIKit
import XCTest

/// A picture of the whole screen, the right way up.
///
/// An iPad on its side gives `app.screenshot()` back turned a quarter and
/// cut short, and the screen's own picture is still the upright tablet's,
/// with the app drawn across it on its side. Neither the app's frame nor the
/// picture says the app has turned (both stay upright), so the device's turn
/// does: on an iPad held on its side the picture is turned to match. An
/// iPhone app stays upright while the phone is turned, so its picture is
/// left alone.
func uprightShot() -> XCTAttachment {
    let screen: XCUIScreenshot = XCUIScreen.main.screenshot()
    let image: UIImage = screen.image
    let side: UIDeviceOrientation = XCUIDevice.shared.orientation
    let onItsSide: Bool = UIDevice.current.userInterfaceIdiom == .pad && side.isLandscape
    guard onItsSide, image.size.height > image.size.width else {
        return XCTAttachment(screenshot: screen)
    }
    let size = CGSize(width: image.size.height, height: image.size.width)
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    let turned: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
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
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    return XCTAttachment(image: turned)
}
