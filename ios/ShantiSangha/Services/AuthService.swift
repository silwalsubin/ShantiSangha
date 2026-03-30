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

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {}

    /// Call after FirebaseApp.configure()
    func startListening() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
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
            print("[Auth] Starting Google Sign-In...")
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            print("[Auth] Google Sign-In succeeded for: \(result.user.profile?.email ?? "unknown")")
            guard let idToken = result.user.idToken?.tokenString else {
                print("[Auth] ERROR: No ID token from Google")
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            print("[Auth] Signing into Firebase...")
            let authResult = try await Auth.auth().signIn(with: credential)
            print("[Auth] Firebase sign-in succeeded: \(authResult.user.email ?? "no email")")
            print("[Auth] isAuthenticated: \(isAuthenticated)")
        } catch {
            print("[Auth] ERROR: \(error)")
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
