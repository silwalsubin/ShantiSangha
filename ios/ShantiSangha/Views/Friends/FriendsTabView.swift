import SwiftUI

/// Root of the Friends tab. Lists existing friendships, surfaces pending
/// invites, and offers the "invite a friend" flow.
struct FriendsTabView: View {
    @EnvironmentObject private var profile: ProfileService
    /// Pending invites + incoming/outgoing requests still live here.
    /// The main connection list moved to `circleVM`.
    @StateObject private var vm = FriendsViewModel()
    @StateObject private var circleVM = CircleViewModel()
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showAddLocal = false
    @State private var navTarget: FriendNavRoute?
    @State private var circleSearchText = ""
    @State private var selectedFilter: CircleFilter = .all
    @State private var solarResetTrigger = UUID()
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
                                circleControls
                                    .padding(.horizontal, SacredSpacing.m)
                                    .padding(.top, SacredSpacing.m)

                                circleDirectory(connections: displayedConnections)
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
        .navigationTitle("Circles")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        // Solar is meant to feel like an immersive sky — hide the main
        // tab bar so the bottom row of solar action buttons can sit
        // where the tab items used to. The "list" button returns the
        // user to list mode, which restores the tab bar. Use
        // `.automatic` (not `.visible`) for the non-solar case so
        // pushed children like FriendChatView and ConnectionDetailView
        // can still set their own `.hidden`.
        .toolbar(
            (viewMode == .solar && !circleVM.connections.isEmpty) ? .hidden : .automatic,
            for: .tabBar)
        .toolbar {
            // List mode → atom toggle (top trailing) to enter solar.
            // Solar mode → back chevron (top leading) to return to list.
            if !circleVM.connections.isEmpty && viewMode == .list {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModeRaw = CircleViewMode.solar.rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "atom")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel("Show solar")
                }
            }

            if viewMode == .solar && !circleVM.connections.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModeRaw = CircleViewMode.list.rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel("Back to list")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        solarResetTrigger = UUID()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel("Reset view")
                }
            }
        }
        .task {
            await vm.refresh()
            await circleVM.refresh()
            resolvePendingChat()
        }
        .refreshable {
            await vm.refresh()
            await circleVM.refresh()
        }
        // Two triggers because the routing intent and the connection
        // list arrive in either order: a warm-launch tap sets the
        // friendship id while connections are already loaded; a
        // cold-launch tap sets it before the first refresh completes.
        .onChange(of: deepLinks.pendingChatFriendshipId) { _, _ in resolvePendingChat() }
        .onChange(of: circleVM.connections) { _, _ in resolvePendingChat() }
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

    // MARK: - Notification deep link

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
                    resetTrigger: solarResetTrigger,
                    onTap: { id in
                        navTarget = .detail(id)
                    })
                    .ignoresSafeArea()
            }

            VStack(spacing: SacredSpacing.s) {
                if hasActiveCircleScope {
                    solarScopePill(shownCount: connections.count, totalCount: totalCount)
                        .padding(.top, SacredSpacing.xs)
                }

                Spacer()

                solarActionRow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, SacredSpacing.m)
            .padding(.bottom, SacredSpacing.m)
        }
    }

    /// Bottom action row in solar mode — invite and add. Returning to
    /// list mode happens via the standard back chevron in the top-leading
    /// toolbar slot.
    private var solarActionRow: some View {
        HStack(spacing: SacredSpacing.s) {
            Spacer()

            SolarActionButton(icon: "paperplane", label: "Invite") {
                Task { await onInvite() }
            }

            SolarActionButton(icon: "plus", label: "Add local") {
                showAddLocal = true
            }

            Spacer()
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)

            TextField("Search your circle", text: $circleSearchText)
                .focused($circleSearchFocused)
                .font(.sacredSmall)
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
                        .padding(6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, circleSearchText.isEmpty ? 14 : 4)
        .frame(minHeight: 38)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.sacredGold.opacity(0.12)))
    }

    /// Static chips first, then the user's circles ranked by usage.
    /// Capped at 6 dynamic chips so the row stays scrollable but doesn't
    /// fan out into a wall of tags for someone with dozens of circles.
    private var availableFilters: [CircleFilter] {
        var filters: [CircleFilter] = [.all, .unread, .onApp, .local]
        let topCircles = circleVM.circleCatalog.prefix(6).map { CircleFilter.circle($0.name) }
        filters.append(contentsOf: topCircles)
        return filters
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                ForEach(availableFilters, id: \.self) { filter in
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
    private func circleDirectory(connections: [Connection]) -> some View {
        VStack(spacing: SacredSpacing.s) {
            if !connections.isEmpty {
                SacredListCard {
                    LazyVStack(spacing: 0) {
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
            } else if trimmedCircleSearch.isEmpty {
                // Filter chip narrowed to nothing — no query to pivot,
                // so the find-on-app row would have nothing to search.
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
                title: "No one matches.",
                subtitle: "Try another filter or clear your search.")
        }
    }

    @ViewBuilder
    private var findOnAppPrompt: some View {
        let query = trimmedCircleSearch
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
                    icon: "person.2",
                    title: "Walking solo for now.",
                    subtitle: "Invite someone you trust to message inside this private space.",
                    actionLabel: "Invite someone"
                ) { Task { await onInvite() } }
            }

            // Secondary discovery affordance — without the Find tile,
            // first-time users with an empty circle would have no path
            // to the app-wide search.
            NavigationLink(destination: UserSearchView()) {
                Text("Or find someone on ShantiSangha")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredGold)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
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

/// Circle directory filter chips. The four `static` cases are always
/// present; `.circle(name)` cases are auto-derived per session from the
/// user's actual circle tags so the chip row reflects how *they*
/// organize their people, not a hardcoded taxonomy.
private enum CircleFilter: Hashable {
    case all
    case unread
    case onApp
    case local
    case circle(String)

    var label: String {
        switch self {
        case .all: return "All"
        case .unread: return "Unread"
        case .onApp: return "On app"
        case .local: return "Local"
        case .circle(let name): return name
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
        case .circle(let name):
            return connection.circles.contains {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
        }
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
        connection.messageable && connection.unreadCount > 0
    }

    private var formattedTimestamp: String? {
        guard let date = FriendsDates.parse(connection.lastMessageAt) else { return nil }
        return ConnectionRow.relativeLabel(for: date, now: Date())
    }

    /// iMessage-style relative timestamp:
    /// - today → "8:51 PM"
    /// - yesterday → "Yesterday"
    /// - within the last 6 days → short weekday ("Mon")
    /// - same calendar year → "MMM d"
    /// - older → "M/d/yy"
    static func relativeLabel(for date: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: date),
            to: cal.startOfDay(for: now)
        ).day ?? 0
        if days < 7 {
            return weekdayFormatter.string(from: date)
        }
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
        if connection.messageable, let preview = connection.lastMessagePreview {
            Text(preview)
                .font(hasUnread ? .sacredSmallSemibold : .sacredSmall)
                .foregroundColor(hasUnread ? .sacredText : .sacredTextSecondary)
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
    func matchesCircleSearch(_ query: String) -> Bool {
        let searchableStrings: [String?] = [
            displayLabel,
            circles.joined(separator: " "),
            person.locationString,
            person.city,
            person.state,
            person.country
        ]
        return searchableStrings
            .compactMap { $0 }
            .contains { value in
                value.range(
                    of: query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
    }
}


private struct SolarActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.sacredBgCard.opacity(0.7))
                        .overlay(
                            Circle().fill(
                                LinearGradient(
                                    colors: [
                                        Color.sacredGoldShine.opacity(0.1),
                                        Color.clear,
                                        Color.sacredGoldDark.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                        )
                )
                .overlay(Circle().stroke(Color.sacredGold.opacity(0.18), lineWidth: 1))
                .sacredCardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
