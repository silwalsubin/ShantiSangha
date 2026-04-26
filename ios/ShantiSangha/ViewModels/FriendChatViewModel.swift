import Foundation
import SwiftUI

@MainActor
final class FriendChatViewModel: ObservableObject {
    let friendshipId: UUID
    let friendUserId: UUID
    let friendDisplayName: String

    @Published var messages: [FriendMessage] = []
    @Published var loading = false
    @Published var sending = false
    @Published var errorMessage: String?

    /// Set of user ids currently typing in the conversation (excluding
    /// us). For 1:1 it's at most one entry; the typing-pill UI is built
    /// to handle a multi-member set so groups need only a string change.
    @Published var typingFromMembers: Set<UUID> = []

    /// Sender-side edit-mode state. Drives the composer's "Save edit"
    /// affordance. When `editingMessageId` is non-nil, the composer is
    /// pre-filled with `editingDraft` and the next submit hits PUT
    /// instead of POST.
    @Published var editingMessageId: UUID?
    @Published var editingDraft: String = ""

    private var observer: NSObjectProtocol?
    private var loadedAll = false

    /// Per-member auto-clear timers so a stale `typing: true` from a
    /// dropped or backgrounded peer eventually fades. Refreshed on each
    /// new typing-true frame from the same member.
    private var typingTimers: [UUID: Task<Void, Never>] = [:]

    /// Debounces our outbound typing pings so we send at most ~1/sec
    /// while the user types, plus a final `false` after 3 s of idleness.
    private var lastTypingSentAt: Date = .distantPast
    private var typingIdleTask: Task<Void, Never>?
    private var lastSentTypingState: Bool = false

    private var realtime: ChatRealtimeClient?

