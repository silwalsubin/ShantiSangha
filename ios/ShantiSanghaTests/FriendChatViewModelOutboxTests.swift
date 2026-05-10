import XCTest
@testable import ShantiSangha

/// Spec: outbox correctness around send, realtime echo, reconnect, and failure.
///
/// 1. A successful send removes the pending entry and lands the
///    server-issued FriendMessage in `messages`.
/// 2. A realtime echo of the same message id (which fires after every
///    successful send via `onMessageReceived`) does not duplicate the bubble.
/// 2b. A realtime echo that arrives BEFORE the HTTP response returns
///     (the common case in practice) clears the matching outbox pending,
///     so the bubble doesn't render twice during the in-flight window.
/// 3. A `flushOutbox` triggered while a send is in flight (e.g. on
///    network reconnect) does NOT trigger a second POST for the same
///    pending — the `inFlightSendIds` guard regression-protects d7c6a03.
/// 4. A non-transient HTTP failure leaves the pending entry in place with
///    `lastError` set, so the bubble can render "tap to retry".
@MainActor
final class FriendChatViewModelOutboxTests: XCTestCase {

    // MARK: - 1. Send success replaces pending with server message

    func test_sendText_success_replacesPendingWithServerMessage() async {
        let friendshipId = UUID()
        let myUserId = UUID()
        let serverMessageId = UUID()

        let api = FakeFriendsMessagingClient()
        api.sendTextHandler = { fId, body, _ in
            FriendMessage.makeStub(
                id: serverMessageId,
                friendshipId: fId,
                senderUserId: myUserId,
                body: body)
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)

        await vm.sendText("hello")

        XCTAssertTrue(vm.outbox.isEmpty, "Pending entry should be cleared after a successful send")
        XCTAssertEqual(vm.messages.count, 1, "Server-issued message should land in `messages`")
        XCTAssertEqual(vm.messages.first?.id, serverMessageId)
        XCTAssertEqual(vm.messages.first?.body, "hello")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - 2. Realtime echo of same id does not duplicate

    func test_sendText_thenRealtimeEcho_doesNotDuplicateBubble() async {
        let friendshipId = UUID()
        let myUserId = UUID()
        let serverMessageId = UUID()

        let api = FakeFriendsMessagingClient()
        api.sendTextHandler = { fId, body, _ in
            FriendMessage.makeStub(
                id: serverMessageId,
                friendshipId: fId,
                senderUserId: myUserId,
                body: body)
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)

        await vm.sendText("hello")
        XCTAssertEqual(vm.messages.count, 1)

        // Simulate the realtime broadcast that lands milliseconds after
        // the POST returns — same message id, same body. The dedup in
        // `upsertMessage` (id-keyed merge) must keep the bubble count at one.
        let echo = FriendMessage.makeStub(
            id: serverMessageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            body: "hello")
        vm.upsertMessage(echo)

        XCTAssertEqual(vm.messages.count, 1, "Realtime echo of the same id must not produce a duplicate row")
        XCTAssertEqual(vm.messages.first?.id, serverMessageId)
    }

    // MARK: - 2b. Realtime echo arriving before HTTP response does not duplicate

    /// On a real network, the server's realtime broadcast usually wins
    /// the race against its own HTTP response — so by the time the POST
    /// returns, the echo (with the server-assigned id) has already been
    /// upserted into `messages`. The pending in `outbox` has a local
    /// UUID that doesn't match the server id, so `outbox.removeAll` by
    /// id can't drop it. Without dedup-by-body in `upsertMessage`, the
    /// chat shows the bubble twice (delivered + "Sending…") for the
    /// duration of the HTTP roundtrip.
    func test_realtimeEchoBeforeHttpResponse_clearsPendingAndShowsOneBubble() async {
        let friendshipId = UUID()
        let myUserId = UUID()
        let serverMessageId = UUID()

        let api = FakeFriendsMessagingClient()
        api.blockSendText = true

        let vm = makeVM(friendshipId: friendshipId, api: api)

        let sendTask = Task { await vm.sendText("hello") }
        await api.waitForSendTextStarted()

        // Pending is in the outbox, HTTP is parked. Now fire the
        // realtime echo (this is what `onMessageReceived` does in
        // `startRealtime`).
        XCTAssertEqual(vm.outbox.count, 1, "Pending should be in the outbox while HTTP is in flight")
        let echo = FriendMessage.makeStub(
            id: serverMessageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            body: "hello")
        vm.upsertMessage(echo)

        XCTAssertEqual(vm.messages.count, 1, "Echo should land in messages")
        XCTAssertTrue(vm.outbox.isEmpty, "Echo of our own send must clear the matching pending so the bubble doesn't render twice")

        // Drain the HTTP — final state should still be one bubble.
        api.releaseBlockedSendText(with: .success(echo))
        await sendTask.value

        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.outbox.isEmpty)
    }

