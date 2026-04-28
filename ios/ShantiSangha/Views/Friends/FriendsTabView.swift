import SwiftUI

/// Root of the Friends tab. Lists existing friendships, surfaces pending
/// invites, and offers the "invite a friend" flow.
struct FriendsTabView: View {
    @EnvironmentObject private var profile: ProfileService
    /// Pending invites + incoming/outgoing requests still live here.
    /// The main connection list moved to `circleVM`.
    @StateObject private var vm = FriendsViewModel()
    @StateObject private var circleVM = CircleViewModel()
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showAddLocal = false
    @State private var navTarget: FriendNavRoute?
    @State private var circleSearchText = ""
    @State private var selectedFilter: CircleFilter = .all
    @FocusState private var circleSearchFocused: Bool
    /// String-backed because @AppStorage with custom enums needs a
    /// `RawRepresentable<String>` plus default-handling boilerplate;
    /// a tiny string compare is cheaper to read at the call site.
    @AppStorage("circle_view_mode") private var viewModeRaw: String = CircleViewMode.list.rawValue

    private var viewMode: CircleViewMode {
        if let mode = CircleViewMode(rawValue: viewModeRaw) { return mode }
        // Migrate the previous mandala raw value to its successor so
        // anyone who had the visualization mode picked doesn't drop
        // back to the list on upgrade.
        if viewModeRaw == "mandala" { return .solar }
        return .list
    }

    /// Programmatic navigation target — both the row body and the avatar
    /// are tappable but route to different destinations, so we need a
    /// single source of truth that `.navigationDestination(item:)` can
    /// drive instead of stacking two NavigationLinks per row.
    enum FriendNavRoute: Hashable {
        case chat(UUID)        // connection id
        case detail(UUID)      // connection id
    }

    enum CircleViewMode: String {
        case list, solar
    }

