import SwiftUI

/// Login screen with native Google Sign-In via Firebase
struct LoginView: View {
    @EnvironmentObject var auth: AuthService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 8) {
                Circle()
                    .fill(RadialGradient.sacredGoldShiny)
                    .frame(width: 64, height: 64)
                    .shimmer()
                    .clipShape(Circle())
                    .overlay(
                        VajraIcon(size: 44, color: .white)
                    )

                Text("ShantiSangha")
                    .font(.sacredHero)
                    .foregroundColor(.sacredText)

                Text("A calmer place to return to.")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
            }

            Spacer()

            // Sign in button
            Button {
                Task { await auth.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    if auth.isLoading {
                        ProgressView()
                            .tint(.sacredText)
                    } else {
                        // Google logo
                        Image(systemName: "g.circle.fill")
                            .font(.sacredHeading)
                            .foregroundColor(.sacredText)
                        Text("Continue with Google")
                            .font(.sacredButtonLabel)
                            .foregroundColor(.sacredText)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.sacredBgCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .sacredMuted.opacity(0.15), radius: 8, y: 4)
            }
            .disabled(auth.isLoading)
            .padding(.horizontal, 32)

            // Quote
            Text("\u{201C}Peace comes from within. Do not seek it without.\u{201D} \u{2014} Buddha")
                .font(.sacredFinePrint)
                .italic()
                .foregroundColor(.sacredMutedLight)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
        .sacredBackground()
    }
}
