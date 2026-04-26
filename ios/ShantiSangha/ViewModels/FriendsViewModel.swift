import Foundation
import Combine
import SwiftUI

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [FriendSummary] = []
    @Published var pendingInvitations: [PendingInvitation] = []
    /// Direct friend requests this user has sent that are still
    /// awaiting a response. Distinct from `pendingInvitations` (which
    /// are token-based share links not yet redeemed).
    @Published var outgoingRequests: [FriendRequestSummary] = []
    /// Direct friend requests sent TO this user that are still pending.
    /// Mirrored to the bell-icon notifications inbox; surfaced here too
    /// so the Friends tab is a durable "where do I stand with each
    /// person" view (the bell inbox is transient).
    @Published var incomingRequests: [FriendRequestSummary] = []
    @Published var loading = false
    @Published var errorMessage: String?

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .friendsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() async {
        loading = true
        defer { loading = false }

        var loadError: Error?

        do {
            friends = try await FriendsAPI.listFriends()
        } catch {
            if !error.isCancellation { loadError = error }
        }

        do {
            pendingInvitations = try await FriendsAPI.listInvitations()
        } catch {
            if !error.isCancellation, loadError == nil { loadError = error }
        }

        do {
            outgoingRequests = try await NotificationsAPI.listOutgoingRequests()
        } catch {
            if !error.isCancellation, loadError == nil { loadError = error }
        }

        do {
            incomingRequests = try await NotificationsAPI.listIncomingRequests()
        } catch {
            if !error.isCancellation, loadError == nil { loadError = error }
        }

        if let loadError {
            errorMessage = friendlyMessage(for: loadError)
        } else {
            errorMessage = nil
        }
    }

    func createInvitation() async -> CreateInvitationResponse? {
        do {
            let result = try await FriendsAPI.createInvitation()
            await refresh()
            return result
        } catch {
            errorMessage = friendlyMessage(for: error)
            return nil
        }
    }

    func revoke(_ invitationId: UUID) async {
        do {
            try await FriendsAPI.revokeInvitation(invitationId)
            await refresh()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Cancel a direct friend request the user previously sent. Drops
    /// the row optimistically; the next refresh reconciles in case the
    /// call failed silently.
    func cancelOutgoingRequest(_ requestId: UUID) async {
        let prev = outgoingRequests
        outgoingRequests.removeAll { $0.id == requestId }
        do {
            try await NotificationsAPI.cancelRequest(requestId)
        } catch {
            outgoingRequests = prev
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Accept an incoming friend request. The new friendship lands in
    /// `friends` on next refresh; we drop the row optimistically and
    /// rely on the post-call refresh to surface it. The bell-inbox copy
    /// of this notification is dismissed via the standard refresh.
    func acceptIncomingRequest(_ requestId: UUID) async {
        let prev = incomingRequests
        incomingRequests.removeAll { $0.id == requestId }
        do {
            _ = try await NotificationsAPI.acceptRequest(requestId)
            await refresh()
            // Notify other surfaces (bell inbox) that the request resolved.
            NotificationCenter.default.post(name: .notificationsRefreshNeeded, object: nil)
        } catch {
            incomingRequests = prev
            errorMessage = friendlyMessage(for: error)
        }
    }

    func declineIncomingRequest(_ requestId: UUID) async {
        let prev = incomingRequests
        incomingRequests.removeAll { $0.id == requestId }
        do {
            try await NotificationsAPI.declineRequest(requestId)
            NotificationCenter.default.post(name: .notificationsRefreshNeeded, object: nil)
        } catch {
            incomingRequests = prev
            errorMessage = friendlyMessage(for: error)
        }
    }

    func endFriendship(_ friendshipId: UUID) async {
        do {
            try await FriendsAPI.endFriendship(friendshipId)
            friends.removeAll { $0.friendshipId == friendshipId }
            errorMessage = nil
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let api = error as? ApiError, case .httpError(let code, let data) = api {
            if code == 422,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = body["error"] as? String,
               err == "display_name_required" {
                return "Set a display name in Settings before inviting friends."
            }
            if code == 429 {
                return "You've created too many invites recently. Try again later."
            }
        }
        return error.localizedDescription
    }
}

extension Notification.Name {
    static let friendsUpdated = Notification.Name("friendsUpdated")
    static let friendMessageReceived = Notification.Name("friendMessageReceived")
}
