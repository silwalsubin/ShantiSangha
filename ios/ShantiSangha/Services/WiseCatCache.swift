import Foundation

/// On-disk cache of WiseCat chart history (per ticker, per range) and the
/// trading signal (per ticker), so the detail screen renders instantly on
/// reopen and the network refresh becomes a stale-while-revalidate pass.
///
/// Each cached payload carries a `refreshedAt` so the view can show a
/// freshness caption — the price chart is public market data shared across
/// users, so the cache key is just the ticker (no user scope needed).
///
/// Pattern mirrors `ChatCache`: Application Support directory, atomic JSON
/// writes on a background queue, synchronous reads from the view's `.task`.
enum WiseCatCache {
    private static let writeQueue = DispatchQueue(label: "wisecat.cache.write", qos: .utility)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()
    private static let decoder = JSONDecoder()

    private static var cacheDir: URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) else { return nil }
        let dir = appSupport.appendingPathComponent("WiseCatCache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func sanitize(_ ticker: String) -> String {
        // Tickers are uppercase A-Z with the occasional `.` (e.g. BRK.B). Lowercase
        // for cross-platform filesystem safety; replace `.` so the filename's only
        // dot is the extension.
        ticker.lowercased().replacingOccurrences(of: ".", with: "_")
    }

    // MARK: - Charts

    /// Disk shape: `[rangeRawValue: ChartHistory]` plus a single refreshedAt.
    /// We don't track per-range refresh times because `prefetchAll()` writes
    /// every range together — they share a fetch wall-clock.
    private struct ChartCacheEntry: Codable {
        let charts: [String: ChartHistory]
        let refreshedAt: Date
    }

    private static func chartFile(for ticker: String) -> URL? {
        cacheDir?.appendingPathComponent("chart-\(sanitize(ticker)).json")
    }

    static func loadCharts(ticker: String) -> (charts: [ChartRange: ChartHistory], refreshedAt: Date)? {
        guard let url = chartFile(for: ticker),
              let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(ChartCacheEntry.self, from: data) else {
            return nil
        }
        var out: [ChartRange: ChartHistory] = [:]
        for (raw, history) in entry.charts {
            if let r = ChartRange(rawValue: raw) { out[r] = history }
        }
        return (out, entry.refreshedAt)
    }

    static func saveCharts(ticker: String, charts: [ChartRange: ChartHistory], refreshedAt: Date) {
        var rawKeyed: [String: ChartHistory] = [:]
        for (r, h) in charts { rawKeyed[r.rawValue] = h }
        let entry = ChartCacheEntry(charts: rawKeyed, refreshedAt: refreshedAt)
        writeQueue.async {
            guard let url = chartFile(for: ticker) else { return }
            do {
                let data = try encoder.encode(entry)
                try data.write(to: url, options: .atomic)
            } catch {
                // Cache failures are silent — the view is already showing
                // fresh data; missing the write just means a refetch on
                // next open.
            }
        }
    }

    // MARK: - Signal

    private struct SignalCacheEntry: Codable {
        let signal: TradingSignal
        let refreshedAt: Date
    }

    private static func signalFile(for ticker: String) -> URL? {
        cacheDir?.appendingPathComponent("signal-\(sanitize(ticker)).json")
    }

    static func loadSignal(ticker: String) -> (signal: TradingSignal, refreshedAt: Date)? {
        guard let url = signalFile(for: ticker),
              let data = try? Data(contentsOf: url),
              let entry = try? decoder.decode(SignalCacheEntry.self, from: data) else {
            return nil
        }
        return (entry.signal, entry.refreshedAt)
    }

    static func saveSignal(ticker: String, signal: TradingSignal, refreshedAt: Date) {
        let entry = SignalCacheEntry(signal: signal, refreshedAt: refreshedAt)
        writeQueue.async {
            guard let url = signalFile(for: ticker) else { return }
            do {
                let data = try encoder.encode(entry)
                try data.write(to: url, options: .atomic)
            } catch {}
        }
    }

    // MARK: - Maintenance

    static func clearAll() {
        guard let dir = cacheDir else { return }
        writeQueue.async {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
