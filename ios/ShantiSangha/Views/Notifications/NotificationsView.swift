import SwiftUI

/// The in-app notification inbox. Pushed from the bell icon on Home.
/// Auto-marks all notifications as viewed when the view appears.
///
/// Pending friend requests deliberately do NOT live here — they belong
/// to the Friends tab "REQUESTS RECEIVED" card, which queries the
/// canonical `/friends/requests/incoming` endpoint and is always in sync.
/// The bell inbox carries terminal events only (request accepted, etc.).
struct NotificationsView: View {
    @StateObject private var vm = NotificationsViewModel()

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: SacredSpacing.s) {
                    if vm.loading && vm.notifications.isEmpty {
                        ProgressView()
                            .padding(.top, SacredSpacing.xl * 2)
                    } else if vm.notifications.isEmpty {
                        SacredEmptyState(
                            icon: "bell",
                            title: "Quiet here.",
                            subtitle: "Updates about your connections will land here.")
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else {
                        ForEach(vm.notifications) { notification in
                            NotificationRow(notification: notification)
                        }
                        .padding(.horizontal, SacredSpacing.m)
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredRed)
                            .padding(.horizontal, SacredSpacing.m)
                    }

                    Color.clear.frame(height: SacredSpacing.tabBarSafe)
                }
                .padding(.top, SacredSpacing.m)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.refresh()
            // Mark-viewed runs after the initial fetch so the unread count
            // we just rendered is correct, then we clear it.
            await vm.markAllViewedOnView()
        }
        .refreshable { await vm.refresh() }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        switch notification.type {
        case "friend_request_accepted":
            if let payload = decode(FriendRequestAcceptedPayload.self) {
                FriendRequestAcceptedRow(notification: notification, payload: payload)
            } else {
                fallbackRow
            }
        default:
            fallbackRow
        }
    }

    /// Generic row for unknown types — better to show a stub than fail
    /// silently when the backend ships a new notification type before iOS
    /// catches up.
    private var fallbackRow: some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "bell.fill")
                .font(.sacredSmall)
                .foregroundColor(.sacredGold.opacity(0.6))
            Text(notification.type)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
            Spacer()
            Text(timeLabel)
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(SacredSpacing.s)
        .luxCardChrome()
    }

    private var timeLabel: String {
        relativeTime(from: notification.createdAt)
    }

    private func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = notification.payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private struct FriendRequestAcceptedRow: View {
    let notification: AppNotification
    let payload: FriendRequestAcceptedPayload

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: payload.byDisplayName,
                avatarUrl: payload.byAvatarUrl,
                size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.byDisplayName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                Text("accepted your friend request")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }

            Spacer()

            Text(relativeTime(from: notification.createdAt))
                .font(.sacredMicro)
                .foregroundColor(.sacredMuted)
        }
        .padding(SacredSpacing.s)
        .luxCardChrome()
    }
}

/// Format an ISO-8601 timestamp string as "5m", "2h", "3d", etc.
private func relativeTime(from iso: String) -> String {
    guard let date = FriendsDates.parse(iso) else { return "" }
    let interval = -date.timeIntervalSinceNow
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    return "\(Int(interval / 86400))d"
}
