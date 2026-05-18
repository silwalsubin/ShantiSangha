import SwiftUI

/// Stocks tab. Renders the user's portfolio plan against the broker
/// (IBKR) — positions, cash, and per-row action badges (HOLD / SELL /
/// TRIM) computed from the 10-rule Mode B strategy. Positions sync from
/// IBKR; there's no manual entry path.
struct WiseCatView: View {
    @StateObject private var vm = PortfolioViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showRules = false
    @State private var showLinkIbkr = false
    @State private var lastFetchAt: Date?

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    if let plan = vm.plan {
                        summary(plan)
                        ibkrSection
                        if plan.positionCount > 0 {
                            holdingsSection(plan)
                        }
                    } else if vm.generatingPlan || vm.loading {
                        ProgressView()
                            .tint(.sacredGold)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        ibkrSection
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
            .refreshable {
                lastFetchAt = Date()
                await vm.generatePlan()
            }
        }
        .navigationTitle("Stocks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRules = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.sacredGold)
                }
                .accessibilityLabel("Edit rules")
            }
        }
        .sheet(isPresented: $showRules, onDismiss: {
            Task { await vm.generatePlan() }
        }) {
            StrategyRulesView()
        }
        .fullScreenCover(isPresented: $showLinkIbkr) {
            LinkIbkrView {
                Task { await vm.linkIbkr() }
            }
        }
        .task {
            await refresh(force: true)
        }
        .onAppear {
            Task { await refresh(force: false, maxAgeSeconds: 5) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh(force: true) }
            }
        }
    }

    private func refresh(force: Bool, maxAgeSeconds: TimeInterval = 30) async {
        if !force, let last = lastFetchAt,
           Date().timeIntervalSince(last) < maxAgeSeconds {
            return
        }
        lastFetchAt = Date()
        await vm.loadPortfolio()
        await vm.generatePlan()
    }

    // MARK: - Sections

    private func summary(_ plan: PortfolioPlan) -> some View {
        let missingPicks = plan.actions
            .filter { $0.kind == .buy && $0.bracket != nil && plan.missingSectors.contains($0.sector) }

        return VStack(alignment: .leading, spacing: SacredSpacing.s) {
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
                sectorBadge(plan, missingPicks: missingPicks)
            }
            Text("\(plan.positionCount) positions · \(money(plan.cashBalance)) cash")
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
        }
    }

    private func sectorBadge(_ plan: PortfolioPlan,
                             missingPicks: [PortfolioAction]) -> some View
    {
        let ok = plan.sectorsCovered >= plan.minSectorsRequired
        let label = "\(plan.sectorsCovered)/\(plan.minSectorsRequired)+ sectors"
        let tint: Color = ok ? .sacredGreen : .sacredRed
        let shortfall = max(0, plan.minSectorsRequired - plan.sectorsCovered)
        let explanation = ok
            ? "You're covering \(plan.sectorsCovered) sectors — diversification is intact."
            : "Spread risk across at least \(plan.minSectorsRequired) sectors. You're holding \(plan.sectorsCovered) — \(shortfall) short. Diversification is what protects you when one sector takes a hit."

        return SacredStatusBadge(label: label, tint: tint) {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text(explanation)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                    .fixedSize(horizontal: false, vertical: true)
                if !missingPicks.isEmpty {
                    Text("MISSING")
                        .font(.sacredSectionLabel)
                        .foregroundColor(.sacredMuted)
                        .padding(.top, SacredSpacing.xxs)
                    Text(missingPicks.map { $0.sector }.joined(separator: ", "))
                        .font(.sacredCaption)
                        .foregroundColor(.sacredTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func holdingsSection(_ plan: PortfolioPlan) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.holdings.enumerated()), id: \.element.id) { index, holding in
                if index > 0 {
                    Rectangle()
                        .fill(Color.sacredMuted.opacity(0.18))
                        .frame(height: 1)
                }
                HoldingRow(
                    holding: holding,
                    action: action(for: holding.ticker, in: plan)
                )
            }
        }
    }

    /// Status row for the IBKR broker link. Shows last-sync time when
    /// linked, a "Connect IBKR" CTA when not, and a "Re-link required"
    /// banner when the OAuth session has expired.
    @ViewBuilder
    private var ibkrSection: some View {
        if let status = vm.ibkrStatus {
            if status.isLinked {
                ibkrLinkedRow(status)
            } else if status.needsReauth {
                ibkrReauthRow(status)
            } else {
                ibkrConnectRow
            }
        } else {
            ibkrConnectRow
        }
    }

    private func ibkrLinkedRow(_ status: IbkrStatus) -> some View {
        let synced = relativeSyncLabel(status.lastSuccessfulSyncAt)
        return HStack(spacing: SacredSpacing.s) {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.sacredGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("Synced from IBKR")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredText)
                Text(synced + " · " + (status.ibkrAccountId ?? ""))
                    .font(.sacredCaption)
                    .foregroundColor(.sacredTextSecondary)
            }
            Spacer()
            if vm.ibkrSyncing {
                ProgressView().tint(.sacredGold)
            } else {
                Button("Resync") {
                    Task { await vm.resyncIbkr() }
                }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(Color.sacredBgCard)
        .cornerRadius(12)
    }

    private func ibkrReauthRow(_ status: IbkrStatus) -> some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.sacredRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("IBKR link expired")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredText)
                Text(status.lastErrorMessage ?? "Re-link to resume live sync")
                    .font(.sacredCaption)
                    .foregroundColor(.sacredTextSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Re-link") {
                showLinkIbkr = true
            }
            .font(.sacredSmallSemibold)
            .foregroundColor(.sacredGold)
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.vertical, SacredSpacing.s)
        .background(Color.sacredBgCard)
        .cornerRadius(12)
    }

    private var ibkrConnectRow: some View {
        Button {
            showLinkIbkr = true
        } label: {
            HStack(spacing: SacredSpacing.s) {
                Image(systemName: "link")
                    .foregroundColor(.sacredGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Interactive Brokers")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredText)
                    Text("Pull live positions and cash directly from your account.")
                        .font(.sacredCaption)
                        .foregroundColor(.sacredTextSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if vm.ibkrSyncing {
                    ProgressView().tint(.sacredGold)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.s)
            .background(Color.sacredBgCard)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func relativeSyncLabel(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else {
            return "Just now"
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
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
                        pBuy: holding.pBuy,
                        pHold: max(0, 1 - holding.pBuy - holding.pSell),
                        pSell: holding.pSell,
                        height: 8,
                        showLabels: false
                    )
                    .frame(width: 120)
                    if let badge = compactReasonBadge {
                        SacredStatusBadge(label: badge.label,
                                          tint: badge.tint,
                                          explanation: badge.explanation)
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
        case .buy:  return "HOLD"
        }
    }

    private var actionColor: Color {
        guard let action else { return .sacredText }
        switch action.kind {
        case .sell:
            return holding.unrealizedReturnPct >= 0.10 ? .sacredGreen : .sacredRed
        case .trim: return .sacredGoldDark
        case .hold: return .sacredText
        case .buy:  return .sacredGreen
        }
    }

    /// Status pill rendered under the action label on SELL / TRIM rows.
    /// The label is the "what"; the explanation surfaces on tap via
    /// `SacredStatusBadge`. Reasons mirror the rule constants the
    /// PortfolioService is actually enforcing (Rule 3 stop, Rule 11
    /// take-profit, Rule 2 concentration cap).
    private var compactReasonBadge: (label: String, tint: Color, explanation: String)? {
        guard let action else { return nil }
        switch action.kind {
        case .sell:
            if holding.unrealizedReturnPct >= 0.10 {
                return (
                    label: "Hit target",
                    tint: .sacredGreen,
                    explanation: "This position has reached your take-profit threshold (default +10% from cost). Cashing out locks in the win and frees the slot for the next signal."
                )
            }
            if holding.unrealizedReturnPct <= -0.07 {
                return (
                    label: "Past stop",
                    tint: .sacredRed,
                    explanation: "This position is down past your stop-loss threshold (default -7% from cost). Exiting at the pre-committed stop is the discipline that prevents another large drawdown."
                )
            }
            if holding.pSell >= 0.55 {
                return (
                    label: "Exit signal",
                    tint: .sacredRed,
                    explanation: "The WiseCat model's exit confidence crossed the advisory threshold (default 0.55). The momentum read has flipped bearish at your entry horizon."
                )
            }
            return (
                label: "Exit triggered",
                tint: .sacredRed,
                explanation: "One of your exit conditions fired against this position. Open the detail view to see which signal triggered it."
            )
        case .trim:
            return (
                label: "Over cap",
                tint: .sacredGoldDark,
                explanation: "Each position is capped at 10% of the portfolio. This holding has grown past the cap — trim back to the target to keep concentration risk bounded."
            )
        case .hold, .buy:
            return nil
        }
    }
}
