import SwiftUI

struct WiseCatDetailView: View {
    let ticker: String

    @State private var signal: TradingSignal?
    @State private var loading = true
    @State private var error: String?
    @State private var selectedHorizon: WiseCatHorizon = .oneWeek
    /// Wall-clock of the most recent successful signal load (cache hydrate or
    /// network refresh). Drives the "refreshed N min ago" suffix on the as-of
    /// caption so the user can spot stale data while revalidation runs.
    @State private var refreshedAt: Date?

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
                        if let signal {
                            asOfCaption(signal)
                            horizonSelector(signal)
                            horizonCard(read: signal.read(for: selectedHorizon))
                        } else if loading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 200)
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
        .task {
            hydrateFromCache()
            await load()
        }
    }

    /// Paints the cached signal synchronously so the page doesn't show a
    /// spinner on reopen. The network refresh runs right after via `load()`,
    /// stale-while-revalidate.
    private func hydrateFromCache() {
        guard let cached = WiseCatCache.loadSignal(ticker: ticker) else { return }
        signal = cached.signal
        refreshedAt = cached.refreshedAt
        loading = false
    }

    private func load() async {
        // Don't flip `loading` back to true if we already have cached data —
        // that would trigger the spinner branch and hide the content. Only
        // first-load (no cache) keeps the spinner.
        if signal == nil { loading = true }
        defer { loading = false }
        do {
            let fresh = try await WiseCatAPI.getSignal(ticker)
            self.signal = fresh
            self.refreshedAt = Date()
            self.error = nil
            WiseCatCache.saveSignal(ticker: ticker, signal: fresh, refreshedAt: Date())
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - As-of caption

    /// Tells the user the scores below reflect data through the last EOD
    /// close — explains the disconnect between the live chart above and a
    /// gauge that doesn't tick intraday. Falls back to the signal's
    /// calendar date for legacy responses that predate `lastBarDate`.
    /// Suffixes a "refreshed …" relative time so the user can tell when the
    /// view is showing cached data vs. a just-completed network revalidation.
    private func asOfCaption(_ s: TradingSignal) -> some View {
        let raw = s.lastBarDate ?? s.date
        let body = "Scores as of \(formatAsOf(raw))"
        // TimelineView re-renders this Text every minute so the relative time
        // ticks forward without any manual Timer plumbing. When `refreshedAt`
        // is nil (first-load before the cache or network resolved) the suffix
        // is suppressed.
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            let suffix = refreshedAt.map {
                " · refreshed \(formatRefreshed($0, now: context.date))"
            } ?? ""
            Text(body + suffix)
                .font(.sacredCaption)
                .foregroundColor(.sacredMuted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func formatRefreshed(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func formatAsOf(_ ymd: String) -> String {
        guard let date = Self.ymdParser.date(from: ymd) else { return ymd }
        return Self.asOfDisplay.string(from: date)
    }

    private static let ymdParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let asOfDisplay: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMM d"
        return f
    }()

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
                // Drivers table = top-8 GBM feature attributions
                // (weight = share of explanation magnitude, score = signed
                // push toward Buy/Sell).
                Divider()
                    .background(Color.sacredMuted.opacity(0.2))
                technicalBlock(read: read)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SacredSpacing.lux)
        }
    }

    /// Verdict label + a three-segment probability bar that visualizes the
    /// GBM's actual uncertainty (pBuy / pHold / pSell carries strictly more
    /// information than a single conviction scalar).
    private func horizonHero(read: HorizonRead) -> some View {
        let action = WiseCatAction.from(read.action)
        return VStack(spacing: SacredSpacing.s) {
            Text(read.action)
                .font(.sacredHeading)
                .foregroundColor(actionColor(action))
            ProbabilityBar(
                pBuy: read.pBuy ?? 0,
                pHold: read.pHold ?? 1,
                pSell: read.pSell ?? 0,
                height: 16
            )
            .frame(maxWidth: 280)
            if let er = read.expectedReturn {
                Text(String(format: "Expected return %+.2f%%", er * 100))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
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
                title: "Drivers",
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
        // GBM features emitted by `compute_all_features`. Each base strategy
        // contributes both `_raw` (unsaturated gap) and `_value` (saturated
        // [-1,+1] score); we label them with a parenthetical so the user can
        // tell which flavor drove the row when both surface.
        switch raw {
        // GBM base technicals (raw + saturated)
        case "trend_50_200_raw":       return "Trend gap (50/200 EMA)"
        case "trend_50_200_value":     return "Trend score (50/200 EMA)"
        case "ts_momentum_12_1_raw":   return "12-1 momentum return"
        case "ts_momentum_12_1_value": return "12-1 momentum score"
        case "fast_trend_5_20_raw":    return "Fast trend gap (5/20)"
        case "fast_trend_5_20_value":  return "Fast trend score (5/20)"

        // GBM cross-sectional return spreads vs SPY
        case "xs_return_spread_3m_vs_spy": return "3-month return vs SPY"
        case "xs_return_spread_6m_vs_spy": return "6-month return vs SPY"
        case "xs_return_spread_1y_vs_spy": return "1-year return vs SPY"

        // GBM earnings window
        case "days_since_earnings":        return "Days since earnings"
        case "days_to_earnings":           return "Days to earnings"
        case "post_earnings_drift_signal": return "Post-earnings drift"

        // GBM calendar
        case "month_of_year":         return "Month of year"
        case "day_of_week":            return "Day of week"
        case "january_effect_flag":    return "January effect"
        case "quarter_end_proximity":  return "Days to quarter end"

        // GBM range / candle shape
        case "range_position_today":   return "Close within day's range"
        case "range_position_5d_avg":  return "Close within range (5d avg)"
        case "body_to_atr_ratio":      return "Body size vs ATR"
        case "upper_wick_pct":         return "Upper wick share"
        case "lower_wick_pct":         return "Lower wick share"

        // GBM VIX regime
        case "vix_level":         return "VIX level"
        case "vix_change_21d":    return "VIX 21-day change"
        case "vix_zscore_252d":   return "VIX vs 1-year average"

        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
