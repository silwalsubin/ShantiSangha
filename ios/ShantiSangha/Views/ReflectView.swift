import SwiftUI

/// Reflect hub — conversations, journals, voice. Mirrors frontend reflect/index.vue
struct ReflectView: View {
    @State private var conversations: [ConversationItem] = []
    @State private var loading = true
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // New conversation button
                Button {
                    Task { await startNewConversation() }
                } label: {
                    HStack {
                        Image(systemName: "plus.bubble")
                            .font(.sacredIcon)
                        Text("New Conversation")
                            .font(.sacredTextSemibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.sacredGoldShiny)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shimmer()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

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
                        Text("Start a reflection to begin your journey.")
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
                    }
                }
            }
            .padding(16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .refreshable { await loadConversations() }
        .navigationTitle("Reflect")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadConversations() }
    }

    private func loadConversations() async {
        do {
            conversations = try await api.get("/conversations")
        } catch {
            print("Failed to load conversations: \(error)")
        }
        loading = false
    }

    private func startNewConversation() async {
        do {
            let conv: ConversationItem = try await api.post("/conversations", body: ["title": "New Conversation"])
            conversations.insert(conv, at: 0)
        } catch {
            print("Failed to create conversation: \(error)")
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
