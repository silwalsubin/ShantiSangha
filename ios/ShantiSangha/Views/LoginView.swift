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
                    .fill(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(
                        VajraIcon(size: 44, color: .white)
                    )

                Text("ShantiSangha")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(.sacredText)

                Text("A calmer place to return to.")
                    .font(.system(size: 14))
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
                            .font(.system(size: 20))
                            .foregroundColor(.sacredText)
                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
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
                .font(.system(size: 11, design: .serif))
                .italic()
                .foregroundColor(.sacredMutedLight)
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
        .background(Color.sacredBg.ignoresSafeArea())
    }
}
