import XCTest
@testable import ShantiSangha

/// Spec: reactions correctness — one reaction per user per message,
/// optimistic local update, revert on failure, and realtime canonical sync.
///
/// 1. Toggle on an unreacted message: optimistically adds my reaction,
///    calls `reactToMessage` once, reconciles with the server response.
/// 2. Toggle the SAME emoji on a message I already reacted to: routes
///    to `removeReaction` (calls `unreactToMessage`, NOT `reactToMessage`).
/// 3. Toggle a DIFFERENT emoji while I already have one: optimistically
///    REPLACES (drops me from old bucket, adds me to new) — never two of
///    my reactions on the same message.
/// 4. API failure on toggle: reactions revert exactly to the pre-toggle
///    state and `errorMessage` is surfaced.
/// 5. `removeReaction` removes me and collapses any bucket whose
///    `byUserIds` becomes empty so no empty pill renders.
/// 6. `applyReactionsChanged` realtime broadcast replaces the row's
///    reactions wholesale with the server's canonical view.
@MainActor
final class FriendChatViewModelReactionsTests: XCTestCase {

    // MARK: - 1. Toggle on unreacted message → adds my reaction

    func test_toggleReaction_onUnreacted_optimisticallyAdds_andCallsReactApi() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.reactToMessageHandler = { _, mid, emoji in
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [
                    FriendMessageReactionSummary(emoji: emoji, byUserIds: [myUserId])
                ])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi"))

        await vm.toggleReaction("❤️", on: messageId, currentUserId: myUserId)

