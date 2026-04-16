import SwiftUI
import CoreMotion

/// Sacred typography — all serif (New York), no sans-serif anywhere.
/// All app text should use these tokens instead of raw .system() calls.
extension Font {
    /// 32pt serif regular — large icons
    static let sacredIconLarge = Font.system(size: 32, design: .serif)
    /// 28pt serif bold — login hero, large titles
    static let sacredHero = Font.system(size: 28, weight: .bold, design: .serif)
    /// 24pt serif bold — large display numbers
    static let sacredDisplayNumber = Font.system(size: 24, weight: .bold, design: .serif)
    /// 22pt serif semibold — page titles ("Your sacred space")
    static let sacredTitle = Font.system(size: 22, weight: .semibold, design: .serif)
    /// 20pt serif bold — section hero (goal name)
    static let sacredHeading = Font.system(size: 20, weight: .bold, design: .serif)
    /// 18pt serif bold — card titles (app name)
    static let sacredSubheading = Font.system(size: 18, weight: .bold, design: .serif)
    /// 16pt serif semibold — button labels, prominent UI text
    static let sacredButtonLabel = Font.system(size: 16, weight: .semibold, design: .serif)
    /// 16pt serif regular — icon-sized text
    static let sacredIcon = Font.system(size: 16, design: .serif)
    /// 14pt serif bold — emphasis (streak counts)
    static let sacredBodyBold = Font.system(size: 14, weight: .bold, design: .serif)
    /// 14pt serif semibold — emphasized body text
    static let sacredTextSemibold = Font.system(size: 14, weight: .semibold, design: .serif)
    /// 14pt serif medium — medium body text
    static let sacredTextMedium = Font.system(size: 14, weight: .medium, design: .serif)
    /// 14pt serif regular — standard body text
    static let sacredText = Font.system(size: 14, design: .serif)
    /// 14pt serif regular — alias for sacredText
    static let sacredBody = Font.system(size: 14, design: .serif)
    /// 12pt serif semibold — emphasized small text
    static let sacredSmallSemibold = Font.system(size: 12, weight: .semibold, design: .serif)
    /// 12pt serif medium — medium small text
    static let sacredSmallMedium = Font.system(size: 12, weight: .medium, design: .serif)
    /// 12pt serif regular — small text, captions
    static let sacredSmall = Font.system(size: 12, design: .serif)
    /// 12pt serif regular — alias for sacredSmall
    static let sacredCaption = Font.system(size: 12, design: .serif)
    /// 11pt serif regular — fine print
    static let sacredFinePrint = Font.system(size: 11, design: .serif)
    /// 10pt serif bold — uppercase micro labels
    static let sacredMicroBold = Font.system(size: 10, weight: .bold, design: .serif)
    /// 10pt serif regular — micro text
    static let sacredMicro = Font.system(size: 10, design: .serif)
    /// 9pt serif bold — section labels ("ACCOUNT", "YOUR DHARMA")
    /// Use with .tracking(3) and .foregroundColor(.sacredLabel)
    static let sacredSectionLabel = Font.system(size: 9, weight: .bold, design: .serif)
}

/// Sacred design tokens — single source of truth for colors.
/// Supports both light and dark mode.
extension Color {
    static let sacredGold = Color(hex: "#c4873b")
    static let sacredGoldDark = Color(hex: "#8b5a1b")
    static let sacredGoldLight = Color(hex: "#d4a054")
    static let sacredGoldShine = Color(hex: "#e8c47a")

    static let sacredText = Color.adaptive(light: "#2b1e10", dark: "#f5ebe0")
    static let sacredTextSecondary = Color.adaptive(light: "#6b5740", dark: "#c4a882")
    static let sacredMuted = Color.adaptive(light: "#9a8568", dark: "#8a7a64")
    static let sacredMutedLight = Color.adaptive(light: "#b5996f", dark: "#7a6a54")
    static let sacredLabel = Color.adaptive(light: "#a38d6d", dark: "#b5996f")
    static let sacredBg = Color.adaptive(light: "#faf5ed", dark: "#1a1410")
    static let sacredBgCard = Color.adaptive(light: "#f5ebe0", dark: "#2a2018")
    static let sacredGreen = Color(hex: "#7aa87a")
    static let sacredGreenDark = Color(hex: "#5a8a5a")
    static let sacredRed = Color(hex: "#b45a3c")

