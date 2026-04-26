import SwiftUI

/// Root of the Friends tab. Lists existing friendships, surfaces pending
/// invites, and offers the "invite a friend" flow.
struct FriendsTabView: View {
    @StateObject private var vm = FriendsViewModel()
    @State private var showShare = false
    @State private var shareItems: [Any] = []

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SacredSpacing.l) {
                    findPeopleRow
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, SacredSpacing.m)

                    if vm.loading && vm.friends.isEmpty && vm.pendingInvitations.isEmpty
                        && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty {
                        ProgressView()
                            .padding(.top, SacredSpacing.xl * 2)
                    } else if vm.friends.isEmpty && vm.pendingInvitations.isEmpty
                        && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty
                        && vm.errorMessage != nil {
                        // Refresh failed and we have nothing to show. Tell
                        // the user the truth instead of "Walking solo for
                        // now" — that lie made a transient API/auth
                        // failure look like an empty friend list.
                        loadFailureState
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else if vm.friends.isEmpty && vm.pendingInvitations.isEmpty
                        && vm.outgoingRequests.isEmpty && vm.incomingRequests.isEmpty {
                        emptyState
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.xl)
                    } else {
                        if !vm.friends.isEmpty {
                            VStack(spacing: SacredSpacing.s) {
                                ForEach(vm.friends) { friend in
                                    NavigationLink(destination: FriendChatView(friend: friend)) {
                                        FriendRow(friend: friend)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, SacredSpacing.l)
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

                        SacredPrimaryButton("Invite another friend", style: .pill, fullWidth: true) {
                            Task { await onInvite() }
                        }
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
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.refresh() }
        .refreshable { await vm.refresh() }
        .sheet(isPresented: $showShare) { ShareSheet(items: shareItems) }
    }

    private var emptyState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "person.2",
                title: "Walking solo for now.",
                subtitle: "Invite someone you trust to message inside this private space.",
                actionLabel: "Invite a friend"
            ) { Task { await onInvite() } }
        }
    }

    /// Shown when refresh failed and there's nothing in the lists. The
    /// emptyState would otherwise lie that the user has no friends.
    private var loadFailureState: some View {
        SacredCard {
            SacredEmptyState(
                icon: "wifi.slash",
                title: "Couldn't load your friends.",
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
        let body = "I'm using ShantiSangha. Join me as a friend: \(link.url)"
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

private struct FriendRow: View {
    let friend: FriendSummary

    var body: some View {
        HStack(spacing: SacredSpacing.s) {
            SacredAvatar(
                displayName: friend.displayName,
                avatarUrl: friend.avatarUrl,
                size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(friend.displayName)
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    Spacer()
                    if friend.unreadCount > 0 {
                        Text("\(friend.unreadCount)")
                            .font(.sacredMicroBold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.sacredGold))
                    }
                }
                if let preview = friend.lastMessagePreview {
                    Text(preview)
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .lineLimit(1)
                } else {
                    Text("Say hello.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMutedLight)
                }
            }
        }
        .padding(SacredSpacing.s)
        .luxCardChrome()
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
