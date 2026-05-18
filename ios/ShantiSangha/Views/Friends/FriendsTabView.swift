import SwiftUI

/// Root of the Circles tab. Solar/mandala visualization of the user's
/// circle — central sun (the user) with planet orbs (connections).
/// Search + filter chips float at the top of the cosmos; an Invite +
/// Add row sits at the bottom. Pending requests and invites surface
/// via a chip near the top that opens a sheet. Tapping a planet
/// routes to `ConnectionDetailView`; chats live in `ChatsTabView`.
struct FriendsTabView: View {
    @EnvironmentObject private var profile: ProfileService
    /// Pending invites + incoming/outgoing requests still live here.
    /// The main connection list moved to `circleVM`.
    @StateObject private var vm = FriendsViewModel()
    @StateObject private var circleVM = CircleViewModel()
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showAddLocal = false
    @State private var showRequestsSheet = false
    @State private var navTarget: FriendNavRoute?
    @State private var circleSearchText = ""
    @State private var selectedFilter: CircleFilter = .all
    @State private var solarResetTrigger = UUID()
    @FocusState private var circleSearchFocused: Bool

    /// Single nav destination. Chats split off to their own tab in
    /// `ChatsTabView`; this tab is now purely about who is in the
    /// circle, so every tap on a row routes to the detail view.
    enum FriendNavRoute: Hashable {
        case detail(UUID)      // connection id
    }

    /// Cosmos contents for one render — connections to plot plus the
    /// map identifying any synthetic group orbs in that list (used at
    /// tap time to disambiguate group orb from real connection) and
    /// the decorations the cosmos uses to dress group orbs differently.
    struct DisplayedOrbs {
        let connections: [Connection]
        let groupTokens: [UUID: GroupTarget]
        let groupDecorations: [UUID: GroupDecoration]
    }

    /// What a group orb resolves to when tapped — either a named
    /// circle filter or the untagged catch-all.
    enum GroupTarget: Hashable {
        case circle(String)
        case untagged
    }

    /// Counted summary of one circle group used to render a synthetic
    /// orb. `isUntagged == true` is the catch-all bucket for
    /// connections with no circle tag at all.
    struct GroupSummary {
        let name: String
        let count: Int
        let isUntagged: Bool
    }

