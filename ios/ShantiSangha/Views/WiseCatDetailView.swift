import SwiftUI

struct WiseCatDetailView: View {
    let ticker: String

    @State private var signal: TradingSignal?
    @State private var loading = true
    @State private var error: String?
    @State private var selectedHorizon: WiseCatHorizon = .oneWeek

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: SacredSpacing.l) {
                    // Chart loads independently — kicks off as soon as the view
                    // appears, in parallel with the signal fetch. Owns its own
                    // internal padding so the canvas can extend edge to edge.
                    WiseCatChartView(ticker: ticker)

                    // Non-chart content stays at the standard inset.
                    VStack(alignment: .leading, spacing: SacredSpacing.l) {
                        if loading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else if let signal {
                            horizonSelector(signal)
                            horizonCard(read: signal.read(for: selectedHorizon))
                        } else if let error {
                            Text(error)
                                .font(.sacredText)
                                .foregroundColor(.sacredRed)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                }
                .padding(.top, SacredSpacing.l)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
            .refreshable { await load() }
        }
        .navigationTitle(ticker)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            self.signal = try await WiseCatAPI.getSignal(ticker)
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Horizon selector

    /// Three pills — one per horizon — each showing that horizon's verdict
    /// in its action color. Tap to swap which horizon's card is rendered
    /// below; divergence still reads at a glance from the strip itself.
    private func horizonSelector(_ s: TradingSignal) -> some View {
        HStack(spacing: SacredSpacing.xxs) {
            ForEach(WiseCatHorizon.allCases) { horizon in
                let read = s.read(for: horizon)
                let action = WiseCatAction.from(read.action)
                let isSelected = horizon == selectedHorizon

                Button {
                    selectedHorizon = horizon
                } label: {
                    HStack(spacing: SacredSpacing.xxs) {
                        Text(horizon.label)
                            .font(.sacredTextMedium)
                            .foregroundColor(isSelected ? .sacredGold : .sacredMuted)
                        Text(read.action)
                            .font(.sacredTextMedium)
                            .foregroundColor(actionColor(action))
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(
                        RoundedRectangle(cornerRadius: SacredRadius.pill)
                            .fill(isSelected ? Color.sacredGold.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SacredRadius.pill)
                            .stroke(
                                isSelected ? Color.sacredGold.opacity(0.45)
                                           : Color.sacredMutedLight.opacity(0.25),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - One horizon card

    private func horizonCard(read: HorizonRead) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.l) {
                horizonHero(read: read)
                Divider()
                    .background(Color.sacredMuted.opacity(0.2))
                technicalBlock(read: read)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SacredSpacing.lux)
        }
    }

    private func horizonHero(read: HorizonRead) -> some View {
        let action = WiseCatAction.from(read.action)
        return VStack(spacing: SacredSpacing.s) {
            ConvictionMeter(
                conviction: read.conviction,
                color: actionColor(action),
                label: read.action,
                diameter: 120,
                lineWidth: 7,
                labelFont: .sacredHeading,
                labelPosition: .diameterLine
            )
            Text(String(format: "Composite %+.2f", read.compositeScore))
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Technical block

    private func technicalBlock(read: HorizonRead) -> some View {
        // Sort by weight desc so the strategies driving this horizon's
        // composite surface first. Hide rows where weight is exactly 0
        // (e.g. short_5d_return at 1Y, long_52w_distance at 1W) — they
        // contribute nothing and are visual noise.
        let sorted = read.technicalSignals
            .filter { $0.weight > 0 }
            .sorted { $0.weight > $1.weight }

        return VStack(alignment: .leading, spacing: SacredSpacing.s) {
            sectionHeader(
                title: "Technical",
                score: read.technicalScore
            )

            if !sorted.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: SacredSpacing.s) {
                    Spacer()
                    Text("weight")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 44, alignment: .trailing)
                    Text("score")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 56, alignment: .trailing)
                }
                .padding(.top, SacredSpacing.xxs)
            }

            if sorted.isEmpty {
                Text("No strategies fired today.")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
            } else {
                ForEach(sorted, id: \.name) { sig in
                    technicalRow(sig)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func actionColor(_ action: WiseCatAction) -> Color {
        switch action {
        case .buy:  return .sacredGreen
        case .sell: return .sacredRed
        case .hold: return .sacredText
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value > 0.1 { return .sacredGreen }
        if value < -0.1 { return .sacredRed }
        return .sacredText
    }

    private func sectionHeader(title: String, score: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Spacer()
            Text(String(format: "%+.2f", score))
                .font(.sacredSubheading)
                .foregroundColor(scoreColor(score))
        }
    }

    private func technicalRow(_ sig: StrategyContribution) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SacredSpacing.s) {
            Text(prettyStrategyName(sig.name))
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f%%", sig.weight * 100))
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
                .frame(width: 44, alignment: .trailing)
            Text(String(format: "%+.2f", sig.contribution))
                .font(.sacredCaption)
                .foregroundColor(.sacredTextSecondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func prettyStrategyName(_ raw: String) -> String {
        // Active ensemble = trend_50_200 + ts_momentum_12_1. The legacy
        // oscillator names are kept as a fallback in case they're re-enabled
        // by a future basket tune; they're filtered out of the UI today via
        // the weight > 0 check above.
        switch raw {
        case "trend_50_200":      return "Trend (50/200 EMA)"
        case "ts_momentum_12_1":  return "Time-series momentum (12-1)"
        case "rsi_14":            return "Momentum (RSI-14)"
        case "bollinger_pctb":    return "Mean reversion (Bollinger)"
        case "volume_confirm":    return "Volume confirmation"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
