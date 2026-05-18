import Foundation
import SwiftUI

/// App-wide badge counts surfaced on the tab bar. Exposes the two
/// concerns separately so the Chats tab badges unread messages and the
/// Circles tab badges pending incoming friend requests — the same
/// service refreshes both with one set of API calls.
///
/// Sources of truth are `/friends/requests/incoming` and `/friends`.
/// Pending friend requests deliberately do NOT live in the bell-icon
/// notifications inbox (the inbox carries terminal events only); this
/// service is the indicator surface for them and message unread counts.
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

    @Published private(set) var unreadMessagesCount: Int = 0
    @Published private(set) var requestsCount: Int = 0

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
            async let requests = NotificationsAPI.listIncomingRequests()
            async let friends = FriendsAPI.listFriends()
            let requestRows = try await requests
            let friendRows = try await friends
            requestsCount = requestRows.count
            unreadMessagesCount = friendRows.reduce(0) { $0 + $1.unreadCount }
        } catch {
            // Silent — a stale badge is better than a noisy error in
            // a passive tab indicator. The next refresh trigger will
            // try again.
        }
    }
}
