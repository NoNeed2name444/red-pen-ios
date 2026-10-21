import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The owner's logo on home (`HomeHeader.nameLine`): the word Stethoscore
/// drawn as a stethoscope, added to the root of the built app's bundle after
/// build and never kept in the public repository.
///
/// The lookup is Foundation-only so `BrandLogoTests` checks it on Linux;
/// loading a `UIImage` from the chosen file is fenced for UIKit.
enum BrandLogo {
    /// The day logo at the root of the built app's bundle.
    static let dayFile: String = "stethoscore-logo.png"
    /// The night logo at the root of the built app's bundle.
    static let nightFile: String = "stethoscore-logo-dark.png"

    /// The logo's pixel dimensions (`1449 x 447`, about 3.2:1).
    static let pixelWidth: Double = 1449
    static let pixelHeight: Double = 447
    static let aspect: Double = pixelWidth / pixelHeight

    /// The name box's height at the default Dynamic Type size, and its bounds
    /// across Dynamic Type (`@ScaledMetric(relativeTo: .largeTitle)`).
    static let defaultHeight: Double = 72
    static let minHeight: Double = 56
    static let maxHeight: Double = 112

    /// Clamps a scaled height to `56...112` points.
    static func clampedHeight(_ raw: Double) -> Double {
        min(max(raw, minHeight), maxHeight)
    }

    /// The name box's size for a scaled height `raw`, fitted down when
    /// `availableWidth` is narrower than the box at `clampedHeight(raw)`.
    static func boxSize(forHeight raw: Double, availableWidth: Double = .infinity) -> (width: Double, height: Double) {
        let h: Double = clampedHeight(raw)
        let w: Double = h * aspect
        guard availableWidth.isFinite, availableWidth < w else {
            return (width: w, height: h)
        }
        let fittedWidth: Double = max(0, availableWidth)
        return (width: fittedWidth, height: fittedWidth / aspect)
    }

    /// Picks the file name to show: at night (`dark == true`), the dark file
    /// if there is one, else the day file; in the day, the day file if there
    /// is one; with neither, `nil`.
    static func fileName(dark: Bool, hasDay: Bool, hasNight: Bool) -> String? {
        if dark && hasNight { return nightFile }
        if hasDay { return dayFile }
        return nil
    }

    /// Picks the logo file's URL in `directory` (the app bundle's root by
    /// default): at night, `stethoscore-logo-dark.png` if present, else
    /// `stethoscore-logo.png`; with neither, `nil`.
    static func url(dark: Bool, in directory: URL = Bundle.main.bundleURL,
                    fileManager: FileManager = .default) -> URL? {
        let dayURL: URL = directory.appendingPathComponent(dayFile, isDirectory: false)
        let nightURL: URL = directory.appendingPathComponent(nightFile, isDirectory: false)
        let hasDay: Bool = fileManager.fileExists(atPath: dayURL.path)
        let hasNight: Bool = fileManager.fileExists(atPath: nightURL.path)
        guard let chosen = fileName(dark: dark, hasDay: hasDay, hasNight: hasNight) else {
            return nil
        }
        return chosen == nightFile ? nightURL : dayURL
    }

    #if canImport(UIKit)
    /// Loads the bundle's logo image for the current appearance, or `nil`
    /// when the build has no logo files in the bundle.
    static func image(dark: Bool, in directory: URL = Bundle.main.bundleURL) -> UIImage? {
        guard let url = url(dark: dark, in: directory) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    #endif
}
