import SwiftUI

/// Read-only preview sheet shown when the user taps a search result. v1
/// surfaces the same fields search exposes (display name, avatar, location)
/// and stubs the action button — when the deferred action design lands,
/// "Connect" swaps to a real send-friend-request call.
struct UserProfilePreviewSheet: View {
    let result: UserSearchResult
    @Environment(\.dismiss) private var dismiss

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

            Spacer(minLength: SacredSpacing.l)

            // Action stubbed for v1. Swap to a real send-friend-request
            // call when the deferred design lands.
            SacredPrimaryButton(
                "Connect (coming soon)",
                style: .commit,
                isDisabled: true
            ) { }

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
}
