import Foundation
import SwiftUI
import Combine

@MainActor
final class FriendChatViewModel: ObservableObject {
    let friendshipId: UUID
    let friendUserId: UUID
    let friendDisplayName: String

    @Published var messages: [FriendMessage] = [] {
        didSet {
            // Persist every mutation to the on-disk thread cache. Saves
            // are async on a background queue; the didSet call here is
            // non-blocking. Ensures cold-open paints instantly from
            // cache and recent history is readable offline.
            ChatCache.save(friendshipId: friendshipId, messages: messages)
        }
    }
    @Published var loading = false
    @Published var loadingOlder = false
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
    @Published var replyTarget: FriendMessage?

    /// Text sends that haven't reached the server yet (failed on first
    /// attempt or fired while offline). Rendered after `messages` in
    /// the chat view with a "sending" / "failed — tap to retry" badge.
    /// Persists to disk so a kill-and-relaunch doesn't lose the text.
    @Published var outbox: [PendingMessage] = [] {
        didSet {
            ChatOutbox.save(friendshipId: friendshipId, items: outbox)
        }
    }

    private var observer: NSObjectProtocol?
    private var loadedAll = false
    private var cancellables: Set<AnyCancellable> = []
    private var flushTask: Task<Void, Never>?

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
        // Hydrate from disk synchronously so the first SwiftUI render
        // shows the last-known thread instead of a flash of empty.
        // The .task-driven refresh() upserts whatever's newer from the
        // API on top of this baseline.
        self.messages = ChatCache.load(friendshipId: friendshipId)
        self.outbox = ChatOutbox.load(friendshipId: friendshipId)

