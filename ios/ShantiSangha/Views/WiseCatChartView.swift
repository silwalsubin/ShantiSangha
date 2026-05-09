import Charts
import SwiftUI

/// Stock price chart for a ticker. Range selector, 52w / all-time stats, and
/// a tap-to-inspect crosshair. yfinance-backed via the wisecat Lambda.
struct WiseCatChartView: View {
    let ticker: String

    // Per-range cache so range switches feel instant after the initial
    // prefetch lands. Also tracks loading + error state per range so the
    // currently selected range's UI is independent of the others.
    @State private var charts: [ChartRange: ChartHistory] = [:]
    @State private var loadingRanges: Set<ChartRange> = []
    @State private var errors: [ChartRange: String] = [:]
    @State private var range: ChartRange = .intraday
    @State private var selectedDate: Date?
    @State private var statsExpanded = false

    private var chart: ChartHistory? { charts[range] }
    private var error: String? { errors[range] }
    private var isLoadingCurrent: Bool { loadingRanges.contains(range) }

    var body: some View {
        // chartArea spans full width; surrounding text/buttons stay inset so
        // they don't touch the screen edges.
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            headline
                .padding(.horizontal, SacredSpacing.m)

            chartArea

            rangeSelector
                .padding(.horizontal, SacredSpacing.m)

            statsCard
                .padding(.horizontal, SacredSpacing.m)
        }
        .task { await prefetchAll() }
    }

    /// Renders one of: chart, loading spinner, or empty/error message — but
    /// never shows a giant blank region with tiny text in the middle.
    @ViewBuilder
    private var chartArea: some View {
        if let bars = chart?.bars, !bars.isEmpty {
            chartCanvas
                .frame(height: 200)
        } else if isLoadingCurrent {
            ProgressView()
                .tint(.sacredGold)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            chartUnavailable
        }
    }

    private var chartUnavailable: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text("Chart unavailable")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Text(error ?? "No price history could be loaded for \(ticker).")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SacredSpacing.s)
    }

    // MARK: - Headline

    @ViewBuilder
    private var headline: some View {
        if let chart {
            if let selected = selectedBar {
                selectedReadout(selected)
            } else {
                headlineReadout(chart)
            }
        }
    }

    private func headlineReadout(_ chart: ChartHistory) -> some View {
        // Intraday: prefer the most recent bar (which may be extended-hours)
        // so the headline reflects the *actual* last trade. Aggregates are
        // computed from the daily series and would lag by hours during
        // pre-market or after-hours.
        let current: Double = {
            if range.isIntraday, let last = chart.bars.last?.close {
                return last
            }
            return chart.aggregates?.currentPrice ?? chart.bars.last?.close ?? 0
        }()
        let baseline = baselineForRange(chart) ?? current
        let change = current - baseline
        let changePct = baseline != 0 ? (change / baseline) * 100 : 0
        let color: Color = change > 0 ? .sacredGreen : change < 0 ? .sacredRed : .sacredText

        return VStack(alignment: .leading, spacing: 2) {
            Text(formatPrice(current))
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)
            HStack(spacing: SacredSpacing.xs) {
                Text(String(format: "%@%.2f", change >= 0 ? "+" : "", change))
                    .font(.sacredSmallSemibold)
                    .foregroundColor(color)
                Text(String(format: "%@%.2f%%", change >= 0 ? "+" : "", changePct))
                    .font(.sacredSmallSemibold)
                    .foregroundColor(color)
                Text(rangeLabel)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        }
    }

    private func baselineForRange(_ chart: ChartHistory) -> Double? {
        if range.isIntraday, let prev = chart.aggregates?.previousClose {
            return prev
        }
        return chart.bars.first?.close
    }

    private var rangeLabel: String {
        switch range {
        case .intraday: return "today"
        case .oneWeek: return "past week"
        case .oneMonth: return "past month"
        case .threeMonth: return "past 3 months"
        case .ytd: return "year to date"
        case .oneYear: return "past year"
        case .fiveYear: return "past 5 years"
        case .max: return "all time"
        }
    }

    private func selectedReadout(_ bar: ChartBar) -> some View {
        let timeLabel: String = {
            guard range.isIntraday else { return formatLongDate(bar.parsedDate) }
            let base = formatTime(bar.parsedDate)
            if let suffix = bar.extendedHoursLabel { return "\(base) · \(suffix)" }
            return base
        }()
        return VStack(alignment: .leading, spacing: 2) {
            Text(formatPrice(bar.close))
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)
            Text(timeLabel)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
        }
    }

    // MARK: - Stats card (collapsible, below the chart)

    @ViewBuilder
    private var statsCard: some View {
        if let agg = chart?.aggregates {
            LuxCard {
                VStack(alignment: .leading, spacing: SacredSpacing.s) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            statsExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Stats")
                                .font(.sacredSubheading)
                                .foregroundColor(.sacredText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                                .rotationEffect(.degrees(statsExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if statsExpanded {
                        VStack(spacing: SacredSpacing.xs) {
                            statRow("52-week high", agg.weekHigh52.map { formatPrice($0) } ?? "—")
                            statRow("52-week low", agg.weekLow52.map { formatPrice($0) } ?? "—")
                            statRow("All-time high", formatPrice(agg.allTimeHigh))
                            statRow("All-time low", formatPrice(agg.allTimeLow))
                            if let today = todaysOHLCV {
                                statRow("Today's open", formatPrice(today.open))
                                statRow("Today's high", formatPrice(today.high))
                                statRow("Today's low", formatPrice(today.low))
                                statRow("Today's volume", formatVolume(today.volume))
                            }
                            // Avg-volume rolling window only makes sense with
                            // daily bars; intraday's last 20 bars = 100 min.
                            if !range.isIntraday, let avg = avgVolume20 {
                                statRow("Avg volume (20d)", formatVolume(avg))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(SacredSpacing.lux)
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
            Spacer()
            Text(value)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)
        }
    }

    private var avgVolume20: Int? {
        guard let bars = chart?.bars, bars.count >= 20 else { return nil }
        let last20 = bars.suffix(20)
        let total = last20.reduce(0) { $0 + $1.volume }
        return total / last20.count
    }

    /// Today's OHLCV — derived differently per range. In 1D mode the rendered
    /// bars *are* today's intraday session, so open is the first bar and
    /// high/low/volume aggregate across all bars. In daily modes the last bar
    /// IS today, so use it directly.
    private var todaysOHLCV: (open: Double, high: Double, low: Double, volume: Int)? {
        guard let bars = chart?.bars, !bars.isEmpty else { return nil }
        if range.isIntraday {
            let open = bars.first!.open
            let high = bars.map(\.high).max() ?? open
            let low = bars.map(\.low).min() ?? open
            let volume = bars.reduce(0) { $0 + $1.volume }
            return (open, high, low, volume)
        }
        let last = bars.last!
        return (last.open, last.high, last.low, last.volume)
    }

    private func formatVolume(_ v: Int) -> String {
        let d = Double(v)
        if d >= 1_000_000_000 { return String(format: "%.2fB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.1fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.0fK", d / 1_000) }
        return String(v)
    }

    // MARK: - Chart canvas

    private var chartCanvas: some View {
        let bars = chart?.bars ?? []
        let split = splitForExtendedHours(bars)
        let extendedDash = StrokeStyle(lineWidth: 2, dash: [3, 3])
        let solid = StrokeStyle(lineWidth: 2)
        return Chart {
            // Regular-session — solid gold line. No area fill (Apple Stocks
            // intraday is line-only; the area gradient created a visible
            // vertical band where the regular hours started/ended that read
            // as a UI artifact, not a chart feature).
            ForEach(split.regular) { bar in
                LineMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close),
                    series: .value("Series", "regular")
                )
                .foregroundStyle(Color.sacredGold)
                .lineStyle(solid)
                .interpolationMethod(.linear)
            }

            // Pre-market — same color, dashed stroke. Bridged into the
            // regular open via splitForExtendedHours so the segments
            // visually connect at the boundary.
            ForEach(split.preMarket) { bar in
                LineMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close),
                    series: .value("Series", "extended-pre")
                )
                .foregroundStyle(Color.sacredGold)
                .lineStyle(extendedDash)
                .interpolationMethod(.linear)
            }

            // After-hours — same treatment.
            ForEach(split.afterHours) { bar in
                LineMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close),
                    series: .value("Series", "extended-post")
                )
                .foregroundStyle(Color.sacredGold)
                .lineStyle(extendedDash)
                .interpolationMethod(.linear)
            }

            if let selectedDate, let bar = selectedBar {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(Color.sacredMuted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close)
                )
                .foregroundStyle(Color.sacredGold)
                .symbolSize(70)
            }
        }
        .chartYScale(domain: yDomain(bars))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedDate)
    }

    private struct ExtendedSplit {
        let regular: [ChartBar]
        let preMarket: [ChartBar]   // pre-market bars + first regular bar (bridge)
        let afterHours: [ChartBar]  // last regular bar (bridge) + after-hours bars
    }

    /// Splits 1D intraday bars into regular vs. extended-hours segments. The
    /// extended segments include one regular bar at the boundary so the
    /// faded line visually connects to the solid line. Daily ranges return
    /// everything in `regular` and leave the extended segments empty.
    private func splitForExtendedHours(_ bars: [ChartBar]) -> ExtendedSplit {
        guard range.isIntraday, bars.contains(where: { $0.extendedHours == true }) else {
            return ExtendedSplit(regular: bars, preMarket: [], afterHours: [])
        }
        let regular = bars.filter { $0.extendedHours != true }

        var preMarket = bars.filter { $0.extendedHoursLabel == "pre-market" }
        if let firstRegular = regular.first { preMarket.append(firstRegular) }

        var afterHours: [ChartBar] = []
        if let lastRegular = regular.last { afterHours.append(lastRegular) }
        afterHours += bars.filter { $0.extendedHoursLabel == "after hours" }

        return ExtendedSplit(regular: regular, preMarket: preMarket, afterHours: afterHours)
    }

    private func yDomain(_ bars: [ChartBar]) -> ClosedRange<Double> {
        guard let lo = bars.map(\.close).min(),
              let hi = bars.map(\.close).max() else { return 0...1 }
        let span = hi - lo
        let pad = span > 0 ? span * 0.08 : max(hi * 0.005, 0.5)
        return (lo - pad)...(hi + pad)
    }

    // MARK: - Range selector

    private var rangeSelector: some View {
        HStack(spacing: SacredSpacing.xxs) {
            ForEach(ChartRange.allCases) { r in
                Button {
                    range = r
                    selectedDate = nil
                    if charts[r] == nil {
                        Task { await load(r) }
                    }
                } label: {
                    Text(r.label)
                        .font(.sacredTextMedium)
                        .foregroundColor(r == range ? .sacredGold : .sacredMuted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: SacredRadius.pill)
                                .fill(r == range ? Color.sacredGold.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SacredRadius.pill)
                                .stroke(r == range ? Color.sacredGold.opacity(0.45) : Color.sacredMutedLight.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var selectedBar: ChartBar? {
        guard let selectedDate, let bars = chart?.bars, !bars.isEmpty else { return nil }
        return bars.min(by: { abs($0.parsedDate.timeIntervalSince(selectedDate)) < abs($1.parsedDate.timeIntervalSince(selectedDate)) })
    }

    /// Fetches every range in parallel so range switches feel instant. The
    /// selected range fires first; the rest race behind it. `load(_:)` is
    /// idempotent — already-cached or already-in-flight ranges no-op.
    private func prefetchAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await load(range) }
            for r in ChartRange.allCases where r != range {
                group.addTask { await load(r) }
            }
        }
    }

    private func load(_ r: ChartRange) async {
        if charts[r] != nil { return }
        if loadingRanges.contains(r) { return }
        loadingRanges.insert(r)
        defer { loadingRanges.remove(r) }
        do {
            let result = try await WiseCatAPI.getChart(ticker, range: r)
            charts[r] = result
            errors[r] = nil
        } catch {
            if error.isCancellation { return }
            errors[r] = error.localizedDescription
        }
    }

    private func formatPrice(_ v: Double) -> String {
        if v >= 1000 {
            return String(format: "$%,.0f", v)
        }
        return String(format: "$%.2f", v)
    }

    private func formatLongDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    private func formatTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}
