import UIKit
import XCTest

/// A picture of the whole screen, the right way up.
///
/// An iPad on its side gives `app.screenshot()` back turned a quarter and
/// cut short: the screen's own picture is still the upright tablet's, with
/// the app drawn across it on its side, and the app's frame (now wider than
/// tall) is cut out of that. So the screen's picture is taken whole and,
/// when the app is on its side but the picture is not, turned to match.
/// An iPhone app that stays upright while the phone is turned is left alone.
func uprightShot(_ app: XCUIApplication) -> XCTAttachment {
    let screen: XCUIScreenshot = XCUIScreen.main.screenshot()
    let image: UIImage = screen.image
    let wide: Bool = app.frame.width > app.frame.height
    guard wide, image.size.height > image.size.width else {
        return XCTAttachment(screenshot: screen)
    }
    let size = CGSize(width: image.size.height, height: image.size.width)
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    let turned: UIImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
        let cg: CGContext = context.cgContext
        if XCUIDevice.shared.orientation == .landscapeRight {
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
