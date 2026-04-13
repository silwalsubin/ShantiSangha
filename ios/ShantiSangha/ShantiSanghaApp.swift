import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "361305168424-umc433jdki16tbit3ou2kkjv1p7k327g.apps.googleusercontent.com"
        )

        // FCM setup
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        // Register for remote notifications synchronously in didFinishLaunching
        application.registerForRemoteNotifications()
        AppLogger.shared.info("Push", "registerForRemoteNotifications called")

        AuthService.shared.startListening()
        return true
    }

    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - APNs token forwarded to FCM

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        AppLogger.shared.info("Push", "APNs token received (\(deviceToken.count) bytes)")

        // Now that APNs token is set, request FCM token with retry
        Task {
            await self.fetchFCMTokenWithRetry(maxAttempts: 3)
        }
    }

    private func fetchFCMTokenWithRetry(maxAttempts: Int) async {
        for attempt in 1...maxAttempts {
            do {
                let token = try await Messaging.messaging().token()
                AppLogger.shared.info("Push", "FCM token obtained (attempt \(attempt)): \(token.prefix(20))...")
                await PushTokenService.shared.registerToken(token)
                return
            } catch {
                AppLogger.shared.error("Push", "FCM token attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000) // 3s, 6s backoff
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            AppLogger.shared.error("Push", "Failed to register: \(error.localizedDescription)")
        }
    }

    // MARK: - FCM token

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in
            AppLogger.shared.info("Push", "FCM token: \(token)")
        }
        Task { await PushTokenService.shared.registerToken(token) }
    }

    // MARK: - Silent push handler

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let type = userInfo["type"] as? String ?? "unknown"
        Task { @MainActor in
            AppLogger.shared.info("Push", "didReceiveRemoteNotification: \(type)")
        }
        Task {
            await SilentPushHandler.handle(userInfo: userInfo)
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate (called by Firebase swizzling)

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "unknown"
        Task { @MainActor in
            AppLogger.shared.info("Push", "willPresent notification: \(type)")
        }
        Task {
            await SilentPushHandler.handle(userInfo: userInfo)
        }
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "unknown"
        Task { @MainActor in
            AppLogger.shared.info("Push", "didReceive response: \(type)")
        }
        Task {
            await SilentPushHandler.handle(userInfo: userInfo)
        }
        completionHandler()
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
