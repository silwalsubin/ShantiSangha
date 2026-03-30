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
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
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

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.role == "user" { Spacer() }
            Text(msg.content)
                .font(.sacredText)
                .foregroundColor(msg.role == "user" ? .white : .sacredText)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(msg.role == "user"
                              ? LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.sacredBgCard, Color.sacredBgCard], startPoint: .top, endPoint: .bottom))
                )
                .overlay(
                    msg.role == "assistant"
                    ? RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12))
                    : nil
                )
            if msg.role == "assistant" { Spacer() }
        }
    }

    private func loadMessages() async {
        do {
            messages = try await api.get("/conversations/\(conversationId)/messages")
        } catch {
            print("Failed to load messages: \(error)")
        }
        loading = false
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        sending = true

        // Add user message immediately
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", content: text)
        messages.append(userMsg)

        // Add placeholder for assistant
        let assistantId = UUID().uuidString
        messages.append(ChatMessage(id: assistantId, role: "assistant", content: ""))

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
                        }
                    }
                }
            }
        } catch {
            print("Stream error: \(error)")
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if messages[idx].content.isEmpty {
                    messages[idx].content = "Sorry, something went wrong. Please try again."
                }
            }
        }

        sending = false
    }
}

struct ChatMessage: Codable, Identifiable {
    var id: String
    let role: String
    var content: String

    enum CodingKeys: String, CodingKey {
        case id, role, content
    }

    init(id: String, role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
    }
}
