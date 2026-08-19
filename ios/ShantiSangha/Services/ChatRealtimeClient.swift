import Foundation

/// Native WebSocket client for the chat realtime channel.
///
/// One instance per active conversation view. Connects to
/// `wss://shantisangha.com/api/chat/realtime?token=...&conversationId=...`,
/// auto-reconnects with exponential backoff + jitter, and surfaces
/// inbound events to the view model via callbacks.
///
/// Group-readiness: every event carries `conversationId` and (where
/// applicable) `fromUserId` / `byUserId`, so the same protocol works
/// for groups when they land. The `conversationId` for v1 is just the
/// friendship id, but the client never assumes that.
@MainActor
final class ChatRealtimeClient {
    typealias TokenProvider = () async -> String?

    let conversationId: UUID

    /// Fired once per inbound JSON frame, after `kind` has been routed.
    var onMessageReceived: ((FriendMessage) -> Void)?
    var onMessageEdited:   ((FriendMessage) -> Void)?
    var onMessageDeleted:  ((UUID /* messageId */) -> Void)?
    var onMessagesRead:    ((_ readByUserId: UUID, _ lastMessageId: UUID, _ readAt: String) -> Void)?
    var onTyping:          ((_ fromUserId: UUID, _ isTyping: Bool) -> Void)?
    var onReactionsChanged: ((_ messageId: UUID, _ reactions: [FriendMessageReactionSummary]) -> Void)?
    /// Fired when the server-side detector has finished processing a
    /// message and produced a reminder suggestion for it. The view model
    /// finds the matching message and attaches the suggestion inline.
    var onSuggestionReady: ((_ messageId: UUID, _ suggestion: FriendMessageSuggestion) -> Void)?

    private let tokenProvider: TokenProvider
    private let baseURL: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reconnectAttempt: Int = 0
    private var explicitlyClosed: Bool = false
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private static let decoder: JSONDecoder = JSONDecoder()
    private static let encoder: JSONEncoder = JSONEncoder()

