import SwiftUI

/// Compact home-card surface for Wise Cat. Tapping opens the full WiseCatView.
struct WiseCatHomeCard: View {
    @StateObject private var vm = WiseCatViewModel()

    var body: some View {
        NavigationLink(destination: WiseCatView()) {
            LuxCard {
                VStack(alignment: .leading, spacing: SacredSpacing.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Wise Cat")
                            .font(.sacredSubheading)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Text("Today's read")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)
                    }

                    if vm.watchlist.isEmpty {
                        Text("Add a ticker to begin reading the markets each day.")
                            .font(.sacredText)
                            .foregroundColor(.sacredTextSecondary)
                    } else if vm.signals.isEmpty {
                        Text("Today's read is being prepared.")
                            .font(.sacredText)
                            .foregroundColor(.sacredTextSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                            ForEach(topThreeSignals()) { sig in
                                HStack {
                                    Text(sig.ticker)
                                        .font(.sacredTextMedium)
                                        .foregroundColor(.sacredText)
                                    Spacer()
                                    Text(sig.action)
                                        .font(.sacredSmallSemibold)
                                        .foregroundColor(actionColor(sig.action))
                                }
                            }
                            if vm.hasStrongCalls {
                                Text("Strong call today")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredGold)
                                    .padding(.top, SacredSpacing.xxs)
                            }
                        }
                    }
                }
                .padding(SacredSpacing.lux)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .task { await vm.refresh() }
    }

    private func topThreeSignals() -> [TradingSignal] {
        Array(vm.signals
            .sorted(by: { $0.conviction > $1.conviction })
            .prefix(3))
    }

    private func actionColor(_ action: String) -> Color {
        switch WiseCatAction.from(action) {
        case .buy: return .sacredGold
        case .sell: return .sacredGoldDark
        case .hold: return .sacredText
        }
    }
}
