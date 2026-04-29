import Foundation
@testable import ShantiSangha

// MARK: - FakeFriendsMessagingClient

/// In-memory stand-in for `LiveFriendsMessagingClient`. Each method
/// either runs the matching closure handler, throws the matching error,
/// or `fatalError`s with the method name — that way an unexpected call
/// from a future code path fails loudly instead of silently returning a
/// bogus value. `@unchecked Sendable` is fine here because XCTest runs
/// each test serially and we never share an instance across tasks.
final class FakeFriendsMessagingClient: FriendsMessagingClient, @unchecked Sendable {

    // MARK: send text

    var sendTextHandler: ((UUID, String, UUID?) -> FriendMessage)?
    var sendTextError: Error?
    private(set) var sendTextCallCount = 0

    /// When true, `sendText` parks on a continuation instead of
    /// returning immediately — the test releases it via
    /// `releaseBlockedSendText`. Use this to hold a send "in flight"
    /// while triggering a concurrent flush / retry.
    var blockSendText = false
    private var sendTextContinuation: CheckedContinuation<FriendMessage, Error>?
    private var sendTextStartedContinuation: CheckedContinuation<Void, Never>?

    /// Suspends until the next `sendText` call has entered its body and
    /// is parked on the blocking continuation. Use to deterministically
    /// know "the send is in flight" before triggering a race.
    func waitForSendTextStarted() async {
        await withCheckedContinuation { cont in
            sendTextStartedContinuation = cont
        }
    }

    func releaseBlockedSendText(with result: Result<FriendMessage, Error>) {
        let cont = sendTextContinuation
        sendTextContinuation = nil
        switch result {
        case .success(let msg): cont?.resume(returning: msg)
        case .failure(let err): cont?.resume(throwing: err)
        }
    }

    func sendText(friendshipId: UUID, body: String, replyToMessageId: UUID?) async throws -> FriendMessage {
        sendTextCallCount += 1
        if let error = sendTextError { throw error }
        if blockSendText {
            return try await withCheckedThrowingContinuation { cont in
                sendTextContinuation = cont
                // Resume the started signal AFTER registering the
                // continuation so the test can trust that "started"
                // means "parked and observable".
                let waiter = sendTextStartedContinuation
                sendTextStartedContinuation = nil
                waiter?.resume()
            }
        }
        guard let handler = sendTextHandler else {
            fatalError("FakeFriendsMessagingClient.sendText called without a handler")
        }
        return handler(friendshipId, body, replyToMessageId)
    }

    // MARK: edit text

    var editTextHandler: ((UUID, UUID, String) -> FriendMessage)?
    var editTextError: Error?
    private(set) var editTextCallCount = 0

    func editText(friendshipId: UUID, messageId: UUID, body: String) async throws -> FriendMessage {
        editTextCallCount += 1
        if let error = editTextError { throw error }
        guard let handler = editTextHandler else {
            fatalError("FakeFriendsMessagingClient.editText called without a handler")
        }
        return handler(friendshipId, messageId, body)
    }

    // MARK: delete message

    var deleteMessageHandler: ((UUID, UUID) -> FriendMessage)?
    var deleteMessageError: Error?
    private(set) var deleteMessageCallCount = 0

    func deleteMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage {
        deleteMessageCallCount += 1
        if let error = deleteMessageError { throw error }
        guard let handler = deleteMessageHandler else {
            fatalError("FakeFriendsMessagingClient.deleteMessage called without a handler")
        }
        return handler(friendshipId, messageId)
    }

    // MARK: react / unreact

    var reactToMessageHandler: ((UUID, UUID, String) -> FriendMessage)?
    var reactToMessageError: Error?
    private(set) var reactToMessageCallCount = 0

    var unreactToMessageHandler: ((UUID, UUID) -> FriendMessage)?
    var unreactToMessageError: Error?
    private(set) var unreactToMessageCallCount = 0

    func reactToMessage(friendshipId: UUID, messageId: UUID, emoji: String) async throws -> FriendMessage {
        reactToMessageCallCount += 1
        if let error = reactToMessageError { throw error }
        guard let handler = reactToMessageHandler else {
            fatalError("FakeFriendsMessagingClient.reactToMessage called without a handler")
        }
        return handler(friendshipId, messageId, emoji)
    }

    func unreactToMessage(friendshipId: UUID, messageId: UUID) async throws -> FriendMessage {
        unreactToMessageCallCount += 1
        if let error = unreactToMessageError { throw error }
        guard let handler = unreactToMessageHandler else {
            fatalError("FakeFriendsMessagingClient.unreactToMessage called without a handler")
        }
        return handler(friendshipId, messageId)
    }

    // MARK: misc / unused-by-default

    func listMessages(friendshipId: UUID, before: Date?, limit: Int) async throws -> [FriendMessage] { [] }

    func markReadThrough(friendshipId: UUID, lastMessageId: UUID) async throws {
        // No-op — refresh()'s post-fetch read receipt fires this and we
        // don't want tests to fatal on it.
    }

    func createImageUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        fatalError("not stubbed: createImageUpload")
    }
    func createVoiceUpload(friendshipId: UUID, contentType: String) async throws -> CreateMediaUploadResponse {
        fatalError("not stubbed: createVoiceUpload")
    }
    func uploadMedia(uploadUrl: String, contentType: String, data: Data) async throws {
        fatalError("not stubbed: uploadMedia")
    }
    func commitImage(friendshipId: UUID, objectKey: String, replyToMessageId: UUID?) async throws -> FriendMessage {
        fatalError("not stubbed: commitImage")
    }
    func commitVoice(friendshipId: UUID, objectKey: String, durationMs: Int, replyToMessageId: UUID?) async throws -> FriendMessage {
        fatalError("not stubbed: commitVoice")
    }
}

// MARK: - FriendMessage builder

extension FriendMessage {
    /// Build a minimal valid `FriendMessage` for tests — every field has
    /// a default so individual cases override only what they care about.
    static func makeStub(
        id: UUID = UUID(),
        friendshipId: UUID = UUID(),
        senderUserId: UUID = UUID(),
        kind: FriendMessageKind = .text,
        body: String? = "stub",
        sentAt: String = ISO8601DateFormatter().string(from: Date()),
        editedAt: String? = nil,
        deletedAt: String? = nil,
        reactions: [FriendMessageReactionSummary]? = nil
    ) -> FriendMessage {
        FriendMessage(
            id: id,
            friendshipId: friendshipId,
            conversationId: friendshipId,
            senderUserId: senderUserId,
            replyToMessageId: nil,
            replyPreview: nil,
            kind: kind,
            body: body,
            mediaUrl: nil,
            durationMs: nil,
            sentAt: sentAt,
            readAt: nil,
            editedAt: editedAt,
            deletedAt: deletedAt,
            reactions: reactions)
    }
}
