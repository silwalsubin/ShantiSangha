import RealityKit
import UIKit
import CoreGraphics

/// Procedural surface textures for planets. Generates a noise-blob
/// pattern via CoreGraphics, converts to a `TextureResource`, and
/// returns nil on failure so the caller can fall back to a flat tint.
///
/// Stylized rather than photoreal — we're not trying to look like
/// NASA, we're trying to read like sacred-palette planets that have
/// surface character. The "professional" leap above this requires
/// Reality Composer Pro shader materials in an .rkassets bundle.
@MainActor
enum PlanetTextures {
    /// Per-pixel atmospheric ring — alpha is 0 at the center
    /// (transparent so the planet shows through), peaks in a
    /// gaussian ring at ~0.55 of radius (the "atmosphere"), and
    /// fades to 0 at the texture edge. White grayscale; tint applied
    /// at the material level so one texture serves any planet hue.
    static func atmosphereRing(size: Int = 512) -> TextureResource? {
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let cx = Float(width) / 2.0
        let cy = Float(height) / 2.0
        let maxR = Float(width) / 2.0
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let ringPeak: Float = 0.55
        let ringSigma: Float = 0.18
        let ringAmplitude: Float = 0.95

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - cx
                let dy = Float(y) - cy
                let r = sqrtf(dx * dx + dy * dy) / maxR

                let gauss = expf(-powf((r - ringPeak) / ringSigma, 2.0) * 0.5)
                let edgeFade = powf(max(0, 1.0 - r), 1.5)
                let alpha = max(0, min(1, ringAmplitude * gauss * edgeFade))
                let alphaByte = UInt8(alpha * 255.0)

                let idx = (y * width + x) * bytesPerPixel
                // Premultiplied white: RGB == A
                pixels[idx + 0] = alphaByte
                pixels[idx + 1] = alphaByte
                pixels[idx + 2] = alphaByte
                pixels[idx + 3] = alphaByte
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }

        return try? TextureResource(
            image: cgImage,
            options: TextureResource.CreateOptions(semantic: .color))
    }

    /// Soft radial gradient with alpha falloff from opaque-white center
    /// to fully transparent edge. Per-pixel gaussian × edge-fade with a
    /// tiny noise dither — `CGGradient`'s discrete stops produce
    /// visible ring seams where stop slopes change, and 8-bit alpha
    /// without dither shows banding even with a perfect math curve.
    /// Tinted at the material level so a single grayscale texture
    /// serves any color of glow.
    static func radialGradient(size: Int = 1024) -> TextureResource? {
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel

        let cx = Float(width) / 2.0
        let cy = Float(height) / 2.0
        let maxR = Float(width) / 2.0

        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        var generator = SystemRandomNumberGenerator()

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - cx
                let dy = Float(y) - cy
                let r = sqrtf(dx * dx + dy * dy)
                let t = min(1.0, r / maxR)            // 0 at center → 1 at rim

                // Gaussian-ish core × edge fade. The edge fade pushes
                // the curve hard to zero at t=1 so there's no
                // hard-cutoff line at the texture rim.
                let gaussian = expf(-t * t * 4.0)
                let edgeFade = powf(max(0, 1.0 - t), 1.8)

                // 1/255 noise dither — visually imperceptible but
                // breaks up the smooth banding that 8-bit alpha
                // would otherwise show in a continuous gradient.
                let noise = (Float(UInt8.random(in: 0...255, using: &generator)) - 127.5) / (255.0 * 255.0)
                let alpha = max(0, min(1, gaussian * edgeFade + noise))
                let alphaByte = UInt8(alpha * 255.0)

                let idx = (y * width + x) * bytesPerPixel
                // Premultiplied alpha for white tint: RGB == A
                pixels[idx + 0] = alphaByte
                pixels[idx + 1] = alphaByte
                pixels[idx + 2] = alphaByte
                pixels[idx + 3] = alphaByte
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent)
        else { return nil }

        return try? TextureResource(
            image: cgImage,
            options: TextureResource.CreateOptions(semantic: .color))
    }

    /// Generate a 512×512 noise texture for a planet body.
    /// `accentBlobs` controls density — higher counts read as
    /// busier surfaces (good for rocky inner planets), lower counts
    /// as smoother (good for matte outer planets).
    static func generate(
        base: UIColor,
        accent: UIColor,
        highlight: UIColor,
        accentBlobs: Int = 240,
        highlightBlobs: Int = 80
    ) -> TextureResource? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            base.setFill()
            ctx.fill(rect)

            // Mid-tone noise: irregular blobs in the accent color
            // give the surface a varied, lived-in feel.
            for _ in 0..<accentBlobs {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let r = CGFloat.random(in: 6..<32)
                let alpha = CGFloat.random(in: 0.04..<0.20)
                accent.withAlphaComponent(alpha).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: x - r, y: y - r, width: r * 2, height: r * 2))
            }

            // Sparse bright highlights — sun-catches, mineral
            // glints. Keeps the surface from reading uniformly
            // muddy.
            for _ in 0..<highlightBlobs {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let r = CGFloat.random(in: 3..<14)
                let alpha = CGFloat.random(in: 0.08..<0.30)
                highlight.withAlphaComponent(alpha).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(
            image: cg,
            options: TextureResource.CreateOptions(semantic: .color))
    }
}
