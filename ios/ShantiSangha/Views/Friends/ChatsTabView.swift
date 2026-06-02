import SwiftUI

/// Root of the Chats tab. Lists messageable connections sorted by
/// unread first, then last-message recency, then alphabetically — and
/// pushes `FriendChatView` on tap. Circles tab covers everything else
/// about a connection (circles, requests, invites, mandala).
struct ChatsTabView: View {
    @StateObject private var circleVM = CircleViewModel()
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @State private var searchText = ""
    @State private var selectedFilter: ChatsFilter = .all
    @State private var navTarget: ChatsNavRoute?
    @FocusState private var searchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// How often to re-pull the conversation list while it's on screen.
    /// Silent pushes are the fast path, but iOS throttles them too hard
    /// to rely on in the foreground — this keeps row previews and unread
    /// dots live without the user having to leave and come back.
    private static let pollInterval: UInt64 = 15 * 1_000_000_000

    private enum ChatsNavRoute: Hashable {
        case chat(UUID)
        case detail(UUID)
    }

    private enum ChatsFilter: Hashable {
        case all
        case unread

        var label: String {
            switch self {
            case .all: return "All"
            case .unread: return "Unread"
            }
        }

        func includes(_ connection: Connection) -> Bool {
            switch self {
            case .all: return true
            case .unread: return connection.unreadCount > 0
            }
        }
    }

    var body: some View {
        let rows = filteredConversations

        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: SacredSpacing.l) {
                    if circleVM.loading && circleVM.connections.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, SacredSpacing.xl * 2)
                    } else if messageableConnections.isEmpty && circleVM.errorMessage != nil {
                        loadFailureState
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else if messageableConnections.isEmpty {
                        emptyState
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else {
                        chatControls
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.m)

                        chatList(rows: rows)
                    }

                    if let err = circleVM.errorMessage, !messageableConnections.isEmpty {
                        Text(err)
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SacredSpacing.m)
                    }
                }
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task {
            await circleVM.refresh()
            resolvePendingChat()
            // Keep the list live while it's visible. `.task` is cancelled
            // automatically on disappear, which ends this loop; switching
            // tabs or pushing a chat both tear it down and the re-appear
            // restarts it with a fresh pull.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                if Task.isCancelled { break }
                await circleVM.refresh()
            }
        }
        .refreshable { await circleVM.refresh() }
        // Returning from the background doesn't re-fire `.task`, so pull
        // once on reactivation to catch anything that arrived while away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await circleVM.refresh() }
            }
        }
        // Two triggers because the routing intent and the connection
        // list arrive in either order — same dual-listener pattern as
        // FriendsTabView used before chats split off.
        .onChange(of: deepLinks.pendingChatFriendshipId) { _, _ in resolvePendingChat() }
        .onChange(of: circleVM.connections) { _, _ in resolvePendingChat() }
        .navigationDestination(item: $navTarget) { route in
            switch route {
            case .chat(let id):
                if let conn = circleVM.connections.first(where: { $0.id == id }), conn.messageable {
                    FriendChatView(connection: conn, circleVM: circleVM)
                }
            case .detail(let id):
                ConnectionDetailView(connectionId: id, vm: circleVM)
            }
        }
    }

    // MARK: - Filtering & sorting

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageableConnections: [Connection] {
        circleVM.connections.filter { $0.messageable }
    }

    private var filteredConversations: [Connection] {
        let query = trimmedSearch
        let entries = messageableConnections.compactMap { conn -> ChatDirectoryEntry? in
            guard selectedFilter.includes(conn) else { return nil }
            guard query.isEmpty || conn.matchesChatSearch(query) else { return nil }
            return ChatDirectoryEntry(
                connection: conn,
                lastMessageDate: FriendsDates.parse(conn.lastMessageAt))
        }
        return entries
            .sorted(by: sortEntries)
            .map(\.connection)
    }

    private func sortEntries(_ lhs: ChatDirectoryEntry, _ rhs: ChatDirectoryEntry) -> Bool {
        if lhs.connection.unreadCount != rhs.connection.unreadCount {
            return lhs.connection.unreadCount > rhs.connection.unreadCount
        }
        switch (lhs.lastMessageDate, rhs.lastMessageDate) {
        case let (l?, r?) where l != r:
            return l > r
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            let cmp = lhs.connection.displayLabel
                .localizedCaseInsensitiveCompare(rhs.connection.displayLabel)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.connection.id.uuidString < rhs.connection.id.uuidString
        }
    }

    // MARK: - Controls

    private var chatControls: some View {
        VStack(spacing: SacredSpacing.s) {
            searchField
            filterChips
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            TextField("Search your chats", text: $searchText)
                .focused($searchFocused)
                .font(.sacredSmall)
                .foregroundColor(.sacredText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .padding(6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, searchText.isEmpty ? 14 : 4)
        .frame(minHeight: 38)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.12)))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                ForEach([ChatsFilter.all, .unread], id: \.self) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(filter.label)
                            .font(.sacredMicroBold)
                            .foregroundColor(selectedFilter == filter ? .white : .sacredTextSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter
                                          ? Color.sacredGold
                                          : Color.sacredBgCard.opacity(0.72))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.sacredGold.opacity(selectedFilter == filter ? 0 : 0.14),
                                            lineWidth: 1)
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func chatList(rows: [Connection]) -> some View {
        VStack(spacing: SacredSpacing.s) {
            if !rows.isEmpty {
                SacredListCard {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { conn in
                            ChatRow(
                                connection: conn,
                                onTapAvatar: { navTarget = .detail(conn.id) },
                                onTapBody: { navTarget = .chat(conn.id) })

                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
            } else {
                noMatchesState
            }

            findOnAppPrompt
        }
        .padding(.horizontal, SacredSpacing.m)
    }

    private var noMatchesState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "magnifyingglass",
                title: "No chats match.",
                subtitle: "Try another filter or clear your search.")
        }
    }

    @ViewBuilder
    private var findOnAppPrompt: some View {
        let query = trimmedSearch
        if !query.isEmpty {
            NavigationLink(destination: UserSearchView(initialQuery: query)) {
                HStack(spacing: SacredSpacing.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredGold)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.sacredGold.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find on ShantiSangha")
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                        Text("Search the app for \u{201C}\(query)\u{201D}")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.sacredMuted.opacity(0.6))
                }
                .padding(SacredSpacing.m)
                .luxCardChrome()
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: SacredSpacing.s) {
            SacredCard {
                SacredEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "No conversations yet.",
                    subtitle: "Find someone you trust to start a quiet thread.")
            }

            NavigationLink(destination: UserSearchView()) {
                Text("Find someone on ShantiSangha")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredGold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadFailureState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "wifi.slash",
                title: "Couldn't load your chats.",
                subtitle: circleVM.errorMessage ?? "Pull to refresh, or check your connection.",
                actionLabel: "Try again"
            ) {
                Task { await circleVM.refresh() }
            }
        }
    }

    // MARK: - Deep link

    /// Resolves a "new message" notification tap into a chat push.
    /// No-ops until the matching Connection is in `circleVM.connections`
    /// — the `.onChange(of: circleVM.connections)` retry covers the
    /// cold-launch case where connections load after the tap fires.
    private func resolvePendingChat() {
        guard let friendshipId = deepLinks.pendingChatFriendshipId else { return }
        guard let conn = circleVM.connections.first(where: { $0.friendshipId == friendshipId }),
              conn.messageable else {
            return
        }
        deepLinks.clearChat()
        navTarget = .chat(conn.id)
    }
}

