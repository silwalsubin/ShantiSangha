import SwiftUI

/// Unified reflection hub — conversations, journals, and voice notes in one timeline.
struct ReflectView: View {
    @State private var conversations: [ConversationItem] = []
    @State private var journals: [JournalItem] = []
    @State private var voiceNotes: [VoiceNoteItem] = []
    @State private var loading = true
    @State private var newConversationId: String?
    @State private var showBeginReflection = false
    @State private var pendingNavigation: ReflectNavDestination?
    @State private var toastMessage: String?
    private let api = ApiService.shared

    // MARK: - Unified timeline

    private var timelineItems: [ReflectTimelineItem] {
        var items: [ReflectTimelineItem] = []

        for conv in conversations {
            let hasTitle = conv.title != "Conversation" && conv.title != "New Conversation"
            let fallbackTitle = conv.lastUserMessage ?? conv.lastMessage
            items.append(ReflectTimelineItem(
                id: conv.id,
                type: .conversation,
                title: hasTitle ? conv.title : fallbackTitle,
                preview: hasTitle ? (conv.lastUserMessage ?? conv.lastMessage) : "",
                date: conv.updatedAt
            ))
        }

        for journal in journals {
            items.append(ReflectTimelineItem(
                id: journal.id,
                type: .journal,
                title: journal.title,
                preview: journal.preview,
                date: journal.updatedAt
            ))
        }

        for voice in voiceNotes {
            let transcript = voice.transcriptPreview ?? (voice.hasTranscript ? "Voice note" : "Transcribing...")
            items.append(ReflectTimelineItem(
                id: voice.id,
                type: .voice,
                title: transcript,
                preview: "",
                date: voice.updatedAt
            ))
        }

        return items.sorted { $0.date > $1.date }
    }

    private var groupedTimeline: [(String, [ReflectTimelineItem])] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [ReflectTimelineItem]] = [:]
        var order: [String] = []

        for item in timelineItems {
            let label = timePeriodLabel(for: item.date, now: now, calendar: calendar)
            if groups[label] == nil {
                order.append(label)
            }
            groups[label, default: []].append(item)
        }

        return order.map { ($0, groups[$0]!) }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if timelineItems.isEmpty {
                        SacredEmptyState(
                            icon: "leaf",
                            title: "Your reflections will appear here.",
                            subtitle: "Begin once. Let the form follow.",
                            actionLabel: "Begin reflection",
                            action: { showBeginReflection = true }
                        )
                    } else {
                        ForEach(groupedTimeline, id: \.0) { group in
                            let (label, items) = group

                            Text(label)
                                .font(.sacredTitle)
                                .foregroundColor(.sacredText)
                                .padding(.top, SacredSpacing.l)
                                .padding(.bottom, SacredSpacing.s)

                            SacredListCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                        timelineRow(item, section: label)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    Task { await deleteItem(item) }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }

                                        if index < items.count - 1 {
                                            Divider()
                                                .padding(.leading, 48)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, SacredSpacing.m)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
            .background(Color.clear)
            .refreshable { await loadAll() }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadAll() }
            .onAppear {
                Task {
                    // Brief delay to let any in-flight deletes (empty journals) complete
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await loadAll()
                }
            }

            SacredFAB(icon: "square.and.pencil") {
                showBeginReflection = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .navigationDestination(item: $pendingNavigation) { dest in
            switch dest {
            case .chat(let id):
                ChatView(conversationId: id, title: "New Conversation")
            case .journal:
                JournalEditorView(journalId: nil, isNew: true)
            case .voice:
                VoiceNoteView()
            }
        }
        .sheet(isPresented: $showBeginReflection) {
            BeginReflectionSheet(
                onChat: {
                    showBeginReflection = false
                    Task { await startChat() }
                },
                onJournal: {
                    showBeginReflection = false
                    pendingNavigation = .journal
                },
                onVoice: {
                    showBeginReflection = false
                    pendingNavigation = .voice
                }
            )
        }
        .sacredToast($toastMessage)
    }

    // MARK: - Timeline row

    private func timelineRow(_ item: ReflectTimelineItem, section: String) -> some View {
        Group {
            switch item.type {
            case .conversation:
                NavigationLink(destination: ChatView(conversationId: item.id, title: item.title ?? "Conversation")) {
                    rowContent(item, section: section)
                }
            case .journal:
                NavigationLink(destination: JournalEditorView(journalId: item.id, isNew: false)) {
                    rowContent(item, section: section)
                }
            case .voice:
                NavigationLink(destination: VoiceNoteDetailView(entryId: item.id)) {
                    rowContent(item, section: section)
                }
            }
        }
    }

    private func rowContent(_ item: ReflectTimelineItem, section: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Type indicator
            Image(systemName: item.type.icon)
                .font(.sacredIcon)
                .foregroundColor(item.type.color)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Title or date
                if let title = item.title, !title.isEmpty, title != "Untitled" {
                    Text(title)
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                        .lineLimit(1)
                }

                Text(formatDateTime(item.date, in: section))
                    .font(item.title != nil ? .sacredSmall : .sacredTextSemibold)
                    .foregroundColor(item.title != nil ? .sacredMuted : .sacredText)

                if !item.preview.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(item.preview.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.sacredSmall)
                        .foregroundColor(.sacredTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func timePeriodLabel(for date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0

        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if days < 7 { return "Previous 7 Days" }
        if days < 30 { return "Previous 30 Days" }

        let f = DateFormatter()
        f.dateFormat = "MMMM"
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        if year != currentYear {
            f.dateFormat = "MMMM yyyy"
        }
        return f.string(from: date)
    }

    private func formatDateTime(_ date: Date, in section: String) -> String {
        let f = DateFormatter()
        switch section {
        case "Today", "Yesterday":
            f.dateFormat = "h:mm a"
        case "Previous 7 Days":
            f.dateFormat = "EEEE, h:mm a"
        default:
            f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        }
        return f.string(from: date)
    }

    // MARK: - Network

    private func loadAll() async {
        async let convTask: () = loadConversations()
        async let journalTask: () = loadJournals()
        async let voiceTask: () = loadVoiceNotes()
        _ = await (convTask, journalTask, voiceTask)
        loading = false
    }

    private func loadConversations() async {
        do {
            let all: [ConversationItem] = try await api.get("/conversations")
            conversations = all.filter { !$0.lastMessage.isEmpty }
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Reflect", "Failed to load conversations: \(error)")
            }
        }
    }

    private func loadJournals() async {
        do {
            let items: [JournalItem] = try await api.get("/journals?page=1&pageSize=50")
            journals = items
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Reflect", "Failed to load journals: \(error)")
            }
        }
    }

    private func loadVoiceNotes() async {
        do {
            let items: [VoiceNoteItem] = try await api.get("/voice/entries?page=1&pageSize=50")
            voiceNotes = items
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Reflect", "Failed to load voice notes: \(error)")
            }
        }
    }

    private func startChat() async {
        do {
            let conv: ConversationItem = try await api.post("/conversations", body: ["title": "New Conversation"])
            newConversationId = conv.id
            pendingNavigation = .chat(id: conv.id)
        } catch {
            toastMessage = "Could not open a conversation. Try again in a moment."
            AppLogger.shared.error("Reflect", "Failed to create conversation: \(error)")
        }
    }

    private func deleteItem(_ item: ReflectTimelineItem) async {
        switch item.type {
        case .conversation:
            conversations.removeAll { $0.id == item.id }
            do { try await api.delete("/conversations/\(item.id)") } catch {
                AppLogger.shared.error("Reflect", "Failed to delete conversation: \(error)")
                await loadConversations()
            }
        case .journal:
            journals.removeAll { $0.id == item.id }
            do { try await api.delete("/journals/\(item.id)") } catch {
                AppLogger.shared.error("Reflect", "Failed to delete journal: \(error)")
                await loadJournals()
            }
        case .voice:
            voiceNotes.removeAll { $0.id == item.id }
            do { try await api.delete("/voice/entries/\(item.id)") } catch {
                AppLogger.shared.error("Reflect", "Failed to delete voice note: \(error)")
                await loadVoiceNotes()
            }
        }
    }
}

