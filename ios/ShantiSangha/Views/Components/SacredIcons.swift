import SwiftUI

/// Sacred icon shapes matching the web app's SacredIcons.vue
/// Used for tab bar and throughout the app
enum SacredIcon: String {
    case vajra
    case dialogue
    case diya
    case chakra
}

struct SacredIconView: View {
    let icon: SacredIcon
    var size: CGFloat = 22

    var body: some View {
        switch icon {
        case .vajra:
            VajraShape()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        case .dialogue:
            DialogueShape()
                .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .overlay(DialogueDots())
                .frame(width: size, height: size)
        case .diya:
            DiyaShape()
                .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .overlay(DiyaFill())
                .frame(width: size, height: size)
        case .chakra:
            ChakraShape()
                .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .overlay(ChakraDots())
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Vajra (Vishwa Vajra)

private struct VajraShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var p = Path()

        // Central orb
        p.addEllipse(in: CGRect(x: 12*s - 2.2*s, y: 12*s - 2.2*s, width: 4.4*s, height: 4.4*s))

        // Up prong
        p.move(to: CGPoint(x: 11*s, y: 8*s))
        p.addCurve(to: CGPoint(x: 8.5*s, y: 4.8*s),
                    control1: CGPoint(x: 10.5*s, y: 6.8*s),
                    control2: CGPoint(x: 9*s, y: 5.5*s))
        p.move(to: CGPoint(x: 13*s, y: 8*s))
        p.addCurve(to: CGPoint(x: 15.5*s, y: 4.8*s),
                    control1: CGPoint(x: 13.5*s, y: 6.8*s),
                    control2: CGPoint(x: 15*s, y: 5.5*s))
        p.move(to: CGPoint(x: 12*s, y: 8*s))
        p.addLine(to: CGPoint(x: 12*s, y: 2.5*s))
        p.move(to: CGPoint(x: 11.3*s, y: 1.2*s))
        p.addLine(to: CGPoint(x: 12*s, y: 0.3*s))
        p.addLine(to: CGPoint(x: 12.7*s, y: 1.2*s))

        // Down prong
        p.move(to: CGPoint(x: 11*s, y: 16*s))
        p.addCurve(to: CGPoint(x: 8.5*s, y: 19.2*s),
                    control1: CGPoint(x: 10.5*s, y: 17.2*s),
                    control2: CGPoint(x: 9*s, y: 18.5*s))
        p.move(to: CGPoint(x: 13*s, y: 16*s))
        p.addCurve(to: CGPoint(x: 15.5*s, y: 19.2*s),
                    control1: CGPoint(x: 13.5*s, y: 17.2*s),
                    control2: CGPoint(x: 15*s, y: 18.5*s))
        p.move(to: CGPoint(x: 12*s, y: 16*s))
        p.addLine(to: CGPoint(x: 12*s, y: 21.5*s))
        p.move(to: CGPoint(x: 11.3*s, y: 22.8*s))
        p.addLine(to: CGPoint(x: 12*s, y: 23.7*s))
        p.addLine(to: CGPoint(x: 12.7*s, y: 22.8*s))

        // Left prong
        p.move(to: CGPoint(x: 8*s, y: 11*s))
        p.addCurve(to: CGPoint(x: 4.8*s, y: 8.5*s),
                    control1: CGPoint(x: 6.8*s, y: 10.5*s),
                    control2: CGPoint(x: 5.5*s, y: 9*s))
        p.move(to: CGPoint(x: 8*s, y: 13*s))
        p.addCurve(to: CGPoint(x: 4.8*s, y: 15.5*s),
                    control1: CGPoint(x: 6.8*s, y: 13.5*s),
                    control2: CGPoint(x: 5.5*s, y: 15*s))
        p.move(to: CGPoint(x: 8*s, y: 12*s))
        p.addLine(to: CGPoint(x: 2.5*s, y: 12*s))
        p.move(to: CGPoint(x: 1.2*s, y: 11.3*s))
        p.addLine(to: CGPoint(x: 0.3*s, y: 12*s))
        p.addLine(to: CGPoint(x: 1.2*s, y: 12.7*s))

        // Right prong
        p.move(to: CGPoint(x: 16*s, y: 11*s))
        p.addCurve(to: CGPoint(x: 19.2*s, y: 8.5*s),
                    control1: CGPoint(x: 17.2*s, y: 10.5*s),
                    control2: CGPoint(x: 18.5*s, y: 9*s))
        p.move(to: CGPoint(x: 16*s, y: 13*s))
        p.addCurve(to: CGPoint(x: 19.2*s, y: 15.5*s),
                    control1: CGPoint(x: 17.2*s, y: 13.5*s),
                    control2: CGPoint(x: 18.5*s, y: 15*s))
        p.move(to: CGPoint(x: 16*s, y: 12*s))
        p.addLine(to: CGPoint(x: 21.5*s, y: 12*s))
        p.move(to: CGPoint(x: 22.8*s, y: 11.3*s))
        p.addLine(to: CGPoint(x: 23.7*s, y: 12*s))
        p.addLine(to: CGPoint(x: 22.8*s, y: 12.7*s))

        return p
    }
}

// MARK: - Dialogue (Chat bubble)

private struct DialogueShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var p = Path()
        // Main bubble: M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z
        p.move(to: CGPoint(x: 21*s, y: 15*s))
        p.addQuadCurve(to: CGPoint(x: 19*s, y: 17*s), control: CGPoint(x: 21*s, y: 17*s))
        p.addLine(to: CGPoint(x: 7*s, y: 17*s))
        p.addLine(to: CGPoint(x: 3*s, y: 21*s))
        p.addLine(to: CGPoint(x: 3*s, y: 5*s))
        p.addQuadCurve(to: CGPoint(x: 5*s, y: 3*s), control: CGPoint(x: 3*s, y: 3*s))
        p.addLine(to: CGPoint(x: 19*s, y: 3*s))
        p.addQuadCurve(to: CGPoint(x: 21*s, y: 5*s), control: CGPoint(x: 21*s, y: 3*s))
        p.closeSubpath()
        return p
    }
}

