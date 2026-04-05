import SwiftUI
import SwiftData
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
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var repo = TaskRepository.shared
    @StateObject private var notifications = NotificationService.shared

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: CachedTask.self, CachedConversation.self, SyncQueueItem.self)
        } catch {
            // Migration failed — delete old store and recreate
            // Data will be re-fetched from server on next refresh
            print("[App] ModelContainer migration failed, resetting local DB: \(error)")
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            // Also remove WAL/SHM files
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            do {
                container = try ModelContainer(for: CachedTask.self, CachedConversation.self, SyncQueueItem.self)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                        .environmentObject(auth)
                        .environmentObject(network)
                        .environmentObject(repo)
                } else {
                    LoginView()
                        .environmentObject(auth)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .task {
                // Configure repository with SwiftData context
                let context = container.mainContext
                repo.configure(context: context)
                await SyncService.shared.configure(container: container)

                // Request notification permission on first launch
                if !UserDefaults.standard.bool(forKey: "notificationPermissionAsked") {
                    UserDefaults.standard.set(true, forKey: "notificationPermissionAsked")
                    await notifications.requestPermission()
                }
            }
            .onChange(of: repo.tasks) {
                notifications.reschedule(tasks: repo.tasks)
            }
        }
        .modelContainer(container)
    }
}
