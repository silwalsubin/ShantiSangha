import SwiftUI

struct ConvictionMeter: View {
    let conviction: Double
    let color: Color
    var label: String? = nil
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 5
    var labelFont: Font = .sacredButtonLabel
    /// Where the label sits relative to the arc.
    /// `.upperHalf` (default) — centered inside the upper half of the arc,
    /// matches the detail-view hero meter.
    /// `.diameterLine` — center aligns with the line connecting the arc's
    /// two endpoints, used by the row-list layout where the label needs to
    /// share the row's horizontal baseline.
    var labelPosition: LabelPosition = .upperHalf

    enum LabelPosition { case upperHalf, diameterLine }

    var body: some View {
        let value = max(0, min(1, conviction))
        let labelOffset: CGFloat = {
            switch labelPosition {
            case .upperHalf: return -(diameter - lineWidth) / 4
            case .diameterLine: return 0
            }
        }()
        // When the label sits on the diameter line, half of it spills below
        // the arc area — claim that space in the layout box so it doesn't
        // overlap whatever is rendered below.
        let extraBelow: CGFloat = labelPosition == .diameterLine ? 10 : 0

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
                    .offset(y: labelOffset)
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(width: diameter, height: diameter / 2 + lineWidth + extraBelow, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Conviction")
        .accessibilityValue(String(format: "%.0f percent", value * 100))
    }
}
