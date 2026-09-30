import CoreGraphics
import Foundation
import ImageIO
import Metal
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The nebula, baked once
//
// The backdrop's gas and dust are made ONCE, off the main thread, and kept
// in Caches; every later launch just loads two PNGs. Nothing about them is
// worked out per frame: the backdrop only slides and fades the two pictures.
//
//   gas   domain-warped fBm (q = fbm(p), r = fbm(p + 4q), f = fbm(p + 4r),
//         after Inigo Quilez) coloured in the sky's blue, violet and teal
//         with H-alpha rose in the densest knots; black where there is none,
//         so it is laid on with a screen blend
//   dust  ridged noise following the same warp: white, with dark lanes where
//         the gas is, laid on with a multiply blend
//
// Fast path: one Metal compute kernel, compiled from source at run time
// (MTLDevice.makeLibrary(source:)) - Swift Playgrounds cannot compile .metal
// files. If Metal is missing, the kernel fails to compile, or it draws
// nothing, the same maths runs on the CPU at a smaller size (the nebula is
// soft; upscaling it shows nothing).

/// The two baked layers.
struct NebulaLayers: @unchecked Sendable {
    let gas: CGImage
    let dust: CGImage
}

nonisolated enum NebulaBaker {
    static let gpuSize = (width: 600, height: 1000)
    static let cpuSize = (width: 240, height: 400)

    /// From the cache, or baked now (slow: call off the main thread).
    static func loadOrBake() -> NebulaLayers? {
        if let cached = loadCached() { return cached }
        let baked: NebulaLayers? = bakeOnGPU() ?? bakeOnCPU()
        if let baked { save(baked) }
        return baked
    }

    // MARK: Cache

    private static func folder() -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir: URL = caches.appendingPathComponent("SkyBake", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ layer: String) -> URL? {
        let name: String = "nebula-v\(SkyChart.version)-\(layer).png"
        return folder()?.appendingPathComponent(name)
    }

    private static func loadCached() -> NebulaLayers? {
        guard let gasURL = url("gas"), let dustURL = url("dust") else { return nil }
        guard let gas = readPNG(gasURL), let dust = readPNG(dustURL) else { return nil }
        return NebulaLayers(gas: gas, dust: dust)
    }

    private static func readPNG(_ url: URL) -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func save(_ layers: NebulaLayers) {
        if let gasURL = url("gas") { writePNG(layers.gas, to: gasURL) }
        if let dustURL = url("dust") { writePNG(layers.dust, to: dustURL) }
    }

    private static func writePNG(_ image: CGImage, to url: URL) {
        let type: CFString = UTType.png.identifier as CFString
        guard let target = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return }
        CGImageDestinationAddImage(target, image, nil)
        _ = CGImageDestinationFinalize(target)
    }

    // MARK: GPU

    private static func bakeOnGPU() -> NebulaLayers? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        guard let library = try? device.makeLibrary(source: NebulaKernel.source, options: nil) else { return nil }
        guard let function = library.makeFunction(name: "rpNebula") else { return nil }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }
        let width: Int = gpuSize.width
        let height: Int = gpuSize.height
        guard let gasTexture = makeTexture(device, width, height) else { return nil }
        guard let dustTexture = makeTexture(device, width, height) else { return nil }
        guard let buffer = queue.makeCommandBuffer() else { return nil }
        guard let encoder = buffer.makeComputeCommandEncoder() else { return nil }
        var info = SIMD4<Float>(Float(width), Float(height), 0, 0)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(gasTexture, index: 0)
        encoder.setTexture(dustTexture, index: 1)
        encoder.setBytes(&info, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        let side: Int = 16
        let across: Int = (width + side - 1) / side
        let down: Int = (height + side - 1) / side
        let groups = MTLSize(width: across, height: down, depth: 1)
        let perGroup = MTLSize(width: side, height: side, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: perGroup)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        guard buffer.status == .completed else { return nil }
        guard let gas = readBack(gasTexture), let dust = readBack(dustTexture) else { return nil }
        // a kernel that compiled but drew nothing (all black gas) is a failure
        guard hasLight(gasTexture) else { return nil }
        return NebulaLayers(gas: gas, dust: dust)
    }

    private static func makeTexture(_ device: MTLDevice, _ width: Int, _ height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private static func bytes(of texture: MTLTexture) -> [UInt8] {
        let width: Int = texture.width
        let height: Int = texture.height
        let rowBytes: Int = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        let region = MTLRegionMake2D(0, 0, width, height)
        pixels.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                texture.getBytes(base, bytesPerRow: rowBytes, from: region, mipmapLevel: 0)
            }
        }
        return pixels
    }

    private static func readBack(_ texture: MTLTexture) -> CGImage? {
        let pixels: [UInt8] = bytes(of: texture)
        return image(pixels, width: texture.width, height: texture.height)
    }

    private static func hasLight(_ texture: MTLTexture) -> Bool {
        let pixels: [UInt8] = bytes(of: texture)
        var total: Int = 0
        var index: Int = 0
        while index < pixels.count {
            total += Int(pixels[index]) + Int(pixels[index + 2])
            index += 4 * 97
        }
        return total > 0
    }

    // MARK: CPU

    private static func bakeOnCPU() -> NebulaLayers? {
        let width: Int = cpuSize.width
        let height: Int = cpuSize.height
        let count: Int = width * height * 4
        var gas = [UInt8](repeating: 255, count: count)
        var dust = [UInt8](repeating: 255, count: count)
        gas.withUnsafeMutableBufferPointer { gasOut in
            dust.withUnsafeMutableBufferPointer { dustOut in
                let gasBase = gasOut
                let dustBase = dustOut
                DispatchQueue.concurrentPerform(iterations: height) { y in
                    for x in 0..<width {
                        let shade: NebulaShade = NebulaMath.shade(x: x, y: y, width: width, height: height)
                        let at: Int = (y * width + x) * 4
                        gasBase[at] = byte(shade.gas.x)
                        gasBase[at + 1] = byte(shade.gas.y)
                        gasBase[at + 2] = byte(shade.gas.z)
                        let d: UInt8 = byte(shade.dust)
                        dustBase[at] = d
                        dustBase[at + 1] = d
                        dustBase[at + 2] = d
                    }
                }
            }
        }
        guard let gasImage = image(gas, width: width, height: height) else { return nil }
        guard let dustImage = image(dust, width: width, height: height) else { return nil }
        return NebulaLayers(gas: gasImage, dust: dustImage)
    }

    private static func byte(_ v: Float) -> UInt8 {
        let clamped: Float = min(1, max(0, v))
        return UInt8(clamped * 255 + 0.5)
    }

    /// Opaque RGBX pixels to a CGImage.
    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - The maths, twice