        // Auto-flush whenever the network becomes reachable. The
        // initial true → true case is also handled below so a cold-open
        // already-online doesn't need a network change to drain.
        NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                if connected { Task { await self?.flushOutbox() } }
            }
            .store(in: &cancellables)

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
            // Upsert into the cache-hydrated baseline rather than
            // replacing it: a thread the user has paginated deeper on
            // still has those older rows in `messages` from disk; we
            // don't want a foreground refresh to truncate them back to
            // the latest 50.
            mergeFetched(loaded)
            errorMessage = nil
            await markUnreadAsRead()
        } catch {
            // Network failure with cached messages on screen is fine —
            // user can still read history. Surface the error only if
            // we have nothing to show.
            if !error.isCancellation, messages.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Merge a freshly-fetched API page into `messages`, replacing any
    /// existing rows by id and preserving older cached rows the page
    /// didn't include. Sort by sentAt at the end so out-of-order arrivals
    /// land in the right place.
    private func mergeFetched(_ fetched: [FriendMessage]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for msg in fetched {
            byId[msg.id] = msg
        }
        messages = byId.values.sorted { $0.sentAt < $1.sentAt }
    }

    func loadOlder() async {
        guard !loadedAll, let oldest = messages.first,
              let oldestDate = FriendsDates.parse(oldest.sentAt),
              !loadingOlder else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let older = try await FriendsAPI.listMessages(friendshipId: friendshipId, before: oldestDate, limit: 50)
            if older.isEmpty { loadedAll = true; return }
            // Merge by id so a partial overlap with the existing range
            // doesn't duplicate rows in the cache.
            mergeFetched(older)
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

        let pending = PendingMessage(
            body: trimmed,
            replyToMessageId: replyTarget?.id)
        // Optimistically push the pending row into the outbox so the
        // bubble renders right away (with a "sending" badge), then
        // attempt the actual send. On success we drop it from the
        // outbox and replace with the server-issued FriendMessage; on
        // failure it stays in the outbox for reconnect-flush or manual
        // retry.
        outbox.append(pending)
        replyTarget = nil
        await attemptSend(pending)
    }

    /// Attempt one outbox entry. Updates the entry's `lastError` on
    /// failure (so the bubble can render "Tap to retry") and removes it
    /// on success. Treats network errors as transient (clears any
    /// previous lastError) — they'll retry automatically on reconnect;
    /// HTTP errors as non-transient — they need user action.
    private func attemptSend(_ pending: PendingMessage) async {
        sending = true
        defer { sending = false }
        do {
            let msg = try await FriendsAPI.sendText(
                friendshipId: friendshipId,
                body: pending.body,
                replyToMessageId: pending.replyToMessageId)
            // The realtime broadcast will also fire `message_received`
            // which would dedupe — append now so the UI feels instant
            // and let the broadcast harmlessly upsert if it arrives.
            upsertMessage(msg)
            outbox.removeAll { $0.id == pending.id }
            errorMessage = nil
        } catch {
            if isTransient(error) {
                // Stay in the outbox without a visible error; reconnect
                // will retry. Clear any stale failure label.
                if let i = outbox.firstIndex(where: { $0.id == pending.id }) {
                    outbox[i].lastError = nil
                }
            } else {
                if let i = outbox.firstIndex(where: { $0.id == pending.id }) {
                    outbox[i].lastError = error.localizedDescription
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Re-attempt every pending outbox entry. Called automatically on
    /// network reconnect and explicitly by the manual "retry" tap.
    func flushOutbox() async {
        // Coalesce concurrent flush requests — multiple isConnected →
        // true edits or rapid retry taps shouldn't all fire send loops.
        flushTask?.cancel()
        let snapshot = outbox
        flushTask = Task {
            for pending in snapshot {
                if Task.isCancelled { return }
                // Pick the live row (lastError may have been cleared
                // since the snapshot was taken).
                guard outbox.contains(where: { $0.id == pending.id }) else { continue }
                await attemptSend(pending)
            }
        }
        await flushTask?.value
    }

    /// Manual retry from a long-press on a failed bubble. Clears the
    /// error label first so the UI flips back to "sending".
    func retryPending(_ id: UUID) async {
        guard let i = outbox.firstIndex(where: { $0.id == id }) else { return }
        outbox[i].lastError = nil
        let pending = outbox[i]
        await attemptSend(pending)
    }

    func deletePending(_ id: UUID) {
        outbox.removeAll { $0.id == id }
    }

    /// Heuristic: treat URLSession-level errors and 5xx as transient
    /// (worth retrying on reconnect); 4xx as permanent (user action
    /// needed). The chat send is a tiny POST so timeouts also fall in
    /// the transient bucket.
    private func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotConnectToHost, .cannotFindHost,
                 .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        if let api = error as? ApiError, case .httpError(let code, _) = api {
            return code >= 500
        }
        return false
    }

    func sendImage(data: Data, contentType: String) async {
        sending = true
        defer { sending = false }
        do {
            let upload = try await FriendsAPI.createImageUpload(friendshipId: friendshipId, contentType: contentType)
            try await FriendsAPI.uploadMedia(uploadUrl: upload.uploadUrl, contentType: contentType, data: data)
            let msg = try await FriendsAPI.commitImage(
                friendshipId: friendshipId,
                objectKey: upload.objectKey,
                replyToMessageId: replyTarget?.id)
            upsertMessage(msg)
            replyTarget = nil
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
                durationMs: durationMs,
                replyToMessageId: replyTarget?.id)
            upsertMessage(msg)
            replyTarget = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markUnreadAsRead() async {
        guard let lastUnread = messages.last(where: { $0.readAt == nil && $0.senderUserId == friendUserId }) else {
            return
        }
        try? await FriendsAPI.markReadThrough(friendshipId: friendshipId, lastMessageId: lastUnread.id)
        NotificationCenter.default.post(name: .friendsUpdated, object: nil)
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
        replyTarget = nil
    }

    func cancelEdit() {
        editingMessageId = nil
        editingDraft = ""
    }

    func beginReply(_ message: FriendMessage) {
        guard !message.isDeleted else { return }
        cancelEdit()
        replyTarget = message
    }

    func cancelReply() {
        replyTarget = nil
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
                        try? await FriendsAPI.markReadThrough(friendshipId: self.friendshipId, lastMessageId: msg.id)
                        NotificationCenter.default.post(name: .friendsUpdated, object: nil)
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
            replyToMessageId: m.replyToMessageId,
            replyPreview: m.replyPreview,
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
                replyToMessageId: m.replyToMessageId,
                replyPreview: m.replyPreview,
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
