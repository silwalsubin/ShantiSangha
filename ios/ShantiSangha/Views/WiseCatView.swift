import SwiftUI

/// Stocks tab. Renders the user's portfolio plan: holdings with action
/// badges (HOLD / SELL / TRIM) + recommended buys against the 10-rule
/// Mode B strategy. The watchlist concept is hidden — held tickers
/// auto-sync to the watchlist on the server so the daily-signal cron
/// keeps firing for them.
struct WiseCatView: View {
    @StateObject private var vm = PortfolioViewModel()
    @State private var showPortfolioInput = false

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    if let plan = vm.plan, plan.positionCount > 0 {
                        summary(plan)
                        holdingsSection(plan)
                        buysSection(plan)
                        rulesFooter
                    } else if vm.generatingPlan || vm.loading {
                        ProgressView()
                            .tint(.sacredGold)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        emptyState
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
            .refreshable { await vm.generatePlan() }
        }
        .navigationTitle("Stocks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPortfolioInput = true
                } label: {
                    Image(systemName: "briefcase")
                        .foregroundColor(.sacredGold)
                }
                .accessibilityLabel("Edit portfolio")
            }
        }
        .sheet(isPresented: $showPortfolioInput, onDismiss: {
            // Pick up any changes the user made in the input sheet.
            Task { await vm.generatePlan() }
        }) {
            PortfolioInputView()
        }
        .task {
            await vm.loadPortfolio()
            await vm.generatePlan()
        }
    }

    // MARK: - Sections

    private func summary(_ plan: PortfolioPlan) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portfolio")
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredMuted)
                        Text(money(plan.totalValue))
                            .font(.sacredTitle)
                            .foregroundColor(.sacredText)
                    }
                    Spacer()
                    sectorBadge(plan)
                }
                Text("\(plan.positionCount) positions · \(money(plan.cashBalance)) cash")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func sectorBadge(_ plan: PortfolioPlan) -> some View {
        let ok = plan.sectorsCovered >= plan.minSectorsRequired
        let label = "\(plan.sectorsCovered)/\(plan.minSectorsRequired)+ sectors"
        return Text(label)
            .font(.sacredSmallSemibold)
            .foregroundColor(ok ? .sacredGreen : .sacredRed)
            .padding(.horizontal, SacredSpacing.s)
            .padding(.vertical, SacredSpacing.xxs)
            .background(
                Capsule()
                    .fill((ok ? Color.sacredGreen : Color.sacredRed).opacity(0.12))
            )
    }

    @ViewBuilder
    private func holdingsSection(_ plan: PortfolioPlan) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.xs) {
            Text("Your holdings")
                .font(.sacredSubheading)
                .foregroundColor(.sacredText)

            VStack(spacing: 0) {
                ForEach(Array(plan.holdings.enumerated()), id: \.element.id) { index, holding in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sacredMuted.opacity(0.18))
                            .frame(height: 1)
                    }
                    HoldingRow(holding: holding, action: action(for: holding.ticker, in: plan))
                }
            }
        }
    }

    @ViewBuilder
    private func buysSection(_ plan: PortfolioPlan) -> some View {
        let buys = plan.actions.filter { $0.kind == .buy }
        if !buys.isEmpty {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Recommended buys")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)

                VStack(spacing: 0) {
                    ForEach(Array(buys.enumerated()), id: \.element.id) { index, action in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sacredMuted.opacity(0.18))
                                .frame(height: 1)
                        }
                        BuyRow(action: action)
                    }
                }
            }
        }
    }

    private var rulesFooter: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Discipline")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredMuted)
                Text("Trade on your monthly day. -10% stop fires immediately. New entries require WiseCat 1M ≥ 0.70.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var emptyState: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("Build your portfolio")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                Text("Add the stocks you currently own (ticker, shares, cost per share). The app then tells you what to hold, trim, sell, and which sectors to fill.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                Button {
                    showPortfolioInput = true
                } label: {
                    Text("Add positions")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredGold)
                        .padding(.top, SacredSpacing.xs)
                }
                .frame(minHeight: 44, alignment: .leading)
            }
            .padding(SacredSpacing.lux)
        }
    }

    // MARK: - Helpers

    private func action(for ticker: String, in plan: PortfolioPlan) -> PortfolioAction? {
        plan.actions.first(where: { $0.ticker == ticker && $0.kind != .buy })
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - Rows

private struct HoldingRow: View {
    let holding: PortfolioHolding
    let action: PortfolioAction?

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: holding.ticker)) {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text(holding.ticker)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                    Text(metaLine)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                    Text(unrealizedLine)
                        .font(.sacredCaption)
                        .foregroundColor(holding.unrealizedReturnPct >= 0 ? .sacredGreen : .sacredRed)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                    Text(actionBadge)
                        .font(.sacredButtonLabel)
                        .foregroundColor(actionColor)
                    ProbabilityBar(
                        pBuy: holding.pBuy1M,
                        pHold: max(0, 1 - holding.pBuy1M - holding.pSell1M),
                        pSell: holding.pSell1M,
                        height: 8,
                        showLabels: false
                    )
                    .frame(width: 120)
                    if let reason = compactReason {
                        Text(reason)
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.vertical, SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        let priceStr = String(format: "$%.2f", holding.currentPrice)
        let pctPort = String(format: "%.1f%%", holding.percentOfPortfolio * 100)
        return "\(priceStr) · \(pctPort) · \(holding.sector)"
    }

    private var unrealizedLine: String {
        let sign = holding.unrealizedReturnPct >= 0 ? "+" : ""
        return String(format: "%@%.1f%% from cost", sign, holding.unrealizedReturnPct * 100)
    }

    private var actionBadge: String {
        guard let action else { return "HOLD" }
        switch action.kind {
        case .sell: return "SELL"
        case .trim: return "TRIM"
        case .hold: return "HOLD"
        case .buy:  return "HOLD"  // shouldn't happen for held tickers
        }
    }

    private var actionColor: Color {
        guard let action else { return .sacredText }
        switch action.kind {
        case .sell: return .sacredRed
        case .trim: return .sacredGoldDark
        case .hold: return .sacredText
        case .buy:  return .sacredGreen
        }
    }

    /// Short reason hint for SELL / TRIM rows.
    private var compactReason: String? {
        guard let action else { return nil }
        switch action.kind {
        case .sell:
            if holding.unrealizedReturnPct <= -0.10 { return "Past -10% stop" }
            if holding.pSell1M >= 0.55 { return "Model: exit signal" }
            return "Rule violation"
        case .trim:
            return "Over 10% cap"
        case .hold, .buy:
            return nil
        }
    }
}

