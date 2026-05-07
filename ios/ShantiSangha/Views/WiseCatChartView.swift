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

    var body: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            statsStrip

            chartArea

            rangeSelector
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

    // MARK: - Stats strip

    @ViewBuilder
    private var statsStrip: some View {
        if let agg = chart?.aggregates {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                if let selected = selectedBar {
                    selectedReadout(selected)
                } else {
                    headlineReadout(agg)
                }

                statsRow(agg)
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

    private func statsRow(_ agg: ChartAggregates) -> some View {
        HStack(alignment: .top, spacing: SacredSpacing.l) {
            statBlock(label: "52W HIGH", value: agg.weekHigh52)
            statBlock(label: "52W LOW", value: agg.weekLow52)
            statBlock(label: "ALL-TIME HIGH", value: agg.allTimeHigh)
            statBlock(label: "ALL-TIME LOW", value: agg.allTimeLow)
        }
        .padding(.top, SacredSpacing.xs)
    }

    private func statBlock(label: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.sacredMicroBold)
                .tracking(2)
                .foregroundColor(.sacredLabel)
            Text(value.map { formatPrice($0) } ?? "—")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredText)
        }
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
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(formatAxisDate(date))
                            .font(.sacredFinePrint)
                            .foregroundStyle(Color.sacredMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.sacredMutedLight.opacity(0.15))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                if let v = value.as(Double.self) {
                    AxisValueLabel {
                        Text(formatPrice(v))
                            .font(.sacredFinePrint)
                            .foregroundStyle(Color.sacredMuted)
                    }
                }
                AxisGridLine().foregroundStyle(Color.sacredMutedLight.opacity(0.15))
            }
        }
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
                        .font(.sacredSmallSemibold)
                        .tracking(1)
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

    private func formatAxisDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch range {
        case .oneMonth, .sixMonth: f.dateFormat = "MMM d"
        case .oneYear: f.dateFormat = "MMM"
        case .fiveYear, .max: f.dateFormat = "yyyy"
        }
        return f.string(from: d)
    }

    private func formatLongDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}
