import Foundation

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published private(set) var positions: [PortfolioPosition] = []
    @Published var cashBalance: Double = 0
    @Published private(set) var plan: PortfolioPlan?
    @Published private(set) var loading = false
    @Published private(set) var generatingPlan = false
    @Published var error: String?

    func loadPortfolio() async {
        loading = true
        defer { loading = false }
        do {
            self.positions = try await WiseCatAPI.listPortfolio()
            self.error = nil
        } catch {
            self.error = "Could not load portfolio. \(error.localizedDescription)"
        }
    }

    func savePortfolio(_ positions: [SavePortfolioPosition]) async {
        loading = true
        defer { loading = false }
        do {
            self.positions = try await WiseCatAPI.savePortfolio(positions, cashBalance: cashBalance)
            self.error = nil
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }

    func generatePlan() async {
        generatingPlan = true
        defer { generatingPlan = false }
        do {
            self.plan = try await WiseCatAPI.getPortfolioPlan(cashBalance: cashBalance)
            self.error = nil
        } catch {
            self.error = "Could not generate plan: \(error.localizedDescription)"
        }
    }

    /// Add a single position. Returns true if the call succeeded.
    @discardableResult
    func addPosition(ticker: String, shares: Double, costBasis: Double) async -> Bool {
        do {
            let saved = try await WiseCatAPI.addPortfolioPosition(
                SavePortfolioPosition(ticker: ticker, shares: shares, costBasis: costBasis)
            )
            self.positions.append(saved)
            self.error = nil
            // Plan is now stale — regenerate eagerly so the Stocks tab
            // shows the new holding immediately on return.
            await generatePlan()
            return true
        } catch {
            self.error = "Could not add position: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func removePosition(_ ticker: String) async -> Bool {
        do {
            try await WiseCatAPI.removePortfolioPosition(ticker)
            self.positions.removeAll { $0.ticker == ticker }
            // Optimistically prune the plan's holdings so the UI updates
            // immediately, then regenerate from the server for the new
            // action set (this position may have had SELL/TRIM actions
            // tied to it, and the basket recommendations shift too).
            if let plan = self.plan {
                let filteredHoldings = plan.holdings.filter { $0.ticker != ticker }
                let filteredActions = plan.actions.filter { $0.ticker != ticker || $0.kind == .buy }
                self.plan = PortfolioPlan(
                    generatedAt: plan.generatedAt,
                    totalValue: plan.totalValue,
                    investedValue: plan.investedValue,
                    cashBalance: plan.cashBalance,
                    positionCount: filteredHoldings.count,
                    sectorsCovered: plan.sectorsCovered,
                    minSectorsRequired: plan.minSectorsRequired,
                    missingSectors: plan.missingSectors,
                    holdings: filteredHoldings,
                    sectorBreakdown: plan.sectorBreakdown,
                    actions: filteredActions
                )
            }
            self.error = nil
            await generatePlan()
            return true
        } catch {
            self.error = "Could not remove position: \(error.localizedDescription)"
            return false
        }
    }
}