    init(friendshipId: UUID, friendUserId: UUID, friendDisplayName: String) {
        self.friendshipId = friendshipId
        self.friendUserId = friendUserId
        self.friendDisplayName = friendDisplayName
        observer = NotificationCenter.default.addObserver(
            forName: .friendMessageReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let received = note.userInfo?["friendshipId"] as? String
            if received == self.friendshipId.uuidString.lowercased()
                || received == self.friendshipId.uuidString {
                Task { await self.refresh() }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await FriendsAPI.listMessages(friendshipId: friendshipId, limit: 50)
            messages = loaded
            errorMessage = nil
            await markUnreadAsRead()
        } catch {
            if !error.isCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadOlder() async {
        guard !loadedAll, let oldest = messages.first,
              let oldestDate = FriendsDates.parse(oldest.sentAt) else { return }
        do {
            let older = try await FriendsAPI.listMessages(friendshipId: friendshipId, before: oldestDate, limit: 50)
            if older.isEmpty { loadedAll = true; return }
            messages = older + messages
        } catch {
            // silent; the caller can retry
        }
    }

    func sendText(_ body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Clear our own typing-on signal as soon as we send, otherwise
        // the recipient sees a stale "typing…" while reading the message.
        await flushTyping(false)
        sending = true
        defer { sending = false }
        do {
            let msg = try await FriendsAPI.sendText(friendshipId: friendshipId, body: trimmed)
            // The realtime broadcast will also fire `message_received`
            // which would dedupe — append now so the UI feels instant
            // and let the broadcast harmlessly upsert if it arrives.
            upsertMessage(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendImage(data: Data, contentType: String) async {
        sending = true
        defer { sending = false }
        do {
            let upload = try await FriendsAPI.createImageUpload(friendshipId: friendshipId, contentType: contentType)
            try await FriendsAPI.uploadMedia(uploadUrl: upload.uploadUrl, contentType: contentType, data: data)
            let msg = try await FriendsAPI.commitImage(friendshipId: friendshipId, objectKey: upload.objectKey)
            upsertMessage(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendVoice(data: Data, contentType: String, durationMs: Int) async {
        sending = true
        defer { sending = false }
        do {
            let upload = try await FriendsAPI.createVoiceUpload(friendshipId: friendshipId, contentType: contentType)
            try await FriendsAPI.uploadMedia(uploadUrl: upload.uploadUrl, contentType: contentType, data: data)
            let msg = try await FriendsAPI.commitVoice(
                friendshipId: friendshipId,
                objectKey: upload.objectKey,
                durationMs: durationMs)
            upsertMessage(msg)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markUnreadAsRead() async {
        for m in messages where m.readAt == nil && m.senderUserId == friendUserId {
            try? await FriendsAPI.markRead(friendshipId: friendshipId, messageId: m.id)
        }
    }

    func isFromFriend(_ message: FriendMessage) -> Bool {
        message.senderUserId == friendUserId
    }

    // MARK: - Edit / Delete (sender only)

    /// Whether the sender can still edit this Text message — within the
    /// 15-min window the backend enforces. Used to gate the long-press
    /// menu so users don't tap a button that will 422.
    func canEdit(_ message: FriendMessage) -> Bool {
        guard !isFromFriend(message),
              message.kind == .text,
              !message.isDeleted,
              let sentAt = FriendsDates.parse(message.sentAt) else { return false }
        return Date().timeIntervalSince(sentAt) < 15 * 60
    }

    func canDelete(_ message: FriendMessage) -> Bool {
        !isFromFriend(message) && !message.isDeleted
    }

    func beginEdit(_ message: FriendMessage) {
        guard canEdit(message) else { return }
        editingMessageId = message.id
        editingDraft = message.body ?? ""
    }

    func cancelEdit() {
        editingMessageId = nil
        editingDraft = ""
    }

    /// Submit the in-flight edit. The realtime broadcast will replace
    /// the local row when it lands; we also upsert the response body so
    /// the UI updates even if the socket is briefly offline.
    func submitEdit() async {
        guard let id = editingMessageId else { return }
        let body = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            let updated = try await FriendsAPI.editText(friendshipId: friendshipId, messageId: id, body: body)
            upsertMessage(updated)
            cancelEdit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMessage(_ message: FriendMessage) async {
        guard canDelete(message) else { return }
        do {
            let updated = try await FriendsAPI.deleteMessage(friendshipId: friendshipId, messageId: message.id)
            upsertMessage(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Realtime lifecycle

    /// Connect the per-conversation WebSocket. Idempotent — repeated
    /// calls (e.g. on view re-task) reuse the existing client.
    func startRealtime() {
        guard realtime == nil else { return }
        Task {
            let baseURL = await ApiService.shared.getBaseURL()
            let client = ChatRealtimeClient(
                conversationId: friendshipId,
                baseURL: baseURL,
                tokenProvider: { await ApiService.shared.currentToken() })

            client.onMessageReceived = { [weak self] msg in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.upsertMessage(msg)
                    // If this is from the friend AND we're actively viewing,
                    // mark it read immediately so the sender sees the receipt
                    // without a refetch round-trip.
                    if msg.senderUserId == self.friendUserId, msg.readAt == nil {
                        try? await FriendsAPI.markRead(friendshipId: self.friendshipId, messageId: msg.id)
                    }
                }
            }
            client.onMessageEdited = { [weak self] msg in
                Task { @MainActor [weak self] in self?.upsertMessage(msg) }
            }
            client.onMessageDeleted = { [weak self] id in
                Task { @MainActor [weak self] in self?.applyDeleted(id) }
            }
            client.onMessagesRead = { [weak self] readBy, lastMessageId, readAt in
                Task { @MainActor [weak self] in
                    self?.applyReadReceipt(readByUserId: readBy, lastMessageId: lastMessageId, readAt: readAt)
                }
            }
            client.onTyping = { [weak self] from, isTyping in
                Task { @MainActor [weak self] in
                    self?.applyTyping(fromUserId: from, isTyping: isTyping)
                }
            }

            self.realtime = client
            client.connect()
        }
    }

    func stopRealtime() {
        realtime?.disconnect()
        realtime = nil
        typingTimers.values.forEach { $0.cancel() }
        typingTimers.removeAll()
        typingFromMembers.removeAll()
        typingIdleTask?.cancel()
        typingIdleTask = nil
    }

    // MARK: - Typing presence (outbound)

    /// Called from the composer's text binding. Pings `typing: true`
    /// at most once a second, and schedules a `typing: false` after
    /// 3 s of no further typing so the recipient's pill auto-clears.
    func sendTypingState(hasText: Bool) async {
        if hasText {
            let now = Date()
            if !lastSentTypingState || now.timeIntervalSince(lastTypingSentAt) >= 1.0 {
                await realtime?.sendTyping(true)
                lastTypingSentAt = now
                lastSentTypingState = true
            }
            scheduleTypingIdle()
        } else {
            await flushTyping(false)
        }
    }

    private func scheduleTypingIdle() {
        typingIdleTask?.cancel()
        typingIdleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushTyping(false)
        }
    }

    private func flushTyping(_ value: Bool) async {
        guard lastSentTypingState != value else { return }
        await realtime?.sendTyping(value)
        lastSentTypingState = value
    }

    // MARK: - Realtime → state reducers

    private func upsertMessage(_ msg: FriendMessage) {
        if let i = messages.firstIndex(where: { $0.id == msg.id }) {
            messages[i] = msg
        } else {
            // Insert sorted by sentAt so an out-of-order arrival
            // (history fetch racing the broadcast) lands in the right spot.
            messages.append(msg)
            messages.sort { ($0.sentAt) < ($1.sentAt) }
        }
    }

    private func applyDeleted(_ id: UUID) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        let m = messages[i]
        messages[i] = FriendMessage(
            id: m.id,
            friendshipId: m.friendshipId,
            conversationId: m.conversationId,
            senderUserId: m.senderUserId,
            kind: m.kind,
            body: nil,
            mediaUrl: nil,
            durationMs: m.durationMs,
            sentAt: m.sentAt,
            readAt: m.readAt,
            editedAt: m.editedAt,
            deletedAt: ISO8601DateFormatter().string(from: Date()))
    }

    /// `messages_read` from the friend means everything we sent up to
    /// (and including) `lastMessageId` has been read. Stamp `readAt` on
    /// each of our outgoing messages whose `sentAt <= cutoff` so the
    /// double-tick UI updates without a refetch.
    private func applyReadReceipt(readByUserId: UUID, lastMessageId: UUID, readAt: String) {
        // Only flip checkmarks for our own messages — incoming messages
        // already get marked read on our own action.
        guard readByUserId == friendUserId else { return }
        guard let cutoffMsg = messages.first(where: { $0.id == lastMessageId }),
              let cutoff = FriendsDates.parse(cutoffMsg.sentAt) else { return }
        for i in messages.indices {
            let m = messages[i]
            guard m.senderUserId != friendUserId, m.readAt == nil else { continue }
            guard let sent = FriendsDates.parse(m.sentAt), sent <= cutoff else { continue }
            messages[i] = FriendMessage(
                id: m.id,
                friendshipId: m.friendshipId,
                conversationId: m.conversationId,
                senderUserId: m.senderUserId,
                kind: m.kind,
                body: m.body,
                mediaUrl: m.mediaUrl,
                durationMs: m.durationMs,
                sentAt: m.sentAt,
                readAt: readAt,
                editedAt: m.editedAt,
                deletedAt: m.deletedAt)
        }
    }

    private func applyTyping(fromUserId: UUID, isTyping: Bool) {
        // Backend echoes typing frames to all conversation members
        // including the sender; ignore our own ping so we don't show
        // ourselves a "you are typing" pill.
        guard fromUserId == friendUserId else { return }

        if isTyping {
            typingFromMembers.insert(fromUserId)
            // Auto-clear after 4 s of no fresh typing-true. Cancels any
            // existing timer for this member so the window slides.
            typingTimers[fromUserId]?.cancel()
            typingTimers[fromUserId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.typingFromMembers.remove(fromUserId)
                    self?.typingTimers.removeValue(forKey: fromUserId)
                }
            }
        } else {
            typingFromMembers.remove(fromUserId)
            typingTimers[fromUserId]?.cancel()
            typingTimers.removeValue(forKey: fromUserId)
        }
    }
}