    // MARK: - Helpers

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: h).scanHexInt64(&int)
            return UIColor(
                red: CGFloat((int >> 16) & 0xFF) / 255,
                green: CGFloat((int >> 8) & 0xFF) / 255,
                blue: CGFloat(int & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// Subtle shimmer animation — sweeps a light highlight across gold elements.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.06), location: 0.4),
                            .init(color: .white.opacity(0.12), location: 0.5),
                            .init(color: .white.opacity(0.06), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: geo.size.width * phase)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 3.5)
                            .repeatForever(autoreverses: false)
                            .delay(2)
                        ) {
                            phase = 1.5
                        }
                    }
                }
            )
            .clipped()
    }
}

extension View {
    /// Adds a subtle, repeating shimmer sweep over gold elements.
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// Radial shiny gold — for circular elements (avatars, FAB).
extension RadialGradient {
    static let sacredGoldShiny = RadialGradient(
        stops: [
            .init(color: .sacredGoldShine, location: 0),
            .init(color: .sacredGold, location: 0.45),
            .init(color: .sacredGoldDark, location: 1),
        ],
        center: .init(x: 0.35, y: 0.35),
        startRadius: 0,
        endRadius: 40
    )
}

/// Cymbal-textured gold — concentric rings like a brushed metal cymbal.
/// Use on circular FAB buttons for a tactile, sacred-instrument feel.
struct CymbalGoldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Bright golden base
                    RadialGradient(
                        stops: [
                            .init(color: .sacredGoldShine, location: 0),
                            .init(color: .sacredGold, location: 0.5),
                            .init(color: .sacredGoldDark, location: 1),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )

                    // Concentric ring grooves — centered
                    Canvas { ctx, size in
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                        let maxRadius = min(size.width, size.height) * 0.5
                        let ringCount = 16

                        for i in 0..<ringCount {
                            let t = CGFloat(i + 2) / CGFloat(ringCount + 2)
                            let radius = maxRadius * t
                            let rect = CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                            let ring = Path(ellipseIn: rect)
                            let bright = (i % 2 == 0)
                            ctx.stroke(
                                ring,
                                with: .color(bright ? .white.opacity(0.18) : .black.opacity(0.1)),
                                lineWidth: 0.15
                            )
                        }
                    }

                    // Highlight sheen — top-left
                    RadialGradient(
                        stops: [
                            .init(color: .white.opacity(0.3), location: 0),
                            .init(color: .white.opacity(0.05), location: 0.4),
                            .init(color: .clear, location: 0.7),
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 25
                    )
                }
            )
    }
}

extension View {
    func cymbalGold() -> some View {
        modifier(CymbalGoldModifier())
    }
}

/// Simple gold background with a motion-reactive shine highlight.
/// Clean and flat — no concentric rings or cymbal texture.
struct GoldShineModifier: ViewModifier {
    @ObservedObject private var motion = MotionManager.shared

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.sacredGold

                    // Motion shine — follows device tilt
                    GeometryReader { geo in
                        let cx = (1 + motion.shineX) / 2 * geo.size.width
                        let cy = (1 - motion.shineY) / 2 * geo.size.height
                        RadialGradient(
                            stops: [
                                .init(color: .white.opacity(0.45), location: 0),
                                .init(color: .sacredGoldShine.opacity(0.25), location: 0.35),
                                .init(color: .clear, location: 0.7),
                            ],
                            center: UnitPoint(x: cx / geo.size.width, y: cy / geo.size.height),
                            startRadius: 0,
                            endRadius: max(geo.size.width, geo.size.height) * 0.6
                        )
                    }
                }
            )
    }
}

extension View {
    func goldShine() -> some View {
        modifier(GoldShineModifier())
    }
}

