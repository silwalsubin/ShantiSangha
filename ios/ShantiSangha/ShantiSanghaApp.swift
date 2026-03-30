import SwiftUI
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "361305168424-umc433jdki16tbit3ou2kkjv1p7k327g.apps.googleusercontent.com"
        )
        AuthService.shared.startListening()
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct ShantiSanghaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                        .environmentObject(auth)
                } else {
                    LoginView()
                        .environmentObject(auth)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