//
// The Swift below and the Metal kernel are the same functions line for line,
// so the CPU fallback looks like the GPU bake, only softer.

struct NebulaShade {
    var gas: SIMD3<Float>
    var dust: Float
}

nonisolated enum NebulaMath {
    static let indigo = SIMD3<Float>(0.20, 0.30, 0.78)
    static let violet = SIMD3<Float>(0.46, 0.24, 0.80)
    static let teal = SIMD3<Float>(0.10, 0.52, 0.62)
    static let rose = SIMD3<Float>(0.95, 0.30, 0.48)
    static let core = SIMD3<Float>(0.95, 0.90, 1.0)

    static func fract(_ v: Float) -> Float { v - v.rounded(.down) }

    static func clamp01(_ v: Float) -> Float { min(1, max(0, v)) }

    static func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t: Float = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }

    static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }

    static func hash(_ px: Float, _ py: Float) -> Float {
        var x: Float = fract(px * 123.34)
        var y: Float = fract(py * 456.21)
        let d: Float = x * (x + 45.32) + y * (y + 45.32)
        x += d
        y += d
        return fract(x * y)
    }

    static func noise(_ px: Float, _ py: Float) -> Float {
        let ix: Float = px.rounded(.down)
        let iy: Float = py.rounded(.down)
        let fx: Float = px - ix
        let fy: Float = py - iy
        let ux: Float = fx * fx * (3 - 2 * fx)
        let uy: Float = fy * fy * (3 - 2 * fy)
        let a: Float = hash(ix, iy)
        let b: Float = hash(ix + 1, iy)
        let c: Float = hash(ix, iy + 1)
        let d: Float = hash(ix + 1, iy + 1)
        let bottom: Float = a + (b - a) * ux
        let top: Float = c + (d - c) * ux
        return bottom + (top - bottom) * uy
    }

    static func fbm(_ px: Float, _ py: Float) -> Float {
        var sum: Float = 0
        var amp: Float = 0.5
        var x: Float = px
        var y: Float = py
        for _ in 0..<5 {
            sum += amp * noise(x, y)
            x = x * 2.03 + 1.7
            y = y * 2.03 + 9.2
            amp *= 0.5
        }
        return sum
    }

    static func ridged(_ px: Float, _ py: Float) -> Float {
        var sum: Float = 0
        var amp: Float = 0.55
        var x: Float = px
        var y: Float = py
        for _ in 0..<4 {
            let n: Float = 1 - abs(2 * noise(x, y) - 1)
            sum += amp * n * n
            x = x * 2.1 + 3.1
            y = y * 2.1 + 7.7
            amp *= 0.5
        }
        return sum
    }

    static func shade(x: Int, y: Int, width: Int, height: Int) -> NebulaShade {
        let w: Float = Float(width)
        let h: Float = Float(height)
        let aspect: Float = w / h
        let u: Float = (Float(x) + 0.5) / w
        let v: Float = (Float(y) + 0.5) / h
        // away from the origin, where value noise is at its plainest
        let px: Float = u * aspect * 1.9 + 7.3
        let py: Float = v * 1.9 + 2.2

        let qx: Float = fbm(px, py)
        let qy: Float = fbm(px + 5.2, py + 1.3)
        let wx: Float = px + 3 * qx
        let wy: Float = py + 3 * qy
        let rx: Float = fbm(wx + 1.7, wy + 9.2)
        let ry: Float = fbm(wx + 8.3, wy + 2.8)
        let f: Float = fbm(px + 3 * rx, py + 3 * ry)

        let haze: Float = smooth(0.36, 0.60, f)
        let density: Float = smooth(0.45, 0.66, f)
        var colour: SIMD3<Float> = mix(indigo, violet, smooth(0.36, 0.48, rx))
        colour = mix(colour, teal, smooth(0.42, 0.62, qy))
        colour = mix(colour, rose, smooth(0.44, 0.54, ry) * density)
        let hot: Float = density * density * density
        colour += core * (hot * 0.25)
        let glow: Float = haze * 0.35 + density * 0.65
        let gas: SIMD3<Float> = colour * glow

        let lx: Float = px * 1.6 + rx * 1.2
        let ly: Float = py * 1.6 + ry * 1.2
        let lanes: Float = ridged(lx, ly)
        let there: Float = smooth(0.38, 0.56, f)
        let dark: Float = smooth(0.50, 0.85, lanes) * there
        let dust: Float = 1 - 0.6 * dark
        return NebulaShade(gas: gas, dust: dust)
    }
}

