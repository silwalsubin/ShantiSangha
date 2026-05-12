import Foundation
import SwiftData

/// Observable sync status for UI indicators.
@MainActor
class SyncStatus: ObservableObject {
    static let shared = SyncStatus()
    @Published var syncing = false
    @Published var pendingCount = 0
}

/// Manages queued writes for offline-first sync.
/// When online: sends immediately. When offline: queues for later.
///
/// No feature currently enqueues work — reminders write through the server
/// directly and don't need an offline cache. Kept here as the infrastructure
/// hook for any future offline-capable feature.
actor SyncService {
    static let shared = SyncService()

    private let api = ApiService.shared
    private var modelContainer: ModelContainer?
    private var isDraining = false

    func configure(container: ModelContainer) {
        self.modelContainer = container
    }

    /// Queue a write operation for background sync
    func enqueue(method: String, path: String, body: Encodable? = nil, tempId: String? = nil) {
        guard let container = modelContainer else { return }
        let bodyData: Data?
        if let rawBody = body as? RawData {
            bodyData = rawBody.data
        } else if let body = body {
            bodyData = try? JSONEncoder().encode(body)
        } else {
            bodyData = nil
        }

        let context = ModelContext(container)
        let item = SyncQueueItem(method: method, path: path, body: bodyData, tempId: tempId)
        context.insert(item)
        try? context.save()

        // Update pending count
        let count = (try? context.fetch(FetchDescriptor<SyncQueueItem>()))?.count ?? 0
        Task { @MainActor in SyncStatus.shared.pendingCount = count }

        // Try to send immediately
        Task { await drain() }
    }

    /// Send all pending queue items with exponential backoff, 404/401 handling
    func drain() async {
        guard let container = modelContainer else { return }
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        await MainActor.run { SyncStatus.shared.syncing = true }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SyncQueueItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let items = try? context.fetch(descriptor), !items.isEmpty else {
            await MainActor.run {
                SyncStatus.shared.syncing = false
                SyncStatus.shared.pendingCount = 0
            }
            return
        }

        var hasSkippedItems = false

        for item in items {
            // Discard items older than 24h
            if item.createdAt.timeIntervalSinceNow < -86400 {
                context.delete(item)
                continue
            }

            // Discard items that exceeded max retries
            if item.retryCount >= 5 {
                context.delete(item)
                continue
            }

            // Exponential backoff: 1s, 2s, 4s, 8s, 16s
            if item.retryCount > 0, let lastAttempt = item.lastAttemptedAt {
                let backoff = pow(2.0, Double(item.retryCount - 1))
                if Date().timeIntervalSince(lastAttempt) < backoff {
                    hasSkippedItems = true
                    continue
                }
            }

            do {
                try await sendItem(item)
                await log(.info, "Synced \(item.method) \(item.path)")
                context.delete(item)
            } catch {
                if case ApiError.httpError(let statusCode, let responseData) = error {
                    switch statusCode {
                    case 404:
                        // Resource gone server-side — discard
                        await log(.warn, "404 \(item.method) \(item.path) — discarding")
                        context.delete(item)
                    case 401:
                        // Token expired — don't count as retry, stop draining
                        await log(.warn, "401 — token may be expired, will retry later")
                        item.lastAttemptedAt = Date()
                        try? context.save()
                        break
                    default:
                        item.retryCount += 1
                        item.lastAttemptedAt = Date()
                        let body = String(data: responseData, encoding: .utf8) ?? ""
                        await log(.error, "\(item.method) \(item.path): HTTP \(statusCode) \(body) (retry \(item.retryCount))")
                    }
                } else {
                    item.retryCount += 1
                    item.lastAttemptedAt = Date()
                    await log(.error, "\(item.method) \(item.path): \(error) (retry \(item.retryCount))")
                }
            }
        }

        try? context.save()

        // Update UI state
        let remaining = (try? context.fetch(FetchDescriptor<SyncQueueItem>()))?.count ?? 0
        await MainActor.run {
            SyncStatus.shared.syncing = false
            SyncStatus.shared.pendingCount = remaining
        }

        // Re-drain after delay if items were skipped due to backoff
        if hasSkippedItems {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.drain()
            }
        }
    }

    /// Send a single queue item. Generic — no per-feature decoding.
    private func sendItem(_ item: SyncQueueItem) async throws {
        switch item.method {
        case "POST":
            if let body = item.body {
                let _: EmptyResponse = try await api.postRaw(item.path, body: body)
            }
        case "PATCH":
            if let body = item.body {
                let _: EmptyResponse = try await api.patchRaw(item.path, body: body)
            }
        case "DELETE":
            try await api.delete(item.path)
        default:
            break
        }
    }

    /// Log to AppLogger from actor context
    private func log(_ level: AppLogger.LogEntry.Level, _ message: String) async {
        await MainActor.run {
            switch level {
            case .info: AppLogger.shared.info("Sync", message)
            case .warn: AppLogger.shared.warn("Sync", message)
            case .error: AppLogger.shared.error("Sync", message)
            }
        }
    }
}
