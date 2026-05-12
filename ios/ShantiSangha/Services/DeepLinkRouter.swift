import Foundation

/// Holds the most recently received deep-link state for the running app.
/// Views observe this to present the matching modal (e.g. invite acceptance).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingInviteToken: String?
    /// Set when the user taps a "new message" push. The Circles tab
    /// resolves this to the matching Connection and pushes the chat
    /// thread; the FriendChatView clears it once shown.
    @Published var pendingChatFriendshipId: UUID?

    private init() {}

    func handle(url: URL) {
        if let token = FriendsDeepLink.parse(url) {
            pendingInviteToken = token
        }
    }

    /// Called from the notification tap handler when the payload's
    /// `type` is `friend_message`. Stores a routing intent that
    /// FriendsTabView observes to push the matching chat thread.
    func handleChatNotification(friendshipId: UUID) {
        pendingChatFriendshipId = friendshipId
    }

    func clear() {
        pendingInviteToken = nil
    }

    func clearChat() {
        pendingChatFriendshipId = nil
    }
}
