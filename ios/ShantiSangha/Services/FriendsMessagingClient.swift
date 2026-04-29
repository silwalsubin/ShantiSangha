import Foundation

/// Test seam for the chat-message API surface used by `FriendChatViewModel`.
/// Production code uses `LiveFriendsMessagingClient`, which forwards to the
/// `FriendsAPI` static methods. Tests pass a fake to drive the VM without
/// touching the network.
protocol FriendsMessagingClient {
    func listMessages(friendshipId: UUID, before: Date?, limit: Int) async throws -> [FriendMessage]
    func sendText(friendshipId: UUID, body: String, replyToMessageId: UUID?) async throws -> FriendMessage
    func createImageUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse
    func createVoiceUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse
    func uploadMedia(uploadUrl: String, contentType: String, data: Data) async throws
    func commitImage(friendshipId: UUID, objectKey: String, replyToMessageId: UUID?) async throws -> FriendMessage
    func commitVoice(friendshipId: UUID, objectKey: String, durationMs: Int, replyToMessageId: UUID?) async throws -> FriendMessage
    func markReadThrough(friendshipId: UUID, lastMessageId: UUID) async throws
    func editText(friendshipId: UUID, messageId: UUID, body: String) async throws -> FriendMessage
    func deleteMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage
    func reactToMessage(friendshipId: UUID, messageId: UUID, emoji: String) async throws -> FriendMessage
    func unreactToMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage
}

struct LiveFriendsMessagingClient: FriendsMessagingClient {
    func listMessages(friendshipId: UUID, before: Date?, limit: Int) async throws -> [FriendMessage] {
        try await FriendsAPI.listMessages(friendshipId: friendshipId, before: before, limit: limit)
    }
    func sendText(friendshipId: UUID, body: String, replyToMessageId: UUID?) async throws -> FriendMessage {
        try await FriendsAPI.sendText(friendshipId: friendshipId, body: body, replyToMessageId: replyToMessageId)
    }
    func createImageUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        try await FriendsAPI.createImageUpload(friendshipId: friendshipId, contentType: contentType)
    }
    func createVoiceUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        try await FriendsAPI.createVoiceUpload(friendshipId: friendshipId, contentType: contentType)
    }
    func uploadMedia(uploadUrl: String, contentType: String, data: Data) async throws {
        try await FriendsAPI.uploadMedia(uploadUrl: uploadUrl, contentType: contentType, data: data)
    }
    func commitImage(friendshipId: UUID, objectKey: String, replyToMessageId: UUID?) async throws -> FriendMessage {
        try await FriendsAPI.commitImage(friendshipId: friendshipId, objectKey: objectKey, replyToMessageId: replyToMessageId)
    }
    func commitVoice(friendshipId: UUID, objectKey: String, durationMs: Int, replyToMessageId: UUID?) async throws -> FriendMessage {
        try await FriendsAPI.commitVoice(friendshipId: friendshipId, objectKey: objectKey, durationMs: durationMs, replyToMessageId: replyToMessageId)
    }
    func markReadThrough(friendshipId: UUID, lastMessageId: UUID) async throws {
        try await FriendsAPI.markReadThrough(friendshipId: friendshipId, lastMessageId: lastMessageId)
    }
    func editText(friendshipId: UUID, messageId: UUID, body: String) async throws -> FriendMessage {
        try await FriendsAPI.editText(friendshipId: friendshipId, messageId: messageId, body: body)
    }
    func deleteMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage {
        try await FriendsAPI.deleteMessage(friendshipId: friendshipId, messageId: messageId)
    }
    func reactToMessage(friendshipId: UUID, messageId: UUID, emoji: String) async throws -> FriendMessage {
        try await FriendsAPI.reactToMessage(friendshipId: friendshipId, messageId: messageId, emoji: emoji)
    }
    func unreactToMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage {
        try await FriendsAPI.unreactToMessage(friendshipId: friendshipId, messageId: messageId)
    }
}
