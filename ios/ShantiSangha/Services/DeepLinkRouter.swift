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
    /// Text the user shared into the app from another app's share sheet
    /// (Safari, Notes, Messages, etc.). Home observes this and opens
    /// the assistant chat with the text pre-filled in the composer.
    @Published var pendingSharedText: String?

    private static let appGroup = "group.com.shantisangha.app"
    private static let sharedTextKey = "share.pendingText"
    private static let sharedDateKey = "share.pendingDate"
    /// Shared payloads older than this are ignored on cold launch so
    /// a stale write from days ago doesn't surprise the user.
    private static let staleAfter: TimeInterval = 60 * 60

    private init() {}

    func handle(url: URL) {
        if url.scheme == "shantisangha", url.host == "share" {
            consumeSharedText()
            return
        }
        if let token = FriendsDeepLink.parse(url) {
            pendingInviteToken = token
        }
    }

    /// Drains any shared payload sitting in the App Group container.
    /// Called from `handle(url:)` on a warm launch via the share
    /// extension, and from the app's `.task` on cold launch so a kill
    /// + share still surfaces the text once the UI is up.
    func consumeSharedText() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let text = defaults.string(forKey: Self.sharedTextKey),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        if let date = defaults.object(forKey: Self.sharedDateKey) as? Date,
           Date().timeIntervalSince(date) > Self.staleAfter {
            defaults.removeObject(forKey: Self.sharedTextKey)
            defaults.removeObject(forKey: Self.sharedDateKey)
            return
        }

        defaults.removeObject(forKey: Self.sharedTextKey)
        defaults.removeObject(forKey: Self.sharedDateKey)
        pendingSharedText = text
    }

    /// Called from the notification tap handler when the payload's
    /// `type` is `friend_message`. Stores a routing intent that
    /// ChatsTabView observes to push the matching chat thread.
    func handleChatNotification(friendshipId: UUID) {
        pendingChatFriendshipId = friendshipId
    }

    func clear() {
        pendingInviteToken = nil
    }

    func clearChat() {
        pendingChatFriendshipId = nil
    }

    func clearSharedText() {
        pendingSharedText = nil
    }
}
