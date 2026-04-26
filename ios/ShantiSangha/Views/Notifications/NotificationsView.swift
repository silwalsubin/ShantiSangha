import SwiftUI

/// The in-app notification inbox. Pushed from the bell icon on Home.
/// Auto-marks all notifications as viewed when the view appears (clears
/// the bell badge) but rows stay visible — for friend requests, the row
/// itself carries Accept/Decline buttons that resolve the underlying
/// FriendRequest entity.
struct NotificationsView: View {
    @StateObject private var vm = NotificationsViewModel()
    @State private var pushedFriendship: FriendSummary?

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
                            subtitle: "Notifications about friend requests and accepted connections will land here.")
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else {
                        ForEach(vm.notifications) { notification in
                            NotificationRow(
                                notification: notification,
                                onAccept: { requestId in
                                    Task {
                                        if let summary = await vm.acceptRequest(requestId, removingNotification: notification.id) {
                                            pushedFriendship = summary
                                        }
                                    }
                                },
                                onDecline: { requestId in
                                    Task { await vm.declineRequest(requestId, removingNotification: notification.id) }
                                })
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
        .navigationDestination(item: $pushedFriendship) { friendship in
            FriendChatView(friend: friendship)
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification
    let onAccept: (UUID) -> Void
    let onDecline: (UUID) -> Void

    var body: some View {
        switch notification.type {
        case "friend_request_received":
            if let payload = decode(FriendRequestReceivedPayload.self) {
                FriendRequestReceivedRow(
                    notification: notification,
                    payload: payload,
                    onAccept: { onAccept(payload.requestId) },
                    onDecline: { onDecline(payload.requestId) })
            } else {
                fallbackRow
            }
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

private struct FriendRequestReceivedRow: View {
    let notification: AppNotification
    let payload: FriendRequestReceivedPayload
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: SacredSpacing.s) {
            HStack(spacing: SacredSpacing.s) {
                SacredAvatar(
                    displayName: payload.fromDisplayName,
                    avatarUrl: payload.fromAvatarUrl,
                    size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.fromDisplayName)
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    Text("wants to be friends")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }

                Spacer()

                Text(relativeTime(from: notification.createdAt))
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }

            HStack(spacing: SacredSpacing.s) {
                Button("Decline") { onDecline() }
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredMuted)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Capsule().fill(Color.sacredBgCard))

                Button("Accept") { onAccept() }
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Capsule().fill(LinearGradient.sacredGoldShinyVertical))
            }
            .buttonStyle(.plain)
        }
        .padding(SacredSpacing.s)
        .luxCardChrome()
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
