import SwiftUI
import FirebaseAuth

/// AI Chat — streaming conversation. Mirrors frontend reflect/chat.vue
struct ChatView: View {
    let conversationId: String
    let title: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var loading = true
    @State private var sending = false
    private let api = ApiService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }

                        // Typing indicator
                        if sending, let last = messages.last, last.role == "assistant", last.content.isEmpty {
                            typingIndicator
                                .id("typing")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: messages.last?.content) {
                    scrollToBottom(proxy)
                }
            }

            // Input
            HStack(spacing: 12) {
                TextField("Share what's on your mind...", text: $inputText, axis: .vertical)
                    .font(.sacredText)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBg))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.15)))

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.sacredIconLarge)
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty || sending ? .sacredMuted.opacity(0.3) : .sacredGold)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.sacredBg)
        }
        .background(Color.sacredBgCard.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadMessages() }
    }

    // MARK: - Message bubble

    private func messageBubble(_ msg: ChatMessage) -> some View {
        VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
            HStack {
                if msg.role == "user" { Spacer() }
                Text(msg.content)
                    .font(.sacredText)
                    .foregroundColor(msg.role == "user" ? .white : .sacredText)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(msg.role == "user"
                                  ? LinearGradient.sacredGoldShiny
                                  : LinearGradient(colors: [Color.sacredBgCard, Color.sacredBgCard], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        msg.role == "assistant"
                        ? RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12))
                        : nil
                    )
                if msg.role == "assistant" { Spacer() }
            }

            // Timestamp
            if let ts = msg.timestamp {
                Text(formatTimestamp(ts))
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Typing indicator

    private var typingIndicator: some View {
        HStack {
            TypingDotsView()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.sacredBgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12))
                )
            Spacer()
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else {
            f.dateFormat = "MMM d, h:mm a"
        }
        return f.string(from: date)
    }

    // MARK: - Network

    private func loadMessages() async {
        do {
            let conversation: ConversationDetail = try await api.get("/conversations/\(conversationId)")
            messages = conversation.messages
        } catch {
            AppLogger.shared.error("Chat", "Failed to load messages: \(error)")
        }
        loading = false
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        sending = true

        // Add user message immediately
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", content: text, timestamp: Date())
        messages.append(userMsg)

        // Add placeholder for assistant (empty = shows typing indicator)
        let assistantId = UUID().uuidString
        messages.append(ChatMessage(id: assistantId, role: "assistant", content: "", timestamp: nil))

        // Stream response
        do {
            let token = try await Auth.auth().currentUser?.getIDToken()
            guard let url = URL(string: "https://shantisangha.com/api/conversations/\(conversationId)/messages") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try JSONEncoder().encode(["content": text])

            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var buffer = ""

            for try await byte in bytes {
                buffer += String(UnicodeScalar(byte))
                if buffer.hasSuffix("\n") {
                    let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer = ""
                    if line.hasPrefix("data: ") {
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { continue }
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += payload
                            // Set timestamp on first token
                            if messages[idx].timestamp == nil {
                                messages[idx].timestamp = Date()
                            }
                        }
                    }
                }
            }
        } catch {
            AppLogger.shared.error("Chat", "Stream error: \(error)")
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if messages[idx].content.isEmpty {
                    messages[idx].content = "Sorry, something went wrong. Please try again."
                }
                messages[idx].timestamp = Date()
            }
        }

        sending = false
    }
}

// MARK: - Typing dots animation

private struct TypingDotsView: View {
    @State private var dotIndex = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.sacredMuted)
                    .frame(width: 7, height: 7)
                    .scaleEffect(dotIndex == i ? 1.3 : 0.8)
                    .opacity(dotIndex == i ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.3), value: dotIndex)
            }
        }
        .onReceive(timer) { _ in
            dotIndex = (dotIndex + 1) % 3
        }
    }
}

// MARK: - Model

struct ChatMessage: Identifiable, Decodable {
    var id: String
    let role: String
    var content: String
    var timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id, role, content, createdAt
    }

    init(id: String, role: String, content: String, timestamp: Date? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        content = try c.decode(String.self, forKey: .content)

        // Role can be string ("user"/"assistant") or int (0=User, 1=Assistant)
        if let roleStr = try? c.decode(String.self, forKey: .role) {
            role = roleStr.lowercased()
        } else if let roleInt = try? c.decode(Int.self, forKey: .role) {
            role = roleInt == 0 ? "user" : "assistant"
        } else {
            role = "assistant"
        }

        // Parse createdAt from server
        if let dateStr = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]
            timestamp = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr)
        } else {
            timestamp = nil
        }
    }
}

struct ConversationDetail: Decodable {
    let id: String
    let title: String?
    let messages: [ChatMessage]
}