/// The same maths as NebulaMath, in Metal Shading Language.
nonisolated enum NebulaKernel {
    static let source: String = """
    #include <metal_stdlib>
    using namespace metal;

    float rpHash(float px, float py) {
        float x = fract(px * 123.34);
        float y = fract(py * 456.21);
        float d = x * (x + 45.32) + y * (y + 45.32);
        x += d;
        y += d;
        return fract(x * y);
    }

    float rpNoise(float px, float py) {
        float ix = floor(px);
        float iy = floor(py);
        float fx = px - ix;
        float fy = py - iy;
        float ux = fx * fx * (3.0 - 2.0 * fx);
        float uy = fy * fy * (3.0 - 2.0 * fy);
        float a = rpHash(ix, iy);
        float b = rpHash(ix + 1.0, iy);
        float c = rpHash(ix, iy + 1.0);
        float d = rpHash(ix + 1.0, iy + 1.0);
        float bottom = a + (b - a) * ux;
        float top = c + (d - c) * ux;
        return bottom + (top - bottom) * uy;
    }

    float rpFbm(float px, float py) {
        float sum = 0.0;
        float amp = 0.5;
        float x = px;
        float y = py;
        for (int k = 0; k < 5; k++) {
            sum += amp * rpNoise(x, y);
            x = x * 2.03 + 1.7;
            y = y * 2.03 + 9.2;
            amp *= 0.5;
        }
        return sum;
    }

    float rpRidged(float px, float py) {
        float sum = 0.0;
        float amp = 0.55;
        float x = px;
        float y = py;
        for (int k = 0; k < 4; k++) {
            float n = 1.0 - fabs(2.0 * rpNoise(x, y) - 1.0);
            sum += amp * n * n;
            x = x * 2.1 + 3.1;
            y = y * 2.1 + 7.7;
            amp *= 0.5;
        }
        return sum;
    }

    float rpSmooth(float a, float b, float x) {
        float t = clamp((x - a) / (b - a), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    kernel void rpNebula(texture2d<float, access::write> gasOut [[texture(0)]],
                         texture2d<float, access::write> dustOut [[texture(1)]],
                         constant float4 &info [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
        float w = info.x;
        float h = info.y;
        if (float(gid.x) >= w || float(gid.y) >= h) { return; }
        float aspect = w / h;
        float u = (float(gid.x) + 0.5) / w;
        float v = (float(gid.y) + 0.5) / h;
        float px = u * aspect * 1.9 + 7.3;
        float py = v * 1.9 + 2.2;

        float qx = rpFbm(px, py);
        float qy = rpFbm(px + 5.2, py + 1.3);
        float wx = px + 3.0 * qx;
        float wy = py + 3.0 * qy;
        float rx = rpFbm(wx + 1.7, wy + 9.2);
        float ry = rpFbm(wx + 8.3, wy + 2.8);
        float f = rpFbm(px + 3.0 * rx, py + 3.0 * ry);

        float3 indigo = float3(0.20, 0.30, 0.78);
        float3 violet = float3(0.46, 0.24, 0.80);
        float3 teal = float3(0.10, 0.52, 0.62);
        float3 rose = float3(0.95, 0.30, 0.48);
        float3 core = float3(0.95, 0.90, 1.0);

        float haze = rpSmooth(0.36, 0.60, f);
        float density = rpSmooth(0.45, 0.66, f);
        float3 colour = mix(indigo, violet, rpSmooth(0.36, 0.48, rx));
        colour = mix(colour, teal, rpSmooth(0.42, 0.62, qy));
        float roseShare = rpSmooth(0.44, 0.54, ry) * density;
        colour = mix(colour, rose, roseShare);
        float hot = density * density * density;
        colour += core * (hot * 0.25);
        float glow = haze * 0.35 + density * 0.65;
        float3 gas = colour * glow;

        float lx = px * 1.6 + rx * 1.2;
        float ly = py * 1.6 + ry * 1.2;
        float lanes = rpRidged(lx, ly);
        float there = rpSmooth(0.38, 0.56, f);
        float dark = rpSmooth(0.50, 0.85, lanes) * there;
        float dust = 1.0 - 0.6 * dark;

        gasOut.write(float4(clamp(gas, 0.0, 1.0), 1.0), gid);
        dustOut.write(float4(dust, dust, dust, 1.0), gid);
    }
    """
}

// MARK: - Loaded once, for every backdrop

/// The baked nebula, ready for SwiftUI. Asked for by the first backdrop on
/// screen; every backdrop after that shares the same two pictures.
@MainActor
@Observable
final class SkyNebula {
    static let shared = SkyNebula()

    private(set) var gas: Image?
    private(set) var dust: Image?
    @ObservationIgnored private var started = false

    private init() {}

    func prepare() {
        guard !started else { return }
        started = true
        Task.detached(priority: .utility) {
            let layers: NebulaLayers? = NebulaBaker.loadOrBake()
            await MainActor.run {
                SkyNebula.shared.accept(layers)
            }
        }
    }

    private func accept(_ layers: NebulaLayers?) {
        guard let layers else { return }
        withAnimation(.easeInOut(duration: 1.2)) {
            gas = Image(decorative: layers.gas, scale: 1)
            dust = Image(decorative: layers.dust, scale: 1)
        }
    }
}
