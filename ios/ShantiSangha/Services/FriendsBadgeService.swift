import Foundation
import SwiftUI

/// App-wide badge count for the Friends tab. Mirrors the count of
/// pending incoming friend requests so the user sees a dot on the tab
/// no matter where they are in the app.
///
/// Source of truth is `/friends/requests/incoming`. Pending friend
/// requests deliberately do NOT live in the bell-icon notifications
/// inbox (the inbox carries terminal events only); this service is the
/// indicator surface for them.
///
/// Refresh triggers:
///   - `friendsUpdated` — posted when a friendship changes (accept,
///     decline, end-friendship, etc.) so the count drops as soon as the
///     user acts.
///   - `notificationsRefreshNeeded` — posted by `SilentPushHandler` when
///     a `friend_request_received` silent push lands. The badge updates
///     without the user opening any specific screen.
@MainActor
final class FriendsBadgeService: ObservableObject {
    static let shared = FriendsBadgeService()

    @Published private(set) var pendingIncomingCount: Int = 0

    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: .friendsUpdated, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refresh() }
            })
        observers.append(
            center.addObserver(forName: .notificationsRefreshNeeded, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.refresh() }
            })
    }

    deinit {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
    }

    func refresh() async {
        do {
            let rows = try await NotificationsAPI.listIncomingRequests()
            pendingIncomingCount = rows.count
        } catch {
            // Silent — a stale badge is better than a noisy error in
            // a passive tab indicator. The next refresh trigger will
            // try again.
        }
    }
}
