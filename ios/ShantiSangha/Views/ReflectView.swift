import SwiftUI

/// Reflect hub — conversations with AI spiritual companion
struct ReflectView: View {
    @State private var conversations: [ConversationItem] = []
    @State private var loading = true
    @State private var navigateToChat = false
    @State private var newConversationId: String?
    private let api = ApiService.shared

    /// Group conversations by time period
    private var groupedConversations: [(String, [ConversationItem])] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [ConversationItem]] = [:]
        var order: [String] = []

        for conv in conversations {
            let label = timePeriodLabel(for: conv.updatedAt, now: now, calendar: calendar)
            if groups[label] == nil {
                order.append(label)
            }
            groups[label, default: []].append(conv)
        }

        return order.map { ($0, groups[$0]!) }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if conversations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.sacredHero)
                                .foregroundColor(.sacredMutedLight)
                            Text("No conversations yet.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                            Text("Tap the chat button to begin a reflection.")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(groupedConversations, id: \.0) { group in
                            let (label, items) = group

                            // Section header
                            Text(label)
                                .font(.sacredTitle)
                                .foregroundColor(.sacredText)
                                .padding(.top, 24)
                                .padding(.bottom, 12)

                            // Conversation cards in a single card container
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, conv in
                                    NavigationLink(destination: ChatView(conversationId: conv.id, title: conv.title)) {
                                        conversationRow(conv, section: label)
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task { await deleteConversation(conv.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                    if index < items.count - 1 {
                                        Divider()
                                            .padding(.leading, 16)
                                    }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.1)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable { await loadConversations() }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadConversations() }

            // Floating chat button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await startChat() }
            } label: {
                Image(systemName: "bubble.left.fill")
                    .font(.sacredHeading)
                    .foregroundColor(.sacredGold)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.sacredGold.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .background(
            NavigationLink(
                destination: newConversationId.map { id in
                    ChatView(conversationId: id, title: "New Conversation")
                },
                isActive: $navigateToChat
            ) {
                EmptyView()
            }
            .hidden()
        )
    }

    // MARK: - Conversation row

    private func conversationRow(_ conv: ConversationItem, section: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatDateTime(conv.updatedAt, in: section))
                .font(.sacredTextSemibold)
                .foregroundColor(.sacredText)

            if !conv.lastMessage.isEmpty {
                Text(conv.lastMessage.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
                    .lineLimit(2)
            }
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

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
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

    private func loadConversations() async {
        do {
            let all: [ConversationItem] = try await api.get("/conversations")
            conversations = all.filter { !$0.lastMessage.isEmpty }
        } catch {
            AppLogger.shared.error("Reflect", "Failed to load conversations: \(error)")
        }
        loading = false
    }

    private func startChat() async {
        do {
            let conv: ConversationItem = try await api.post("/conversations", body: ["title": "New Conversation"])
            newConversationId = conv.id
            navigateToChat = true
        } catch {
            AppLogger.shared.error("Reflect", "Failed to create conversation: \(error)")
        }
    }

    private func deleteConversation(_ id: String) async {
        conversations.removeAll { $0.id == id }
        do {
            try await api.delete("/conversations/\(id)")
        } catch {
            AppLogger.shared.error("Reflect", "Failed to delete conversation: \(error)")
            await loadConversations()
        }
    }
}

// MARK: - Model

struct ConversationItem: Identifiable, Decodable {
    let id: String
    let title: String
    var lastMessage: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, lastMessage, updatedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
        let rawMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
        // Trim all whitespace including non-breaking spaces
        lastMessage = rawMessage.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)

        // Parse updatedAt or createdAt
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
