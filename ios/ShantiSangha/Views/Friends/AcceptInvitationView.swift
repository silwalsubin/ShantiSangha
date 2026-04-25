import SwiftUI

/// Sheet presented when the user opens an invite deep link. Previews who
/// invited them, then accepts on confirmation.
struct AcceptInvitationView: View {
    let token: String
    let onAccepted: (FriendSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var preview: InvitationPreview?
    @State private var loading = true
    @State private var accepting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: SacredSpacing.l) {
            if loading {
                ProgressView()
                    .padding(.top, SacredSpacing.xl)
            } else if let preview = preview {
                content(for: preview)
            } else if let err = errorMessage {
                errorView(err)
            } else {
                errorView("Couldn't load this invite.")
            }

            Spacer()
        }
        .padding(SacredSpacing.l)
        .background(Color.sacredBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            preview = try await FriendsAPI.previewInvitation(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(for p: InvitationPreview) -> some View {
        VStack(alignment: .leading, spacing: SacredSpacing.s) {
            Text(p.inviterDisplayName)
                .font(.sacredHero)
                .foregroundColor(.sacredText)
            Text("invites you to be friends inside ShantiSangha")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        SacredCard("WHAT THEY'LL SEE") {
            VStack(alignment: .leading, spacing: 6) {
                Text("• Your chosen display name")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
                Text("• Messages you choose to send them")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredTextSecondary)
                Text("Nothing else. Your journals, AI chats, voice notes, and reflections stay private.")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                    .padding(.top, 4)
            }
        }

        if p.tokenExpired {
            inlineError("This invite has expired. Ask them to send a new one.")
        } else if p.tokenAlreadyUsed {
            inlineError("This invite has already been used.")
        } else if p.alreadyFriends {
            inlineError("You're already friends with \(p.inviterDisplayName).")
        } else if p.isOwnInvite {
            inlineError("You can't accept your own invite.")
        } else if let err = errorMessage {
            inlineError(err)
        }

        VStack(spacing: SacredSpacing.xs) {
            SacredPrimaryButton(
                "Accept",
                style: .commit,
                isDisabled: !canAccept(p),
                isLoading: accepting
            ) { Task { await accept() } }

            Button("Not now") { dismiss() }
                .font(.sacredText)
                .foregroundColor(.sacredMuted)
        }
    }

    private func canAccept(_ p: InvitationPreview) -> Bool {
        !p.tokenExpired && !p.tokenAlreadyUsed && !p.alreadyFriends && !p.isOwnInvite
    }

    @ViewBuilder
    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.sacredSmall)
            .foregroundColor(.sacredRed)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: SacredSpacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.sacredHero)
                .foregroundColor(.sacredMutedLight)
            Text(message)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .multilineTextAlignment(.center)
            SacredPrimaryButton("Close") { dismiss() }
        }
    }

    private func accept() async {
        accepting = true
        defer { accepting = false }
        do {
            let result = try await FriendsAPI.acceptInvitation(token: token)
            NotificationCenter.default.post(name: .friendsUpdated, object: nil)
            onAccepted(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
