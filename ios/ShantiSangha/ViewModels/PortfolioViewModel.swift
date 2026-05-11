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
}
