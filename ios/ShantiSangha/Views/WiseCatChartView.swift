import Charts
import SwiftUI

/// Stock price chart for a ticker. Range selector, 52w / all-time stats, and
/// a tap-to-inspect crosshair. yfinance-backed via the wisecat Lambda.
struct WiseCatChartView: View {
    let ticker: String

    @State private var chart: ChartHistory?
    @State private var range: ChartRange = .oneYear
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDate: Date?
    @State private var statsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            headline

            chartArea

            rangeSelector

            statsCard
        }
        .task { await load(range) }
    }

    /// Renders one of: chart, loading spinner, or empty/error message — but
    /// never shows a giant blank region with tiny text in the middle.
    @ViewBuilder
    private var chartArea: some View {
        if loading && (chart?.bars.isEmpty ?? true) {
            ProgressView()
                .tint(.sacredGold)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let bars = chart?.bars, !bars.isEmpty {
            chartCanvas
                .frame(height: 200)
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
        if let agg = chart?.aggregates {
            if let selected = selectedBar {
                selectedReadout(selected)
            } else {
                headlineReadout(agg)
            }
        }
    }

    private func headlineReadout(_ agg: ChartAggregates) -> some View {
        let prev = agg.previousClose ?? agg.currentPrice
        let change = agg.currentPrice - prev
        let changePct = prev != 0 ? (change / prev) * 100 : 0
        let color: Color = change > 0 ? .sacredGold : change < 0 ? .sacredGoldDark : .sacredText

        return VStack(alignment: .leading, spacing: 2) {
            Text(formatPrice(agg.currentPrice))
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)
            HStack(spacing: SacredSpacing.xs) {
                Text(String(format: "%@%.2f", change >= 0 ? "+" : "", change))
                    .font(.sacredSmallSemibold)
                    .foregroundColor(color)
                Text(String(format: "%@%.2f%%", change >= 0 ? "+" : "", changePct))
                    .font(.sacredSmallSemibold)
                    .foregroundColor(color)
                Text("today")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        }
    }

    private func selectedReadout(_ bar: ChartBar) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formatPrice(bar.close))
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredText)
            Text(formatLongDate(bar.parsedDate))
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
                            if let lastBar = chart?.bars.last {
                                statRow("Today's open", formatPrice(lastBar.open))
                                statRow("Today's high", formatPrice(lastBar.high))
                                statRow("Today's low", formatPrice(lastBar.low))
                                statRow("Today's volume", formatVolume(lastBar.volume))
                            }
                            if let avg = avgVolume20 {
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
        return Chart {
            ForEach(bars) { bar in
                LineMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close)
                )
                .foregroundStyle(Color.sacredGold)
                .interpolationMethod(.linear)

                AreaMark(
                    x: .value("Date", bar.parsedDate),
                    y: .value("Price", bar.close)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.sacredGold.opacity(0.18), Color.sacredGold.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
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
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: $selectedDate)
    }

    // MARK: - Range selector

    private var rangeSelector: some View {
        HStack(spacing: SacredSpacing.xxs) {
            ForEach(ChartRange.allCases) { r in
                Button {
                    range = r
                    selectedDate = nil
                    Task { await load(r) }
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

    private func load(_ r: ChartRange) async {
        loading = true
        defer { loading = false }
        do {
            let result = try await WiseCatAPI.getChart(ticker, range: r)
            self.chart = result
            self.error = nil
        } catch {
            if error.isCancellation { return }
            self.error = error.localizedDescription
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
}
