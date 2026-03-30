import SwiftUI
import Combine
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift

/// Handles Firebase authentication with native Google Sign-In.
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var user: FirebaseAuth.User?

    init() {
        // Listen for auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil
                if user != nil {
                    self?.configureApiToken()
                }
            }
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else { return }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        } catch {
            print("Google Sign-In failed: \(error)")
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    private func configureApiToken() {
        Task {
            await ApiService.shared.setTokenProvider {
                try? await Auth.auth().currentUser?.getIDToken()
            }
        }
    }
}