    var body: some View {
        let orbs = displayedOrbs
        let displayed = orbs.connections
        let groupTokens = orbs.groupTokens
        let totalCount = circleVM.connections.count
        let isInitialLoading = (circleVM.loading || vm.loading) && totalCount == 0
            && !hasPendingActivity
        let didLoadFail = totalCount == 0 && !circleVM.loading && !vm.loading
            && !hasPendingActivity
            && (circleVM.errorMessage != nil || vm.errorMessage != nil)

        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            // Cosmos — sun always visible. Planets are either real
            // connections (filtered view) or synthetic group orbs
            // (default "All" view); the tap handler disambiguates.
            CircleSpriteSystemView(
                connections: displayed,
                myAvatarUrl: profile.profile?.avatarUrl,
                myDisplayName: profile.profile?.displayName,
                groupDecorations: orbs.groupDecorations,
                resetTrigger: solarResetTrigger,
                onTap: { id in handleOrbTap(id: id, groupTokens: groupTokens) })
                .ignoresSafeArea()

            centeredStatusOverlay(
                displayed: displayed,
                totalCount: totalCount,
                isInitialLoading: isInitialLoading,
                didLoadFail: didLoadFail)

            VStack(spacing: 0) {
                topOverlay(totalCount: totalCount)

                Spacer()

                if !didLoadFail {
                    solarActionRow
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.bottom, SacredSpacing.m)
                }
            }
        }
        .navigationTitle("Circles")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if totalCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        solarResetTrigger = UUID()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        }
        .refreshable {
            await vm.refresh()
            await circleVM.refresh()
        }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showAddLocal) {
            AddConnectionView(vm: circleVM)
        }
        .sheet(isPresented: $showRequestsSheet) {
            requestsAndInvitesSheet
        }
        .navigationDestination(item: $navTarget) { route in
            switch route {
            case .detail(let id):
                ConnectionDetailView(connectionId: id, vm: circleVM)
            }
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private func topOverlay(totalCount: Int) -> some View {
        VStack(spacing: SacredSpacing.s) {
            if totalCount > 0 || hasActiveCircleScope {
                circleSearchField
                filterChips
            }

            if hasPendingActivity {
                requestsChip
            }
        }
        .padding(.horizontal, SacredSpacing.m)
        .padding(.top, SacredSpacing.xs)
    }

    @ViewBuilder
    private func centeredStatusOverlay(
        displayed: [Connection],
        totalCount: Int,
        isInitialLoading: Bool,
        didLoadFail: Bool
    ) -> some View {
        if isInitialLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if didLoadFail {
            VStack {
                Spacer()
                loadFailureState
                    .padding(.horizontal, SacredSpacing.m)
                Spacer()
                Spacer()
            }
        } else if totalCount == 0 {
            walkingSoloOverlay
        } else if displayed.isEmpty {
            VStack(spacing: SacredSpacing.s) {
                Spacer()
                noMatchesState
                    .padding(.horizontal, SacredSpacing.m)
                findOnAppPrompt
                    .padding(.horizontal, SacredSpacing.m)
                Spacer()
                Spacer()
            }
        }
    }

    private var walkingSoloOverlay: some View {
        VStack(spacing: SacredSpacing.s) {
            Spacer()
            Spacer()
            VStack(spacing: 6) {
                Text("Walking solo for now.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                Text("Invite someone you trust to share this space.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .multilineTextAlignment(.center)
            }

            NavigationLink(destination: UserSearchView()) {
                Text("Or find someone on ShantiSangha")
                    .font(.sacredSmallSemibold)
                    .foregroundColor(.sacredGold)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, SacredSpacing.m)
    }

    // MARK: - Cosmos contents

    private var trimmedCircleSearch: String {
        circleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the cosmos renders. The `.all` chip in member view would
    /// produce a wall of avatars, so when nothing else is narrowing the
    /// scope we collapse the people into their groups (Family, Friend,
    /// circle names…). Group orbs are synthetic `Connection` values —
    /// the cosmos only cares about the shape — and the `groupTokens`
    /// map identifies them at tap time so we can switch the filter
    /// instead of pushing a detail view.
    private var displayedOrbs: DisplayedOrbs {
        let query = trimmedCircleSearch

        if selectedFilter == .all && query.isEmpty && !circleVM.connections.isEmpty {
            return groupedOrbs()
        }

        let connections = circleVM.connections
            .filter { selectedFilter.includes($0) }
            .filter { query.isEmpty || $0.matchesCircleSearch(query) }
            .sorted(by: sortDirectoryEntries)
        return DisplayedOrbs(connections: connections, groupTokens: [:], groupDecorations: [:])
    }

    private func groupedOrbs() -> DisplayedOrbs {
        var byCircle: [String: Int] = [:]
        var untaggedCount = 0
        for conn in circleVM.connections {
            let tags = conn.circles
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if tags.isEmpty {
                untaggedCount += 1
            } else {
                for tag in tags { byCircle[tag, default: 0] += 1 }
            }
        }

        var summaries: [GroupSummary] = byCircle
            .map { GroupSummary(name: $0.key, count: $0.value, isUntagged: false) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if untaggedCount > 0 {
            summaries.append(GroupSummary(name: "Untagged", count: untaggedCount, isUntagged: true))
        }

        var tokens: [UUID: GroupTarget] = [:]
        var decorations: [UUID: GroupDecoration] = [:]
        let orbs = summaries.map { summary -> Connection in
            let orb = Self.syntheticConnection(for: summary)
            tokens[orb.id] = summary.isUntagged ? .untagged : .circle(summary.name)
            decorations[orb.id] = GroupDecoration(
                name: summary.isUntagged ? "Untagged" : summary.name,
                memberCount: summary.count,
                memberAvatarUrls: collageAvatars(for: summary))
            return orb
        }
        return DisplayedOrbs(connections: orbs, groupTokens: tokens, groupDecorations: decorations)
    }

    /// Pick up to three avatars to populate the group orb's collage —
    /// recent activity first (so the freshest faces lead), then locals
    /// or anyone left over. Members without an avatar URL are skipped,
    /// not represented by a placeholder, so the collage never includes
    /// blank tiles.
    private func collageAvatars(for group: GroupSummary) -> [String] {
        let members = circleVM.connections.filter { conn -> Bool in
            if group.isUntagged {
                return conn.circles.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            return conn.circles.contains { $0.caseInsensitiveCompare(group.name) == .orderedSame }
        }
        let ranked = members.sorted { lhs, rhs in
            let l = FriendsDates.parse(lhs.lastMessageAt)
            let r = FriendsDates.parse(rhs.lastMessageAt)
            if let l, let r, l != r { return l > r }
            if (l != nil) != (r != nil) { return l != nil }
            return lhs.displayLabel.localizedCaseInsensitiveCompare(rhs.displayLabel) == .orderedAscending
        }
        return ranked.compactMap { $0.ownerVisibleAvatarUrl }.prefix(3).map { $0 }
    }

    /// Alphabetical by display name. Chat recency lives in Chats tab;
    /// the Circles directory is a stable, scannable address book.
    private func sortDirectoryEntries(_ lhs: Connection, _ rhs: Connection) -> Bool {
        let nameCompare = lhs.displayLabel
            .localizedCaseInsensitiveCompare(rhs.displayLabel)
        if nameCompare != .orderedSame { return nameCompare == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Builds a Connection-shaped stand-in for a circle group so the
    /// existing SpriteKit scene can render it as just another planet.
    /// The UUID is derived from the group name so SpriteKit doesn't
    /// re-add the node every render. `circles` is set to the group's
    /// name (or empty for Untagged) which drops the orb on the correct
    /// ring via `RingAssignment` — Family lands on the inner orbit,
    /// Friend on the middle, anything else on the outer.
    private static func syntheticConnection(for group: GroupSummary) -> Connection {
        let label = group.isUntagged ? "Untagged" : group.name
        let token = stableUUID(seed: "circle-group::\(label)")
        let person = Person(
            id: stableUUID(seed: "circle-group-person::\(label)"),
            userId: nil,
            displayName: label,
            phoneNumber: nil,
            email: nil,
            country: nil,
            state: nil,
            city: nil,
            address: nil,
            avatarKey: nil,
            avatarUrl: nil)
        return Connection(
            id: token,
            ownerUserId: token,
            personId: person.id,
            circles: group.isUntagged ? [] : [group.name],
            nickname: nil,
            privateNotes: nil,
            friendshipId: nil,
            messageable: false,
            createdAt: "",
            updatedAt: "",
            person: person,
            lastMessagePreview: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            privateAvatarUrl: nil)
    }

    /// Deterministic UUID from a seed string. UUID v4 layout (random)
    /// with version + variant bits patched so the sprite scene's UUID
    /// keying stays stable across renders for the same group.
    private static func stableUUID(seed: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        let seedBytes = Array(seed.utf8)
        for i in 0..<16 {
            // Simple FNV-ish fold so different prefixes diverge even
            // when seeds share leading bytes.
            var acc: UInt8 = 0
            for j in stride(from: i, to: seedBytes.count, by: 16) {
                acc = acc &+ seedBytes[j] &+ UInt8(j & 0xFF)
            }
            bytes[i] = acc
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40 // v4
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func handleOrbTap(id: UUID, groupTokens: [UUID: GroupTarget]) {
        if let target = groupTokens[id] {
            withAnimation(.easeOut(duration: 0.2)) {
                switch target {
                case .untagged: selectedFilter = .untagged
                case .circle(let name): selectedFilter = .circle(name)
                }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            navTarget = .detail(id)
        }
    }

    /// Bottom action row — invite + add local. Always pinned above
    /// the tab bar (cosmos is the only Circles view now).
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
    /// Capped at 6 dynamic circle chips so the row stays scrollable but
    /// doesn't fan out into a wall of tags. `.untagged` only shows up
    /// when there are connections with no circle tag — otherwise the
    /// chip would look like a dead end.
    private var availableFilters: [CircleFilter] {
        var filters: [CircleFilter] = [.all, .onApp, .local]
        if circleVM.connections.contains(where: { $0.circles.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }) {
            filters.append(.untagged)
        }
        let topCircles = circleVM.circleCatalog.prefix(6).map { CircleFilter.circle($0.name) }
        filters.append(contentsOf: topCircles)
        return filters
    }

    private var filterChips: some View {
        ScrollViewReader { proxy in
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
                        .id(filter)
                    }
                }
                .padding(.vertical, 1)
            }
            .onChange(of: selectedFilter) { _, new in
                // Tapping a group orb (or any chip off-screen) flips
                // the filter; scroll the matching chip into view so
                // the user always sees what they've drilled into.
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
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

    /// Shown when refresh failed and there's nothing in the lists.
    /// `walkingSoloOverlay` would otherwise lie that the user has no
    /// circle when really we just failed to fetch it.
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

    private var inlineErrorMessage: String? {
        circleVM.errorMessage ?? vm.errorMessage
    }

    // MARK: - Requests & invites

    private var hasPendingActivity: Bool {
        !vm.incomingRequests.isEmpty
            || !vm.pendingInvitations.isEmpty
            || !vm.outgoingRequests.isEmpty
    }

    /// Short summary so the chip reads as a status, not a count badge:
    /// "2 requests · 1 invite" beats "3 pending."
    private var pendingActivityLabel: String {
        var parts: [String] = []
        if !vm.incomingRequests.isEmpty {
            let n = vm.incomingRequests.count
            parts.append("\(n) request\(n == 1 ? "" : "s")")
        }
        if !vm.pendingInvitations.isEmpty {
            let n = vm.pendingInvitations.count
            parts.append("\(n) invite\(n == 1 ? "" : "s")")
        }
        if !vm.outgoingRequests.isEmpty && parts.isEmpty {
            let n = vm.outgoingRequests.count
            parts.append("\(n) awaiting reply")
        }
        return parts.joined(separator: " · ")
    }

    private var requestsChip: some View {
        Button {
            showRequestsSheet = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: SacredSpacing.xs) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.sacredSmallSemibold)
                Text(pendingActivityLabel)
                    .font(.sacredSmallSemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: SacredSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.sacredMicro)
                    .opacity(0.7)
            }
            .foregroundColor(.sacredGold)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.sacredBgCard.opacity(0.72)))
            .overlay(Capsule().stroke(Color.sacredGold.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pendingActivityLabel)
    }

    private var requestsAndInvitesSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SacredSpacing.l) {
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
                    }

                    if !hasPendingActivity {
                        SacredEmptyState(
                            icon: "tray",
                            title: "Nothing pending.",
                            subtitle: "Friend requests and invites will show up here.")
                            .padding(.top, SacredSpacing.xl)
                    }
                }
                .padding(SacredSpacing.m)
            }
            .background(SacredBackground().ignoresSafeArea())
            .navigationTitle("Pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRequestsSheet = false }
                        .foregroundColor(.sacredGold)
                }
            }
        }
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

/// Circle directory filter chips. The three `static` cases are always
/// present; `.circle(name)` cases are auto-derived per session from the
/// user's actual circle tags so the chip row reflects how *they*
/// organize their people, not a hardcoded taxonomy.
private enum CircleFilter: Hashable {
    case all
    case onApp
    case local
    case untagged
    case circle(String)

    var label: String {
        switch self {
        case .all: return "All"
        case .onApp: return "On app"
        case .local: return "Local"
        case .untagged: return "Untagged"
        case .circle(let name): return name
        }
    }

    func includes(_ connection: Connection) -> Bool {
        switch self {
        case .all:
            return true
        case .onApp:
            return connection.messageable
        case .local:
            return connection.person.userId == nil
        case .untagged:
            return connection.circles.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .circle(let name):
            return connection.circles.contains {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
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
