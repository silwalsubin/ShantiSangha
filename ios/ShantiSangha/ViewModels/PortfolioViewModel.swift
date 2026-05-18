import Foundation

@MainActor
final class PortfolioViewModel: ObservableObject {
    @Published private(set) var positions: [PortfolioPosition] = []
    @Published var cashBalance: Double = 0
    @Published private(set) var plan: PortfolioPlan?
    @Published private(set) var loading = false
    @Published private(set) var generatingPlan = false
    @Published var error: String?

    /// IBKR link state. When `ibkrStatus?.isLinked == true`, positions are
    /// broker-sourced and manual add/remove is disabled (server rejects
    /// the call anyway, but hiding the UI keeps the surface honest).
    @Published private(set) var ibkrStatus: IbkrStatus?
    @Published private(set) var ibkrSyncing = false

    var isIbkrLinked: Bool { ibkrStatus?.isLinked ?? false }

    func loadPortfolio() async {
        loading = true
        defer { loading = false }
        async let positionsTask = WiseCatAPI.listPortfolio()
        async let statusTask = WiseCatAPI.getIbkrStatus()
        do {
            self.positions = try await positionsTask
            self.ibkrStatus = try await statusTask
            if let cash = ibkrStatus?.cashBalance, isIbkrLinked {
                self.cashBalance = cash
            }
            self.error = nil
        } catch {
            self.error = "Could not load portfolio. \(error.localizedDescription)"
        }
    }

    // MARK: - IBKR

    @discardableResult
    func linkIbkr() async -> Bool {
        ibkrSyncing = true
        defer { ibkrSyncing = false }
        do {
            _ = try await WiseCatAPI.linkIbkr()
            self.ibkrStatus = try await WiseCatAPI.getIbkrStatus()
            self.positions = try await WiseCatAPI.listPortfolio()
            if let cash = ibkrStatus?.cashBalance, isIbkrLinked {
                self.cashBalance = cash
            }
            self.error = nil
            await generatePlan()
            return true
        } catch {
            self.error = "Could not link IBKR: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func resyncIbkr() async -> Bool {
        ibkrSyncing = true
        defer { ibkrSyncing = false }
        do {
            _ = try await WiseCatAPI.resyncIbkr()
            self.ibkrStatus = try await WiseCatAPI.getIbkrStatus()
            self.positions = try await WiseCatAPI.listPortfolio()
            if let cash = ibkrStatus?.cashBalance, isIbkrLinked {
                self.cashBalance = cash
            }
            self.error = nil
            await generatePlan()
            return true
        } catch {
            self.error = "Could not resync IBKR: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func unlinkIbkr() async -> Bool {
        ibkrSyncing = true
        defer { ibkrSyncing = false }
        do {
            try await WiseCatAPI.unlinkIbkr()
            self.ibkrStatus = try await WiseCatAPI.getIbkrStatus()
            self.error = nil
            return true
        } catch {
            self.error = "Could not unlink IBKR: \(error.localizedDescription)"
            return false
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
