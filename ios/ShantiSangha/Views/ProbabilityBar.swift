import SwiftUI

/// Single horizontal capsule split into three width-proportional segments —
/// Buy (green), Hold (muted), Sell (red) — visualizing the model's
/// {pBuy, pHold, pSell} verdict distribution. Inputs are normalized before
/// rendering so callers can pass raw probabilities even if rounding pushes
/// the sum slightly off 1.0.
struct ProbabilityBar: View {
    let pBuy: Double
    let pHold: Double
    let pSell: Double
    var height: CGFloat = 14
    var showLabels: Bool = true

    /// Below this segment-width fraction we suppress the inline label to
    /// avoid cramping; the segment itself still renders.
    private static let labelMinFraction: Double = 0.08

    var body: some View {
        let normalized = Self.normalize(pBuy: pBuy, pHold: pHold, pSell: pSell)

        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    segment(width: w * normalized.buy, color: .sacredGreen)
                    segment(width: w * normalized.hold, color: .sacredMuted.opacity(0.55))
                    segment(width: w * normalized.sell, color: .sacredRed)
                }
                .frame(width: w, height: height)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.sacredGold.opacity(0.18), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.4), value: normalized.buy)
                .animation(.easeOut(duration: 0.4), value: normalized.hold)
                .animation(.easeOut(duration: 0.4), value: normalized.sell)
            }
            .frame(height: height)

            if showLabels {
                labelRow(normalized: normalized)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verdict probabilities")
        .accessibilityValue(
            String(
                format: "Buy %.0f percent, Hold %.0f percent, Sell %.0f percent",
                normalized.buy * 100, normalized.hold * 100, normalized.sell * 100
            )
        )
    }

    @ViewBuilder
    private func segment(width: CGFloat, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width))
    }

    @ViewBuilder
    private func labelRow(normalized: Normalized) -> some View {
        HStack(spacing: SacredSpacing.s) {
            label(for: normalized.buy, color: .sacredGreen)
            Spacer(minLength: 0)
            label(for: normalized.hold, color: .sacredMuted)
            Spacer(minLength: 0)
            label(for: normalized.sell, color: .sacredRed)
        }
        .font(.sacredCaption)
    }

    @ViewBuilder
    private func label(for fraction: Double, color: Color) -> some View {
        if fraction >= Self.labelMinFraction {
            Text("\(Int((fraction * 100).rounded()))%")
                .foregroundColor(color)
        } else {
            // Reserve space so the remaining labels don't jump as
            // probabilities animate across the threshold.
            Text(" ")
                .foregroundColor(.clear)
        }
    }

    // MARK: - Normalization

    private struct Normalized {
        let buy: Double
        let hold: Double
        let sell: Double
    }

    private static func normalize(pBuy: Double, pHold: Double, pSell: Double) -> Normalized {
        let b = max(0, pBuy)
        let h = max(0, pHold)
        let s = max(0, pSell)
        let total = b + h + s
        guard total > 0 else {
            return Normalized(buy: 0, hold: 0, sell: 0)
        }
        return Normalized(buy: b / total, hold: h / total, sell: s / total)
    }
}

#Preview {
    ZStack {
        SacredBackground().ignoresSafeArea()
        VStack(alignment: .leading, spacing: SacredSpacing.l) {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Confident Buy")
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                ProbabilityBar(pBuy: 0.75, pHold: 0.20, pSell: 0.05)
            }

            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Uncertain")
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                ProbabilityBar(pBuy: 0.40, pHold: 0.35, pSell: 0.25)
            }

            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Confident Sell")
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                ProbabilityBar(pBuy: 0.05, pHold: 0.25, pSell: 0.70)
            }
        }
        .padding(SacredSpacing.m)
    }
}
