import SwiftUI

/// Compact home-card surface for Wise Cat. Reads the portfolio plan and
/// only surfaces *actions* (Sell / Trim / Buy) — Hold positions are not
/// counted, because a hold isn't an action. Tapping opens the Stocks tab.
struct WiseCatHomeCard: View {
    @StateObject private var vm = PortfolioViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastFetchAt: Date?

    var body: some View {
        NavigationLink(destination: WiseCatView()) {
            LuxCard {
                VStack(alignment: .leading, spacing: SacredSpacing.lux) {
                    header

                    if let plan = vm.plan, plan.positionCount > 0 {
                        statsRow(plan)
                    }
                }
                .padding(SacredSpacing.lux)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .task { await refresh(force: true) }
        .onAppear { Task { await refresh(force: false, maxAgeSeconds: 60) } }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refresh(force: true) }
            }
        }
    }

    private func refresh(force: Bool, maxAgeSeconds: TimeInterval = 60) async {
        if !force, let last = lastFetchAt,
           Date().timeIntervalSince(last) < maxAgeSeconds {
            return
        }
        lastFetchAt = Date()
        await vm.loadPortfolio()
        await vm.generatePlan()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                Text("STOCKS")
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)
                Text(subtitle)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        guard let plan = vm.plan else { return "Loading…" }
        if plan.positionCount == 0 {
            return "Build your portfolio."
        }
        let counts = actionCounts(in: plan)
        let total = counts.sell + counts.trim + counts.buy
        if total == 0 {
            return "Portfolio aligned — no actions today."
        }
        return "\(total) action\(total == 1 ? "" : "s") this month"
    }

    @ViewBuilder
    private func statsRow(_ plan: PortfolioPlan) -> some View {
        let counts = actionCounts(in: plan)
        if counts.sell + counts.trim + counts.buy > 0 {
            HStack(spacing: 0) {
                statCell(count: counts.sell, label: "Sell", activeColor: .sacredRed)
                statCell(count: counts.trim, label: "Trim", activeColor: .sacredGoldDark)
                statCell(count: counts.buy,  label: "Buy",  activeColor: .sacredGreen)
            }
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

    private func actionCounts(in plan: PortfolioPlan) -> (sell: Int, trim: Int, buy: Int) {
        var sell = 0, trim = 0, buy = 0
        for a in plan.actions {
            switch a.kind {
            case .sell: sell += 1
            case .trim: trim += 1
            case .buy:  buy  += 1
            case .hold: break  // intentionally not counted
            }
        }
        return (sell, trim, buy)
    }
}
