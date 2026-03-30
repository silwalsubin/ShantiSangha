import SwiftUI
import FirebaseCore

@main
struct ShantiSanghaApp: App {
    @StateObject private var auth = AuthService.shared

    init() {
        FirebaseApp.configure()
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
