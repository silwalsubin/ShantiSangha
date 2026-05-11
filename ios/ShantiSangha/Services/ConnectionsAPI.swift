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

    // ── Attachments (keepsakes) ─────────────────────────────────────

    static func listAttachments(_ connectionId: UUID) async throws -> [ConnectionAttachment] {
        try await ApiService.shared.get(
            "/connections/\(connectionId.uuidString.lowercased())/attachments")
    }

    static func createAttachmentUpload(
        _ connectionId: UUID,
        request: CreateConnectionAttachmentUploadRequest
    ) async throws -> CreateConnectionAttachmentUploadResponse {
        try await ApiService.shared.post(
            "/connections/\(connectionId.uuidString.lowercased())/attachments/upload-url",
            body: request)
    }

    static func commitAttachment(
        _ connectionId: UUID,
        request: CommitConnectionAttachmentRequest
    ) async throws -> ConnectionAttachment {
        try await ApiService.shared.post(
            "/connections/\(connectionId.uuidString.lowercased())/attachments",
            body: request)
    }

    static func updateAttachment(
        _ connectionId: UUID,
        attachmentId: UUID,
        request: UpdateConnectionAttachmentRequest
    ) async throws -> ConnectionAttachment {
        try await ApiService.shared.patch(
            "/connections/\(connectionId.uuidString.lowercased())/attachments/\(attachmentId.uuidString.lowercased())",
            body: request)
    }

    static func deleteAttachment(_ connectionId: UUID, attachmentId: UUID) async throws {
        try await ApiService.shared.delete(
            "/connections/\(connectionId.uuidString.lowercased())/attachments/\(attachmentId.uuidString.lowercased())")
    }

    /// Three-step upload helper used by the keepsake picker:
    /// 1. Ask the backend for a presigned PUT URL.
    /// 2. PUT the bytes directly to S3 (skips ECS so the API doesn't
    ///    relay large videos/files).
    /// 3. Commit, returning the canonical attachment row with its
    ///    presigned download URL.
    /// Throws on any step. Optional `progress` is reported during the
    /// PUT phase only — steps 1 and 3 are tiny JSON round-trips.
    static func uploadAttachment(
        _ connectionId: UUID,
        data: Data,
        contentType: String,
        fileName: String,
        caption: String? = nil
    ) async throws -> ConnectionAttachment {
        let upload = try await createAttachmentUpload(
            connectionId,
            request: CreateConnectionAttachmentUploadRequest(
                contentType: contentType,
                fileName: fileName))

        try await putAttachmentBytes(
            uploadUrl: upload.uploadUrl,
            contentType: contentType,
            data: data)

        return try await commitAttachment(
            connectionId,
            request: CommitConnectionAttachmentRequest(
                objectKey: upload.objectKey,
                contentType: contentType,
                fileName: fileName,
                caption: caption))
    }

    private static func putAttachmentBytes(
        uploadUrl: String,
        contentType: String,
        data: Data
    ) async throws {
        guard let url = URL(string: uploadUrl) else { throw ApiError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw ApiError.invalidResponse
        }
    }

    // ── Owner-private avatar ────────────────────────────────────────

    /// Three-step private-avatar upload, mirroring `uploadAttachment`:
    /// 1. Ask the backend for a presigned PUT URL.
    /// 2. PUT JPEG bytes directly to S3.
    /// 3. PATCH the connection with the new key (backend deletes the
    ///    superseded S3 object out-of-band).
    /// Returns the refreshed `Connection` so callers can update local
    /// state with the new presigned download URL.
    static func uploadPrivateAvatar(
        _ connectionId: UUID,
        jpegData data: Data
    ) async throws -> Connection {
        let upload: CreateConnectionAvatarUploadResponse = try await ApiService.shared.post(
            "/connections/\(connectionId.uuidString.lowercased())/avatar/upload-url",
            body: CreateConnectionAvatarUploadRequest(contentType: "image/jpeg"))

        try await putAttachmentBytes(
            uploadUrl: upload.uploadUrl,
            contentType: "image/jpeg",
            data: data)

        return try await update(
            connectionId,
            request: UpdateConnectionRequest(privateAvatarKey: upload.objectKey))
    }

    /// Drops the owner-private avatar; the linked Person's public
    /// avatar (if any) takes over again. The backend deletes the S3
    /// object out-of-band.
    static func clearPrivateAvatar(_ connectionId: UUID) async throws -> Connection {
        try await update(
            connectionId,
            request: UpdateConnectionRequest(clearPrivateAvatar: true))
    }
}

struct CreateConnectionAvatarUploadRequest: Encodable {
    let contentType: String
}