/// Reusable shiny gold gradients — metallic highlight for sacred elements.
extension LinearGradient {
    /// Shiny gold — horizontal with center highlight band
    static let sacredGoldShiny = LinearGradient(
        stops: [
            .init(color: .sacredGoldDark, location: 0),
            .init(color: .sacredGold, location: 0.3),
            .init(color: .sacredGoldShine, location: 0.5),
            .init(color: .sacredGold, location: 0.7),
            .init(color: .sacredGoldDark, location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Shiny gold — vertical variant for buttons
    static let sacredGoldShinyVertical = LinearGradient(
        stops: [
            .init(color: .sacredGoldDark, location: 0),
            .init(color: .sacredGold, location: 0.25),
            .init(color: .sacredGoldShine, location: 0.45),
            .init(color: .sacredGold, location: 0.7),
            .init(color: .sacredGoldDark, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Device motion for gold shine

/// Tracks device tilt via CoreMotion and exposes a shine angle + offset.
/// Shared singleton — starts/stops automatically based on observer count.
@MainActor
final class MotionManager: ObservableObject {
    static let shared = MotionManager()

    /// Angle in degrees where the shine highlight sits (0–360, clockwise from top).
    @Published var shineAngle: Angle = .degrees(0)
    /// Normalized X offset (-1...1) from device roll — for linear shine positioning.
    @Published var shineX: CGFloat = 0
    /// Normalized Y offset (-1...1) from device pitch.
    @Published var shineY: CGFloat = 0

    private let cm = CMMotionManager()
    private var observerCount = 0

    private init() {}

    func start() {
        observerCount += 1
        guard observerCount == 1, cm.isDeviceMotionAvailable, !cm.isDeviceMotionActive else { return }
        cm.deviceMotionUpdateInterval = 1.0 / 30 // 30 Hz — smooth but efficient
        cm.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            // roll = left/right tilt, pitch = forward/back tilt
            let roll = m.attitude.roll   // radians, ±π
            let pitch = m.attitude.pitch // radians, ±π/2

            // Map to a shine angle — roll dominates the circular position
            let angle = atan2(roll, -pitch)
            self.shineAngle = .radians(angle)
            self.shineX = max(-1, min(1, roll / .pi * 2))
            self.shineY = max(-1, min(1, pitch / (.pi / 2)))
        }
    }

    func stop() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        cm.stopDeviceMotionUpdates()
    }
}

/// A gold shine overlay for circular elements that follows device tilt.
/// The highlight spot orbits the ring as you move the phone.
struct GoldShineRing: View {
    @ObservedObject private var motion = MotionManager.shared
    let size: CGFloat
    let lineWidth: CGFloat
    /// How much of the ring is filled (0...1). Shine only appears on the filled portion.
    var progress: CGFloat = 1

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(
                    stops: shineStops,
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-90)) // match the ring's coordinate system
    }

    private var shineStops: [Gradient.Stop] {
        let center = normalizedAngle
        let spread: CGFloat = 0.12
        let peak: CGFloat = 0.04

        // Only show the shine if it falls within the filled portion
        let visible = center <= progress + spread
        guard visible else {
            return [Gradient.Stop(color: .clear, location: 0), Gradient.Stop(color: .clear, location: 1)]
        }

        let raw: [(Color, CGFloat)] = [
            (.clear, 0),
            (.clear, center - spread),
            (Color.sacredGoldShine.opacity(0.3), center - peak),
            (Color.white.opacity(0.45), center),
            (Color.sacredGoldShine.opacity(0.3), center + peak),
            (.clear, center + spread),
            (.clear, 1),
        ]

        return raw.map { color, loc in
            Gradient.Stop(color: color, location: max(0, min(1, loc)))
        }
    }

    /// Convert the motion angle to 0...1 range for AngularGradient
    private var normalizedAngle: CGFloat {
        let degrees = motion.shineAngle.degrees.truncatingRemainder(dividingBy: 360)
        let positive = degrees < 0 ? degrees + 360 : degrees
        return positive / 360
    }
}
