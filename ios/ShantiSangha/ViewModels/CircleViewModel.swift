import Foundation
import Combine
import SwiftUI

/// Owns the user's Circle (list of `Connection`s) — the new top-level
/// concept that replaces "friends list" in the UI. Pending invitations
/// and incoming/outgoing friend requests still live in
/// `FriendsViewModel` for now; this VM only owns the unified
/// connection list. Both can coexist on the Circle tab during the
/// transition.
@MainActor
final class CircleViewModel: ObservableObject {
    @Published var connections: [Connection] = []
    @Published var loading = false
    @Published var errorMessage: String?

    private var observer: NSObjectProtocol?

    init() {
        // Reuse the same notification the Friends list listens to —
        // friendship lifecycle events should refresh the circle too.
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
        do {
            connections = try await ConnectionsAPI.list()
            errorMessage = nil
        } catch {
            if !error.isCancellation {
                errorMessage = "Couldn't load your circle. Try again."
            }
        }
    }

    /// Adds a new local Person + Connection in one call. The server
    /// returns the full row; we prepend it so the new entry shows at
    /// the top of the list right away.
    @discardableResult
    func addLocal(_ request: CreateConnectionRequest) async throws -> Connection {
        let created = try await ConnectionsAPI.createLocal(request)
        connections.insert(created, at: 0)
        return created
    }

    @discardableResult
    func updateOverlay(
        connectionId: UUID,
        relationType: ConnectionType? = nil,
        customRelationLabel: String? = nil,
        nickname: String? = nil,
        privateNotes: String? = nil,
        clearCustomRelationLabel: Bool = false,
        clearNickname: Bool = false,
        clearPrivateNotes: Bool = false
    ) async throws -> Connection {
        let req = UpdateConnectionRequest(
            relationType: relationType?.rawValue,
            customRelationLabel: customRelationLabel,
            nickname: nickname,
            privateNotes: privateNotes,
            clearCustomRelationLabel: clearCustomRelationLabel ? true : nil,
            clearNickname: clearNickname ? true : nil,
            clearPrivateNotes: clearPrivateNotes ? true : nil)
        let updated = try await ConnectionsAPI.update(connectionId, request: req)
        replaceInPlace(updated)
        return updated
    }

    @discardableResult
    func updatePerson(
        connectionId: UUID,
        request: UpdatePersonRequest
    ) async throws -> Person {
        let person = try await ConnectionsAPI.updatePerson(connectionId, request: request)
        // Re-fetch the connection to pick up the updated embedded person.
        let refreshed = try await ConnectionsAPI.get(connectionId)
        replaceInPlace(refreshed)
        return person
    }

    func delete(connectionId: UUID) async throws {
        try await ConnectionsAPI.delete(connectionId)
        connections.removeAll { $0.id == connectionId }
    }

    private func replaceInPlace(_ updated: Connection) {
        if let i = connections.firstIndex(where: { $0.id == updated.id }) {
            connections[i] = updated
        } else {
            connections.insert(updated, at: 0)
        }
    }
}
