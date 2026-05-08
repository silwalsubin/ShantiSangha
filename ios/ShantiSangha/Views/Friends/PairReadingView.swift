import SwiftUI

/// Viewer's private four-section reading of a specific friend, generated
/// server-side from both birth charts plus their cross-chart dynamics.
/// Reached from `ConnectionDetailView` only when the friend has shared
/// their birth chart with the current user. Asymmetric — the friend would
/// see a different reading about the current user from their own POV.
struct PairReadingView: View {
    let subjectUserId: UUID
    let subjectName: String

    @State private var reading: PairChartReadingAPI.Reading?
    @State private var loading = true
    @State private var error: String?
    @State private var expanded: Set<String> = []

    // Pair-chat ("Ask about Name") state. Creating the conversation hits the
    // backend; once we have an id we navigate to the existing ChatView.
    // String id matches ChatView's signature and the existing chart-chat path.
    @State private var pendingChatId: String?
    @State private var startingChat: Bool = false
    @State private var chatError: String?

    /// Section keys + display titles in canonical order. Match the backend's
    /// `PairReadingSection` constants.
    private let sections: [(key: String, title: String)] = [
        ("what_they_bring", "What they bring you"),
        ("where_it_eases", "Where it eases"),
        ("where_it_asks_work", "Where it asks work"),
        ("the_shape", "The shape of this in your life"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: SacredSpacing.l) {
                if loading && reading == nil {
                    loadingCard
                } else if let reading {
                    readingCard(reading)
                } else if let error {
                    errorCard(error)
                }

                if reading != nil {
                    askChatButton
                    if let chatError {
                        Text(chatError)
                            .font(.sacredMicro)
                            .foregroundColor(.sacredRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SacredSpacing.m)
                    }
                }

                Text("This reading is private to you. \(subjectName) is not seeing it.")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.s)
            }
            .padding(.horizontal, SacredSpacing.m)
            .padding(.vertical, SacredSpacing.l)
        }
        .background(SacredBackground().ignoresSafeArea())
        .navigationTitle("\(subjectName) through your chart")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $pendingChatId) { id in
            ChatView(conversationId: id, title: "About \(subjectName)")
        }
    }

    private var askChatButton: some View {
        Button {
            Task { await startPairChat() }
        } label: {
            HStack(spacing: 8) {
                if startingChat {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    Image(systemName: "bubble.left")
                        .font(.sacredText)
                }
                Text(startingChat ? "Opening…" : "Ask about \(subjectName)")
                    .font(.sacredTextMedium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .goldShine()
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(startingChat)
        .padding(.horizontal, SacredSpacing.s)
    }

    private func startPairChat() async {
        guard !startingChat else { return }
        startingChat = true
        defer { startingChat = false }
        do {
            let conv = try await PairChartReadingAPI.startChat(
                subjectUserId: subjectUserId,
                subjectName: subjectName)
            pendingChatId = conv.id
            chatError = nil
        } catch let apiError as ApiError {
            switch apiError {
            case .httpError(statusCode: 403, _):
                chatError = "\(subjectName) hasn't shared their chart with you anymore."
            default:
                chatError = "Couldn't open the chat. Try again."
            }
        } catch {
            chatError = "Couldn't open the chat. Try again."
        }
    }

    // MARK: - States

    private var loadingCard: some View {
        SacredCard("READING") {
            HStack(spacing: 10) {
                ProgressView().tint(.sacredGold)
                Text("Composing this reading from both your charts and the classical sources…")
                    .font(.sacredMicro)
                    .italic()
                    .foregroundColor(.sacredMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        SacredCard("READING") {
            Text(message)
                .font(.sacredMicro)
                .italic()
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readingCard(_ reading: PairChartReadingAPI.Reading) -> some View {
        SacredCard("READING") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sections, id: \.key) { section in
                    if let prose = reading.sections[section.key], !prose.isEmpty {
                        SacredDisclosure(
                            section.title,
                            titleStyle: .body,
                            isExpanded: disclosureBinding($expanded, key: section.key)
                        ) {
                            Text(prose)
                                .font(.sacredSmall)
                                .italic()
                                .foregroundColor(.sacredTextSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            reading = try await PairChartReadingAPI.get(of: subjectUserId)
            error = nil
        } catch let apiError as ApiError {
            switch apiError {
            case .httpError(statusCode: 403, _):
                // The share was revoked between this view's parent rendering
                // and this fetch. Tell the user gently.
                error = "\(subjectName) hasn't shared their chart with you (or just stopped). The reading isn't available."
            case .httpError(statusCode: 422, _):
                error = "\(subjectName) hasn't completed their birth details yet."
            default:
                error = "Couldn't load this reading. Try again in a moment."
            }
        } catch _ {
            error = "Couldn't load this reading. Try again in a moment."
        }
    }
}
