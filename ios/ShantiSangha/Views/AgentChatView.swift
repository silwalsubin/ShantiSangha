import SwiftUI
import PhotosUI
import UIKit

/// Agent chat — the in-app surface where GPT-4o can call backend
/// operations as tools. Spike scope: Reminders only (list / schedule /
/// reschedule / cancel). Server persists the last N turns per user so
/// follow-ups like "move that to next Friday" resolve correctly.
struct AgentChatView: View {
    @EnvironmentObject private var profile: ProfileService
    @StateObject private var connections = ConnectionsRepository.shared
    @State private var messages: [AgentMessage] = []
    @State private var inputText: String
    @State private var sending = false
    @State private var stagedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    /// When set, this chat is scoped to one reminder ("Plan with assistant"):
    /// no global history, every turn carries the reminderId, scoped starters.
    private let reminderId: UUID?
    private let reminderLabel: String?
    private var isScoped: Bool { reminderId != nil }

    /// A prompt sent automatically as soon as the chat opens — used by the
    /// Home starter chips, which promise an answer, not a staged draft.
    private let autoSend: String?

    init(prefill: String = "", prefillImage: UIImage? = nil,
         autoSend: String? = nil,
         reminderId: UUID? = nil, reminderLabel: String? = nil) {
        _inputText = State(initialValue: prefill)
        _stagedImage = State(initialValue: prefillImage)
        self.autoSend = autoSend
        self.reminderId = reminderId
        self.reminderLabel = reminderLabel
    }

    @State private var autoSendFired = false

