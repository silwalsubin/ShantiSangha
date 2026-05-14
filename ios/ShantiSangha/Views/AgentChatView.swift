import SwiftUI

/// Agent chat — the in-app surface where GPT-4o can call backend
/// operations as tools. Spike scope: Reminders only (list / schedule /
/// reschedule / cancel). Server persists the last N turns per user so
/// follow-ups like "move that to next Friday" resolve correctly.
struct AgentChatView: View {
    @State private var messages: [AgentMessage] = []
    @State private var inputText: String
    @State private var sending = false

    init(prefill: String = "") {
        _inputText = State(initialValue: prefill)
    }

    @State private var loadingHistory = true
    @State private var failedSendText: String?
    @State private var showClearConfirmation = false
    @State private var editTarget: ReminderEditTarget?
    @State private var activeSwipeId: String?

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                scrollArea
                failedBanner
                composer
            }
        }
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !messages.isEmpty {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        .task { await loadHistory() }
        .confirmationDialog(
            "Start fresh?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear conversation", role: .destructive) {
                Task { await clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes everything you've said to the assistant. It won't touch your reminders.")
        }
        .navigationDestination(item: $editTarget) { target in
            ReminderEditView(
                target: target,
                onSave: { label, date, recurrence in
                    if case .edit(let original) = target {
                        if let updated = try? await ReminderRepository.shared.update(
                            id: original.id,
                            label: label,
                            date: date,
                            recurrence: recurrence)
                        {
                            patchAttachedReminder(updated)
                        }
                    }
                },
                onDelete: {
                    if case .edit(let reminder) = target {
                        return {
                            try? await ReminderRepository.shared.delete(id: reminder.id)
                            removeAttachedReminder(reminder.id)
                        }
                    }
                    return nil
                }()
            )
        }
    }

    // MARK: - Subviews

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SacredSpacing.m) {
                    if loadingHistory {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if messages.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    }

                    ForEach(messages) { msg in
                        messageRow(msg)
                    }

                    if showTypingIndicator {
                        typingIndicator
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
            .onChange(of: messages.last?.attachedReminders.count) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom") }
                }
            }
        }
    }

    private func loadHistory() async {
        do {
            let history = try await AgentChatService.shared.fetchHistory()
            messages = history.map {
                AgentMessage(
                    role: $0.role == "user" ? .user : .assistant,
                    content: $0.content,
                    attachedReminders: $0.attachedReminders ?? [])
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Agent", "History load failed: \(error)")
            }
        }
        loadingHistory = false
    }

    private func clearHistory() async {
        do {
            try await AgentChatService.shared.clearHistory()
            messages = []
            failedSendText = nil
        } catch {
            AppLogger.shared.error("Agent", "History clear failed: \(error)")
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: AgentMessage) -> some View {
        if msg.role == .assistant && msg.content.isEmpty && msg.attachedReminders.isEmpty && sending {
            EmptyView()
        } else {
            bubble(msg).id(msg.id)
        }
    }

    private var showTypingIndicator: Bool {
        guard sending, let last = messages.last else { return false }
        return last.role == .assistant && last.content.isEmpty && last.attachedReminders.isEmpty
    }

    private var typingIndicator: some View {
        HStack {
            AgentTypingDots()
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            Spacer()
        }
        .id("typing")
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
                    Task { await retry(failedSendText) }
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
            placeholder: "Ask about your reminders…",
            canSend: !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !sending,
            onSend: { Task { await send() } },
            accessories: { SacredVoiceInputButton(text: $inputText) },
            banner: { EmptyView() })
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            Text("Try one of these")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredMuted)
                .tracking(2)

            ForEach(Self.starterPrompts, id: \.self) { prompt in
                Button {
                    inputText = prompt
                } label: {
                    Text(prompt)
                        .font(.sacredText)
                        .foregroundColor(.sacredText)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Color.sacredBgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static let starterPrompts = [
        "What reminders do I have this week?",
        "Remind me about my dad's birthday on June 10, yearly.",
        "Cancel the electric bill reminder.",
    ]

    @ViewBuilder
    private func bubble(_ msg: AgentMessage) -> some View {
        let side: SacredChatSide = msg.role == .user ? .mine : .theirs
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: SacredSpacing.s) {
            if !msg.content.isEmpty {
                SacredChatBubbleRow(side: side) {
                    Text(msg.content)
                }
            }
            if !msg.attachedReminders.isEmpty {
                reminderAttachments(msg.attachedReminders)
            }
        }
    }

    /// Interactive cards for reminders the assistant referenced this turn.
    /// Tap pushes the edit page; swipe-right marks complete (mirrors Home).
    /// On complete / delete the card drops out of the bubble so the chat
    /// reflects the user's most recent action.
    private func reminderAttachments(_ reminders: [Reminder]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(reminders.enumerated()), id: \.element.id) { idx, reminder in
                ReminderRow(
                    reminder: reminder,
                    allowSwipeToComplete: true,
                    showDateStamp: true,
                    onTap: { editTarget = .edit(reminder) },
                    onComplete: {
                        Task {
                            if let updated = try? await ReminderRepository.shared.markComplete(id: reminder.id) {
                                patchAttachedReminder(updated)
                            }
                        }
                    },
                    activeSwipeId: $activeSwipeId
                )

                if idx < reminders.count - 1 {
                    Divider()
                        .padding(.leading, 104)
                        .padding(.trailing, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sacredBgCard.opacity(0.5))
        )
    }

    // MARK: - Send

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        failedSendText = nil
        inputText = ""
        sending = true

        messages.append(AgentMessage(role: .user, content: text))
        let assistantId = UUID()
        messages.append(AgentMessage(id: assistantId, role: .assistant, content: ""))

        do {
            for try await event in AgentChatService.shared.stream(message: text) {
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { continue }
                switch event {
                case .text(let chunk):
                    messages[idx].content += chunk
                case .reminders(let items):
                    messages[idx].attachedReminders = items
                }
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Agent", "Stream error: \(error)")
                failedSendText = text
                if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                   messages[idx].content.isEmpty,
                   messages[idx].attachedReminders.isEmpty {
                    messages[idx].content = "Sorry, something went wrong. Please try again."
                }
            }
        }

        sending = false
    }

    private func retry(_ text: String) async {
        inputText = text
        failedSendText = nil
        await send()
    }

    // MARK: - Card state

    private func patchAttachedReminder(_ updated: Reminder) {
        for i in messages.indices {
            if let j = messages[i].attachedReminders.firstIndex(where: { $0.id == updated.id }) {
                messages[i].attachedReminders[j] = updated
            }
        }
    }

    private func removeAttachedReminder(_ id: UUID) {
        for i in messages.indices {
            messages[i].attachedReminders.removeAll { $0.id == id }
        }
    }
}

// MARK: - Model

struct AgentMessage: Identifiable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var content: String
    var attachedReminders: [Reminder]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachedReminders: [Reminder] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedReminders = attachedReminders
    }
}

// MARK: - Typing dots

/// Local copy because `ChatView`'s `TypingDotsView` is `private` to that file.
private struct AgentTypingDots: View {
    @State private var dotIndex = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

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
