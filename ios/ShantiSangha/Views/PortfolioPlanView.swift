import SwiftUI

/// Read-only render of the audit + action plan. Pushed from PortfolioInputView.
struct PortfolioPlanView: View {
    let plan: PortfolioPlan?
    let regenerating: Bool
    let onRefresh: () async -> Void

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                if let plan {
                    VStack(alignment: .leading, spacing: SacredSpacing.l) {
                        summary(plan)
                        sectorSpread(plan)
                        actionsSection(plan, kind: .sell, title: "Immediate exits", tint: .sacredRed)
                        actionsSection(plan, kind: .trim, title: "Trim to 10% cap", tint: .sacredGoldDark)
                        actionsSection(plan, kind: .buy,  title: "Add positions",   tint: .sacredGreen)
                        actionsSection(plan, kind: .hold, title: "Hold (in good shape)", tint: .sacredText)
                        rulesFooter
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.l)
                    .padding(.bottom, SacredSpacing.tabBarSafe)
                } else if regenerating {
                    ProgressView("Generating plan…")
                        .tint(.sacredGold)
                        .padding(.top, 80)
                } else {
                    Text("No plan yet. Tap refresh.")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                        .padding(.top, 80)
                }
            }
            .refreshable { await onRefresh() }
        }
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await onRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.sacredGold)
                }
                .accessibilityLabel("Regenerate plan")
            }
        }
    }

    // MARK: sections

    private func summary(_ plan: PortfolioPlan) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                Text("Portfolio audit")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                HStack(alignment: .firstTextBaseline) {
                    Text(money(plan.totalValue))
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)
                    Spacer()
                    sectorBadge(plan)
                }
                Text("\(money(plan.investedValue)) invested · \(money(plan.cashBalance)) cash · \(plan.positionCount) positions")
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
    private func sectorSpread(_ plan: PortfolioPlan) -> some View {
        if !plan.sectorBreakdown.isEmpty {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Sector spread")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)

                LuxCard {
                    VStack(spacing: SacredSpacing.xs) {
                        ForEach(plan.sectorBreakdown, id: \.sector) { row in
                            HStack {
                                Text(row.sector)
                                    .font(.sacredText)
                                    .foregroundColor(.sacredText)
                                Spacer()
                                Text("\(money(row.marketValue))  \(percent(row.percentOfPortfolio))")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredTextSecondary)
                            }
                        }
                        if !plan.missingSectors.isEmpty {
                            Rectangle()
                                .fill(Color.sacredMuted.opacity(0.15))
                                .frame(height: 1)
                                .padding(.vertical, SacredSpacing.xxs)
                            HStack(alignment: .top) {
                                Text("Missing:")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredRed)
                                Text(plan.missingSectors.joined(separator: ", "))
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredTextSecondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(SacredSpacing.lux)
                }
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ plan: PortfolioPlan, kind: PortfolioActionKind, title: String, tint: Color) -> some View {
        let items = plan.actions.filter { $0.kind == kind }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                HStack(spacing: SacredSpacing.xs) {
                    Text(title)
                        .font(.sacredSubheading)
                        .foregroundColor(.sacredText)
                    Text("\(items.count)")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(tint)
                        .padding(.horizontal, SacredSpacing.xs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.12)))
                    Spacer()
                }

                VStack(spacing: SacredSpacing.xs) {
                    ForEach(items) { action in
                        ActionRow(action: action, tint: tint)
                    }
                }
            }
        }
    }

    private var rulesFooter: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                Text("Reminder")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredMuted)
                Text("Execute these on your monthly trading day. The -10% stop fires immediately if breached. Journal every action.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
            }
            .padding(SacredSpacing.lux)
        }
    }

    // MARK: helpers

    private func money(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func percent(_ v: Double) -> String {
        return String(format: "%.1f%%", v * 100)
    }
}

private struct ActionRow: View {
    let action: PortfolioAction
    let tint: Color

    var body: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.xs) {
                HStack(alignment: .center, spacing: SacredSpacing.s) {
                    Text(action.kind.label)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(tint)
                        .padding(.horizontal, SacredSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.15)))
                    Text(action.ticker)
                        .font(.sacredSubheading)
                        .foregroundColor(.sacredText)
                    Text(action.sector)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                    Spacer()
                    if let amount = action.amount {
                        Text(moneyShort(amount))
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredText)
                    }
                }
                if let shares = action.shares, let price = action.price, shares > 0 {
                    Text(detailLine(shares: shares, price: price))
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                }
                Text(action.reason)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            .padding(SacredSpacing.lux)
        }
    }

    private func detailLine(shares: Double, price: Double) -> String {
        let s = shares.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", shares)
            : String(format: "%.2f", shares)
        return "\(s) shares · ~$\(String(format: "%.2f", price))/sh"
    }

    private func moneyShort(_ v: Double) -> String {
        if v >= 1000 {
            return String(format: "$%.1fk", v / 1000)
        }
        return String(format: "$%.0f", v)
    }
}
