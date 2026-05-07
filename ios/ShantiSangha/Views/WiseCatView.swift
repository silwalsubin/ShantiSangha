import SwiftUI

/// Wise Cat — astro-aware trading signals. Shown via deep link from the Home card.
struct WiseCatView: View {
    @StateObject private var vm = WiseCatViewModel()
    @State private var showWatchlistEdit = false
    @State private var skyExpanded = false

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
                        if let sky = vm.todaysSky {
                            todaysSkyCard(sky)
                        }
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

    private func todaysSkyCard(_ sky: WiseCatViewModel.TodaysSky) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        skyExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: SacredSpacing.s) {
                        Text("Today's sky")
                            .font(.sacredSubheading)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Text(skyBiasLabel(sky))
                            .font(.sacredTextMedium)
                            .foregroundColor(skyBiasColor(sky))
                        Image(systemName: "chevron.right")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .rotationEffect(.degrees(skyExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if skyExpanded {
                    VStack(alignment: .leading, spacing: SacredSpacing.s) {
                        if !sky.userNatal.highlights.isEmpty && sky.userNatal.highlights.first != "no data" {
                            skyAngleSection(title: "Your transits", highlights: sky.userNatal.highlights)
                        }
                        if !sky.panchang.highlights.isEmpty {
                            skyAngleSection(title: "Panchang", highlights: sky.panchang.highlights)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func skyAngleSection(title: String, highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
            Text(title)
                .font(.sacredTextMedium)
                .foregroundColor(.sacredText)
            ForEach(highlights, id: \.self) { h in
                Text("· \(h)")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        }
        .padding(.top, SacredSpacing.xxs)
    }

    private func skyBiasLabel(_ sky: WiseCatViewModel.TodaysSky) -> String {
        let avg = (sky.userNatal.score + sky.panchang.score) / 2
        if avg > 0.15 { return "Benefic" }
        if avg < -0.15 { return "Cautious" }
        return "Neutral"
    }

    private func skyBiasColor(_ sky: WiseCatViewModel.TodaysSky) -> Color {
        let avg = (sky.userNatal.score + sky.panchang.score) / 2
        if avg > 0.15 { return .sacredGold }
        if avg < -0.15 { return .sacredGoldDark }
        return .sacredMuted
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
                            if let label = convictionLabel(signal) {
                                Text(label)
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                            }
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

    /// Small textual conviction cue — only meaningful for BUY/SELL. HOLD has no
    /// "strength of holding," so we return nil and show nothing.
    private func convictionLabel(_ s: TradingSignal) -> String? {
        guard WiseCatAction.from(s.action) != .hold else { return nil }
        switch s.conviction {
        case ..<0.5: return "soft"
        case ..<0.8: return "clear"
        default: return "strong"
        }
    }

    private func priceLabel(_ s: TradingSignal) -> String {
        if let price = s.price {
            return String(format: "$%.2f", price)
        }
        return s.date
    }
}
