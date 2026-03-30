import SwiftUI
import AuthenticationServices

/// Handles Clerk authentication via web-based OAuth.
/// Opens Clerk's sign-in page in a system browser sheet,
/// receives the session token back via redirect URI.
@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var sessionToken: String?
    @Published var isLoading = false

    private let clerkDomain = "clerk.shantisangha.com"
    private let redirectScheme = "shantisangha"

    // Keychain key for persisting the session
    private let tokenKey = "clerk_session_token"

    init() {
        // Restore session from keychain
        if let token = KeychainHelper.read(key: tokenKey) {
            self.sessionToken = token
            self.isAuthenticated = true
            Task {
                await ApiService.shared.setTokenProvider { [weak self] in
                    self?.sessionToken
                }
            }
        }
    }

    func signIn() {
        isLoading = true

        let signInURL = "https://\(clerkDomain)/sign-in?redirect_url=\(redirectScheme)://auth/callback"

        guard let url = URL(string: signInURL) else {
            isLoading = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: redirectScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.isLoading = false

                guard let callbackURL = callbackURL, error == nil else { return }

                // Extract token from callback URL
                if let token = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "session_token" })?.value {
                    self?.setSession(token: token)
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = ASWebAuthPresentationContext.shared
        session.start()
    }

    func signOut() {
        sessionToken = nil
        isAuthenticated = false
        KeychainHelper.delete(key: tokenKey)
    }

    private func setSession(token: String) {
        sessionToken = token
        isAuthenticated = true
        KeychainHelper.save(key: tokenKey, value: token)

        Task {
            await ApiService.shared.setTokenProvider { [weak self] in
                self?.sessionToken
            }
        }
    }
}

// MARK: - ASWebAuthentication presentation context

class ASWebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = ASWebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Simple keychain helper

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
