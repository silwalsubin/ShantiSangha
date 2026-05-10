import SwiftUI

/// Wise Cat — technical trading signals. Shown via deep link from the Home card.
struct WiseCatView: View {
    @StateObject private var vm = WiseCatViewModel()
    @State private var showWatchlistEdit = false
    /// Horizon that drives every row's action label + probability bar.
    /// 1M is the canonical default (matches what the home card highlights).
    @State private var selectedHorizon: WiseCatHorizon = .oneMonth

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
                        horizonSelector
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

    private var horizonSelector: some View {
        HStack(spacing: SacredSpacing.xxs) {
            ForEach(WiseCatHorizon.allCases) { horizon in
                Button {
                    selectedHorizon = horizon
                } label: {
                    Text(horizon.label)
                        .font(.sacredTextMedium)
                        .foregroundColor(horizon == selectedHorizon ? .sacredGold : .sacredMuted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: SacredRadius.pill)
                                .fill(horizon == selectedHorizon ? Color.sacredGold.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: SacredRadius.pill)
                                .stroke(
                                    horizon == selectedHorizon ? Color.sacredGold.opacity(0.45)
                                                               : Color.sacredMutedLight.opacity(0.25),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
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
                    horizon: selectedHorizon,
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
    let horizon: WiseCatHorizon
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
                    let read = signal.read(for: horizon)
                    VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                        Text(read.action)
                            .font(.sacredButtonLabel)
                            .foregroundColor(actionColor(read.action))
                        ProbabilityBar(
                            pBuy: read.pBuy ?? 0,
                            pHold: read.pHold ?? 1,
                            pSell: read.pSell ?? 0,
                            height: 8,
                            showLabels: false
                        )
                        .frame(width: 120)
                    }
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

    private func actionColor(_ action: String) -> Color {
        switch WiseCatAction.from(action) {
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