// MARK: - Timeline item model

struct ReflectTimelineItem: Identifiable {
    let id: String
    let type: ReflectType
    let title: String?
    let preview: String
    let date: Date
}

enum ReflectNavDestination: Identifiable, Hashable {
    case chat(id: String)
    case journal
    case voice

    var id: String {
        switch self {
        case .chat(let id): return "chat-\(id)"
        case .journal: return "journal"
        case .voice: return "voice"
        }
    }
}

enum ReflectType {
    case conversation, journal, voice

    var icon: String {
        switch self {
        case .conversation: return "bubble.left"
        case .journal: return "doc.text"
        case .voice: return "mic"
        }
    }

    var color: Color {
        switch self {
        case .conversation: return .sacredGold
        case .journal: return .sacredGold
        case .voice: return .sacredGold
        }
    }
}

private struct BeginReflectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onChat: () -> Void
    let onJournal: () -> Void
    let onVoice: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                SacredBackground()
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose the shape this reflection wants.")
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                        .padding(.top, SacredSpacing.s)
                        .padding(.bottom, SacredSpacing.l)

                    SacredListCard {
                        VStack(spacing: 0) {
                            reflectionRow(icon: "doc.text", title: "Write", action: onJournal)
                            Divider().padding(.leading, 56)
                            reflectionRow(icon: "bubble.left", title: "Talk", action: onChat)
                            Divider().padding(.leading, 56)
                            reflectionRow(icon: "mic", title: "Speak", action: onVoice)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Begin Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    private func reflectionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            SacredMenuRow(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - API models

struct ConversationItem: Identifiable, Decodable {
    let id: String
    let title: String
    var lastMessage: String
    var lastUserMessage: String?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, lastMessage, lastUserMessage, updatedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
        let rawMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
        lastMessage = rawMessage.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        lastUserMessage = try c.decodeIfPresent(String.self, forKey: .lastUserMessage)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let dateStr = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else if let dateStr = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else {
            updatedAt = Date()
        }
    }
}

struct JournalItem: Identifiable, Decodable {
    let id: String
    let title: String
    let preview: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, preview, updatedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let dateStr = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else if let dateStr = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else {
            updatedAt = Date()
        }
    }
}

struct VoiceNoteItem: Identifiable, Decodable {
    let id: String
    let status: String
    let hasTranscript: Bool
    let transcriptPreview: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, hasTranscript, transcriptPreview, updatedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "Pending"
        hasTranscript = try c.decodeIfPresent(Bool.self, forKey: .hasTranscript) ?? false
        transcriptPreview = try c.decodeIfPresent(String.self, forKey: .transcriptPreview)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let dateStr = try c.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else if let dateStr = try c.decodeIfPresent(String.self, forKey: .createdAt) {
            updatedAt = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) ?? Date()
        } else {
            updatedAt = Date()
        }
    }
}

struct JournalCreatedResponse: Decodable {
    let id: String
}

struct CreateJournalRequest: Encodable {
    let title: String
    let content: String
}
