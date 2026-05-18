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

}
