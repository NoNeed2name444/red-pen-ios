import Foundation
import CoreGraphics
import ImageIO
import Metal

/// The rocky planet's Earth (GraphStyleShaders.rockBody), from NASA's maps in
/// Resources/Earth (each file's source, licence and credit are in its
/// SOURCES.md; Settings credits them through ContentSources.nasaEarth), as
/// the two textures the shader samples:
///
/// - `day`, RGBA8 sRGB, so it samples in linear light: the day colour, with
///   the cloud cover in alpha (alpha is never sRGB-encoded);
/// - `aux`, RG8: the lights at night (sRGB-encoded; the shader squares them)
///   and the open water (the glint's mask).
///
/// The day map is 4096 x 2048 where the style shaders run at the High tier's
/// detail and 2048 x 1024 below it; `aux` is 2048 x 1024. Both carry full
/// mipmaps, sampled with the planet's own gradients, so the coasts stay sharp
/// at any size without shimmering.
///
/// Made off the main thread before a build (Graph3DView), with one GPU blit
/// into private storage, and kept in an NSCache: the system can take the
/// maps back under memory pressure, while a scene's materials keep the
/// textures they use. A failure is not kept: the next build tries again,
/// and the planet is drawn in its flat colour meanwhile (GraphStyleKit).
nonisolated final class GraphEarth: @unchecked Sendable {
    static let shared = GraphEarth()

    /// The day map's width at each size; `aux` is always the small one.
    static let largeWidth: Int = 4096
    static let smallWidth: Int = 2048

    private let kept = NSCache<NSNumber, GraphEarthMaps>()
    /// One making at a time. Never taken on the main thread: `ready` only
    /// reads the cache, which is safe from any thread.
    private let making = NSLock()

    private init() {}

    /// Whether the style shaders' detail (GraphStyleKit's `detail`) calls
    /// for the large day map: the High tier's, where they also draw the
    /// clouds' shadows.
    static func large(detail: Float) -> Bool { detail > 0.5 }

    /// `large(detail:)` for the detail the scene builders give the kit now:
    /// at full liveliness, the graphics tier's shader detail, else none.
    @MainActor static var largeNow: Bool {
        large(detail: SpaceQuality.current() == .full ? GraphQuality.current.shaderDetail : 0)
    }

    /// The maps if they are made, without making them (for the main
    /// thread): the size asked for, else the other one, else nil.
    func ready(large: Bool) -> GraphEarthMaps? {
        kept.object(forKey: NSNumber(value: large)) ?? kept.object(forKey: NSNumber(value: !large))
    }

    /// Makes the maps if they are not made: decoding and a GPU blit, a
    /// fraction of a second, so never on the main thread.
    @discardableResult
    func prefetch(large: Bool) -> GraphEarthMaps? {
        let key = NSNumber(value: large)
        if let made = kept.object(forKey: key) { return made }
        making.lock()
        defer { making.unlock() }
        if let made = kept.object(forKey: key) { return made }
        guard let device = MTLCreateSystemDefaultDevice(),
              let made = Self.make(width: large ? Self.largeWidth : Self.smallWidth, device: device)
        else { return nil }
        kept.setObject(made, forKey: key)
        return made
    }

    // MARK: making them

    private static func make(width: Int, device: MTLDevice) -> GraphEarthMaps? {
        let height: Int = width / 2
        let small: Int = smallWidth
        let smallHeight: Int = small / 2
        guard let dayImage = image("earth-day", "jpg", longest: width),
              let cloudImage = image("earth-clouds", "jpg", longest: width),
              let lightImage = image("earth-lights", "jpg", longest: small),
              let waterImage = image("earth-water", "png", longest: small),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let dayBuffer = device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let auxBuffer = device.makeBuffer(length: small * smallHeight * 2, options: .storageModeShared),
              let day = texture(.rgba8Unorm_srgb, width: width, device: device),
              let aux = texture(.rg8Unorm, width: small, device: device)
        else { return nil }

        // the day colour straight into the buffer the blit reads (its fourth
        // byte left for the clouds), then the cover into that byte
        let info: UInt32 = CGImageAlphaInfo.noneSkipLast.rawValue
        guard draw(dayImage, into: dayBuffer.contents(), width: width, height: height,
                   rowBytes: width * 4, space: srgb, info: info),
              let cover = grey(cloudImage, width: width, height: height),
              let lights = grey(lightImage, width: small, height: smallHeight),
              let water = grey(waterImage, width: small, height: smallHeight)
        else { return nil }
        let rgba = dayBuffer.contents().bindMemory(to: UInt8.self, capacity: width * height * 4)
        cover.withUnsafeBufferPointer { c in
            for k in 0..<(width * height) { rgba[4 * k + 3] = c[k] }
        }
        let rg = auxBuffer.contents().bindMemory(to: UInt8.self, capacity: small * smallHeight * 2)
        lights.withUnsafeBufferPointer { l in
            water.withUnsafeBufferPointer { w in
                for k in 0..<(small * smallHeight) {
                    rg[2 * k] = l[k]
                    rg[2 * k + 1] = w[k]
                }
            }
        }

        guard let queue = device.makeCommandQueue(),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder()
        else { return nil }
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        blit.copy(from: dayBuffer, sourceOffset: 0, sourceBytesPerRow: width * 4,
                  sourceBytesPerImage: width * height * 4,
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: day, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        blit.copy(from: auxBuffer, sourceOffset: 0, sourceBytesPerRow: small * 2,
                  sourceBytesPerImage: small * smallHeight * 2,
                  sourceSize: MTLSize(width: small, height: smallHeight, depth: 1),
                  to: aux, destinationSlice: 0, destinationLevel: 0, destinationOrigin: origin)
        blit.generateMipmaps(for: day)
        blit.generateMipmaps(for: aux)
        blit.endEncoding()
        commands.commit()
        // (in the background the GPU refuses the work: not kept, tried again)
        commands.waitUntilCompleted()
        guard commands.status == .completed else { return nil }
        return GraphEarthMaps(day: day, aux: aux)
    }

    /// A mipmapped texture twice as wide as high, for the GPU only.
    private static func texture(_ format: MTLPixelFormat, width: Int, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                  height: width / 2, mipmapped: true)
        // the blit makes the mipmaps by drawing them
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// One map, decoded now, at most `longest` pixels wide (ImageIO scales a
    /// larger one down as it decodes).
    private static func image(_ name: String, _ ext: String, longest: Int) -> CGImage? {
        guard let url = file(name, ext), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let wide: Int = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        if wide > 0 && wide <= longest {
            let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A grey map's values as they are: drawn in its own grey space, so
    /// nothing converts them.
    private static func grey(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height)
        let own: CGColorSpace? = image.colorSpace.flatMap { $0.model == .monochrome ? $0 : nil }
        let info: UInt32 = CGImageAlphaInfo.none.rawValue
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            for space in [own, CGColorSpaceCreateDeviceGray()].compactMap({ $0 }) {
                if draw(image, into: raw.baseAddress, width: width, height: height,
                        rowBytes: width, space: space, info: info) { return true }
            }
            return false
        }
        return drawn ? bytes : nil
    }

    /// Draws a map to fill `data` (rows from the top: north first, as the
    /// textures want them). False if the context could not be made.
    private static func draw(_ image: CGImage, into data: UnsafeMutableRawPointer?, width: Int, height: Int,
                             rowBytes: Int, space: CGColorSpace, info: UInt32) -> Bool {
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: rowBytes, space: space, bitmapInfo: info)
        else { return false }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    /// A map in the Earth folder, wherever the build put it: the app's own
    /// folder, the Swift package's resource bundle, or a resource bundle
    /// inside the app (Swift Playgrounds).
    private static func file(_ name: String, _ ext: String) -> URL? {
        var bundles: [Bundle] = [Bundle.main]
        #if SWIFT_PACKAGE
        bundles.append(Bundle.module)
        #endif
        let inside = (try? FileManager.default.contentsOfDirectory(
            at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)) ?? []
        bundles += inside.filter { $0.pathExtension == "bundle" }.compactMap(Bundle.init(url:))
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Earth") { return url }
        }
        return nil
    }
}

/// The Earth's two textures (GraphEarth): `day` (colour, clouds in alpha)
/// and `aux` (lights, water).
nonisolated final class GraphEarthMaps: @unchecked Sendable {
    let day: MTLTexture
    let aux: MTLTexture

    init(day: MTLTexture, aux: MTLTexture) {
        self.day = day
        self.aux = aux
    }
}
