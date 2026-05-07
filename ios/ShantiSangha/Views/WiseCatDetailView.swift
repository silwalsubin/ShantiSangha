import SwiftUI

struct WiseCatDetailView: View {
    let ticker: String

    @State private var signal: TradingSignal?
    @State private var loading = true
    @State private var error: String?

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
                            actionSummary(signal)
                            technicalBlock(signal)
                            astroBlock(signal)
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

    private func actionSummary(_ s: TradingSignal) -> some View {
        let action = WiseCatAction.from(s.action)
        let color: Color = {
            switch action {
            case .buy: return .sacredGreen
            case .sell: return .sacredRed
            case .hold: return .sacredText
            }
        }()
        return LuxCard {
            VStack(spacing: SacredSpacing.s) {
                Text("Today's call")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                ConvictionMeter(
                    conviction: s.conviction,
                    color: color,
                    label: s.action,
                    diameter: 140,
                    lineWidth: 8,
                    labelFont: .sacredHeading,
                    labelPosition: .diameterLine
                )
                Text(String(format: "Composite %+.2f", s.compositeScore))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(SacredSpacing.lux)
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value > 0.1 { return .sacredGreen }
        if value < -0.1 { return .sacredRed }
        return .sacredText
    }

    private func technicalBlock(_ s: TradingSignal) -> some View {
        // Sort by weight desc so the strategies driving the composite
        // surface first. Weights were chosen from a 16y SPY backtest:
        // trend + TS momentum had real edge (54-55% hit rate, n≈4100);
        // RSI / Bollinger / volume were ≤ coin flip and got down-weighted.
        let sorted = s.technicalSignals.sorted { $0.weight > $1.weight }

        return LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                sectionHeader(
                    title: "Technical",
                    weightInComposite: 0.6,
                    score: s.technicalScore
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
            .padding(SacredSpacing.lux)
        }
    }

    private func sectionHeader(title: String, weightInComposite: Double, score: Double) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Spacer()
                Text(String(format: "%+.2f", score))
                    .font(.sacredSubheading)
                    .foregroundColor(scoreColor(score))
            }
            Text(String(format: "%.0f%% weight in composite", weightInComposite * 100))
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
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

    private func astroBlock(_ s: TradingSignal) -> some View {
        let stockChart = s.astroAngles.first(where: { $0.angle == "stock_natal" })
        let hasStockData = stockChart != nil
            && !(stockChart?.highlights.first == "no data")
            && !(stockChart?.highlights.isEmpty ?? true)

        return LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                sectionHeader(
                    title: "Astrological",
                    weightInComposite: 0.4,
                    score: s.astroScore
                )

                if let stockChart, hasStockData {
                    VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                        Text("Transits to \(ticker)'s IPO chart")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        ForEach(stockChart.highlights, id: \.self) { h in
                            Text("· \(h)")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                    }
                    .padding(.top, SacredSpacing.xxs)
                } else {
                    Text("Today's read for this stock comes from your transits and the panchang — see Today's sky on the Stocks page.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .padding(.top, SacredSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SacredSpacing.lux)
        }
    }

    private func prettyStrategyName(_ raw: String) -> String {
        switch raw {
        case "trend_50_200": return "Trend (50/200 EMA)"
        case "rsi_14": return "Momentum (RSI-14)"
        case "bollinger_pctb": return "Mean reversion (Bollinger)"
        case "volume_confirm": return "Volume confirmation"
        case "ts_momentum_12_1": return "Time-series momentum (12-1)"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

}