private struct DialogueDots: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24.0
            Circle()
                .fill(Color.current)
                .frame(width: 1.6*s, height: 1.6*s)
                .position(x: 9*s, y: 10*s)
            Circle()
                .fill(Color.current)
                .frame(width: 1.6*s, height: 1.6*s)
                .position(x: 12*s, y: 10*s)
            Circle()
                .fill(Color.current)
                .frame(width: 1.6*s, height: 1.6*s)
                .position(x: 15*s, y: 10*s)
        }
    }
}

// MARK: - Diya (Oil lamp)

private struct DiyaShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var p = Path()

        // Flame outline
        p.move(to: CGPoint(x: 12*s, y: 3*s))
        p.addCurve(to: CGPoint(x: 10.5*s, y: 7.5*s),
                    control1: CGPoint(x: 11.2*s, y: 4.5*s),
                    control2: CGPoint(x: 10.5*s, y: 6*s))
        p.addCurve(to: CGPoint(x: 12*s, y: 10*s),
                    control1: CGPoint(x: 10.5*s, y: 9*s),
                    control2: CGPoint(x: 11.3*s, y: 10*s))
        p.addCurve(to: CGPoint(x: 13.5*s, y: 7.5*s),
                    control1: CGPoint(x: 12.7*s, y: 10*s),
                    control2: CGPoint(x: 13.5*s, y: 9*s))
        p.addCurve(to: CGPoint(x: 12*s, y: 3*s),
                    control1: CGPoint(x: 13.5*s, y: 6*s),
                    control2: CGPoint(x: 12.8*s, y: 4.5*s))

        // Lamp bowl
        p.move(to: CGPoint(x: 6.5*s, y: 14*s))
        p.addCurve(to: CGPoint(x: 17.5*s, y: 14*s),
                    control1: CGPoint(x: 6.5*s, y: 11.5*s),
                    control2: CGPoint(x: 17.5*s, y: 11.5*s))
        p.move(to: CGPoint(x: 4*s, y: 14*s))
        p.addLine(to: CGPoint(x: 20*s, y: 14*s))

        // Lamp base
        p.move(to: CGPoint(x: 5.5*s, y: 14*s))
        p.addLine(to: CGPoint(x: 7*s, y: 19*s))
        p.addLine(to: CGPoint(x: 17*s, y: 19*s))
        p.addLine(to: CGPoint(x: 18.5*s, y: 14*s))

        // Pedestal
        p.move(to: CGPoint(x: 9*s, y: 19*s))
        p.addLine(to: CGPoint(x: 9*s, y: 20.5*s))
        p.move(to: CGPoint(x: 15*s, y: 19*s))
        p.addLine(to: CGPoint(x: 15*s, y: 20.5*s))
        p.move(to: CGPoint(x: 9*s, y: 20.5*s))
        p.addLine(to: CGPoint(x: 15*s, y: 20.5*s))

        // Wick
        p.move(to: CGPoint(x: 12*s, y: 10*s))
        p.addLine(to: CGPoint(x: 12*s, y: 11*s))

        return p
    }
}

