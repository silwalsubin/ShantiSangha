import SwiftUI

/// Login screen — mirrors frontend/src/pages/login.vue
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
                        Image(systemName: "shield.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
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
                auth.signIn()
            } label: {
                HStack(spacing: 8) {
                    if auth.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign in with Google")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(auth.isLoading)
            .padding(.horizontal, 32)

            // Quote
            Text(""Peace comes from within. Do not seek it without." — Buddha")
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