    init(
        conversationId: UUID,
        baseURL: String,
        tokenProvider: @escaping TokenProvider
    ) {
        self.conversationId = conversationId
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    func connect() {
        explicitlyClosed = false
        Task { await openSocket() }
    }

    func disconnect() {
        explicitlyClosed = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// Send a typing-presence frame. The backend currently only accepts
    /// `kind: "typing"` from clients; everything else is forwarded via
    /// REST so failures surface as HTTP status codes.
    func sendTyping(_ isTyping: Bool) async {
        guard let task = task else { return }
        let envelope: [String: Any] = ["kind": "typing", "isTyping": isTyping]
        // Must be a TEXT frame: the server's read loop ignores any frame
        // that isn't `WebSocketMessageType.Text`, so a `.data` (binary)
        // send is silently dropped and never broadcast. `typing` is the
        // only client→server frame, which is why this was the only thing
        // that silently failed while messages/reads/reactions worked.
        guard let data = try? JSONSerialization.data(withJSONObject: envelope),
              let json = String(data: data, encoding: .utf8) else { return }
        do {
            try await task.send(.string(json))
        } catch {
            // The send failure will be picked up by the receive loop's
            // error handler, which kicks off reconnection. Don't double-
            // schedule it from here.
        }
    }

    // MARK: - Private

    private func openSocket() async {
        guard !explicitlyClosed else { return }

        guard let token = await tokenProvider(), !token.isEmpty else {
            AppLogger.shared.warn("ChatRealtime", "No auth token; deferring connect")
            scheduleReconnect()
            return
        }

        // Replace https:// with wss:// (and http with ws for local dev).
        var wsBase = baseURL
        if wsBase.hasPrefix("https://") {
            wsBase = "wss://" + wsBase.dropFirst("https://".count)
        } else if wsBase.hasPrefix("http://") {
            wsBase = "ws://" + wsBase.dropFirst("http://".count)
        }

        guard var components = URLComponents(string: "\(wsBase)/chat/realtime") else {
            AppLogger.shared.error("ChatRealtime", "Bad WS URL")
            return
        }
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "conversationId", value: conversationId.uuidString.lowercased())
        ]
        guard let url = components.url else {
            AppLogger.shared.error("ChatRealtime", "Failed to build WS URL")
            return
        }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.task = task
        task.resume()
        AppLogger.shared.info("ChatRealtime", "Connecting to \(url.absoluteString.replacingOccurrences(of: token, with: "***"))")

        receiveTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        guard let task = task else { return }
        do {
            while !Task.isCancelled, !explicitlyClosed {
                let message = try await task.receive()
                handleIncoming(message)
            }
        } catch {
            if !explicitlyClosed {
                AppLogger.shared.warn("ChatRealtime", "Read failed: \(error.localizedDescription); reconnecting")
                scheduleReconnect()
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        // Successful frames reset the backoff so the next disconnect
        // starts at the lowest delay.
        reconnectAttempt = 0

        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = envelope["kind"] as? String else {
            return
        }
        switch kind {
        case "message_received":
            if let msg = decodeMessage(from: envelope, key: "message") {
                onMessageReceived?(msg)
            }
        case "message_edited":
            if let msg = decodeMessage(from: envelope, key: "message") {
                onMessageEdited?(msg)
            }
        case "message_deleted":
            if let id = (envelope["messageId"] as? String).flatMap(UUID.init(uuidString:)) {
                onMessageDeleted?(id)
            }
        case "messages_read":
            if let by = (envelope["readByUserId"] as? String).flatMap(UUID.init(uuidString:)),
               let last = (envelope["lastMessageId"] as? String).flatMap(UUID.init(uuidString:)),
               let readAt = envelope["readAt"] as? String {
                onMessagesRead?(by, last, readAt)
            }
        case "typing":
            if let from = (envelope["fromUserId"] as? String).flatMap(UUID.init(uuidString:)) {
                let isTyping = (envelope["isTyping"] as? Bool) ?? false
                onTyping?(from, isTyping)
            }
        case "message_reactions_changed":
            if let id = (envelope["messageId"] as? String).flatMap(UUID.init(uuidString:)),
               let rawReactions = envelope["reactions"] as? [Any],
               let data = try? JSONSerialization.data(withJSONObject: rawReactions),
               let reactions = try? Self.decoder.decode([FriendMessageReactionSummary].self, from: data) {
                onReactionsChanged?(id, reactions)
            }
        case "suggestion_ready":
            // Server-side detector finished and produced a reminder
            // suggestion. The envelope carries the message id this
            // suggestion attaches to plus the extracted fields.
            if let id = (envelope["messageId"] as? String).flatMap(UUID.init(uuidString:)),
               let label = envelope["label"] as? String,
               let date = envelope["date"] as? String {
                let recurrence = (envelope["recurrence"] as? String) ?? "none"
                // Synthesize a client-side FriendMessageSuggestion. The
                // suggestion id field gets a fresh UUID for the client
                // record; persisted state is keyed server-side by
                // (messageId, userId), so the synthesized id is local-only
                // and never sent back. dismissed/accepted start false.
                let suggestion = FriendMessageSuggestion(
                    id: UUID(),
                    kind: "reminder",
                    label: label,
                    date: date,
                    recurrence: recurrence,
                    dismissed: false,
                    accepted: false)
                onSuggestionReady?(id, suggestion)
            }
        default:
            break
        }
    }

    private func decodeMessage(from envelope: [String: Any], key: String) -> FriendMessage? {
        guard let nested = envelope[key] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: nested) else {
            return nil
        }
        return try? Self.decoder.decode(FriendMessage.self, from: data)
    }

    private func scheduleReconnect() {
        guard !explicitlyClosed else { return }
        reconnectTask?.cancel()
        // Exponential backoff capped at 30 s with 200–500 ms jitter to
        // smooth out the thundering herd after a server restart.
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let base = min(30.0, pow(2.0, Double(attempt)))
        let jitter = Double.random(in: 0.2...0.5)
        let delay = base + jitter

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.explicitlyClosed, !Task.isCancelled else { return }
            await self.openSocket()
        }
    }
}
