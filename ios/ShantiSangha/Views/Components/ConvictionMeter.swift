import SwiftUI

struct ConvictionMeter: View {
    let conviction: Double
    let color: Color
    var label: String? = nil
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 5
    var labelFont: Font = .sacredButtonLabel

    var body: some View {
        let value = max(0, min(1, conviction))
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(
                    Color.sacredMuted.opacity(0.22),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0.5, to: 0.5 + 0.5 * value)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            if let label {
                Text(label)
                    .font(labelFont)
                    .foregroundColor(color)
                    .offset(y: -(diameter - lineWidth) / 4)
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(width: diameter, height: diameter / 2 + lineWidth, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Conviction")
        .accessibilityValue(String(format: "%.0f percent", value * 100))
    }
}
