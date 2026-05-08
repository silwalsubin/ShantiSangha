import Foundation

/// Holds the most recently received deep-link state for the running app.
/// Views observe this to present the matching modal (e.g. invite acceptance)
/// or push the matching destination (e.g. open a friend's profile when their
/// birth-chart-shared push is tapped).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingInviteToken: String?

    /// User ID of a friend whose profile we should jump to. Set from a
    /// notification-tap handler (e.g. birth_details_shared push). The Friends
    /// tab consumes this — finds the matching connection, navigates to its
    /// detail, and clears the field.
    @Published var pendingFriendUserId: UUID?

    private init() {}

    func handle(url: URL) {
        if let token = FriendsDeepLink.parse(url) {
            pendingInviteToken = token
        }
    }

    func clear() {
        pendingInviteToken = nil
    }

    func clearFriend() {
        pendingFriendUserId = nil
    }
}