    var body: some View {
        let displayedConnections = filteredConnections

        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            // Solar with at least one connection goes full-bleed —
            // the SpriteView fills the viewport edge-to-edge, scope
            // pill overlays at the top, requests/invites are reachable
            // by toggling back to list. Everything else (loading,
            // empty, error, list mode, list-mode-with-no-connections)
            // routes through the existing scroll view.
            if viewMode == .solar && !circleVM.connections.isEmpty {
                fullBleedSolar(
                    connections: displayedConnections,
                    totalCount: circleVM.connections.count)
            } else {
                ScrollView {
                    LazyVStack(spacing: SacredSpacing.l) {
                        if (circleVM.loading || vm.loading) && circleVM.connections.isEmpty
                            && vm.pendingInvitations.isEmpty
                            && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty {
                            // LazyVStack shrinks to its sole child's
                            // intrinsic width when nothing else
                            // stretches it — without the explicit
                            // max-width the spinner ends up pinned to
                            // the leading edge instead of centered.
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, SacredSpacing.xl * 2)
                        } else if circleVM.connections.isEmpty && vm.pendingInvitations.isEmpty
                                    && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty
                                    && (circleVM.errorMessage != nil || vm.errorMessage != nil) {
                            // Refresh failed and we have nothing to
                            // show. Tell the user the truth instead of
                            // "Walking solo for now" — that lie made a
                            // transient API/auth failure look like an
                            // empty circle.
                            loadFailureState
                                .padding(.horizontal, SacredSpacing.m)
                                .padding(.top, SacredSpacing.xl)
                        } else if circleVM.connections.isEmpty && vm.pendingInvitations.isEmpty
                                    && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty {
                            emptyState
                                .padding(.horizontal, SacredSpacing.m)
                                .padding(.top, SacredSpacing.xl)
                        } else {
                            if !circleVM.connections.isEmpty {
                                // Solar branch handled above; this
                                // path is list-only when reached.
                                circleOverview(connections: circleVM.connections)
                                    .padding(.horizontal, SacredSpacing.m)
                                    .padding(.top, SacredSpacing.m)

                                circleActions
                                    .padding(.horizontal, SacredSpacing.m)

                                circleControls
                                    .padding(.horizontal, SacredSpacing.m)

                                circleDirectory(connections: displayedConnections)
                            } else {
                                circleActions
                                    .padding(.horizontal, SacredSpacing.m)
                                    .padding(.top, SacredSpacing.m)
                            }

                            if !vm.incomingRequests.isEmpty {
                                SacredCard("REQUESTS RECEIVED") {
                                    VStack(spacing: SacredSpacing.s) {
                                        ForEach(vm.incomingRequests) { req in
                                            IncomingRequestRow(
                                                request: req,
                                                onAccept: { Task { await vm.acceptIncomingRequest(req.id) } },
                                                onDecline: { Task { await vm.declineIncomingRequest(req.id) } })
                                        }
                                    }
                                }
                                .padding(.horizontal, SacredSpacing.m)
                            }

                            if !vm.outgoingRequests.isEmpty {
                                SacredCard("AWAITING REPLY") {
                                    VStack(spacing: SacredSpacing.s) {
                                        ForEach(vm.outgoingRequests) { req in
                                            OutgoingRequestRow(
                                                request: req,
                                                onCancel: { Task { await vm.cancelOutgoingRequest(req.id) } })
                                        }
                                    }
                                }
                                .padding(.horizontal, SacredSpacing.m)
                            }

                            if !vm.pendingInvitations.isEmpty {
                                SacredCard("PENDING INVITES") {
                                    VStack(spacing: SacredSpacing.s) {
                                        ForEach(vm.pendingInvitations) { invite in
                                            PendingInviteRow(
                                                invite: invite,
                                                onShare: { share(invite) },
                                                onRevoke: { Task { await vm.revoke(invite.invitationId) } })
                                        }
                                    }
                                }
                                .padding(.horizontal, SacredSpacing.m)
                            }
                        }

                        if let err = inlineErrorMessage, !shouldHideError {
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
        }
        .navigationTitle("Circle")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // Only surface the toggle once there's actually a circle
            // to render — toggling between two empty states is noise.
            if !circleVM.connections.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModeRaw = (viewMode == .list ? CircleViewMode.solar : .list).rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: viewMode == .list
                              ? "atom"
                              : "list.bullet")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel(viewMode == .list ? "Show solar" : "Show list")
                }
            }
        }
        .task {
            await vm.refresh()
            await circleVM.refresh()
        }
        .refreshable {
            await vm.refresh()
            await circleVM.refresh()
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showAddLocal) {
            AddConnectionView(vm: circleVM)
        }
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

    // MARK: - Circle directory

    private var trimmedCircleSearch: String {
        circleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredConnections: [Connection] {
        let query = trimmedCircleSearch
        let entries = circleVM.connections.compactMap { conn -> CircleDirectoryEntry? in
            guard selectedFilter.includes(conn) else { return nil }
            guard query.isEmpty || conn.matchesCircleSearch(query) else { return nil }
            return CircleDirectoryEntry(
                connection: conn,
                lastMessageDate: FriendsDates.parse(conn.lastMessageAt))
        }

        return entries
            .sorted(by: sortDirectoryEntries)
            .map(\.connection)
    }

    private func sortDirectoryEntries(_ lhs: CircleDirectoryEntry, _ rhs: CircleDirectoryEntry) -> Bool {
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
            let nameCompare = lhs.connection.displayLabel
                .localizedCaseInsensitiveCompare(rhs.connection.displayLabel)
            if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
            return lhs.connection.id.uuidString < rhs.connection.id.uuidString
        }
    }

    private var directoryTitle: String {
        trimmedCircleSearch.isEmpty ? selectedFilter.sectionTitle : "MATCHES"
    }

    private var circleControls: some View {
        VStack(spacing: SacredSpacing.s) {
            circleSearchField
            filterChips
        }
    }

    /// Solar mode, full-bleed: SpriteView fills the entire viewport
    /// (ignoring safe areas top + bottom so the cosmic feel runs into
    /// nav and tab bars), with the scope pill floating on top when
    /// the user has narrowed the circle by filter or search.
    @ViewBuilder
    private func fullBleedSolar(connections: [Connection], totalCount: Int) -> some View {
        ZStack(alignment: .top) {
            if connections.isEmpty {
                // Filter active but nothing matches.
                VStack {
                    Spacer()
                    noMatchesState
                        .padding(.horizontal, SacredSpacing.m)
                    Spacer()
                }
            } else {
                CircleSpriteSystemView(
                    connections: connections,
                    myAvatarUrl: profile.profile?.avatarUrl,
                    myDisplayName: profile.profile?.displayName,
                    onTap: { id in
                        if let conn = circleVM.connections.first(where: { $0.id == id }) {
                            navTarget = conn.messageable ? .chat(id) : .detail(id)
                        } else {
                            navTarget = .detail(id)
                        }
                    })
                    .ignoresSafeArea()
            }

            if hasActiveCircleScope {
                solarScopePill(shownCount: connections.count, totalCount: totalCount)
                    .padding(.horizontal, SacredSpacing.m)
                    .padding(.top, SacredSpacing.xs)
            }
        }
    }

    private var hasActiveCircleScope: Bool {
        selectedFilter != .all || !trimmedCircleSearch.isEmpty
    }

    private var solarScopeLabel: String {
        var parts: [String] = []
        if selectedFilter != .all { parts.append(selectedFilter.label) }
        if !trimmedCircleSearch.isEmpty { parts.append(trimmedCircleSearch) }
        return parts.joined(separator: " · ")
    }

    private func solarScopePill(shownCount: Int, totalCount: Int) -> some View {
        HStack(spacing: SacredSpacing.s) {
            Text("\(shownCount.formatted()) of \(totalCount.formatted()) shown")
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(solarScopeLabel)
                .font(.sacredMicroBold)
                .foregroundColor(.sacredGold)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: SacredSpacing.xs)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedFilter = .all
                    circleSearchText = ""
                    circleSearchFocused = false
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("Clear")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredGold)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minHeight: 48)
        .background(Capsule().fill(Color.sacredBgCard.opacity(0.72)))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.12), lineWidth: 1))
    }

    private var circleSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            TextField("Search your circle", text: $circleSearchText)
                .focused($circleSearchFocused)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)

            if !circleSearchText.isEmpty {
                Button {
                    circleSearchText = ""
                    circleSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, circleSearchText.isEmpty ? 14 : 2)
        .frame(minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sacredGold.opacity(0.12)))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                ForEach(CircleFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(filter.label)
                            .font(.sacredSmallSemibold)
                            .foregroundColor(selectedFilter == filter ? .white : .sacredTextSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func circleDirectory(connections: [Connection]) -> some View {
        if connections.isEmpty {
            noMatchesState
                .padding(.horizontal, SacredSpacing.m)
        } else {
            SacredListCard {
                LazyVStack(spacing: 0) {
                    CircleDirectoryHeader(title: directoryTitle, count: connections.count)

                    ForEach(connections) { conn in
                        ConnectionRow(
                            connection: conn,
                            onTapAvatar: { navTarget = .detail(conn.id) },
                            onTapBody: {
                                navTarget = conn.messageable
                                    ? .chat(conn.id)
                                    : .detail(conn.id)
                            })

                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .padding(.horizontal, SacredSpacing.m)
        }
    }

    private var noMatchesState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "magnifyingglass",
                title: "No one matches.",
                subtitle: "Try another name, relation, or place.")
        }
    }

    // MARK: - Top summary and actions

    private func circleOverview(connections: [Connection]) -> some View {
        CircleOverviewCard(connections: connections)
    }

    private var circleActions: some View {
        HStack(spacing: SacredSpacing.s) {
            NavigationLink(destination: UserSearchView()) {
                CircleActionTile(icon: "magnifyingglass", title: "Find")
            }
            .buttonStyle(.plain)

            Button {
                Task { await onInvite() }
            } label: {
                CircleActionTile(icon: "paperplane", title: "Invite")
            }
            .buttonStyle(.plain)

            Button {
                showAddLocal = true
            } label: {
                CircleActionTile(icon: "plus", title: "Add local")
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "person.2",
                title: "Walking solo for now.",
                subtitle: "Invite someone you trust to message inside this private space.",
                actionLabel: "Invite someone"
            ) { Task { await onInvite() } }
        }
    }

    /// Shown when refresh failed and there's nothing in the lists. The
    /// emptyState would otherwise lie that the user has no circle.
    private var loadFailureState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "wifi.slash",
                title: "Couldn't load your circle.",
                subtitle: inlineErrorMessage ?? "Pull to refresh, or check your connection.",
                actionLabel: "Try again"
            ) {
                Task {
                    await vm.refresh()
                    await circleVM.refresh()
                }
            }
        }
    }

    /// Hide a one-off decode/network error when we have nothing to show — the
    /// empty state is the message at that point. Surface errors only when the
    /// user is mid-action or has loaded data and a follow-up call failed.
    private var shouldHideError: Bool {
        circleVM.connections.isEmpty && vm.pendingInvitations.isEmpty
            && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty
    }

    private var inlineErrorMessage: String? {
        circleVM.errorMessage ?? vm.errorMessage
    }

    private func onInvite() async {
        // The root-level required-data gate (`DisplayNameGate`) guarantees the
        // user has set a display name before reaching the Friends tab — the
        // legacy `display_name_required` fallback path is no longer reachable.
        guard let invite = await vm.createInvitation() else { return }
        share(.init(invite))
    }

    private func share(_ link: ShareLink) {
        let url = URL(string: link.url) ?? URL(string: "https://shantisangha.com")!
        let body = "I'm using ShantiSangha. Join me here: \(link.url)"
        shareItems = [body, url]
        showShare = true
    }

    private func share(_ invite: PendingInvitation) {
        share(.init(invite))
    }
}