        XCTAssertEqual(api.reactToMessageCallCount, 1)
        XCTAssertEqual(api.unreactToMessageCallCount, 0, "Adding a reaction must NOT call unreact")
        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions.first?.emoji, "❤️")
        XCTAssertEqual(reactions.first?.byUserIds, [myUserId])
    }

    // MARK: - 2. Toggle SAME emoji → routes to remove (unreact)

    func test_toggleReaction_sameEmojiAgain_routesToUnreact() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.unreactToMessageHandler = { _, mid in
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId])
            ]))

        await vm.toggleReaction("❤️", on: messageId, currentUserId: myUserId)

        XCTAssertEqual(api.unreactToMessageCallCount, 1, "Re-tapping the same emoji is a toggle-off — must call unreact")
        XCTAssertEqual(api.reactToMessageCallCount, 0, "Toggle-off must NOT call react")
        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertTrue(reactions.isEmpty, "After toggling off, my reaction should be gone — no empty bucket either")
    }

    // MARK: - 3. Toggle DIFFERENT emoji → optimistic replace

    func test_toggleReaction_differentEmoji_replacesMine_neverDuplicates() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.reactToMessageHandler = { _, mid, emoji in
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [
                    FriendMessageReactionSummary(emoji: emoji, byUserIds: [myUserId])
                ])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId])
            ]))

        await vm.toggleReaction("👍", on: messageId, currentUserId: myUserId)

        XCTAssertEqual(api.reactToMessageCallCount, 1)
        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertEqual(reactions.count, 1, "Switching emoji must REPLACE — never end up with two of my reactions")
        XCTAssertEqual(reactions.first?.emoji, "👍")
        XCTAssertEqual(reactions.first?.byUserIds, [myUserId])
    }

    func test_toggleReaction_differentEmoji_preservesOtherUsersInOldBucket() async {
        // The old bucket should only lose ME — anyone else who had the
        // old emoji must remain on the message.
        let myUserId = UUID()
        let otherUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.reactToMessageHandler = { _, mid, emoji in
            // Simulate server response after my switch: "❤️" still has the
            // other user, "👍" now has me.
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [
                    FriendMessageReactionSummary(emoji: "❤️", byUserIds: [otherUserId]),
                    FriendMessageReactionSummary(emoji: emoji, byUserIds: [myUserId])
                ])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId, otherUserId])
            ]))

        await vm.toggleReaction("👍", on: messageId, currentUserId: myUserId)

        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertEqual(reactions.count, 2)
        let heartRow = reactions.first(where: { $0.emoji == "❤️" })
        XCTAssertEqual(heartRow?.byUserIds, [otherUserId], "Old bucket should retain other users — only I switch off")
        let thumbsRow = reactions.first(where: { $0.emoji == "👍" })
        XCTAssertEqual(thumbsRow?.byUserIds, [myUserId])
    }

    // MARK: - 4. Failure reverts

    func test_toggleReaction_apiFailure_revertsOptimisticState() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()
        let originalReactions = [
            FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId])
        ]

        let api = FakeFriendsMessagingClient()
        api.reactToMessageError = ApiError.httpError(statusCode: 500, data: Data())

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: originalReactions))

        await vm.toggleReaction("👍", on: messageId, currentUserId: myUserId)

        XCTAssertEqual(api.reactToMessageCallCount, 1)
        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertEqual(reactions, originalReactions, "Failed react must revert to the EXACT pre-toggle state — no orphan optimistic edits")
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - 5. removeReaction collapses empty buckets

    func test_removeReaction_collapsesBucketWhenIWasTheOnlyReactor() async {
        let myUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.unreactToMessageHandler = { _, mid in
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId])
            ]))

        await vm.removeReaction(on: messageId, currentUserId: myUserId)

        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertTrue(reactions.isEmpty, "Bucket whose `byUserIds` becomes empty must be removed — no empty pill should render")
    }

    func test_removeReaction_keepsBucketWhenOtherUsersStillReacted() async {
        let myUserId = UUID()
        let otherUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let api = FakeFriendsMessagingClient()
        api.unreactToMessageHandler = { _, mid in
            FriendMessage.makeStub(
                id: mid,
                friendshipId: friendshipId,
                senderUserId: myUserId,
                kind: .text,
                body: "hi",
                reactions: [
                    FriendMessageReactionSummary(emoji: "❤️", byUserIds: [otherUserId])
                ])
        }

        let vm = makeVM(friendshipId: friendshipId, api: api)
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId, otherUserId])
            ]))

        await vm.removeReaction(on: messageId, currentUserId: myUserId)

        let reactions = vm.messages.first?.reactions ?? []
        XCTAssertEqual(reactions.count, 1, "Bucket should remain — other users still reacting")
        XCTAssertEqual(reactions.first?.byUserIds, [otherUserId])
    }

    // MARK: - 6. Realtime applyReactionsChanged replaces wholesale

    func test_applyReactionsChanged_replacesReactionsWithCanonicalServerView() {
        let myUserId = UUID()
        let friendUserId = UUID()
        let messageId = UUID()
        let friendshipId = UUID()

        let vm = makeVM(friendshipId: friendshipId, friendUserId: friendUserId, api: FakeFriendsMessagingClient())
        vm.upsertMessage(FriendMessage.makeStub(
            id: messageId,
            friendshipId: friendshipId,
            senderUserId: myUserId,
            kind: .text,
            body: "hi",
            reactions: [
                FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId])
            ]))

        // Friend reacts with 🔥 — server broadcasts the canonical view.
        let canonical = [
            FriendMessageReactionSummary(emoji: "❤️", byUserIds: [myUserId]),
            FriendMessageReactionSummary(emoji: "🔥", byUserIds: [friendUserId])
        ]
        vm.applyReactionsChanged(messageId: messageId, reactions: canonical)

        XCTAssertEqual(vm.messages.first?.reactions, canonical, "Realtime broadcast replaces reactions wholesale with the server's view")
    }

    func test_applyReactionsChanged_forUnknownMessageId_isIgnored() {
        let vm = makeVM(api: FakeFriendsMessagingClient())
        vm.upsertMessage(FriendMessage.makeStub(body: "only message"))
        let originalReactions = vm.messages.first?.reactions

        // Broadcast for a message we don't have — must not crash, must not affect existing rows.
        vm.applyReactionsChanged(messageId: UUID(), reactions: [
            FriendMessageReactionSummary(emoji: "❤️", byUserIds: [UUID()])
        ])

        XCTAssertEqual(vm.messages.first?.reactions, originalReactions)
    }

    // MARK: - Helpers

    private func makeVM(
        friendshipId: UUID = UUID(),
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
