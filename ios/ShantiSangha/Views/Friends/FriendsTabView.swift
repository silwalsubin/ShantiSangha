import SwiftUI

/// Root of the Friends tab. Lists existing friendships, surfaces pending
/// invites, and offers the "invite a friend" flow.
struct FriendsTabView: View {
    /// Pending invites + incoming/outgoing requests still live here.
    /// The main connection list moved to `circleVM`.
    @StateObject private var vm = FriendsViewModel()
    @StateObject private var circleVM = CircleViewModel()
    @State private var showShare = false
    @State private var shareItems: [Any] = []
    @State private var showAddLocal = false
    @State private var navTarget: FriendNavRoute?
    /// String-backed because @AppStorage with custom enums needs a
    /// `RawRepresentable<String>` plus default-handling boilerplate;
    /// a tiny string compare is cheaper to read at the call site.
    @AppStorage("circle_view_mode") private var viewModeRaw: String = CircleViewMode.list.rawValue

    private var viewMode: CircleViewMode {
        CircleViewMode(rawValue: viewModeRaw) ?? .list
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
        case list, mandala
    }

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    findPeopleRow
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, SacredSpacing.m)

                    if (circleVM.loading || vm.loading) && circleVM.connections.isEmpty
                        && vm.pendingInvitations.isEmpty
                        && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty {
                        ProgressView()
                            .padding(.top, SacredSpacing.xl * 2)
                    } else if circleVM.connections.isEmpty && vm.pendingInvitations.isEmpty
                        && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty
                        && (circleVM.errorMessage != nil || vm.errorMessage != nil) {
                        // Refresh failed and we have nothing to show. Tell
                        // the user the truth instead of "Walking solo for
                        // now" — that lie made a transient API/auth
                        // failure look like an empty circle.
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
                            switch viewMode {
                            case .list:
                                SacredListCard {
                                    VStack(spacing: 0) {
                                        ForEach(Array(circleVM.connections.enumerated()), id: \.element.id) { index, conn in
                                            ConnectionRow(
                                                connection: conn,
                                                onTapAvatar: { navTarget = .detail(conn.id) },
                                                onTapBody: {
                                                    navTarget = conn.messageable
                                                        ? .chat(conn.id)
                                                        : .detail(conn.id)
                                                })

                                            if index < circleVM.connections.count - 1 {
                                                Divider()
                                                    .padding(.leading, 68)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, SacredSpacing.m)
                                .padding(.top, SacredSpacing.l)
                            case .mandala:
                                CircleMandalaView(
                                    connections: circleVM.connections,
                                    onTap: { id in
                                        if let conn = circleVM.connections.first(where: { $0.id == id }) {
                                            navTarget = conn.messageable ? .chat(id) : .detail(id)
                                        } else {
                                            navTarget = .detail(id)
                                        }
                                    })
                                    .frame(height: 480)
                                    .padding(.top, SacredSpacing.s)
                            }
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

                        SacredPrimaryButton("Invite to your circle", style: .pill, fullWidth: true) {
                            Task { await onInvite() }
                        }
                        .padding(.horizontal, SacredSpacing.m)

                        Button { showAddLocal = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14, weight: .regular))
                                Text("Add someone not on the app")
                                    .font(.sacredSmall)
                            }
                            .foregroundColor(.sacredGold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, SacredSpacing.m)
                    }

                    if let err = vm.errorMessage, !shouldHideError {
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
        .navigationTitle("Circle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only surface the toggle once there's actually a circle
            // to render — toggling between two empty states is noise.
            if !circleVM.connections.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            viewModeRaw = (viewMode == .list ? CircleViewMode.mandala : .list).rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: viewMode == .list
                              ? "circle.grid.cross"
                              : "list.bullet")
                            .foregroundColor(.sacredGold)
                    }
                    .accessibilityLabel(viewMode == .list ? "Show mandala" : "Show list")
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
                subtitle: vm.errorMessage ?? "Pull to refresh, or check your connection.",
                actionLabel: "Try again"
            ) { Task { await vm.refresh() } }
        }
    }

    /// Persistent entry point at the top of the Friends tab. Pushes the
    /// dedicated user-search screen. Styled as a search-bar lookalike so
    /// the affordance is obvious without the screen actually being a live
    /// search field (less keyboard accidents on tab open).
    private var findPeopleRow: some View {
        NavigationLink(destination: UserSearchView()) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                Text("Find people by name or location")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.sacredMuted.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sacredGold.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    /// Hide a one-off decode/network error when we have nothing to show — the
    /// empty state is the message at that point. Surface errors only when the
    /// user is mid-action or has loaded data and a follow-up call failed.
    private var shouldHideError: Bool {
        vm.friends.isEmpty && vm.pendingInvitations.isEmpty
            && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty
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
            }
            .buttonStyle(.plain)

            Button(action: onTapBody) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(connection.displayLabel)
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                        relationChip
                        Spacer()
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


/// UIKit share sheet bridge — uses the system's `UIActivityViewController`.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
