import SwiftUI

/// Wise Cat — technical trading signals. Shown via deep link from the Home card.
struct WiseCatView: View {
    @StateObject private var vm = WiseCatViewModel()
    @State private var showWatchlistEdit = false

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    header

                    if vm.loading && vm.watchlist.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else if vm.watchlist.isEmpty {
                        emptyWatchlist
                    } else {
                        watchlistList
                    }

                    if let err = vm.error {
                        Text(err)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredRed)
                            .padding(.horizontal, SacredSpacing.m)
                    }
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.top, SacredSpacing.l)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Stocks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWatchlistEdit = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.sacredGold)
                }
                .accessibilityLabel("Edit watchlist")
            }
        }
        .sheet(isPresented: $showWatchlistEdit) {
            WiseCatWatchlistEditView(vm: vm)
        }
        .task { await vm.refresh() }
    }

    private var header: some View {
        Text("Today's read")
            .font(.sacredTitle)
            .foregroundColor(.sacredText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watchlistList: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.watchlist.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.18))
                        .frame(height: 1)
                }
                WiseCatRow(
                    entry: entry,
                    signal: vm.signal(for: entry.ticker),
                    generating: vm.generatingTickers.contains(entry.ticker)
                )
            }
        }
    }

    private var emptyWatchlist: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("No tickers yet")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("Add a ticker to begin reading the markets each day.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                Button {
                    showWatchlistEdit = true
                } label: {
                    Text("Add a ticker")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredGold)
                        .padding(.top, SacredSpacing.xs)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            .padding(SacredSpacing.lux)
        }
    }

}

private struct WiseCatRow: View {
    let entry: WatchlistEntry
    let signal: TradingSignal?
    let generating: Bool

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: entry.ticker)) {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text(entry.ticker)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                    if let signal {
                        Text(priceLabel(signal))
                            .font(.sacredSmall)
                            .foregroundColor(.sacredTextSecondary)
                    } else if generating {
                        Text("Reading the sky…")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    } else {
                        Text("Waiting for today's read")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }

                Spacer()

                if let signal {
                    ConvictionMeter(
                        conviction: signal.conviction,
                        color: meterColor(signal),
                        label: signal.action,
                        diameter: 72,
                        lineWidth: 5,
                        labelFont: .sacredButtonLabel,
                        labelPosition: .diameterLine
                    )
                } else if generating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.sacredGold)
                }
            }
            .padding(.vertical, SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meterColor(_ s: TradingSignal) -> Color {
        switch WiseCatAction.from(s.action) {
        case .buy: return .sacredGreen
        case .sell: return .sacredRed
        case .hold: return .sacredText
        }
    }

    private func priceLabel(_ s: TradingSignal) -> String {
        if let price = s.price {
            return String(format: "$%.2f", price)
        }
        return s.date
    }
}
