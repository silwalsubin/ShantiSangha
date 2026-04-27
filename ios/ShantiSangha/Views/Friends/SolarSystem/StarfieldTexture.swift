import RealityKit
import UIKit
import CoreGraphics

/// Procedural 4K equirectangular starfield + nebula texture for the
/// sky dome. Replaces pure black with a real cosmic backdrop:
///
///   - Dark indigo gradient (top → bottom) so the void doesn't read
///     as a flat painted wall
///   - 5 soft colored nebula blobs in the equatorial band — saffron /
///     blue / violet / teal — at low opacity, just enough to give
///     the scene chromatic depth
///   - ~800 stars with cubic brightness falloff (many faint, few
///     bright) plus a tint variation on the brightest stars (warm
///     ivory / cool blue-white) so the field doesn't read as a
///     uniform white speckle
///
/// Generated once per scene at init. ~50ms on iPhone 13-class. Static
/// — we don't animate. Phase 8 polish can layer drift/parallax via
/// a separate particle system if it adds value.
@MainActor
enum StarfieldTexture {
    static func generate(width: Int = 4096, height: Int = 2048) -> TextureResource? {
        let pxSize = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: pxSize)
        let image = renderer.image { ctx in
            let cgctx = ctx.cgContext

            drawBackground(in: cgctx, size: pxSize)
            drawNebulas(in: cgctx, size: pxSize)
            drawStars(in: cgctx, size: pxSize)
        }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(
            image: cg,
            options: TextureResource.CreateOptions(semantic: .color))
    }

    private static func drawBackground(in ctx: CGContext, size: CGSize) {
        let colors: [CGColor] = [
            UIColor(red: 0.025, green: 0.020, blue: 0.045, alpha: 1.0).cgColor,
            UIColor(red: 0.045, green: 0.035, blue: 0.075, alpha: 1.0).cgColor,
            UIColor(red: 0.025, green: 0.020, blue: 0.045, alpha: 1.0).cgColor,
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0.0, 0.5, 1.0])
        else { return }
        ctx.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: 0, y: size.height),
            options: [])
    }

    private static func drawNebulas(in ctx: CGContext, size: CGSize) {
        // Cluster nebulas in the equatorial band (camera looks ~along
        // the equator). Top/bottom poles stay near-black so the dome
        // doesn't reveal poly seams when the user pans elevation.
        let palette: [UIColor] = [
            UIColor(red: 0.95, green: 0.50, blue: 0.25, alpha: 1.0),  // saffron
            UIColor(red: 0.30, green: 0.50, blue: 0.85, alpha: 1.0),  // cool blue
            UIColor(red: 0.55, green: 0.30, blue: 0.65, alpha: 1.0),  // violet
            UIColor(red: 0.20, green: 0.65, blue: 0.55, alpha: 1.0),  // teal
            UIColor(red: 0.85, green: 0.40, blue: 0.55, alpha: 1.0),  // dusty pink
        ]
        for color in palette {
            let cx = CGFloat.random(in: 0..<size.width)
            let cy = CGFloat.random(in: size.height * 0.30..<size.height * 0.70)
            let radius = CGFloat.random(in: 220..<480)
            let neb: [CGColor] = [
                color.withAlphaComponent(0.22).cgColor,
                color.withAlphaComponent(0.10).cgColor,
                color.withAlphaComponent(0.0).cgColor,
            ]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: neb as CFArray,
                locations: [0.0, 0.55, 1.0])
            else { continue }
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endCenter: CGPoint(x: cx, y: cy),
                endRadius: radius,
                options: [])
        }
    }

    private static func drawStars(in ctx: CGContext, size: CGSize, count: Int = 800) {
        for _ in 0..<count {
            let u = CGFloat.random(in: 0..<size.width)
            let v = CGFloat.random(in: 0..<size.height)
            // Cubic falloff biases the population toward dim — a
            // realistic star field has many faint background stars
            // and few bright foreground ones.
            let r = CGFloat.random(in: 0..<1)
            let brightness = r * r * r
            // Bumped sizes so stars survive RealityKit's mipmap
            // filtering when wrapped on the 500m sky dome — at the
            // previous 1–3px range they were sub-pixel after
            // filtering and disappeared entirely.
            let starSize: CGFloat = brightness > 0.7
                ? CGFloat.random(in: 5.0..<10.0)
                : CGFloat.random(in: 2.5..<5.0)
            let alpha = 0.45 + brightness * 0.55

            let tint: UIColor
            if brightness > 0.85 {
                // Brightest stars get a warm or cool tint — gives
                // the field subtle chromatic interest at full zoom.
                tint = Bool.random()
                    ? UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: alpha)
                    : UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: alpha)
            } else {
                tint = UIColor(white: 1.0, alpha: alpha)
            }
            tint.setFill()
            ctx.fillEllipse(in: CGRect(
                x: u - starSize / 2,
                y: v - starSize / 2,
                width: starSize,
                height: starSize))
        }
    }
}