private struct ShareLink {
    let url: String
    init(_ invite: CreateInvitationResponse) { self.url = invite.shareUrl }
    init(_ invite: PendingInvitation) { self.url = invite.shareUrl }
}

private struct CircleDirectoryEntry {
    let connection: Connection
    let lastMessageDate: Date?
}

private enum CircleFilter: String, CaseIterable, Identifiable {
    case all
    case unread
    case onApp
    case local
    case family
    case close
    case broader

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .onApp: return "On app"
        case .local: return "Local"
        case .family: return "Family"
        case .close: return "Close"
        case .broader: return "Broader"
        }
    }

    var sectionTitle: String {
        switch self {
        case .all: return "ALL CONNECTIONS"
        case .unread: return "UNREAD"
        case .onApp: return "ON THE APP"
        case .local: return "LOCAL"
        case .family: return "FAMILY"
        case .close: return "CLOSE"
        case .broader: return "BROADER"
        }
    }

    func includes(_ connection: Connection) -> Bool {
        switch self {
        case .all:
            return true
        case .unread:
            return connection.unreadCount > 0
        case .onApp:
            return connection.messageable
        case .local:
            return connection.person.userId == nil
        case .family:
            return [.spouse, .parent, .child].contains(connection.parsedRelationType)
        case .close:
            return [.sibling, .friend].contains(connection.parsedRelationType)
        case .broader:
            return [.colleague, .other].contains(connection.parsedRelationType)
        }
    }
}

