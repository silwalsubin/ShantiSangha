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

        // Regenerate any ticker whose cached signal is missing, from an
        // earlier UTC day, or has empty technical contributions (which
        // typically means an upstream Lambda call failed and persisted a
        // hollow row — e.g. the Finnhub 403 incident). Existing healthy
        // rows for today are kept as-is so the UI doesn't churn.
        let needsRefresh = watchlist
            .map { $0.ticker }
            .filter { ticker in
                guard let signal = signals.first(where: { $0.ticker == ticker }) else { return true }
                return isStale(signal)
            }
        if needsRefresh.isEmpty { return }

        generatingTickers = Set(needsRefresh)
        await withTaskGroup(of: TradingSignal?.self) { group in
            for ticker in needsRefresh {
                group.addTask {
                    try? await WiseCatAPI.getSignal(ticker)
                }
            }
            for await signal in group {
                guard let signal else { continue }
                if let idx = self.signals.firstIndex(where: { $0.ticker == signal.ticker }) {
                    self.signals[idx] = signal
                } else {
                    self.signals.append(signal)
                }
                self.generatingTickers.remove(signal.ticker)
            }
        }
        generatingTickers = []
    }

    private static let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func isStale(_ signal: TradingSignal) -> Bool {
        // Calendar-day check applies to every row — yesterday's signal is
        // always stale regardless of which scoring path produced it.
        if signal.date != Self.utcDateFormatter.string(from: Date()) { return true }

        // The "empty technicalSignals" heuristic was added to catch hollow
        // legacy rows persisted after an upstream Lambda failure (Finnhub
        // 403 incident). It only signals failure for legacy weighted-sum
        // rows — GBM-served horizons return `signals = []` by design
        // (per-feature SHAP is a Phase 4 follow-up). Skip the heuristic
        // when the 1M horizon already carries a real probabilistic
        // verdict.
        if !signal.horizon1M.hasProbabilisticVerdict
            && signal.technicalSignals.isEmpty {
            return true
        }
        return false
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
}

extension Notification.Name {
    static let tradingSignalReceived = Notification.Name("tradingSignalReceived")
}