private struct DiyaFill: View {
    var body: some View {
        GeometryReader { geo in
            // Flame glow fill
            FlameFillShape()
                .fill(Color.current.opacity(0.15))
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
        }
    }
}

private struct FlameFillShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var p = Path()
        p.move(to: CGPoint(x: 12*s, y: 3*s))
        p.addCurve(to: CGPoint(x: 10.5*s, y: 7.5*s),
                    control1: CGPoint(x: 11.2*s, y: 4.5*s),
                    control2: CGPoint(x: 10.5*s, y: 6*s))
        p.addCurve(to: CGPoint(x: 12*s, y: 10*s),
                    control1: CGPoint(x: 10.5*s, y: 9*s),
                    control2: CGPoint(x: 11.3*s, y: 10*s))
        p.addCurve(to: CGPoint(x: 13.5*s, y: 7.5*s),
                    control1: CGPoint(x: 12.7*s, y: 10*s),
                    control2: CGPoint(x: 13.5*s, y: 9*s))
        p.addCurve(to: CGPoint(x: 12*s, y: 3*s),
                    control1: CGPoint(x: 13.5*s, y: 6*s),
                    control2: CGPoint(x: 12.8*s, y: 4.5*s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Chakra (Sacred geometry for Settings)

private struct ChakraShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        var p = Path()

        // Outer ring
        p.addEllipse(in: CGRect(x: 2.5*s, y: 2.5*s, width: 19*s, height: 19*s))
        // Inner ring
        p.addEllipse(in: CGRect(x: 7*s, y: 7*s, width: 10*s, height: 10*s))
        // Center
        p.addEllipse(in: CGRect(x: 10.5*s, y: 10.5*s, width: 3*s, height: 3*s))

        // Cardinal spokes
        p.move(to: CGPoint(x: 12*s, y: 2.5*s))
        p.addLine(to: CGPoint(x: 12*s, y: 6.5*s))
        p.move(to: CGPoint(x: 12*s, y: 17.5*s))
        p.addLine(to: CGPoint(x: 12*s, y: 21.5*s))
        p.move(to: CGPoint(x: 2.5*s, y: 12*s))
        p.addLine(to: CGPoint(x: 6.5*s, y: 12*s))
        p.move(to: CGPoint(x: 17.5*s, y: 12*s))
        p.addLine(to: CGPoint(x: 21.5*s, y: 12*s))

        // Diagonal spokes
        p.move(to: CGPoint(x: 5.3*s, y: 5.3*s))
        p.addLine(to: CGPoint(x: 8.1*s, y: 8.1*s))
        p.move(to: CGPoint(x: 15.9*s, y: 15.9*s))
        p.addLine(to: CGPoint(x: 18.7*s, y: 18.7*s))
        p.move(to: CGPoint(x: 5.3*s, y: 18.7*s))
        p.addLine(to: CGPoint(x: 8.1*s, y: 15.9*s))
        p.move(to: CGPoint(x: 15.9*s, y: 8.1*s))
        p.addLine(to: CGPoint(x: 18.7*s, y: 5.3*s))

        return p
    }
}

private struct ChakraDots: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24.0
            Circle()
                .fill(Color.current)
                .frame(width: s, height: s)
                .position(x: 12*s, y: 7*s)
            Circle()
                .fill(Color.current)
                .frame(width: s, height: s)
                .position(x: 12*s, y: 17*s)
            Circle()
                .fill(Color.current)
                .frame(width: s, height: s)
                .position(x: 7*s, y: 12*s)
            Circle()
                .fill(Color.current)
                .frame(width: s, height: s)
                .position(x: 17*s, y: 12*s)
        }
    }
}

// MARK: - Color helper

private extension Color {
    static var current: Color { Color.primary }
}