private struct CircleOverviewCard: View {
    let connections: [Connection]

    private var totalCount: Int { connections.count }
    private var messageableCount: Int { connections.filter { $0.messageable }.count }
    private var localCount: Int { connections.filter { $0.person.userId == nil }.count }
    private var unreadMessageCount: Int { connections.reduce(0) { $0 + $1.unreadCount } }

    private var recentCount: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return connections.filter { conn in
            guard let date = FriendsDates.parse(conn.lastMessageAt) else { return false }
            return date >= cutoff
        }.count
    }

    private var summaryText: String {
        var parts: [String] = []
        if messageableCount > 0 { parts.append("\(messageableCount.formatted()) on the app") }
        if localCount > 0 { parts.append("\(localCount.formatted()) local") }
        if recentCount > 0 { parts.append("\(recentCount.formatted()) active this week") }
        return parts.isEmpty ? "Private connections you choose." : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            CircleAvatarCluster(connections: connections)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(totalCount.formatted()) in your circle")
                    .font(.sacredTitle)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(summaryText)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if unreadMessageCount > 0 {
                VStack(spacing: 1) {
                    Text(unreadMessageCount.formatted())
                        .font(.sacredBodyBold)
                    Text("unread")
                        .font(.sacredMicro)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.sacredGold))
                .accessibilityLabel("\(unreadMessageCount) unread messages")
            }
        }
        .padding(SacredSpacing.m)
        .luxCardChrome()
    }
}

private struct CircleAvatarCluster: View {
    let connections: [Connection]

    private var visibleConnections: [Connection] {
        Array(connections.prefix(4))
    }

    private var remainingCount: Int {
        max(0, connections.count - visibleConnections.count)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(visibleConnections.enumerated()), id: \.element.id) { index, conn in
                SacredAvatar(
                    displayName: conn.displayLabel,
                    avatarUrl: conn.person.avatarUrl,
                    size: 34)
                    .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                    .offset(x: CGFloat(index) * 18)
                    .zIndex(Double(visibleConnections.count - index))
            }

