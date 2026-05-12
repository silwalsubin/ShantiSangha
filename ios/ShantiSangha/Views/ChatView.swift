import SwiftUI
import FirebaseAuth

/// AI Chat — streaming conversation. Mirrors frontend reflect/chat.vue
struct ChatView: View {
    let conversationId: String
    let title: String
    let initialText: String?

    @State private var displayTitle: String
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var loading = true
    @State private var sending = false
    @State private var failedSendText: String?
    @State private var openingPrompt = "You are here. What feels present today?"
    private let api = ApiService.shared

    init(conversationId: String, title: String, initialText: String? = nil) {
        self.conversationId = conversationId
        self.title = title
        self.initialText = initialText
        let initial = (title.isEmpty || title == "New Conversation") ? "Conversation" : title
        _displayTitle = State(initialValue: initial)
        _inputText = State(initialValue: initialText ?? "")
    }

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: SacredSpacing.m) {
                            if loading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 80)
                            } else if messages.isEmpty {
                                SacredOpeningCard(
                                    icon: "sparkle",
                                    prompt: openingPrompt,
                                    subtitle: initialText != nil
                                        ? "Your note is ready below if you want to begin there."
                                        : nil
                                )
                                .padding(.top, 40)
                            }

                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                                if let label = dateDividerLabel(at: index) {
                                    Text(label)
                                        .font(.sacredSmallSemibold)
                                        .foregroundColor(.sacredMuted)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, SacredSpacing.xxs)
                                }

                                // Hide empty assistant placeholder — typing indicator replaces it
                                if !(msg.role == "assistant" && msg.content.isEmpty && sending) {
                                    messageBubble(msg)
                                        .id(msg.id)
                                }
                            }

                            if sending, let last = messages.last, last.role == "assistant", last.content.isEmpty {
                                typingIndicator
                                    .id("typing")
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(SacredSpacing.m)
                        .padding(.bottom, 60)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                        }
                    }
                    .onChange(of: messages.last?.content) {
                        proxy.scrollTo("bottom")
                    }
                }

                if let failedSendText {
                    HStack(spacing: 10) {
                        Text("Message did not send.")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        Spacer()
                        Button {
                            Task { await retryMessage(failedSendText) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Try again")
                            }
                            .font(.sacredSmallSemibold)
                            .foregroundColor(.sacredGold)
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.xs)
                    .background(Color.sacredBg)
                }

                SacredChatComposer(
                    text: $inputText,
                    placeholder: "Share what's on your mind...",
                    canSend: !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !sending,
                    onSend: { Task { await sendMessage() } })
            }
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !messages.isEmpty {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        .task {
            await loadMessages()
            if messages.isEmpty {
                await loadOpeningPrompt()
            }
        }
    }

    // MARK: - Share

    private var shareText: String {
        messages.map { msg in
            let label = msg.role == "user" ? "Me" : "ShantiSangha"
            return "\(label): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    // MARK: - Message bubble

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let side: SacredChatSide = msg.role == "user" ? .mine : .theirs
        return VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
            SacredChatBubbleRow(side: side) {
                Text(msg.content)
            }

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
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            Spacer()
        }
    }

    // MARK: - Date dividers

    private func dateDividerLabel(at index: Int) -> String? {
        let msg = messages[index]
        guard let date = msg.timestamp else { return index == 0 ? "Today" : nil }

        let calendar = Calendar.current

        if index == 0 {
            return dateLabelFor(date, calendar: calendar)
        }

        let prevDate = messages[index - 1].timestamp
        guard let prev = prevDate else {
            return dateLabelFor(date, calendar: calendar)
        }

        // Show divider if the day changed
        if !calendar.isDate(date, inSameDayAs: prev) {
            return dateLabelFor(date, calendar: calendar)
        }

        return nil
    }

    private func dateLabelFor(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let days = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: date)
        }

        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
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
            if let t = conversation.title, t != "Conversation", t != "New Conversation", !t.isEmpty {
                displayTitle = t
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chat", "Failed to load messages: \(error)")
            }
        }
        loading = false
    }

    private func loadOpeningPrompt() async {
        do {
            let reminders: [Reminder] = try await api.get("/reminders")
            if let upcoming = reminders.first(where: { $0.completedAt == nil && $0.daysRemaining <= 7 }) {
                openingPrompt = "\(upcoming.label) is in your field. What would help you meet it clearly?"
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chat", "Failed to load opening prompt context: \(error)")
            }
        }
    }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        failedSendText = nil
        inputText = ""
        sending = true

        // Add user message immediately
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", content: text, timestamp: Date())
        messages.append(userMsg)

        // Add placeholder for assistant (empty = shows typing indicator)
        let assistantId = UUID().uuidString
        messages.append(ChatMessage(id: assistantId, role: "assistant", content: "", timestamp: nil))

        // Stream response
        let typingStart = Date()
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
            var buffer = Data()
            var firstToken = true
            let eventTerminator = Data("\n\n".utf8)

            for try await byte in bytes {
                buffer.append(byte)

                // Drain any complete SSE events from the buffer. Events are
                // separated by `\n\n` per spec.
                while let range = buffer.range(of: eventTerminator) {
                    let eventData = buffer.subdata(in: 0..<range.lowerBound)
                    buffer.removeSubrange(0..<range.upperBound)

                    guard let eventText = String(data: eventData, encoding: .utf8) else { continue }

                    // An SSE event may have multiple `data:` lines; join their
                    // payloads with `\n` per spec.
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

                    // Each payload is a JSON-encoded string. Decoding restores
                    // any embedded newlines, quotes, or non-ASCII chars intact.
                    guard let payloadData = payload.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(String.self, from: payloadData) else {
                        continue
                    }

                    // Ensure typing indicator shows for at least 1 second
                    if firstToken {
                        let elapsed = Date().timeIntervalSince(typingStart)
                        if elapsed < 1.0 {
                            try? await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
                        }
                        firstToken = false
                    }

                    if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                        messages[idx].content += decoded
                        if messages[idx].timestamp == nil {
                            messages[idx].timestamp = Date()
                        }
                    }
                }
            }
            failedSendText = nil
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chat", "Stream error: \(error)")
                failedSendText = text
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    if messages[idx].content.isEmpty {
                        messages[idx].content = "Sorry, something went wrong. Please try again."
                    }
                    messages[idx].timestamp = Date()
                }
            }
        }

        sending = false

        // Refresh title — may have been auto-generated after first exchange
        if displayTitle == "Conversation" {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let conv: ConversationDetail = try? await api.get("/conversations/\(conversationId)") {
                    if let t = conv.title, t != "Conversation", t != "New Conversation", !t.isEmpty {
                        displayTitle = t
                    }
                }
            }
        }
    }

    private func retryMessage(_ text: String) async {
        inputText = text
        failedSendText = nil
        await sendMessage()
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
