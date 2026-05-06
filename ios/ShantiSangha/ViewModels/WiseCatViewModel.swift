import Foundation
import SwiftUI

@MainActor
final class WiseCatViewModel: ObservableObject {
    @Published var watchlist: [WatchlistEntry] = []
    @Published var signals: [TradingSignal] = []
    @Published var loading = false
    @Published var error: String?

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
            self.error = error.localizedDescription
        }
    }

    func add(_ ticker: String) async {
        let cleaned = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cleaned.isEmpty else { return }
        do {
            _ = try await WiseCatAPI.addWatchlist(cleaned)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func remove(_ ticker: String) async {
        do {
            try await WiseCatAPI.removeWatchlist(ticker)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signal(for ticker: String) -> TradingSignal? {
        signals.first(where: { $0.ticker == ticker })
    }

    /// True when no signals have been generated yet (e.g., the daily job hasn't run, or auth-stale state).
    var isStale: Bool { !loading && watchlist.isEmpty == false && signals.isEmpty }

    var hasStrongCalls: Bool {
        signals.contains(where: { $0.conviction >= 0.7 && $0.action != "Hold" })
    }
}

extension Notification.Name {
    static let tradingSignalReceived = Notification.Name("tradingSignalReceived")
}
