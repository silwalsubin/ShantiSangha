import Foundation
import Combine
import SwiftUI

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published var friends: [FriendSummary] = []
    @Published var pendingInvitations: [PendingInvitation] = []
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
