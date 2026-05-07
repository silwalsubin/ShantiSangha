import SwiftUI

/// Compact home-card surface for Wise Cat. Tapping opens the full WiseCatView.
struct WiseCatHomeCard: View {
    @StateObject private var vm = WiseCatViewModel()

    var body: some View {
        NavigationLink(destination: WiseCatView()) {
            LuxCard {
                VStack(alignment: .leading, spacing: SacredSpacing.m) {
                    header

                    if vm.watchlist.isEmpty {
                        Text("Add a ticker to begin reading the markets each day.")
                            .font(.sacredText)
                            .foregroundColor(.sacredTextSecondary)
                    } else if vm.signals.isEmpty {
                        Text("Today's read is being prepared.")
                            .font(.sacredText)
                            .foregroundColor(.sacredTextSecondary)
                    } else {
                        statsRow
                    }
                }
                .padding(SacredSpacing.lux)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .task { await vm.refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Wise Cat")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)
            Spacer()
            if !vm.signals.isEmpty, let bias = skyBias() {
                Text(bias.label)
                    .font(.sacredTextMedium)
                    .foregroundColor(bias.color)
            }
        }
    }

    private var statsRow: some View {
        let counts = actionCounts()
        return HStack(spacing: 0) {
            statCell(count: counts.buy, label: "Buy", activeColor: .sacredGold)
            statCell(count: counts.hold, label: "Hold", activeColor: .sacredText)
            statCell(count: counts.sell, label: "Sell", activeColor: .sacredGoldDark)
        }
    }

    private func statCell(count: Int, label: String, activeColor: Color) -> some View {
        let active = count > 0
        return VStack(spacing: SacredSpacing.xxs) {
            Text("\(count)")
                .font(.sacredDisplayNumber)
                .foregroundColor(active ? activeColor : .sacredMuted)
            Text(label)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionCounts() -> (buy: Int, hold: Int, sell: Int) {
        var buy = 0, hold = 0, sell = 0
        for sig in vm.signals {
            switch WiseCatAction.from(sig.action) {
            case .buy: buy += 1
            case .hold: hold += 1
            case .sell: sell += 1
            }
        }
        return (buy, hold, sell)
    }

    private struct SkyBias {
        let label: String
        let color: Color
    }

    private func skyBias() -> SkyBias? {
        guard let sky = vm.todaysSky else { return nil }
        let avg = (sky.userNatal.score + sky.panchang.score) / 2
        if avg > 0.15 { return SkyBias(label: "Benefic sky", color: .sacredGold) }
        if avg < -0.15 { return SkyBias(label: "Cautious sky", color: .sacredGoldDark) }
        return SkyBias(label: "Neutral sky", color: .sacredMuted)
    }
}
