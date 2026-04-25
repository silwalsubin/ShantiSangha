import SwiftUI
import Combine
import FirebaseAuth
import FirebaseMessaging
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

    /// Tracks the in-flight `configureApiToken()` task per-user so that
    /// downstream services (`ProfileService.load`) can await its completion
    /// before hitting `/me` — `syncTimezone()` lazy-creates the backend
    /// `Profile` row, and `/me` racing it would 404.
    private var initialSyncTask: Task<Void, Never>?
    private var initialSyncUserId: String?

    init() {}

    /// Call after FirebaseApp.configure()
    func startListening() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.user = user
                self.isAuthenticated = user != nil
                if let user {
                    // Spin up the initial sync task per Firebase user so
                    // each sign-in gets its own awaitable handle. Token
                    // refreshes for the same user reuse the existing task.
                    if self.initialSyncUserId != user.uid {
                        self.initialSyncUserId = user.uid
                        self.initialSyncTask = Task { @MainActor in
                            await self.runInitialSync()
                        }
                    }
                } else {
                    self.initialSyncTask?.cancel()
                    self.initialSyncTask = nil
                    self.initialSyncUserId = nil
                }
            }
        }
    }

    /// Suspends until the post-sign-in initial sync (`configureApiToken` +
    /// `syncTimezone`) finishes. Safe to call multiple times — returns
    /// immediately when no sync is in flight.
    func awaitInitialSync() async {
        await initialSyncTask?.value
    }

    @MainActor
    private func runInitialSync() async {
        await ApiService.shared.setTokenProvider {
            let token = try? await Auth.auth().currentUser?.getIDToken()
            // Share token with widget extension via App Group
            if let token {
                UserDefaults(suiteName: WidgetData.appGroupId)?.set(token, forKey: "widget.authToken")
            }
            return token
        }

        await syncTimezone()

        // Register FCM token with backend after API auth is ready (release only)
        #if !DEBUG
        if let fcmToken = Messaging.messaging().fcmToken {
            await PushTokenService.shared.registerToken(fcmToken)
        }
        #endif
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
        Task {
            await PushTokenService.shared.unregisterToken()
            await ApiService.shared.clearTokenCache()
        }
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }

    private func syncTimezone() async {
        let tz = TimeZone.current.identifier
        var body: [String: Any] = ["timezone": tz]

        // Also sync the reminder hour on first login so server-side morning
        // pushes know when to fire for this user.
        let notif = NotificationService.shared
        let enabled = notif.isEnabled
        let hour = notif.reminderHour
        if enabled {
            body["reminderHour"] = hour
        } else {
            body["clearReminderHour"] = true
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let _: TimezoneSyncResponse? = try? await ApiService.shared.patchRaw("/me", body: data)
        AppLogger.shared.info("Auth", "Profile synced: tz=\(tz) reminderEnabled=\(enabled) hour=\(hour)")
    }
}

private struct TimezoneSyncResponse: Decodable {}
