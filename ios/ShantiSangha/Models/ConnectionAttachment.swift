import Foundation

/// Mirror of the backend `ConnectionAttachmentResponse`. Owner-private
/// keepsake (photo, video, file) attached to a single Connection.
/// `kind` is server-assigned from the content type so the iOS UI can
/// split MEDIA from FILES without trusting itself. `downloadUrl` is a
/// short-lived presigned GET — refetch the list to refresh.
struct ConnectionAttachment: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let connectionId: UUID
    let objectKey: String
    let contentType: String
    let byteSize: Int64
    let fileName: String
    let kind: ConnectionAttachmentKind
    let caption: String?
    let downloadUrl: String
    let createdAt: String
    let updatedAt: String

    /// Stable identity for SwiftUI `task(id:)` reloads — combines the
    /// stable id with the rotating download URL so the avatar-style
    /// "refetch when URL changes" pattern keeps working.
    var taskKey: String { "\(id.uuidString):\(downloadUrl)" }
}

enum ConnectionAttachmentKind: String, Codable {
    case media = "Media"
    case file = "File"
}

struct CreateConnectionAttachmentUploadRequest: Encodable {
    let contentType: String
    var fileName: String? = nil
}

struct CreateConnectionAttachmentUploadResponse: Decodable {
    let objectKey: String
    let uploadUrl: String
    let uploadUrlExpiresAt: String
}

struct CommitConnectionAttachmentRequest: Encodable {
    let objectKey: String
    let contentType: String
    let fileName: String
    var caption: String? = nil
}

struct UpdateConnectionAttachmentRequest: Encodable {
    /// Empty string clears the caption; nil leaves it unchanged.
    var caption: String? = nil
}