            if remainingCount > 0 {
                ZStack {
                    Circle()
                        .fill(Color.sacredGold)
                    Text("+\(remainingCount.formatted())")
                        .font(.sacredMicroBold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 2)
                }
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                .offset(x: CGFloat(visibleConnections.count) * 18)
            }
        }
        .frame(width: 112, height: 44, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct CircleActionTile: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
            Text(title)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 64)
        .contentShape(RoundedRectangle(cornerRadius: SacredRadius.card))
        .luxCardChrome()
    }
}

private struct CircleDirectoryHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            Spacer()
            Text(count.formatted())
                .font(.sacredMicroBold)
                .foregroundColor(.sacredGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().stroke(Color.sacredGold.opacity(0.18), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

private struct ConnectionRow: View {
    let connection: Connection
    let onTapAvatar: () -> Void
    let onTapBody: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar gets its own tap target → profile. Body tap
            // (name + preview) → chat (when paired) or profile
            // (when local). Both funnel through the parent's
            // nav-target state.
            Button(action: onTapAvatar) {
                SacredAvatar(
                    displayName: connection.displayLabel,
                    avatarUrl: connection.person.avatarUrl,
                    size: 40)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button(action: onTapBody) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(connection.displayLabel)
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        relationChip
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        if connection.messageable && connection.unreadCount > 0 {
                            Text("\(connection.unreadCount)")
                                .font(.sacredMicroBold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.sacredGold))
                        }
                    }
                    subtitleLine
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

    private var relationChip: some View {
        Text(connection.relationLabel)
            .font(.sacredMicroBold)
            .foregroundColor(.sacredGold.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().stroke(Color.sacredGold.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder
    private var subtitleLine: some View {
        if connection.messageable, let preview = connection.lastMessagePreview {
            Text(preview)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
                .lineLimit(2)
        } else if let location = connection.person.locationString {
            Text(location)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .lineLimit(1)
        } else if connection.messageable {
            Text("Say hello.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMutedLight)
        } else {
            Text("Local — they'll be messageable when they join.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .lineLimit(2)
        }
    }
}

private struct PendingInviteRow: View {
    let invite: PendingInvitation
    let onShare: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            Image(systemName: "envelope")
                .foregroundColor(.sacredGold.opacity(0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting to be accepted")
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                Text(expiresIn)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            Spacer()
            Button("Share") { onShare() }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
            Button("Revoke") { onRevoke() }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredRed)
        }
        .padding(.vertical, 4)
    }

    private var expiresIn: String {
        guard let expires = FriendsDates.parse(invite.expiresAt) else { return "Expires soon" }
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0)
        if days <= 0 { return "Expires today" }
        if days == 1 { return "Expires tomorrow" }
        return "Expires in \(days) days"
    }
}


private struct IncomingRequestRow: View {
    let request: FriendRequestSummary
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: request.otherUserDisplayName,
                avatarUrl: request.otherUserAvatarUrl,
                size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.otherUserDisplayName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                Text("Wants to connect")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            Spacer()
            Button("Decline") { onDecline() }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredMuted)
            Button("Accept") { onAccept() }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
        }
        .padding(.vertical, 4)
    }
}

private struct OutgoingRequestRow: View {
    let request: FriendRequestSummary
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: request.otherUserDisplayName,
                avatarUrl: request.otherUserAvatarUrl,
                size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.otherUserDisplayName)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                Text(sentAgo)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            Spacer()
            Button("Cancel") { onCancel() }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredRed)
        }
        .padding(.vertical, 4)
    }

    private var sentAgo: String {
        guard let sent = FriendsDates.parse(request.createdAt) else { return "Sent" }
        let days = Calendar.current.dateComponents([.day], from: sent, to: Date()).day ?? 0
        if days <= 0 { return "Sent today" }
        if days == 1 { return "Sent yesterday" }
        return "Sent \(days) days ago"
    }
}

private extension Connection {
    var parsedRelationType: ConnectionType {
        ConnectionType(rawValue: relationType.lowercased()) ?? .other
    }

    func matchesCircleSearch(_ query: String) -> Bool {
        [
            displayLabel,
            relationLabel,
            person.locationString,
            person.city,
            person.state,
            person.country
        ]
        .compactMap { $0 }
        .contains { value in
            value.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}


/// UIKit share sheet bridge — uses the system's `UIActivityViewController`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
