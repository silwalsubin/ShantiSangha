import Foundation

/// Holds the most recently received deep-link state for the running app.
/// Views observe this to present the matching modal (e.g. invite acceptance).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingInviteToken: String?

    private init() {}

    func handle(url: URL) {
        if let token = FriendsDeepLink.parse(url) {
            pendingInviteToken = token
        }
    }

    func clear() {
        pendingInviteToken = nil
    }
}
