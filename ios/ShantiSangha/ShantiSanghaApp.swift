import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct ShantiSanghaApp: App {
    @StateObject private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()

        // Configure Google Sign-In with the iOS client ID
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "476549159082-k7ql964hu0j0isjmu94gro7nqks3mp5p.apps.googleusercontent.com"
        )
    }

    var body: some Scene {
        WindowGroup {
            if auth.isAuthenticated {
                MainTabView()
                    .environmentObject(auth)
            } else {
                LoginView()
                    .environmentObject(auth)
            }
        }
    }
}
