import SwiftUI

/// Wise Cat — astro-aware trading signals. Shown via deep link from the Home card.
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
                        ForEach(vm.watchlist) { entry in
                            WiseCatRow(
                                entry: entry,
                                signal: vm.signal(for: entry.ticker),
                                generating: vm.generatingTickers.contains(entry.ticker)
                            )
                        }
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
        .navigationTitle("Wise Cat")
        .navigationBarTitleDisplayMode(.large)
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
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            Text("Today's read")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            Text("Markets, weighed against the sky")
                .font(.sacredHeading)
                .foregroundColor(.sacredText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            LuxCard {
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
                        VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                            actionChip(signal)
                            convictionDots(signal.conviction)
                        }
                    } else if generating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.sacredGold)
                    }
                }
                .padding(SacredSpacing.lux)
            }
        }
        .buttonStyle(.plain)
    }

    private func actionChip(_ s: TradingSignal) -> some View {
        let color: Color = {
            switch WiseCatAction.from(s.action) {
            case .buy: return .sacredGold
            case .sell: return .sacredGoldDark
            case .hold: return .sacredText
            }
        }()
        return Text(s.action)
            .font(.sacredButtonLabel)
            .foregroundColor(color)
            .padding(.horizontal, SacredSpacing.s)
            .padding(.vertical, 6)
            .overlay(
                RoundedRectangle(cornerRadius: SacredRadius.pill)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            )
    }

    private func convictionDots(_ conviction: Double) -> some View {
        let level = Int((conviction * 5).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(i < level ? Color.sacredGold : Color.sacredMutedLight.opacity(0.3))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func priceLabel(_ s: TradingSignal) -> String {
        if let price = s.price {
            return String(format: "$%.2f", price)
        }
        return s.date
    }
}
