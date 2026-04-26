import Foundation

/// Typed wrapper around `ApiService` for the Friends + chat endpoints.
/// Mirrors the backend `FriendsController` and `FriendMessagesController`.
enum FriendsAPI {
    static func listFriends() async throws -> [FriendSummary] {
        try await ApiService.shared.get("/friends")
    }

    static func getFriend(_ friendshipId: UUID) async throws -> FriendSummary {
        try await ApiService.shared.get("/friends/\(friendshipId.uuidString.lowercased())")
    }

    static func createInvitation() async throws -> CreateInvitationResponse {
        try await ApiService.shared.post("/friends/invitations")
    }

    static func listInvitations() async throws -> [PendingInvitation] {
        try await ApiService.shared.get("/friends/invitations")
    }

    static func revokeInvitation(_ invitationId: UUID) async throws {
        try await ApiService.shared.delete("/friends/invitations/\(invitationId.uuidString.lowercased())")
    }

    static func previewInvitation(token: String) async throws -> InvitationPreview {
        let escaped = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token
        return try await ApiService.shared.get("/friends/invitations/preview/\(escaped)")
    }

    struct AcceptBody: Encodable { let token: String }
    static func acceptInvitation(token: String) async throws -> FriendSummary {
        try await ApiService.shared.post("/friends/invitations/accept", body: AcceptBody(token: token))
    }

    static func endFriendship(_ friendshipId: UUID) async throws {
        try await ApiService.shared.delete("/friends/\(friendshipId.uuidString.lowercased())")
    }

    // MARK: - Messages

    static func listMessages(friendshipId: UUID, before: Date? = nil, limit: Int = 50) async throws -> [FriendMessage] {
        var path = "/friends/\(friendshipId.uuidString.lowercased())/messages?limit=\(limit)"
        if let before = before {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let beforeStr = f.string(from: before).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            path += "&before=\(beforeStr)"
        }
        return try await ApiService.shared.get(path)
    }

    struct SendTextBody: Encodable { let body: String }
    static func sendText(friendshipId: UUID, body: String) async throws -> FriendMessage {
        try await ApiService.shared.post("/friends/\(friendshipId.uuidString.lowercased())/messages", body: SendTextBody(body: body))
    }

    struct UploadUrlBody: Encodable { let contentType: String }
    static func createImageUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        try await ApiService.shared.post("/friends/\(friendshipId.uuidString.lowercased())/messages/image/upload-url",
                                          body: UploadUrlBody(contentType: contentType))
    }

    static func createVoiceUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        try await ApiService.shared.post("/friends/\(friendshipId.uuidString.lowercased())/messages/voice/upload-url",
                                          body: UploadUrlBody(contentType: contentType))
    }

    struct CommitMediaBody: Encodable {
        let objectKey: String
        let durationMs: Int?
    }
    static func commitImage(friendshipId: UUID, objectKey: String) async throws -> FriendMessage {
        try await ApiService.shared.post("/friends/\(friendshipId.uuidString.lowercased())/messages/image",
                                          body: CommitMediaBody(objectKey: objectKey, durationMs: nil))
    }
    static func commitVoice(friendshipId: UUID, objectKey: String, durationMs: Int) async throws -> FriendMessage {
        try await ApiService.shared.post("/friends/\(friendshipId.uuidString.lowercased())/messages/voice",
                                          body: CommitMediaBody(objectKey: objectKey, durationMs: durationMs))
    }

    static func markRead(friendshipId: UUID, messageId: UUID) async throws {
        let _: EmptyResponse = try await ApiService.shared.post(
            "/friends/\(friendshipId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())/read")
    }

    struct EditTextBody: Encodable { let body: String }
    /// Sender-only edit, Text only, within 15 minutes of send. Backend
    /// rejects with 422 + `error: "edit_window_expired"` past the window;
    /// the caller is expected to gate the UI affordance, but this enforces
    /// it server-side.
    static func editText(friendshipId: UUID, messageId: UUID, body: String) async throws -> FriendMessage {
        try await ApiService.shared.put(
            "/friends/\(friendshipId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())",
            body: EditTextBody(body: body))
    }

    /// Sender-only soft delete. Idempotent — re-deleting returns the
    /// existing row (with `deletedAt` set, body blanked, media removed).
    static func deleteMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage {
        try await ApiService.shared.deleteReturning(
            "/friends/\(friendshipId.uuidString.lowercased())/messages/\(messageId.uuidString.lowercased())")
    }

    /// Direct PUT upload of binary data to a presigned S3 URL — used by image
    /// and voice attachment flows. Returns when the upload is complete; throws
    /// on non-2xx.
    static func uploadMedia(uploadUrl: String, contentType: String, data: Data) async throws {
        guard let url = URL(string: uploadUrl) else { throw ApiError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ApiError.invalidResponse
        }
    }
}
