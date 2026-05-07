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
                            scoresBlock(signal)
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
            case .buy: return .sacredGold
            case .sell: return .sacredGoldDark
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
                    labelFont: .sacredHeading
                )
            }
            .frame(maxWidth: .infinity)
            .padding(SacredSpacing.lux)
        }
    }

    private func scoresBlock(_ s: TradingSignal) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("Scores")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                scoreRow("Technical", s.technicalScore)
                scoreRow("Astrological", s.astroScore)
                scoreRow("Composite", s.compositeScore)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func scoreRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
            Spacer()
            Text(String(format: "%+.2f", value))
                .font(.sacredTextMedium)
                .foregroundColor(value > 0.1 ? .sacredGold : value < -0.1 ? .sacredGoldDark : .sacredText)
        }
    }

    private func technicalBlock(_ s: TradingSignal) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("Technical")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                if s.technicalSignals.isEmpty {
                    Text("No strategies fired today.")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                } else {
                    ForEach(s.technicalSignals, id: \.name) { sig in
                        HStack(alignment: .firstTextBaseline) {
                            Text(prettyStrategyName(sig.name))
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                            Spacer()
                            Text(String(format: "%+.2f", sig.contribution))
                                .font(.sacredCaption)
                                .foregroundColor(.sacredTextSecondary)
                        }
                    }
                }
            }
            .padding(SacredSpacing.lux)
        }
    }

    @ViewBuilder
    private func astroBlock(_ s: TradingSignal) -> some View {
        let stockChart = s.astroAngles.first(where: { $0.angle == "stock_natal" })
        let hasData = stockChart != nil
            && !(stockChart?.highlights.first == "no data")
            && !(stockChart?.highlights.isEmpty ?? true)

        if let stockChart, hasData {
            LuxCard {
                VStack(alignment: .leading, spacing: SacredSpacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Stock chart")
                            .font(.sacredSubheading)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Text(String(format: "%+.2f", stockChart.score))
                            .font(.sacredCaption)
                            .foregroundColor(.sacredTextSecondary)
                    }
                    Text("Transits to \(ticker)'s IPO chart")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                    ForEach(stockChart.highlights, id: \.self) { h in
                        Text("· \(h)")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
                .padding(SacredSpacing.lux)
            }
        }
    }

    private func prettyStrategyName(_ raw: String) -> String {
        switch raw {
        case "trend_50_200": return "Trend (50/200 EMA)"
        case "rsi_14": return "Momentum (RSI-14)"
        case "bollinger_pctb": return "Mean reversion (Bollinger)"
        case "volume_confirm": return "Volume confirmation"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

}
