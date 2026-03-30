import SwiftUI

/// Vajra (Vishwa Vajra) icon — matches the web app's SacredIcons vajra.
/// Renders as a white symbol on transparent background.
struct VajraIcon: View {
    var size: CGFloat = 22
    var color: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width / 2
            let cy = canvasSize.height / 2
            let scale = s / 24 // viewBox is 0-24

            // Helper to transform coordinates from 0-24 space
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + (x - 12) * scale, y: cy + (y - 12) * scale)
            }

            // Central orb
            let orbPath = Circle().path(in: CGRect(
                x: cx - 2.2 * scale, y: cy - 2.2 * scale,
                width: 4.4 * scale, height: 4.4 * scale
            ))
            context.stroke(orbPath, with: .color(color), lineWidth: 1.3 * scale)

            // Central dot
            let dotPath = Circle().path(in: CGRect(
                x: cx - 0.8 * scale, y: cy - 0.8 * scale,
                width: 1.6 * scale, height: 1.6 * scale
            ))
            context.fill(dotPath, with: .color(color))

            // Draw prongs for all 4 directions
            for angle in [0.0, 90.0, 180.0, 270.0] {
                context.drawLayer { ctx in
                    // Rotate around center
                    let radians = angle * .pi / 180
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: Angle(radians: radians))
                    ctx.translateBy(x: -cx, y: -cy)

                    // Petal
                    var petal = Path()
                    petal.move(to: pt(12, 9.8))
                    petal.addCurve(to: pt(12, 8), control1: pt(11, 9), control2: pt(11, 8))
                    petal.addCurve(to: pt(12, 9.8), control1: pt(13, 8), control2: pt(13, 9))
                    ctx.fill(petal, with: .color(color.opacity(0.2)))
                    ctx.stroke(petal, with: .color(color), lineWidth: 0.8 * scale)

                    // Left curve of prong
                    var leftCurve = Path()
                    leftCurve.move(to: pt(11, 8))
                    leftCurve.addCurve(to: pt(12, 2.5), control1: pt(8.5, 5.5), control2: pt(9.5, 4))
                    ctx.stroke(leftCurve, with: .color(color), lineWidth: 1.4 * scale)

                    // Right curve of prong
                    var rightCurve = Path()
                    rightCurve.move(to: pt(13, 8))
                    rightCurve.addCurve(to: pt(12, 2.5), control1: pt(15.5, 5.5), control2: pt(14.5, 4))
                    ctx.stroke(rightCurve, with: .color(color), lineWidth: 1.4 * scale)

                    // Center line
                    var centerLine = Path()
                    centerLine.move(to: pt(12, 8))
                    centerLine.addLine(to: pt(12, 2.5))
                    ctx.stroke(centerLine, with: .color(color), lineWidth: 0.8 * scale)

                    // Pointed tip
                    var tip = Path()
                    tip.move(to: pt(12, 2.5))
                    tip.addLine(to: pt(11.3, 1.2))
                    ctx.stroke(tip, with: .color(color), lineWidth: 1.2 * scale)

                    var tip2 = Path()
                    tip2.move(to: pt(12, 2.5))
                    tip2.addLine(to: pt(12.7, 1.2))
                    ctx.stroke(tip2, with: .color(color), lineWidth: 1.2 * scale)

                    var tipTop = Path()
                    tipTop.move(to: pt(11.3, 1.2))
                    tipTop.addLine(to: pt(12, 0.3))
                    tipTop.addLine(to: pt(12.7, 1.2))
                    ctx.stroke(tipTop, with: .color(color), lineWidth: 1.2 * scale)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
