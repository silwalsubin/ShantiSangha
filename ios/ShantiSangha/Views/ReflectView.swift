import SwiftUI

/// Reflect hub — conversations with AI spiritual companion
struct ReflectView: View {
    @State private var conversations: [ConversationItem] = []
    @State private var loading = true
    @State private var navigateToChat = false
    @State private var newConversationId: String?
    private let api = ApiService.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                        Text("RECENT CONVERSATIONS")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)

                        ForEach(conversations) { conv in
                            NavigationLink(destination: ChatView(conversationId: conv.id, title: conv.title)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conv.title)
                                            .font(.sacredTextMedium)
                                            .foregroundColor(.sacredText)
                                            .lineLimit(1)
                                        if !conv.lastMessage.isEmpty {
                                            Text(conv.lastMessage)
                                                .font(.sacredSmall)
                                                .foregroundColor(.sacredTextSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.sacredSmall)
                                        .foregroundColor(.sacredMuted)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.1)))
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await deleteConversation(conv.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 80)
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
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(RadialGradient.sacredGoldShiny)
                    .clipShape(Circle())
                    .shimmer()
                    .clipShape(Circle())
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

    private func loadConversations() async {
        do {
            let all: [ConversationItem] = try await api.get("/conversations")
            // Only show conversations that have messages
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

struct ConversationItem: Codable, Identifiable {
    let id: String
    let title: String
    var lastMessage: String

    enum CodingKeys: String, CodingKey {
        case id, title, lastMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Conversation"
        lastMessage = try c.decodeIfPresent(String.self, forKey: .lastMessage) ?? ""
    }
}
