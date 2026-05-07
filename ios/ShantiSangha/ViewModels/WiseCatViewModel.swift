import Foundation
import SwiftUI

@MainActor
final class WiseCatViewModel: ObservableObject {
    @Published var watchlist: [WatchlistEntry] = []
    @Published var signals: [TradingSignal] = []
    @Published var loading = false
    @Published var error: String?
    @Published var generatingTickers: Set<String> = []

    private var pushObserver: NSObjectProtocol?

    init() {
        pushObserver = NotificationCenter.default.addObserver(
            forName: .tradingSignalReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    deinit {
        if let pushObserver { NotificationCenter.default.removeObserver(pushObserver) }
    }

    func refresh() async {
        loading = true
        defer { loading = false }

        do {
            async let wl = WiseCatAPI.listWatchlist()
            async let sig = WiseCatAPI.getSignals()
            self.watchlist = try await wl
            self.signals = try await sig
            self.error = nil
        } catch {
            if error.isCancellation { return }
            self.error = error.localizedDescription
            return
        }

        // For any watchlist ticker without a cached signal — typically a
        // freshly-added one, before the daily Hangfire job runs — generate
        // on-demand in parallel and stream results into the UI as each lands.
        let missing = watchlist
            .map { $0.ticker }
            .filter { ticker in !signals.contains(where: { $0.ticker == ticker }) }
        if missing.isEmpty { return }

        generatingTickers = Set(missing)
        await withTaskGroup(of: TradingSignal?.self) { group in
            for ticker in missing {
                group.addTask {
                    try? await WiseCatAPI.getSignal(ticker)
                }
            }
            for await signal in group {
                guard let signal else { continue }
                if !self.signals.contains(where: { $0.ticker == signal.ticker }) {
                    self.signals.append(signal)
                }
                self.generatingTickers.remove(signal.ticker)
            }
        }
        generatingTickers = []
    }

    func add(_ ticker: String) async {
        let cleaned = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return }
        do {
            _ = try await WiseCatAPI.addWatchlist(cleaned)
            await refresh()
        } catch {
            if error.isCancellation { return }
            self.error = error.localizedDescription
        }
    }

    func remove(_ ticker: String) async {
        do {
            try await WiseCatAPI.removeWatchlist(ticker)
            await refresh()
        } catch {
            if error.isCancellation { return }
            self.error = error.localizedDescription
        }
    }

    func signal(for ticker: String) -> TradingSignal? {
        signals.first(where: { $0.ticker == ticker })
    }

    var hasStrongCalls: Bool {
        signals.contains(where: { $0.conviction >= 0.7 && $0.action != "Hold" })
    }

    /// Today's global astrological context — user's natal transits + panchang.
    /// These angles are the same for every ticker today; we lift them from any
    /// available signal so the user sees them once rather than repeated under
    /// each stock.
    struct TodaysSky {
        let userNatal: AstroAngleScore
        let panchang: AstroAngleScore
    }

    var todaysSky: TodaysSky? {
        for signal in signals {
            let userNatal = signal.astroAngles.first(where: { $0.angle == "user_natal" })
            let panchang = signal.astroAngles.first(where: { $0.angle == "panchang" })
            if let userNatal, let panchang {
                return TodaysSky(userNatal: userNatal, panchang: panchang)
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let tradingSignalReceived = Notification.Name("tradingSignalReceived")
}
