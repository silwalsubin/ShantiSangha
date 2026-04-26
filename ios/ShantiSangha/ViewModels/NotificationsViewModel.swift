import Foundation
import SwiftUI
import UserNotifications

/// Drives the bell-icon badge on Home AND the inbox screen. One source
/// of truth so a notification-shaped push that lands while you're on
/// Home flips the badge AND populates the inbox without a duplicate
/// fetch when you tap into it.
///
/// Pending friend requests are not part of this surface — they live on
/// the Friends tab "REQUESTS RECEIVED" card and are tracked separately
/// by `FriendsBadgeService`. The bell inbox is for terminal events.
///
/// Home-screen icon badge sync: every assignment to `unreadCount`
/// mirrors itself onto `UNUserNotificationCenter.setBadgeCount`. Using
/// didSet rather than calling at every assignment site means new code
/// paths (future notification types, optimistic clears, refresh after
/// push) automatically keep the home-screen icon honest without anyone
/// having to remember.
@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0 {
        didSet {
            guard oldValue != unreadCount else { return }
            // Fire-and-forget — `try?` swallows the "user denied
            // notification permission" error path; in that case the
            // home-screen badge simply doesn't update and the in-app
            // bell badge keeps working on its own.
            Task {
                try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
            }
        }
    }
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?

    private var observer: NSObjectProtocol?

    init() {
        // React to push-driven cache invalidations posted by SilentPushHandler.
        // Either a friend_request_received or friend_request_accepted push
        // landing should refresh the badge; if the user is on the inbox
        // screen, refresh the list too.
        observer = NotificationCenter.default.addObserver(
            forName: .notificationsRefreshNeeded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Pull the inbox + unread count in one round trip.
    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await NotificationsAPI.list()
            notifications = resp.notifications
            unreadCount = resp.unreadCount
            errorMessage = nil
        } catch {
            if !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Cheap badge-only refresh. Used on app foreground / silent push so
    /// the bell icon stays accurate without forcing a full inbox fetch.
    func refreshUnreadCount() async {
        do {
            let resp = try await NotificationsAPI.unreadCount()
            unreadCount = resp.unreadCount
        } catch {
            // Silent — the badge just stays stale until the next refresh.
        }
    }

    /// Mark every notification as viewed. Called automatically when the
    /// inbox screen appears. Optimistically zeroes the local count so the
    /// bell badge clears even before the network round-trip lands.
    func markAllViewedOnView() async {
        let prevCount = unreadCount
        unreadCount = 0
        do {
            try await NotificationsAPI.markAllViewed()
        } catch {
            // Roll back on failure — better to show a stale badge than
            // lie that we cleared the unread state.
            unreadCount = prevCount
            errorMessage = error.localizedDescription
        }
    }

}

extension Notification.Name {
    /// Posted by SilentPushHandler whenever a notification-shaped push
    /// arrives (friend_request_received, friend_request_accepted, or any
    /// future type). Triggers a refresh in any active NotificationsViewModel.
    static let notificationsRefreshNeeded = Notification.Name("notificationsRefreshNeeded")
}
