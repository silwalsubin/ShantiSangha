import SwiftUI

/// Brief splash shown after Firebase sign-in while we hydrate `/me`.
/// In the happy path this is invisible (cached profile means we go straight
/// to the next state). On a slow cold launch the user sees the parchment
/// background + a small gold spinner. After 3 seconds we surface a Sign-out
/// link so a user with a wedged profile-load can always escape their account.
struct GateLoadingView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var showSignOut = false

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            VStack(spacing: SacredSpacing.l) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.sacredGold)

                if showSignOut {
                    Button { auth.signOut() } label: {
                        Text("Sign out")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.easeIn(duration: 0.3)) {
                showSignOut = true
            }
        }
    }
}
