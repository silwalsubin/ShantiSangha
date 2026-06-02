import Foundation

/// A photo shared into the app from another app's share sheet, waiting to
/// be sent to a connection. Carries the raw bytes (already drained from
/// the App Group container) plus its content type.
struct SharedMediaPayload: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let contentType: String
}

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
    /// A photo shared in from another app, waiting to be sent to a
    /// connection. MainTabView observes this and presents the
    /// share-to-connection picker.
    @Published var pendingSharedMedia: SharedMediaPayload?
    /// A photo the user chose to send to the assistant (from the share
    /// picker). Home observes this and opens the assistant chat with the
    /// photo staged in the composer so the user can add a question.
    @Published var pendingAssistantImage: SharedMediaPayload?

    private static let appGroup = "group.com.shantisangha.app"
    private static let sharedTextKey = "share.pendingText"
    private static let sharedDateKey = "share.pendingDate"
    private static let sharedMediaNameKey = "share.pendingMediaName"
    private static let sharedMediaTypeKey = "share.pendingMediaType"
    private static let sharedMediaDateKey = "share.pendingMediaDate"
    private static let inboxDir = "SharedInbox"
    /// Shared payloads older than this are ignored on cold launch so
    /// a stale write from days ago doesn't surprise the user.
    private static let staleAfter: TimeInterval = 60 * 60

    private init() {}

    func handle(url: URL) {
        if url.scheme == "shantisangha", url.host == "share" {
            consumeSharedText()
            consumeSharedMedia()
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

    /// Drains a shared photo sitting in the App Group container: reads
    /// the file the share extension wrote, hands the bytes to the UI via
    /// `pendingSharedMedia`, then deletes the file and its breadcrumbs.
    /// Safe to call repeatedly — once drained there's nothing to find.
    func consumeSharedMedia() {
        guard let defaults = UserDefaults(suiteName: Self.appGroup),
              let name = defaults.string(forKey: Self.sharedMediaNameKey),
              let type = defaults.string(forKey: Self.sharedMediaTypeKey),
              let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
        else { return }

        let fileURL = container
            .appendingPathComponent(Self.inboxDir, isDirectory: true)
            .appendingPathComponent(name)

        func cleanup() {
            defaults.removeObject(forKey: Self.sharedMediaNameKey)
            defaults.removeObject(forKey: Self.sharedMediaTypeKey)
            defaults.removeObject(forKey: Self.sharedMediaDateKey)
            try? FileManager.default.removeItem(at: fileURL)
        }

        if let date = defaults.object(forKey: Self.sharedMediaDateKey) as? Date,
           Date().timeIntervalSince(date) > Self.staleAfter {
            cleanup()
            return
        }

        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            cleanup()
            return
        }
        cleanup()
        pendingSharedMedia = SharedMediaPayload(data: data, contentType: type)
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

    func clearSharedMedia() {
        pendingSharedMedia = nil
    }

    func clearAssistantImage() {
        pendingAssistantImage = nil
    }
}
