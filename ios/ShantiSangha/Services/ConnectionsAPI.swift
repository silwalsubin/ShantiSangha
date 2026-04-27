import Foundation

/// Typed wrapper around the new `/api/connections` endpoint. Mirrors
/// `ConnectionsController` on the backend.
enum ConnectionsAPI {
    static func list() async throws -> [Connection] {
        try await ApiService.shared.get("/connections")
    }

    static func get(_ connectionId: UUID) async throws -> Connection {
        try await ApiService.shared.get("/connections/\(connectionId.uuidString.lowercased())")
    }

    static func createLocal(_ request: CreateConnectionRequest) async throws -> Connection {
        try await ApiService.shared.post("/connections", body: request)
    }

    static func update(_ connectionId: UUID, request: UpdateConnectionRequest) async throws -> Connection {
        try await ApiService.shared.patch(
            "/connections/\(connectionId.uuidString.lowercased())",
            body: request)
    }

    static func updatePerson(_ connectionId: UUID, request: UpdatePersonRequest) async throws -> Person {
        try await ApiService.shared.patch(
            "/connections/\(connectionId.uuidString.lowercased())/person",
            body: request)
    }

    static func delete(_ connectionId: UUID) async throws {
        try await ApiService.shared.delete("/connections/\(connectionId.uuidString.lowercased())")
    }
}
