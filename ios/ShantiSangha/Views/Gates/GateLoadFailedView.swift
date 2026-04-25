import SwiftUI

/// Shown when `/me` fails to load (network down, server error). Offers a
/// retry and a sign-out — never traps the user with a blank screen.
struct GateLoadFailedView: View {
    let message: String
    @EnvironmentObject private var profile: ProfileService
    @EnvironmentObject private var auth: AuthService
    @State private var retrying = false

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            VStack(spacing: SacredSpacing.l) {
                Spacer()

                Image(systemName: "leaf")
                    .font(.sacredHero)
                    .foregroundColor(.sacredMutedLight)

                Text("We couldn't reach the server.")
                    .font(.sacredSubheading)
                    .foregroundColor(.sacredText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SacredSpacing.m)

                SacredPrimaryButton(
                    "Try again",
                    style: .pill,
                    isLoading: retrying
                ) {
                    Task {
                        retrying = true
                        defer { retrying = false }
                        await profile.load()
                    }
                }

                Spacer()

                Button { auth.signOut() } label: {
                    Text("Sign out")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                }
                .buttonStyle(.plain)
                .padding(.bottom, SacredSpacing.m)
            }
            .padding(.horizontal, SacredSpacing.l)
        }
    }
}