private struct ChatDirectoryEntry {
    let connection: Connection
    let lastMessageDate: Date?
}

private struct ChatRow: View {
    let connection: Connection
    let onTapAvatar: () -> Void
    let onTapBody: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onTapAvatar) {
                SacredAvatar(
                    displayName: connection.displayLabel,
                    avatarUrl: connection.ownerVisibleAvatarUrl,
                    size: 40)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button(action: onTapBody) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.displayLabel)
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        subtitleLine
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 6) {
                        if let timestamp = formattedTimestamp {
                            Text(timestamp)
                                .font(.sacredMicro)
                                .foregroundColor(hasUnread ? .sacredGold : .sacredMuted)
                                .lineLimit(1)
                        }
                        if hasUnread {
                            Circle()
                                .fill(Color.sacredGold)
                                .frame(width: 8, height: 8)
                                .accessibilityLabel("\(connection.unreadCount) unread")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasUnread: Bool {
        connection.unreadCount > 0
    }

    private var formattedTimestamp: String? {
        guard let date = FriendsDates.parse(connection.lastMessageAt) else { return nil }
        return Self.relativeLabel(for: date, now: Date())
    }

    /// iMessage-style relative timestamp:
    /// - today → "8:51 PM"
    /// - yesterday → "Yesterday"
    /// - within the last 6 days → short weekday ("Mon")
    /// - same calendar year → "MMM d"
    /// - older → "M/d/yy"
    static func relativeLabel(for date: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: date),
            to: cal.startOfDay(for: now)
        ).day ?? 0
        if days < 7 { return weekdayFormatter.string(from: date) }
        return cal.component(.year, from: date) == cal.component(.year, from: now)
            ? monthDayFormatter.string(from: date)
            : shortDateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()

    private static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df
    }()

    private static let monthDayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df
    }()

    private static let shortDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "M/d/yy"
        return df
    }()

    @ViewBuilder
    private var subtitleLine: some View {
        if let imageUrl = connection.lastMessageImageUrl, !imageUrl.isEmpty {
            // Last message was a photo — the thumbnail itself is the
            // preview (iMessage pattern), so no redundant "Photo" label.
            // Keep it as an accessibility label for VoiceOver.
            MessageThumbnail(urlString: imageUrl, size: 32)
                .accessibilityLabel("Photo")
        } else if let preview = connection.lastMessagePreview, !preview.isEmpty {
            Text(preview)
                .font(hasUnread ? .sacredSmallSemibold : .sacredSmall)
                .foregroundColor(hasUnread ? .sacredText : .sacredTextSecondary)
                .lineLimit(2)
        } else {
            Text("Say hello.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMutedLight)
        }
    }
}

/// Small rounded thumbnail of the chat list's last photo. Loads through
/// the shared presigned-image cache (same one avatars use), which strips
/// the rotating query params so a refreshed URL reuses the cached file.
private struct MessageThumbnail: View {
    let urlString: String
    let size: CGFloat
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.sacredBgCard)
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.sacredGold.opacity(0.15), lineWidth: 0.5))
            .task(id: urlString) {
                guard let url = URL(string: urlString) else { return }
                image = await AvatarImageCache.shared.image(for: url)
            }
    }
}

private extension Connection {
    func matchesChatSearch(_ query: String) -> Bool {
        let candidates: [String?] = [displayLabel, lastMessagePreview]
        return candidates
            .compactMap { $0 }
            .contains { value in
                value.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
    }
}
