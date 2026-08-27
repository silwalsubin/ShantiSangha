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
    @State private var pinnedScrollID: String?
    @State private var composerFocused = false
    @State private var followNextMessage = false
    private let api = ApiService.shared
    private static let bottomAnchorId = "chat-bottom-anchor"
    private static let groupedMessageSpacing: CGFloat = 2

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

            messageList
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                failedBanner
                composer
            }
            .background(Color.sacredBg)
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
                // Companion speaks first in a brand-new conversation — unless
                // the user arrived carrying a voice note to share, where the
                // greeting would step on their intent.
                if initialText == nil {
                    await streamOpener()
                }
                if messages.isEmpty {
                    await loadOpeningPrompt()
                }
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

    // MARK: - Subviews

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
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
                                .padding(.top, index == 0 ? 0 : SacredSpacing.m)
                                .padding(.bottom, SacredSpacing.xs)
                        }

                        // Hide empty assistant placeholder — typing indicator replaces it.
                        if !(msg.role == "assistant" && msg.content.isEmpty && sending) {
                            messageBubble(msg, at: index)
                                .id(msg.id)
                                .padding(.top, spacingBeforeMessage(at: index))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    if sending, let last = messages.last, last.role == "assistant", last.content.isEmpty {
                        typingIndicator
                            .id("typing")
                            .padding(.top, SacredSpacing.s)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorId)
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, SacredSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .scrollPosition(id: $pinnedScrollID, anchor: .bottom)
            .task {
                pinnedScrollID = Self.bottomAnchorId
            }
            .onChange(of: messages.last?.id) { _, newId in
                guard newId != nil else { return }
                let shouldFollow = followNextMessage || isAtBottom
                guard shouldFollow else { return }
                followNextMessage = false
                pinnedScrollID = Self.bottomAnchorId
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: composerFocused) { _, focused in
                guard focused, isAtBottom else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            // During streaming the last message's id never changes — only its
            // content grows — so the id-based follow above never fires and
            // the reply slides out of view behind the composer. Track growth
            // per chunk, unanimated so it feels pinned rather than chased.
            .onChange(of: messages.last?.content) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var failedBanner: some View {
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
    }

    private var composer: some View {
        SacredChatComposer(
            text: $inputText,
            placeholder: "Share what's on your mind...",
            canSend: !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !sending,
            onSend: { Task { await sendMessage() } },
            onFocusChange: { composerFocused = $0 })
    }

    private var isAtBottom: Bool {
        pinnedScrollID == nil || pinnedScrollID == Self.bottomAnchorId
    }

    // MARK: - Message bubble

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage, at index: Int) -> some View {
        let side: SacredChatSide = msg.role == "user" ? .mine : .theirs
        if msg.role == "user" {
            SacredChatBubbleRow(side: side, hasTail: isLastInSenderRun(at: index)) {
                Text(msg.content)
            }
        } else {
            SacredAssistantMessageRow {
                Text(msg.content)
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

        if !calendar.isDate(date, inSameDayAs: prev) {
            return dateLabelFor(date, calendar: calendar)
        }

        if date.timeIntervalSince(prev) >= 30 * 60 {
            return timeLabelFor(date)
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

    private func timeLabelFor(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Helpers

    private func spacingBeforeMessage(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if dateDividerLabel(at: index) != nil { return 0 }

        let msg = messages[index]
        let previous = messages[index - 1]
        return msg.role == previous.role ? Self.groupedMessageSpacing : SacredSpacing.s
    }

    private func isLastInSenderRun(at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return true }
        let msg = messages[index]
        let nextIndex = index + 1
        guard messages.indices.contains(nextIndex) else { return true }

        let next = messages[nextIndex]
        if dateDividerLabel(at: nextIndex) != nil { return true }
        return msg.role != next.role
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
            if let upcoming = reminders.first(where: { $0.completedAt == nil && $0.localDaysRemaining <= 7 }) {
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
        followNextMessage = true

        // Add user message immediately
        let userMsg = ChatMessage(id: UUID().uuidString, role: "user", content: text, timestamp: Date())

        // Add placeholder for assistant (empty = shows typing indicator)
        let assistantId = UUID().uuidString
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(userMsg)
            messages.append(ChatMessage(id: assistantId, role: "assistant", content: "", timestamp: nil))
        }

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

            try await streamSSE(request: request, into: assistantId)
            failedSendText = nil
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chat", "Stream error: \(error)")
                failedSendText = text
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    let update = {
                        if messages[idx].content.isEmpty {
                            messages[idx].content = "Sorry, something went wrong. Please try again."
                        }
                        messages[idx].timestamp = Date()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        update()
                    }
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

    /// Companion speaks first: streams a personalized greeting into a
    /// brand-new conversation. On failure the empty placeholder is removed so
    /// the static opening card quietly takes its place instead.
    private func streamOpener() async {
        sending = true
        let assistantId = UUID().uuidString
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(ChatMessage(id: assistantId, role: "assistant", content: "", timestamp: nil))
        }

        do {
            let token = try await Auth.auth().currentUser?.getIDToken()
            if let url = URL(string: "https://shantisangha.com/api/conversations/\(conversationId)/opener") {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                if let token = token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                try await streamSSE(request: request, into: assistantId)
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Chat", "Opener stream error: \(error)")
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == assistantId }), messages[idx].content.isEmpty {
            messages.remove(at: idx)
        }
        sending = false
    }

    /// Drains an SSE response into the message with `assistantId`. Events are
    /// separated by `\n\n`; each `data:` payload is a JSON-encoded string so
    /// embedded newlines, quotes, and non-ASCII chars survive framing intact.
    private func streamSSE(request: URLRequest, into assistantId: String) async throws {
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        var buffer = Data()
        let eventTerminator = Data("\n\n".utf8)

        for try await byte in bytes {
            buffer.append(byte)

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

                guard let payloadData = payload.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(String.self, from: payloadData) else {
                    continue
                }

                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    let wasEmpty = messages[idx].content.isEmpty
                    let update = {
                        messages[idx].content += decoded
                        if messages[idx].timestamp == nil {
                            messages[idx].timestamp = Date()
                        }
                    }
                    if wasEmpty {
                        withAnimation(.easeOut(duration: 0.2)) {
                            update()
                        }
                    } else {
                        update()
                    }
                }
            }
        }
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
