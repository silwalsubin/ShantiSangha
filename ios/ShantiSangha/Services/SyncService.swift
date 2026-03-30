import Foundation
import SwiftData

/// Manages queued writes for offline-first sync.
/// When online: sends immediately. When offline: queues for later.
actor SyncService {
    static let shared = SyncService()

    private let api = ApiService.shared
    private var modelContainer: ModelContainer?

    func configure(container: ModelContainer) {
        self.modelContainer = container
    }

    /// Queue a write operation for background sync
    func enqueue(method: String, path: String, body: Encodable? = nil) {
        guard let container = modelContainer else { return }
        let bodyData = body != nil ? try? JSONEncoder().encode(body!) : nil

        let context = ModelContext(container)
        let item = SyncQueueItem(method: method, path: path, body: bodyData)
        context.insert(item)
        try? context.save()

        // Try to send immediately
        Task { await drain() }
    }

    /// Send all pending queue items
    func drain() async {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<SyncQueueItem>(
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return }

        for item in items {
            // Skip items older than 24h
            if item.createdAt.timeIntervalSinceNow < -86400 {
                context.delete(item)
                continue
            }

            // Skip items that have been retried too many times
            if item.retryCount >= 5 {
                context.delete(item)
                continue
            }

            do {
                try await sendItem(item)
                context.delete(item)
            } catch {
                item.retryCount += 1
                print("[Sync] Failed to sync \(item.method) \(item.path): \(error) (retry \(item.retryCount))")
            }
        }

        try? context.save()
    }

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
}