    // MARK: - 3. Concurrent flush during in-flight send does not double-POST

    /// Regression guard for the bug d7c6a03 fixed. The original failure
    /// mode: `sendText` was awaiting the POST when the network publisher
    /// fired `isConnected = true`, which triggered `flushOutbox`, which
    /// re-attempted the same pending and the server stored two messages.
    /// `inFlightSendIds` should make this impossible — verified here by
    /// holding `api.sendText` open via a continuation while we run a
    /// concurrent flush.
    func test_concurrentFlush_duringInflightSend_doesNotDoubleSend() async {
        let friendshipId = UUID()
        let myUserId = UUID()
        let serverMessageId = UUID()

        let api = FakeFriendsMessagingClient()
        api.blockSendText = true

        let vm = makeVM(friendshipId: friendshipId, api: api)

        let sendTask = Task { await vm.sendText("hello") }

        // Park here until the send is verifiably in flight (continuation
        // registered, awaiting release). This is the exact moment the
        // network-reconnect publisher used to fire and trigger the dup.
        await api.waitForSendTextStarted()

        // Simulate the reconnect — publisher.sink calls flushOutbox.
        // Without inFlightSendIds, this would reach `api.sendText` again
        // with the same pending and double-POST.
        await vm.flushOutbox()

        // Drain the original send.
        api.releaseBlockedSendText(with: .success(FriendMessage.makeStub(
            id: serverMessageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            body: "hello")))
        await sendTask.value

        XCTAssertEqual(api.sendTextCallCount, 1, "Concurrent flush during in-flight send must NOT trigger a second POST for the same pending")
        XCTAssertTrue(vm.outbox.isEmpty, "Outbox should drain after the inflight send succeeds")
        XCTAssertEqual(vm.messages.count, 1, "Exactly one server message should land")
        XCTAssertEqual(vm.messages.first?.id, serverMessageId)
    }

    // MARK: - 4. Non-transient failure leaves pending with lastError

    func test_sendText_httpFailure_leavesPendingWithLastError() async {
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.sendTextError = ApiError.httpError(statusCode: 422, data: Data())

        let vm = makeVM(friendshipId: friendshipId, api: api)

        await vm.sendText("hello")

        XCTAssertEqual(vm.outbox.count, 1, "Failed send should leave the pending entry in the outbox")
        XCTAssertEqual(vm.outbox.first?.body, "hello")
        XCTAssertNotNil(vm.outbox.first?.lastError, "Non-transient failure should stamp `lastError` so the bubble flips to 'tap to retry'")
        XCTAssertTrue(vm.messages.isEmpty, "No server message should land when the send failed")
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Helpers

    /// Fresh VM bound to a random friendship so on-disk caches
    /// (ChatCache / ChatOutbox) start empty without any teardown.
    private func makeVM(friendshipId: UUID, api: FakeFriendsMessagingClient) -> FriendChatViewModel {
        FriendChatViewModel(
            friendshipId: friendshipId,
            friendUserId: UUID(),
            friendDisplayName: "Test Friend",
            api: api)
    }
}

// Test doubles (`FakeFriendsMessagingClient`, `FriendMessage.makeStub`)
// live in `FriendChatTestSupport.swift` so multiple spec files can share them.