private struct BuyRow: View {
    let action: PortfolioAction

    var body: some View {
        NavigationLink(destination: WiseCatDetailView(ticker: action.ticker)) {
            HStack(alignment: .center, spacing: SacredSpacing.m) {
                VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                    Text(action.ticker)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                    Text(action.sector)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                    if let price = action.price, price > 0 {
                        Text(String(format: "$%.2f", price))
                            .font(.sacredCaption)
                            .foregroundColor(.sacredMuted)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SacredSpacing.xxs) {
                    Text("BUY")
                        .font(.sacredButtonLabel)
                        .foregroundColor(.sacredGreen)
                    if let amount = action.amount, amount > 0 {
                        Text(target(amount))
                            .font(.sacredCaption)
                            .foregroundColor(.sacredTextSecondary)
                    }
                    Text(shortReason)
                        .font(.sacredCaption)
                        .foregroundColor(.sacredMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func target(_ v: Double) -> String {
        if v >= 1000 { return String(format: "~$%.1fk", v / 1000) }
        return String(format: "~$%.0f", v)
    }

    /// Distill the server reason into 1-2 line hint.
    private var shortReason: String {
        let r = action.reason.lowercased()
        if r.contains("high-confidence") { return "High conf · missing sector" }
        if r.contains("missing sector") { return "Missing sector · low conf" }
        return action.reason
    }
}
