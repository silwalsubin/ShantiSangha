import Foundation
import FirebaseAuth

/// SSE-streaming client for the in-app agent at `POST /api/agent/chat`,
/// plus history fetch + clear at `GET/DELETE /api/agent/messages`.
///
/// SSE framing matches `ChatView.sendMessage`: each event is
/// `data: <json-encoded string>\n\n`, terminator is `data: [DONE]\n\n`.
/// In addition, the agent can emit `event: reminders\ndata: <json-array>\n\n`
/// frames carrying the reminders that the assistant referenced this turn —
/// the client renders these as tappable cards under the bubble.
final class AgentChatService {
    static let shared = AgentChatService()
    private init() {}

    struct HistoryMessage: Decodable {
        let role: String
        let content: String
        let attachedReminders: [Reminder]?
        /// Presigned GET URL for a photo attached to this turn, when present.
        let imageUrl: String?
    }

    /// One assistant thread in the unified conversation store.
    struct Thread: Decodable, Identifiable, Hashable {
        let id: String
        let title: String?
        let updatedAt: String
        let lastMessage: String
    }

    /// A tappable follow-up the assistant offers after a reply. `label` is the
    /// short button text; `prompt` is the message sent when the chip is tapped.
    struct QuickAction: Decodable, Hashable {
        let label: String
        let prompt: String
    }

    /// One prior turn sent up for a scoped (reminder) session's within-session
    /// memory. Role is "user" or "assistant".
    struct HistoryTurn: Encodable {
        let role: String
        let content: String
    }

    private struct ChatPayload: Encodable {
        let message: String
        var imageBase64: String? = nil
        var imageContentType: String? = nil
        var reminderId: String? = nil
        var conversationId: String? = nil
        var history: [HistoryTurn]? = nil
    }

    /// One frame in the live reply stream — a chunk of prose, a list of
    /// reminders to render as cards, or up to 3 quick-action chips offered
    /// after the reply.
    enum StreamEvent {
        case text(String)
        case reminders([Reminder])
        case quickActions([QuickAction])
        /// First frame of a turn: the thread id the server resolved for it.
        case conversation(String)
    }

    private struct ConversationRef: Decodable { let id: String }

    func fetchHistory(conversationId: String? = nil) async throws -> [HistoryMessage] {
        let token = try await Auth.auth().currentUser?.getIDToken()
        let baseURL = await ApiService.shared.getBaseURL()
        var path = "\(baseURL)/agent/messages"
        if let conversationId { path += "?conversationId=\(conversationId)" }
        guard let url = URL(string: path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([HistoryMessage].self, from: data)
    }

    func fetchThreads() async throws -> [Thread] {
        let token = try await Auth.auth().currentUser?.getIDToken()
        let baseURL = await ApiService.shared.getBaseURL()
        guard let url = URL(string: "\(baseURL)/agent/conversations") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([Thread].self, from: data)
    }

    func createThread() async throws -> String {
        let token = try await Auth.auth().currentUser?.getIDToken()
        let baseURL = await ApiService.shared.getBaseURL()
        guard let url = URL(string: "\(baseURL)/agent/conversations") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ConversationRef.self, from: data).id
    }

    func deleteThread(id: String) async throws {
        let token = try await Auth.auth().currentUser?.getIDToken()
        let baseURL = await ApiService.shared.getBaseURL()
        guard let url = URL(string: "\(baseURL)/agent/conversations/\(id)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        _ = try await URLSession.shared.data(for: request)
    }

    func clearHistory() async throws {
        let token = try await Auth.auth().currentUser?.getIDToken()
        let baseURL = await ApiService.shared.getBaseURL()
        guard let url = URL(string: "\(baseURL)/agent/messages") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        _ = try await URLSession.shared.data(for: request)
    }

    /// Streams the assistant's reply token-by-token, interleaved with any
    /// structured attachments (reminder lists). Throws on transport
    /// errors; the caller is expected to surface a friendly fallback.
    func stream(
        message: String,
        imageBase64: String? = nil,
        imageContentType: String? = nil,
        reminderId: UUID? = nil,
        conversationId: String? = nil,
        history: [HistoryTurn]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try await Auth.auth().currentUser?.getIDToken()
                    let baseURL = await ApiService.shared.getBaseURL()
                    guard let url = URL(string: "\(baseURL)/agent/chat") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    let payload = ChatPayload(
                        message: message,
                        imageBase64: imageBase64,
                        imageContentType: imageContentType,
                        reminderId: reminderId?.uuidString,
                        conversationId: conversationId,
                        history: history)
                    request.httpBody = try JSONEncoder().encode(payload)

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    var buffer = Data()
                    let eventTerminator = Data("\n\n".utf8)

                    for try await byte in bytes {
                        buffer.append(byte)

                        while let range = buffer.range(of: eventTerminator) {
                            let eventData = buffer.subdata(in: 0..<range.lowerBound)
                            buffer.removeSubrange(0..<range.upperBound)

                            guard let eventText = String(data: eventData, encoding: .utf8) else { continue }

                            var eventName: String? = nil
                            var dataParts: [String] = []
                            for line in eventText.split(separator: "\n", omittingEmptySubsequences: false) {
                                if line.hasPrefix("event: ") {
                                    eventName = String(line.dropFirst(7))
                                } else if line.hasPrefix("event:") {
                                    eventName = String(line.dropFirst(6))
                                } else if line.hasPrefix("data: ") {
                                    dataParts.append(String(line.dropFirst(6)))
                                } else if line.hasPrefix("data:") {
                                    dataParts.append(String(line.dropFirst(5)))
                                }
                            }
                            let payload = dataParts.joined(separator: "\n")
                            if payload.isEmpty || payload == "[DONE]" { continue }
                            guard let payloadData = payload.data(using: .utf8) else { continue }

                            switch eventName {
                            case "conversation":
                                if let ref = try? JSONDecoder().decode(ConversationRef.self, from: payloadData) {
                                    continuation.yield(.conversation(ref.id))
                                }
                            case "reminders":
                                if let reminders = try? JSONDecoder().decode([Reminder].self, from: payloadData) {
                                    continuation.yield(.reminders(reminders))
                                }
                            case "quick_actions":
                                if let actions = try? JSONDecoder().decode([QuickAction].self, from: payloadData) {
                                    continuation.yield(.quickActions(actions))
                                }
                            default:
                                if let decoded = try? JSONDecoder().decode(String.self, from: payloadData) {
                                    continuation.yield(.text(decoded))
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
