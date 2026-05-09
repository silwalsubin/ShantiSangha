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

    /// `circles` follows the backend contract: nil = leave alone,
    /// `[]` = clear, otherwise replace the full set.
    @discardableResult
    func updateOverlay(
        connectionId: UUID,
        circles: [String]? = nil,
        nickname: String? = nil,
        privateNotes: String? = nil,
        clearNickname: Bool = false,
        clearPrivateNotes: Bool = false
    ) async throws -> Connection {
        let req = UpdateConnectionRequest(
            circles: circles,
            nickname: nickname,
            privateNotes: privateNotes,
            clearNickname: clearNickname ? true : nil,
            clearPrivateNotes: clearPrivateNotes ? true : nil)
        let updated = try await ConnectionsAPI.update(connectionId, request: req)
        replaceInPlace(updated)
        return updated
    }

    /// Union of every circle currently in use across the user's
    /// connections, with the count of how many connections carry each
    /// label. Drives the auto-derived filter chips on FriendsTabView and
    /// the "existing circles" suggestions on the chip-input sheet.
    /// Sorted by frequency desc, then name asc.
    var circleCatalog: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for conn in connections {
            for c in conn.circles {
                let key = c.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
            }
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
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

    /// Append a new "important date". Re-fetches the parent connection
    /// so the embedded `dates` list reflects server-side ordering.
    @discardableResult
    func addDate(
        connectionId: UUID,
        label: String,
        date: String,
        recurrence: ConnectionDateRecurrence
    ) async throws -> ConnectionDate {
        let created = try await ConnectionsAPI.addDate(
            connectionId,
            request: AddConnectionDateRequest(
                label: label,
                date: date,
                recurrence: recurrence))
        let refreshed = try await ConnectionsAPI.get(connectionId)
        replaceInPlace(refreshed)
        return created
    }

    @discardableResult
    func updateDate(
        connectionId: UUID,
        dateId: UUID,
        label: String,
        date: String,
        recurrence: ConnectionDateRecurrence
    ) async throws -> ConnectionDate {
        let updated = try await ConnectionsAPI.updateDate(
            connectionId,
            dateId: dateId,
            request: UpdateConnectionDateRequest(
                label: label,
                date: date,
                recurrence: recurrence))
        let refreshed = try await ConnectionsAPI.get(connectionId)
        replaceInPlace(refreshed)
        return updated
    }

    func deleteDate(connectionId: UUID, dateId: UUID) async throws {
        try await ConnectionsAPI.deleteDate(connectionId, dateId: dateId)
        let refreshed = try await ConnectionsAPI.get(connectionId)
        replaceInPlace(refreshed)
    }

    private func replaceInPlace(_ updated: Connection) {
        if let i = connections.firstIndex(where: { $0.id == updated.id }) {
            connections[i] = updated
        } else {
            connections.insert(updated, at: 0)
        }
    }
}