    @State private var loadingHistory = true
    @State private var failedSendText: String?
    @State private var showClearConfirmation = false
    @State private var editTarget: ReminderEditTarget?
    @State private var activeSwipeId: String?
    @State private var pinnedScrollID: String?
    @State private var composerFocused = false
    @State private var followNextMessage = false
    private static let bottomAnchorId = "agent-chat-bottom-anchor"
    private static let groupedMessageSpacing: CGFloat = 2

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            scrollArea
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                failedBanner
                composer
            }
            .background(Color.sacredBg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("tab.vajra")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(.sacredGold)
                    .accessibilityLabel("Assistant")
            }

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
        .task {
            await loadInitialData()
            if let autoSend, !autoSendFired {
                autoSendFired = true
                await sendSuggestion(autoSend)
            }
        }
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
                onSave: { label, date, recurrence, collaboratorIds in
                    if case .edit(let original) = target {
                        if let updated = try? await ReminderRepository.shared.update(
                            id: original.id,
                            label: label,
                            date: date,
                            recurrence: recurrence,
                            collaboratorUserIds: collaboratorIds)
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
                }(),
                onLivePatch: {
                    if case .edit(let reminder) = target {
                        return { patch in
                            let updated = try? await ReminderRepository.shared.update(
                                id: reminder.id,
                                label: patch.label,
                                date: patch.date,
                                recurrence: patch.recurrence,
                                collaboratorUserIds: patch.collaboratorUserIds,
                                notes: patch.notes)
                            if let updated { patchAttachedReminder(updated) }
                            return updated
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    if loadingHistory {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if messages.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                        messageRow(msg, at: index)
                    }

                    if showTypingIndicator {
                        typingIndicator
                            .padding(.top, SacredSpacing.s)
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
            .onChange(of: messages.last?.attachedReminders.count) {
                guard isAtBottom else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
                }
            }
            // THE fix for "the last message hides behind the composer":
            // during streaming the last message's id never changes — only its
            // content grows — so the id-based follow above never fires. Track
            // growth per chunk (no animation: many small hops must feel like
            // pinning, not chasing). Reading upward mid-stream still works —
            // isAtBottom goes false the moment the user scrolls away.
            .onChange(of: messages.last?.content) { _, _ in
                guard isAtBottom else { return }
                proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
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
                    attachedReminders: $0.attachedReminders ?? [],
                    imageUrl: $0.imageUrl)
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
    private func messageRow(_ msg: AgentMessage, at index: Int) -> some View {
        if msg.role == .assistant && msg.content.isEmpty && msg.attachedReminders.isEmpty && sending {
            EmptyView()
        } else {
            bubble(msg, at: index)
                .id(msg.id.uuidString)
                .padding(.top, spacingBeforeMessage(at: index))
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var isAtBottom: Bool {
        pinnedScrollID == nil || pinnedScrollID == Self.bottomAnchorId
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

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespaces).isEmpty || stagedImage != nil) && !sending
    }

    private var composer: some View {
        SacredChatComposer(
            text: $inputText,
            placeholder: "Ask anything…",
            canSend: canSend,
            onSend: { Task { await send() } },
            onFocusChange: { composerFocused = $0 },
            focusOnAppear: true,
            accessories: { composerAccessories },
            banner: { stagedImageBanner })
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    stagedImage = image
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in stagedImage = image }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $photoItem, matching: .images)
    }

    @ViewBuilder
    private var composerAccessories: some View {
        HStack(spacing: 10) {
            // A single "+" collapses the attachment options into one tidy
            // control (ChatGPT-style) instead of a row of inline buttons.
            Menu {
                Button {
                    showPhotoLibrary = true
                } label: {
                    Label("Photo Library", systemImage: "photo")
                }
                // Camera is unavailable on the Simulator and camera-less devices.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22))
                    .foregroundColor(.sacredGold)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Add a photo")

            SacredVoiceInputButton(text: $inputText)
        }
    }

    @ViewBuilder
    private var stagedImageBanner: some View {
        if let stagedImage {
            HStack {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: stagedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.sacredGold.opacity(0.2), lineWidth: 1))

                    Button {
                        self.stagedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .offset(x: 6, y: -6)
                }
                Spacer()
            }
            .padding(.bottom, 4)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            if isScoped, let reminderLabel, !reminderLabel.isEmpty {
                Text("Planning “\(reminderLabel)”")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
            }
            Text("Try one of these")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredMuted)
                .tracking(2)

            ForEach(starters, id: \.self) { prompt in
                suggestionChip(prompt) {
                    Task { await sendSuggestion(prompt) }
                }
            }
        }
    }

    /// Scoped chats nudge toward planning the one reminder; the main chat
    /// mirrors what the assistant can do across reminders + circle.
    private var starters: [String] {
        isScoped ? Self.scopedStarters : Self.starterPrompts
    }

    /// Starters that mirror what the assistant can do — one per primary MCP
    /// capability. Tapping sends immediately, so each is safe to fire as-is:
    /// queries, or open prompts that make the assistant ask for details rather
    /// than create anything on a single tap.
    private static let starterPrompts = [
        "What reminders do I have this week?",
        "Add a reminder",
        "Who's in my circle?",
        "Add someone to my circle",
    ]

    private static let scopedStarters = [
        "Break this into steps",
        "What do I need to prepare?",
        "Add a step",
    ]

    @ViewBuilder
    private func bubble(_ msg: AgentMessage, at index: Int) -> some View {
        let side: SacredChatSide = msg.role == .user ? .mine : .theirs
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: SacredSpacing.xs) {
            if msg.localImage != nil || msg.imageUrl != nil {
                AgentBubbleImage(uiImage: msg.localImage, urlString: msg.imageUrl)
                    // Align to the sender's side — the bare image doesn't
                    // claim full width the way the text bubble row does, so
                    // without this it drifts to the leading edge.
                    .frame(maxWidth: .infinity,
                           alignment: msg.role == .user ? .trailing : .leading)
            }
            if !msg.content.isEmpty {
                if msg.role == .user {
                    SacredChatBubbleRow(side: side, hasTail: isLastInSenderRun(at: index)) {
                        Text(msg.content)
                    }
                } else {
                    SacredAssistantMessageRow {
                        Text(msg.content)
                    }
                }
            }
            if !msg.attachedReminders.isEmpty {
                reminderAttachments(msg.attachedReminders)
            }
            // Quick-action chips ride only on the latest message and only once
            // the reply has fully streamed. When the next turn is appended this
            // message stops being last, so the chips clear themselves — whether
            // the user tapped a chip or typed something custom.
            if msg.role == .assistant,
               !msg.quickActions.isEmpty,
               msg.id == messages.last?.id,
               !sending {
                quickActionChips(msg.quickActions)
            }
        }
    }

    /// Tappable follow-ups under the latest assistant reply — a one-tap path
    /// for the actions the user is most likely to want next. Tapping sends the
    /// chip's prompt through the normal pipeline; the text box stays open for
    /// custom typing. Saffron-outlined pills in the sacred palette.
    private func quickActionChips(_ actions: [AgentChatService.QuickAction]) -> some View {
        WrapLayout(spacing: SacredSpacing.xs, lineSpacing: SacredSpacing.xs) {
            ForEach(actions, id: \.self) { action in
                suggestionChip(action.label) {
                    Task { await sendSuggestion(action.prompt) }
                }
            }
        }
        .padding(.top, SacredSpacing.xs)
    }

    /// A saffron-outlined pill on the card surface — the shared "chip" used by
    /// both the empty-state starter prompts and the post-reply quick actions,
    /// so the two read as one component. Hugs its text; wraps long labels.
    private func suggestionChip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.sacredTextSemibold)
                .foregroundColor(.sacredGold)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, SacredSpacing.m)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Capsule().fill(Color.sacredBgCard))
                .overlay(Capsule().strokeBorder(Color.sacredGold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func spacingBeforeMessage(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let msg = messages[index]
        let previous = messages[index - 1]
        return msg.role == previous.role ? Self.groupedMessageSpacing : SacredSpacing.s
    }

    private func isLastInSenderRun(at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return true }
        let nextIndex = index + 1
        guard messages.indices.contains(nextIndex) else { return true }
        return messages[index].role != messages[nextIndex].role
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
                    connectionLabel: connectionLabel(for: reminder),
                    currentUserId: profile.currentUserId,
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
                        .padding(.leading, 72)
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

    private func loadInitialData() async {
        // Scoped planning chats start fresh — no global history to replay.
        if isScoped {
            loadingHistory = false
            return
        }
        async let connectionLoad: Void = connections.refresh()
        await loadHistory()
        _ = await connectionLoad
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        let image = stagedImage
        guard !text.isEmpty || image != nil else { return }
        failedSendText = nil
        inputText = ""
        stagedImage = nil
        photoItem = nil
        sending = true
        followNextMessage = true

        // Encode the attached photo (if any) for the vision request.
        var imageBase64: String?
        var imageContentType: String?
        if let image, let jpeg = image.jpegData(compressionQuality: 0.8) {
            imageBase64 = jpeg.base64EncodedString()
            imageContentType = "image/jpeg"
        }

        // Scoped chats keep no server-side history, so carry the in-session
        // transcript ourselves. Snapshot it BEFORE appending the new turn.
        let priorHistory: [AgentChatService.HistoryTurn]? = isScoped
            ? messages.compactMap { m in
                m.content.isEmpty ? nil
                    : AgentChatService.HistoryTurn(
                        role: m.role == .user ? "user" : "assistant",
                        content: m.content)
              }
            : nil

        let assistantId = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(AgentMessage(role: .user, content: text, localImage: image))
            messages.append(AgentMessage(id: assistantId, role: .assistant, content: ""))
        }

        do {
            for try await event in AgentChatService.shared.stream(
                message: text, imageBase64: imageBase64, imageContentType: imageContentType,
                reminderId: reminderId, history: priorHistory) {
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { continue }
                switch event {
                case .text(let chunk):
                    let wasEmpty = messages[idx].content.isEmpty
                    if wasEmpty {
                        withAnimation(.easeOut(duration: 0.2)) {
                            messages[idx].content += chunk
                        }
                    } else {
                        messages[idx].content += chunk
                    }
                case .reminders(let items):
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages[idx].attachedReminders = items
                    }
                case .quickActions(let actions):
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages[idx].quickActions = actions
                    }
                }
            }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Agent", "Stream error: \(error)")
                failedSendText = text
                if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                   messages[idx].content.isEmpty,
                   messages[idx].attachedReminders.isEmpty {
                    withAnimation(.easeOut(duration: 0.2)) {
                        messages[idx].content = "Sorry, something went wrong. Please try again."
                    }
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

    /// Fires when the user taps a quick-action chip: prefill the composer with
    /// the chip's prompt and send it through the normal flow.
    private func sendSuggestion(_ prompt: String) async {
        inputText = prompt
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

    private func connectionLabel(for reminder: Reminder) -> String? {
        guard let cid = reminder.connectionId else { return nil }
        return connections.connection(for: cid)?.displayLabel
    }
}

// MARK: - Model

struct AgentMessage: Identifiable {
    enum Role { case user, assistant }
    let id: UUID
    let role: Role
    var content: String
    var attachedReminders: [Reminder]
    /// Photo the user attached to this turn, shown live right after send.
    var localImage: UIImage?
    /// Presigned URL for a persisted photo, populated from history on
    /// reopen (when `localImage` isn't available in-memory).
    var imageUrl: String?
    /// Tappable follow-ups offered after this assistant reply. Ephemeral —
    /// only rendered while this is the latest message, never persisted.
    var quickActions: [AgentChatService.QuickAction]

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachedReminders: [Reminder] = [],
        localImage: UIImage? = nil,
        imageUrl: String? = nil,
        quickActions: [AgentChatService.QuickAction] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedReminders = attachedReminders
        self.localImage = localImage
        self.imageUrl = imageUrl
        self.quickActions = quickActions
    }
}

// MARK: - Bubble image

/// Renders a photo attached to an assistant turn. Uses the in-memory
/// `UIImage` when available (the live turn just after sending); otherwise
/// loads the persisted photo from its presigned URL through the shared
/// image cache (which strips the rotating query params).
private struct AgentBubbleImage: View {
    let uiImage: UIImage?
    let urlString: String?

    @State private var loaded: UIImage?

    private var image: UIImage? { uiImage ?? loaded }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.sacredGold.opacity(0.15), lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.sacredBgCard)
                    .frame(width: 180, height: 180)
                    .overlay(ProgressView().tint(.sacredGold))
            }
        }
        .task(id: urlString) {
            guard uiImage == nil, let urlString, let url = URL(string: urlString) else { return }
            loaded = await AvatarImageCache.shared.image(for: url)
        }
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
