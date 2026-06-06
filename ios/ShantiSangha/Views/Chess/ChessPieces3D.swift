import SceneKit
import UIKit

/// Code-generated 3D chess pieces (no model assets) built by stacking SceneKit
/// primitives — turned-wood style bodies for the round pieces and a stylized
/// knight. Each piece sits with its base at local y = 0 and footprint inside a
/// 1×1 tile. Materials are physically-based so the scene's lighting gives them
/// real highlights and cast shadows.
enum ChessPieces3D {

    static func node(for type: PieceType, isWhite: Bool) -> SCNNode {
        let parent = SCNNode()
        parent.name = "piece"
        let material = makeMaterial(isWhite: isWhite)
        for part in parts(for: type) {
            // Assign to `materials` (not just `firstMaterial`) so an extruded
            // SCNShape's sides get the material too, not default gray.
            part.geometry?.materials = [material]
            part.castsShadow = true
            parent.addChildNode(part)
        }
        return parent
    }

    private static func makeMaterial(isWhite: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if isWhite {
            // Warm ivory.
            m.diffuse.contents = UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1)
            m.roughness.contents = 0.5
            m.metalness.contents = 0.0
        } else {
            // Dark antique gold — reads clearly on the dark board and matches the
            // sacred saffron palette. A touch of metalness + low roughness gives a
            // warm sheen under the key light.
            m.diffuse.contents = UIColor(red: 0.60, green: 0.40, blue: 0.14, alpha: 1)
            m.roughness.contents = 0.32
            m.metalness.contents = 0.45
            m.specular.contents = UIColor(white: 1.0, alpha: 1.0)
        }
        return m
    }

    // MARK: - Primitive helpers (each positioned so its BOTTOM is at `baseY`)

    private static func cyl(_ r: CGFloat, _ h: CGFloat, _ baseY: CGFloat) -> SCNNode {
        let n = SCNNode(geometry: SCNCylinder(radius: r, height: h))
        n.position.y = Float(baseY + h / 2)
        return n
    }

    private static func cone(top: CGFloat, bottom: CGFloat, _ h: CGFloat, _ baseY: CGFloat) -> SCNNode {
        let n = SCNNode(geometry: SCNCone(topRadius: top, bottomRadius: bottom, height: h))
        n.position.y = Float(baseY + h / 2)
        return n
    }

    private static func ball(_ r: CGFloat, _ baseY: CGFloat) -> SCNNode {
        let n = SCNNode(geometry: SCNSphere(radius: r))
        n.position.y = Float(baseY + r)
        return n
    }

    private static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ baseY: CGFloat) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: 0.01)
        let n = SCNNode(geometry: g)
        n.position.y = Float(baseY + h / 2)
        return n
    }

    /// A standard turned base shared by most pieces.
    private static func base(_ topRadius: CGFloat) -> [SCNNode] {
        [cyl(0.32, 0.07, 0.0), cone(top: topRadius, bottom: 0.30, 0.07, 0.07)]
    }

    // MARK: - Per-piece silhouettes

    private static func parts(for type: PieceType) -> [SCNNode] {
        switch type {
        case .pawn:
            return base(0.18) + [
                cone(top: 0.10, bottom: 0.17, 0.20, 0.14),
                cyl(0.15, 0.03, 0.34),
                ball(0.13, 0.35)
            ]
        case .rook:
            return base(0.22) + [
                cyl(0.19, 0.32, 0.14),
                cyl(0.25, 0.08, 0.46),
                // four crenellation nubs around the rim
                box(0.07, 0.07, 0.07, 0.54).x(0.16),
                box(0.07, 0.07, 0.07, 0.54).x(-0.16),
                box(0.07, 0.07, 0.07, 0.54).z(0.16),
                box(0.07, 0.07, 0.07, 0.54).z(-0.16)
            ]
        case .bishop:
            return base(0.20) + [
                cone(top: 0.09, bottom: 0.19, 0.42, 0.14),
                cyl(0.13, 0.04, 0.54),
                ball(0.11, 0.57),
                ball(0.045, 0.79)
            ]
        case .queen:
            return base(0.22) + [
                cone(top: 0.11, bottom: 0.21, 0.48, 0.14),
                cyl(0.17, 0.04, 0.62),
                cone(top: 0.06, bottom: 0.17, 0.12, 0.66),
                ball(0.075, 0.78)
            ]
        case .king:
            return base(0.22) + [
                cone(top: 0.12, bottom: 0.21, 0.52, 0.14),
                cyl(0.18, 0.04, 0.66),
                cyl(0.13, 0.07, 0.70),
                // cross
                box(0.05, 0.18, 0.05, 0.77),
                box(0.14, 0.05, 0.05, 0.83)
            ]
        case .knight:
            // Stylized: a turned base, a forward-leaning neck, and a muzzle.
            let neck = box(0.17, 0.36, 0.20, 0.14)
            neck.eulerAngles.x = -0.30
            neck.position.z = 0.04
            let muzzle = box(0.12, 0.12, 0.20, 0.40)
            muzzle.position.z = 0.12
            let ear1 = box(0.04, 0.10, 0.04, 0.46).x(0.05).z(-0.02)
            let ear2 = box(0.04, 0.10, 0.04, 0.46).x(-0.05).z(-0.02)
            return base(0.22) + [neck, muzzle, ear1, ear2]
        }
    }
}

private extension SCNNode {
    /// Fluent offset helpers for placing decorative nubs.
    func x(_ value: Float) -> SCNNode { position.x = value; return self }
    func z(_ value: Float) -> SCNNode { position.z = value; return self }
}
