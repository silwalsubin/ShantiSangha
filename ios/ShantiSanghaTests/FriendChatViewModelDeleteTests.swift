import XCTest
@testable import ShantiSangha

/// Spec: delete-flow correctness.
///
/// 1. `canDelete(msg)` returns true ONLY for the user's own non-deleted
///    messages — Text, Image, OR Voice (no time window, unlike edit).
///    False for the friend's messages and for already-deleted rows.
/// 2. `deleteMessage(msg)` calls the API once and upserts the returned
///    row, which has `isDeleted == true` and `body == nil`. The row STAYS
///    in `messages` so the bubble can flip to "Message deleted" in place.
/// 3. Calling `deleteMessage` on the friend's message or on an
///    already-deleted message no-ops without an API call.
/// 4. API failure surfaces via `errorMessage` and leaves the original
///    row untouched.
@MainActor
final class FriendChatViewModelDeleteTests: XCTestCase {

    // MARK: - 1. canDelete predicate

    func test_canDelete_ownTextMessage_returnsTrue() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .text, body: "hi")
        XCTAssertTrue(vm.canDelete(msg))
    }

    func test_canDelete_ownImageMessage_returnsTrue() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .image, body: nil)
        XCTAssertTrue(vm.canDelete(msg), "Image messages can be deleted just like text — there's no kind restriction")
    }

    func test_canDelete_ownVoiceMessage_returnsTrue() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .voice, body: nil)
        XCTAssertTrue(vm.canDelete(msg))
    }

    func test_canDelete_ownTextMessageOlderThan15Min_stillReturnsTrue() {
        // Edit has a 15-min window; delete does not. Verify the window
        // doesn't accidentally apply here.
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let oldDate = Date().addingTimeInterval(-60 * 60) // 1 hour ago
        let msg = FriendMessage.makeStub(
            senderUserId: myUserId,
            kind: .text,
            body: "old",
            sentAt: ISO8601DateFormatter().string(from: oldDate))
        XCTAssertTrue(vm.canDelete(msg), "Delete has no time window — old own messages stay deletable")
    }

    func test_canDelete_friendMessage_returnsFalse() {
        let myUserId = UUID()
        let friendUserId = UUID()
        let vm = makeVM(myUserId: myUserId, friendUserId: friendUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: friendUserId, kind: .text, body: "hi")
        XCTAssertFalse(vm.canDelete(msg))
    }

    func test_canDelete_alreadyDeletedMessage_returnsFalse() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(
            senderUserId: myUserId,
            kind: .text,
            body: nil,
            deletedAt: ISO8601DateFormatter().string(from: Date()))
        XCTAssertFalse(vm.canDelete(msg))
    }

    // MARK: - 2. deleteMessage success path

    func test_deleteMessage_success_callsApiOnce_upsertsAsDeletedInPlace() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        var capturedMessageId: UUID?
        api.deleteMessageHandler = { _, mid in
            capturedMessageId = mid
            // Server response shape: deletedAt set, body blanked.
            return FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: nil,
                deletedAt: ISO8601DateFormatter().string(from: Date()))
        }

        let vm = makeVM(friendshipId: friendshipId, myUserId: myUserId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "to be deleted"))

        await vm.deleteMessage(vm.messages.first!)

        XCTAssertEqual(api.deleteMessageCallCount, 1)
        XCTAssertEqual(capturedMessageId, messageId)
        XCTAssertEqual(vm.messages.count, 1, "Deleted row stays in `messages` so the bubble can flip to 'Message deleted' in place")
        XCTAssertTrue(vm.messages.first?.isDeleted == true)
        XCTAssertNil(vm.messages.first?.body, "Server blanks the body on delete and the upsert reflects that")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - 3. Guards: friend's message and already-deleted

    func test_deleteMessage_onFriendMessage_doesNothing() async {
        let myUserId = UUID()
        let friendUserId = UUID()

        let api = FakeFriendsMessagingClient()
        // No handler set — fatalError if api.deleteMessage is called.

        let vm = makeVM(myUserId: myUserId, friendUserId: friendUserId, api: api)
        let friendMsg = FriendMessage.makeStub(senderUserId: friendUserId, kind: .text, body: "hi")
        vm.upsertMessage(friendMsg)

        await vm.deleteMessage(friendMsg)

        XCTAssertEqual(api.deleteMessageCallCount, 0, "deleteMessage must no-op for the friend's messages — `canDelete` returns false")
        XCTAssertFalse(vm.messages.first?.isDeleted ?? true)
    }

    func test_deleteMessage_onAlreadyDeleted_doesNothing() async {
        let myUserId = UUID()

        let api = FakeFriendsMessagingClient()

        let vm = makeVM(myUserId: myUserId, api: api)
        let deletedMsg = FriendMessage.makeStub(
            senderUserId: myUserId,
            kind: .text,
            body: nil,
            deletedAt: ISO8601DateFormatter().string(from: Date()))
        vm.upsertMessage(deletedMsg)

        await vm.deleteMessage(deletedMsg)

        XCTAssertEqual(api.deleteMessageCallCount, 0, "Re-deleting a deleted message must no-op — idempotency at the VM gate")
    }

    // MARK: - 4. Failure path

    func test_deleteMessage_apiFailure_surfacesErrorAndLeavesRowUnchanged() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.deleteMessageError = ApiError.httpError(statusCode: 500, data: Data())

        let vm = makeVM(friendshipId: friendshipId, myUserId: myUserId, api: api)
        let original = FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "original")
        vm.upsertMessage(original)

        await vm.deleteMessage(original)

        XCTAssertEqual(api.deleteMessageCallCount, 1)
        XCTAssertNotNil(vm.errorMessage, "API failure should surface to the user via errorMessage")
        XCTAssertFalse(vm.messages.first?.isDeleted ?? true, "Original row must not flip to deleted when the API call failed")
        XCTAssertEqual(vm.messages.first?.body, "original")
    }

    // MARK: - Helpers

    private func makeVM(
        friendshipId: UUID = UUID(),
        myUserId: UUID = UUID(),
        friendUserId: UUID = UUID(),
        api: FakeFriendsMessagingClient
    ) -> FriendChatViewModel {
        FriendChatViewModel(
            friendshipId: friendshipId,
            friendUserId: friendUserId,
            friendDisplayName: "Test Friend",
            api: api)
    }
}
