import SwiftUI

/// Sacred progress ring — the gold-stroked circle the Home tab uses for
/// "Practices" and "Goals". Built on top of `GoldShineRing` so the filled
/// portion picks up device tilt.
///
/// Pass `detail` instead of a count when the ring should show a textual
/// summary (e.g. "1 carried over • 1 due today"). When `isComplete` is true
/// a checkmark replaces the "of N" label and a soft pulse glow is enabled.
struct SacredProgressRing: View {
    let label: String
    /// SF Symbol name shown next to the label.
    let icon: String
    let done: Int
    let total: Int
    /// Stroke color of the filled arc. Falls back to gold when `almostDone`.
    let color: Color
    var detail: String? = nil
    var isComplete: Bool = false
    var almostDone: Bool = false
    var ringPulse: Bool = false
    var size: CGFloat = 118
    var lineWidth: CGFloat = 10

    var body: some View {
        let progress = total > 0 ? Double(done) / Double(total) : 0
        let strokeColor = almostDone ? Color.sacredGold : color

        VStack(spacing: 14) {
            ZStack {
                // Completion glow — soft radial behind the ring
                if isComplete && ringPulse {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: size + 32, height: size + 32)
                        .blur(radius: 12)
                }

                // Track
                Circle()
                    .stroke(Color.sacredMuted.opacity(0.12), lineWidth: lineWidth)

                // Progress arc
                if done > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [strokeColor.opacity(0.7), strokeColor, strokeColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: progress)
                }

                // Motion-reactive shine on the filled arc
                if done > 0 {
                    GoldShineRing(size: size, lineWidth: lineWidth, progress: progress)
                }

                centerLabel(strokeColor: strokeColor)
            }
            .frame(width: size, height: size)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                Text(label)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredTextSecondary)
            }
        }
    }

    @ViewBuilder
    private func centerLabel(strokeColor: Color) -> some View {
        VStack(spacing: 2) {
            if let detail {
                Text(detail)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("\(done)")
                    .font(.sacredProgressNumber)
                    .foregroundColor(done > 0 ? strokeColor : .sacredMuted)
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.sacredGlyph)
                        .foregroundColor(color.opacity(0.7))
                } else {
                    Text("of \(total)")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
    }
}
