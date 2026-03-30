import Foundation
import Network
import Combine

/// Monitors network connectivity. Triggers sync when connection restores.
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasDisconnected = self?.isConnected == false
                self?.isConnected = path.status == .satisfied

                // Trigger sync when coming back online
                if wasDisconnected && path.status == .satisfied {
                    await SyncService.shared.drain()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
