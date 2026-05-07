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
                            alignmentStrip(signal)
                            ForEach(WiseCatHorizon.allCases) { horizon in
                                horizonCard(horizon: horizon, read: signal.read(for: horizon))
                            }
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

    // MARK: - Alignment strip

    /// One-line summary of all three horizons' verdicts so divergence reads
    /// without scrolling. Example: "1W Hold · 1M Sell · 1Y Sell".
    private func alignmentStrip(_ s: TradingSignal) -> some View {
        HStack(spacing: SacredSpacing.s) {
            ForEach(WiseCatHorizon.allCases) { horizon in
                let read = s.read(for: horizon)
                let action = WiseCatAction.from(read.action)
                HStack(spacing: SacredSpacing.xxs) {
                    Text(horizon.label)
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                    Text(read.action)
                        .font(.sacredCaption)
                        .foregroundColor(actionColor(action))
                }
                if horizon != WiseCatHorizon.allCases.last {
                    Text("·")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One horizon card

    private func horizonCard(horizon: WiseCatHorizon, read: HorizonRead) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.l) {
                horizonHero(horizon: horizon, read: read)
                Divider()
                    .background(Color.sacredMuted.opacity(0.2))
                technicalBlock(read: read)
                Divider()
                    .background(Color.sacredMuted.opacity(0.2))
                astroBlock(read: read, angles: signal?.astroAngles ?? [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SacredSpacing.lux)
        }
    }

    private func horizonHero(horizon: WiseCatHorizon, read: HorizonRead) -> some View {
        let action = WiseCatAction.from(read.action)
        return VStack(spacing: SacredSpacing.s) {
            Text(horizon.label.uppercased())
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
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

    // MARK: - Technical / Astro blocks

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
                weightInComposite: 0.6,
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

    private func astroBlock(read: HorizonRead, angles: [AstroAngleScore]) -> some View {
        let stockChart = angles.first(where: { $0.angle == "stock_natal" })
        let hasStockData = stockChart != nil
            && !(stockChart?.highlights.first == "no data")
            && !(stockChart?.highlights.isEmpty ?? true)

        return VStack(alignment: .leading, spacing: SacredSpacing.s) {
            sectionHeader(
                title: "Astrological",
                weightInComposite: 0.4,
                score: read.astroScore
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
