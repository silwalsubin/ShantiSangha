import Foundation
import Combine

/// Shared, lightweight cache of the user's Circle connections so any screen
/// can resolve a `connectionId` to an avatar / display name without each
/// view fetching the list itself. Refreshes from the server on demand;
/// also listens to `.friendsUpdated` so additions / removals propagate.
@MainActor
final class ConnectionsRepository: ObservableObject {
    static let shared = ConnectionsRepository()

    @Published private(set) var connections: [Connection] = []
    @Published private(set) var loading = false

    private var observer: NSObjectProtocol?
    private var lastRefreshAt: Date?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .friendsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Returns the connection for a given id, or nil. Cheap lookup.
    func connection(for id: UUID) -> Connection? {
        connections.first { $0.id == id }
    }

    /// Pulls the full list. Coalesces calls within a short window so callers
    /// can call freely on view appearance without thrashing the network.
    func refresh(force: Bool = false) async {
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < 60 {
            return
        }
        loading = true
        defer { loading = false }
        do {
            connections = try await ConnectionsAPI.list()
            lastRefreshAt = Date()
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Connections", "Refresh failed: \(error)")
            }
        }
    }
}
