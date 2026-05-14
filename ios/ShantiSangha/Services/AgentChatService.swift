import Foundation
import FirebaseAuth

/// SSE-streaming client for the in-app agent at `POST /api/agent/chat`.
/// Mirrors the framing used by `ChatView.sendMessage`: each event is
/// `data: <json-encoded string>\n\n`, terminator is `data: [DONE]\n\n`.
///
/// The agent endpoint is stateless from the client's perspective — every
/// request is one self-contained user message; conversation memory will
/// be added later if the spike succeeds.
final class AgentChatService {
    static let shared = AgentChatService()
    private init() {}

    /// Streams the assistant's reply token-by-token. Throws on transport
    /// errors; the caller is expected to surface a friendly fallback.
    func stream(
        message: String
    ) -> AsyncThrowingStream<String, Error> {
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
                    request.httpBody = try JSONEncoder().encode(["message": message])

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    var buffer = Data()
                    let eventTerminator = Data("\n\n".utf8)

                    for try await byte in bytes {
                        buffer.append(byte)

                        while let range = buffer.range(of: eventTerminator) {
                            let eventData = buffer.subdata(in: 0..<range.lowerBound)
                            buffer.removeSubrange(0..<range.upperBound)

                            guard let eventText = String(data: eventData, encoding: .utf8) else { continue }

                            var dataParts: [String] = []
                            for line in eventText.split(separator: "\n", omittingEmptySubsequences: false) {
                                if line.hasPrefix("data: ") {
                                    dataParts.append(String(line.dropFirst(6)))
                                } else if line.hasPrefix("data:") {
                                    dataParts.append(String(line.dropFirst(5)))
                                }
                            }
                            let payload = dataParts.joined(separator: "\n")
                            if payload.isEmpty || payload == "[DONE]" { continue }

                            guard let payloadData = payload.data(using: .utf8),
                                  let decoded = try? JSONDecoder().decode(String.self, from: payloadData) else {
                                continue
                            }

                            continuation.yield(decoded)
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
