import SwiftUI

/// Stocks tab. Renders the user's portfolio plan: holdings with action
/// badges (HOLD / SELL / TRIM) + recommended buys against the 10-rule
/// Mode B strategy. The watchlist concept is hidden — held tickers
/// auto-sync to the watchlist on the server so the daily-signal cron
/// keeps firing for them.
struct WiseCatView: View {
    @StateObject private var vm = PortfolioViewModel()
    @State private var showAddPosition = false
    @State private var showRules = false
    @State private var pendingDelete: String?

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
                HStack(spacing: SacredSpacing.s) {
                    Button {
                        showRules = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel("Edit rules")

                    Button {
                        showAddPosition = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel("Add a stock")
                }
            }
        }
        .sheet(isPresented: $showAddPosition) {
            AddPositionView(
                excludedTickers: Set(vm.positions.map { $0.ticker.uppercased() })
            ) {
                // Refresh after a successful add. The add VM already
                // updated its own `positions`, but this VM (the Stocks
                // tab's) needs the position list + plan re-fetched.
                Task {
                    await vm.loadPortfolio()
                    await vm.generatePlan()
                }
            }
        }
        .sheet(isPresented: $showRules, onDismiss: {
            // Rule changes shift the plan output — regenerate.
            Task { await vm.generatePlan() }
        }) {
            StrategyRulesView()
        }
        .confirmationDialog("Remove this position?",
                            isPresented: Binding(
                                get: { pendingDelete != nil },
                                set: { if !$0 { pendingDelete = nil } }
                            ),
                            titleVisibility: .visible) {
            Button("Remove \(pendingDelete ?? "")", role: .destructive) {
                if let t = pendingDelete {
                    Task { await vm.removePosition(t) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Your shares and cost basis will be deleted. The position can be re-added later.")
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
                    HoldingRow(
                        holding: holding,
                        action: action(for: holding.ticker, in: plan),
                        onRequestDelete: { pendingDelete = holding.ticker }
                    )
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
                    showAddPosition = true
                } label: {
                    Text("Add a stock")
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
    var onRequestDelete: () -> Void

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
                        pBuy: holding.pBuy,
                        pHold: max(0, 1 - holding.pBuy - holding.pSell),
                        pSell: holding.pSell,
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onRequestDelete) {
                Label("Remove position", systemImage: "trash")
            }
        }
    }

    private var metaLine: String {
        let priceStr = String(format: "$%.2f", holding.currentPrice)
        let pctPort = String(format: "%.1f%%", holding.percentOfPortfolio * 100)
        return "\(priceStr) · \(pctPort) · \(holding.sector)"
    }

    private var unrealizedLine: String {
        let cost = holding.shares * holding.costBasis
        let dollarPnL = holding.marketValue - cost
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = (abs(dollarPnL) >= 1000) ? 0 : 2
        let formatted = f.string(from: NSNumber(value: abs(dollarPnL))) ?? "$\(abs(Int(dollarPnL)))"
        let sign = dollarPnL >= 0 ? "+" : "-"
        return "\(sign)\(formatted)"
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
        case .sell:
            // Profit-taking exits read green even though the verb is still
            // SELL — celebrates the win rather than punishing the row.
            return holding.unrealizedReturnPct >= 0.10 ? .sacredGreen : .sacredRed
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
            if holding.unrealizedReturnPct >= 0.10 { return "Hit +10% target" }
            if holding.unrealizedReturnPct <= -0.10 { return "Past -10% stop" }
            if holding.pSell >= 0.55 { return "Model: exit signal" }
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
