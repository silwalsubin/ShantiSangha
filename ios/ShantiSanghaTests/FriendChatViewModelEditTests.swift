import XCTest
@testable import ShantiSangha

/// Spec: edit-flow correctness.
///
/// 1. `canEdit(msg)` returns true ONLY for own non-deleted Text messages
///    inside the 15-minute window. False for the friend's messages,
///    deleted messages, image/voice messages, and own messages older
///    than 15 minutes.
/// 2. `beginEdit(msg)` populates `editingMessageId` + `editingDraft` and
///    clears any pending `replyTarget`.
/// 3. `submitEdit` calls the API once with the trimmed body, upserts the
///    returned message (which has `isEdited == true`), and clears edit
///    state.
/// 4. `cancelEdit` clears edit state without calling the API.
/// 5. Empty / whitespace-only bodies do NOT POST.
@MainActor
final class FriendChatViewModelEditTests: XCTestCase {

    // MARK: - 1. canEdit predicate

    func test_canEdit_ownRecentTextMessage_returnsTrue() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .text, body: "hi")
        XCTAssertTrue(vm.canEdit(msg))
    }

    func test_canEdit_friendMessage_returnsFalse() {
        let myUserId = UUID()
        let friendUserId = UUID()
        let vm = makeVM(myUserId: myUserId, friendUserId: friendUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: friendUserId, kind: .text, body: "hi")
        XCTAssertFalse(vm.canEdit(msg))
    }

    func test_canEdit_deletedMessage_returnsFalse() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(
            senderUserId: myUserId,
            kind: .text,
            body: nil,
            deletedAt: ISO8601DateFormatter().string(from: Date()))
        XCTAssertFalse(vm.canEdit(msg))
    }

    func test_canEdit_imageMessage_returnsFalse() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .image, body: nil)
        XCTAssertFalse(vm.canEdit(msg))
    }

    func test_canEdit_voiceMessage_returnsFalse() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .voice, body: nil)
        XCTAssertFalse(vm.canEdit(msg))
    }

    func test_canEdit_ownTextMessageOlderThan15Min_returnsFalse() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())
        let oldDate = Date().addingTimeInterval(-16 * 60) // 16 min ago
        let msg = FriendMessage.makeStub(
            senderUserId: myUserId,
            kind: .text,
            body: "old",
            sentAt: ISO8601DateFormatter().string(from: oldDate))
        XCTAssertFalse(vm.canEdit(msg))
    }

    // MARK: - 2. beginEdit populates state and clears reply

    func test_beginEdit_populatesEditingStateAndClearsReply() {
        let myUserId = UUID()
        let vm = makeVM(myUserId: myUserId, api: FakeFriendsMessagingClient())

        let original = FriendMessage.makeStub(senderUserId: myUserId, kind: .text, body: "first draft")
        let other = FriendMessage.makeStub(senderUserId: myUserId, kind: .text, body: "another")

        // Set up a reply target first — beginEdit should clear it.
        vm.beginReply(other)
        XCTAssertNotNil(vm.replyTarget)

        vm.beginEdit(original)

        XCTAssertEqual(vm.editingMessageId, original.id)
        XCTAssertEqual(vm.editingDraft, "first draft")
        XCTAssertNil(vm.replyTarget, "Starting an edit must clear any pending reply target — they're mutually exclusive composer modes")
    }

    func test_beginEdit_onUneditableMessage_isIgnored() {
        let myUserId = UUID()
        let friendUserId = UUID()
        let vm = makeVM(myUserId: myUserId, friendUserId: friendUserId, api: FakeFriendsMessagingClient())

        let friendMsg = FriendMessage.makeStub(senderUserId: friendUserId, kind: .text, body: "hi")
        vm.beginEdit(friendMsg)

        XCTAssertNil(vm.editingMessageId, "beginEdit must no-op for messages canEdit() returns false on")
        XCTAssertEqual(vm.editingDraft, "")
    }

    // MARK: - 3. submitEdit calls API once, upserts, clears state

    func test_submitEdit_callsApiWithTrimmedBody_upsertsResult_clearsState() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        var capturedBody: String?
        api.editTextHandler = { _, mid, body in
            capturedBody = body
            return FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "edited body",
                editedAt: ISO8601DateFormatter().string(from: Date()))
        }

        let vm = makeVM(friendshipId: friendshipId, myUserId: myUserId, api: api)
        // Seed the original so upsert has something to merge against.
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "original"))

        vm.beginEdit(vm.messages.first!)
        vm.editingDraft = "  edited body  " // intentional whitespace

        await vm.submitEdit()

        XCTAssertEqual(api.editTextCallCount, 1)
        XCTAssertEqual(capturedBody, "edited body", "submitEdit must trim whitespace before POSTing")
        XCTAssertEqual(vm.messages.count, 1, "Edit must upsert in place, not append")
        XCTAssertEqual(vm.messages.first?.body, "edited body")
        XCTAssertTrue(vm.messages.first?.isEdited == true, "Edited row should reflect the server's editedAt stamp")
        XCTAssertNil(vm.editingMessageId, "Edit state should clear after a successful submit")
        XCTAssertEqual(vm.editingDraft, "")
    }

    func test_submitEdit_emptyOrWhitespaceBody_doesNotPOST() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        // No handler set — fatalError if api.editText is called.

        let vm = makeVM(friendshipId: friendshipId, myUserId: myUserId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "original"))

        vm.beginEdit(vm.messages.first!)
        vm.editingDraft = "    " // whitespace only

        await vm.submitEdit()

        XCTAssertEqual(api.editTextCallCount, 0, "Whitespace-only body must NOT trigger an API call — there's nothing to save")
        XCTAssertEqual(vm.editingMessageId, messageId, "Edit state should remain so the user can fix the body and try again")
    }

    // MARK: - 4. cancelEdit clears state without calling the API

    func test_cancelEdit_clearsStateWithoutCallingApi() {
        let myUserId = UUID()
        let api = FakeFriendsMessagingClient()
        // No handler set — fatalError if api.editText is called.

        let vm = makeVM(myUserId: myUserId, api: api)
        let msg = FriendMessage.makeStub(senderUserId: myUserId, kind: .text, body: "hello")
        vm.beginEdit(msg)
        XCTAssertEqual(vm.editingMessageId, msg.id)

        vm.cancelEdit()

        XCTAssertNil(vm.editingMessageId)
        XCTAssertEqual(vm.editingDraft, "")
        XCTAssertEqual(api.editTextCallCount, 0, "cancelEdit is a pure local-state reset — no server call")
    }

    // MARK: - Helpers

    private func makeVM(
        friendshipId: UUID = UUID(),
        myUserId: UUID = UUID(),
        friendUserId: UUID = UUID(),
        api: FakeFriendsMessagingClient
    ) -> FriendChatViewModel {
        // The VM doesn't take a `myUserId` directly — it identifies "us"
        // implicitly by `senderUserId != friendUserId`. Tests pass
        // `friendUserId` so any `myUserId` UUID is treated as own.
        FriendChatViewModel(
            friendshipId: friendshipId,
            friendUserId: friendUserId,
            friendDisplayName: "Test Friend",
            api: api)
    }
}
