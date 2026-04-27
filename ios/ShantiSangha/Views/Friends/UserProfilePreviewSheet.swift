import SwiftUI

/// Preview sheet shown when the user taps a search result. Surfaces the
/// fields search exposes (display name, avatar, location) and lets the
/// viewer send an in-app friend request directly. Outcomes:
///   - .idle           — nothing yet, "Connect" enabled
///   - .sending        — request in flight, button shows spinner
///   - .sent           — success, button swaps to "Request sent"
///   - .alreadyFriends — server told us we're already friends, route to chat
///   - .failed         — server rejected (e.g. user_not_found), show inline error
struct UserProfilePreviewSheet: View {
    let result: UserSearchResult
    @Environment(\.dismiss) private var dismiss
    @State private var state: SendState = .idle
    @State private var errorMessage: String?

    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case alreadyFriends
        case failed
    }

    var body: some View {
        VStack(spacing: SacredSpacing.l) {
            SacredAvatar(
                displayName: result.displayName,
                avatarUrl: result.avatarUrl,
                size: 120)

            VStack(spacing: SacredSpacing.xs) {
                Text(result.displayName)
                    .font(.sacredHeading)
                    .foregroundColor(.sacredText)
                    .multilineTextAlignment(.center)

                if let loc = result.locationString {
                    Text(loc)
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                        .multilineTextAlignment(.center)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.m)
            }

            Spacer(minLength: SacredSpacing.l)

            primaryAction

            Button("Close") { dismiss() }
                .font(.sacredText)
                .foregroundColor(.sacredMuted)
                .padding(.bottom, SacredSpacing.m)
        }
        .padding(SacredSpacing.l)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Color.sacredBg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch state {
        case .idle, .failed:
            SacredPrimaryButton("Invite to your circle", style: .commit) {
                Task { await send() }
            }
        case .sending:
            SacredPrimaryButton("Sending…", style: .commit, isLoading: true) { }
        case .sent:
            SacredPrimaryButton("Invite sent", style: .commit, isDisabled: true) { }
        case .alreadyFriends:
            SacredPrimaryButton("Already in your circle", style: .commit, isDisabled: true) { }
        }
    }

    private func send() async {
        state = .sending
        errorMessage = nil
        do {
            _ = try await NotificationsAPI.sendFriendRequest(toUserId: result.userId)
            state = .sent
        } catch let api as ApiError {
            // Translate backend error codes into clean local state.
            switch api {
            case .httpError(409, let data):
                let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let code = (body?["error"] as? String) ?? ""
                if code == "already_friends" {
                    state = .alreadyFriends
                    errorMessage = nil
                } else if code == "already_pending" {
                    state = .sent
                    errorMessage = "You've already sent them an invite."
                } else {
                    state = .failed
                    errorMessage = (body?["message"] as? String) ?? "Couldn't send the invite."
                }
            case .httpError(404, _):
                state = .failed
                errorMessage = "We couldn't find that person any more."
            default:
                state = .failed
                errorMessage = "Couldn't send the invite. Try again."
            }
        } catch {
            state = .failed
            errorMessage = "Couldn't send the invite. Try again."
        }
    }
}
