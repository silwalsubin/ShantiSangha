import RealityKit
import UIKit

/// Initial-glyph texture used when a connection has no `avatarUrl`
/// or the avatar download fails. Matches the moon's parchment tone
/// so the planet still reads as having a "moon" rather than a
/// missing-image placeholder.
@MainActor
enum AvatarFallbackTextures {
    static func generate(initial: String) -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cgctx = ctx.cgContext
            // Parchment-warm circle for the moon body
            UIColor(red: 0.92, green: 0.84, blue: 0.70, alpha: 1.0).setFill()
            cgctx.fillEllipse(in: CGRect(origin: .zero, size: size))

            // Centered initial in deep brown — readable against the
            // parchment regardless of which side of the planet the
            // moon is on.
            let font = UIFont.systemFont(ofSize: 130, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 1.0),
            ]
            let str = initial as NSString
            let strSize = str.size(withAttributes: attrs)
            let rect = CGRect(
                x: (size.width - strSize.width) / 2,
                y: (size.height - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height)
            str.draw(in: rect, withAttributes: attrs)
        }
        guard let cg = image.cgImage else { return nil }
        return try? TextureResource(
            image: cg,
            options: TextureResource.CreateOptions(semantic: .color))
    }
}
