import SwiftUI
import SwiftData
import UserNotifications
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    /// App-wide orientation gate. The app is portrait-first (mobile-first design
    /// principle); `ChessPresenter` opens chess in a forced-landscape controller
    /// and flips this to allow landscape while it's up, restoring `.portrait` on
    /// dismiss.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "361305168424-umc433jdki16tbit3ou2kkjv1p7k327g.apps.googleusercontent.com"
        )

        // FCM setup (swizzling is OFF — we forward everything manually)
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self

        #if !DEBUG
        // Only register for remote notifications in release builds
        // to avoid simulator/dev tokens conflicting with real device
        application.registerForRemoteNotifications()
        AppLogger.shared.info("Push", "registerForRemoteNotifications called")
        #else
        AppLogger.shared.info("Push", "Skipping FCM registration in debug build")
        #endif

        AuthService.shared.startListening()
        return true
    }

    // URL handling moved to the SwiftUI App body's `.onOpenURL` modifier
    // — iOS 26 deprecated `OpenURLOptionsKey` on the AppDelegate path.
    // The body's onOpenURL already calls `GIDSignIn.sharedInstance.handle(url)`
    // before falling through to DeepLinkRouter, so this delegate method
    // was redundant.

    // MARK: - APNs token forwarded to FCM (manual, swizzling OFF)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Manually forward APNs token to Firebase (required with swizzling OFF)
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
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 3_000_000_000)
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLogger.shared.error("Push", "Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // MARK: - FCM token

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        #if DEBUG
        AppLogger.shared.info("Push", "FCM token received but skipping registration (debug build)")
        #else
        AppLogger.shared.info("Push", "FCM token: \(token.prefix(20))...")
        Task { await PushTokenService.shared.registerToken(token) }
        #endif
    }

    // MARK: - Remote notification received (silent + background pushes)

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Manually forward to Firebase (required with swizzling OFF)
        Messaging.messaging().appDidReceiveMessage(userInfo)

        let type = userInfo["type"] as? String ?? "unknown"
        let keys = userInfo.keys.map { "\($0)" }.joined(separator: ", ")
        AppLogger.shared.info("Push", "didReceiveRemoteNotification: type=\(type) keys=[\(keys)]")

        Task {
            await SilentPushHandler.handle(userInfo: userInfo)
            completionHandler(.newData)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        // Manually forward to Firebase (required with swizzling OFF)
        Messaging.messaging().appDidReceiveMessage(userInfo)

        let type = userInfo["type"] as? String ?? "unknown"
        AppLogger.shared.info("Push", "willPresent notification: \(type)")

        Task {
            await SilentPushHandler.handle(userInfo: userInfo)
        }
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        // Manually forward to Firebase (required with swizzling OFF)
        Messaging.messaging().appDidReceiveMessage(userInfo)

        let type = userInfo["type"] as? String ?? "unknown"
        AppLogger.shared.info("Push", "didReceive response: \(type)")

        // Tap-routing: only fires here (not in willPresent / silent paths)
        // because didReceive is iOS's explicit "user opened this banner"
        // signal. The Circles tab picks up the routing intent and pushes
        // the matching chat thread.
        if type == "friend_message",
           let raw = userInfo["friendshipId"] as? String,
           let friendshipId = UUID(uuidString: raw) {
            Task { @MainActor in
                DeepLinkRouter.shared.handleChatNotification(friendshipId: friendshipId)
            }
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
    @StateObject private var profile = ProfileService.shared
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var reminderRepo = ReminderRepository.shared
    @StateObject private var notifications = NotificationService.shared

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: CachedConversation.self, SyncQueueItem.self)
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
                container = try ModelContainer(for: CachedConversation.self, SyncQueueItem.self)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.isAuthenticated {
                    LoginView()
                        .environmentObject(auth)
                } else if profile.loadState == .idle || profile.loadState == .loading {
                    GateLoadingView()
                        .environmentObject(auth)
                        .environmentObject(profile)
                } else if case .failed(let message) = profile.loadState {
                    GateLoadFailedView(message: message)
                        .environmentObject(auth)
                        .environmentObject(profile)
                } else if let gate = profile.requiredGate {
                    RequiredDataGateView(
                        gate: gate,
                        stepIndex: profile.requiredGateIndex,
                        totalSteps: profile.totalGates
                    )
                    .environmentObject(auth)
                    .environmentObject(profile)
                } else {
                    MainTabView()
                        .environmentObject(auth)
                        .environmentObject(profile)
                        .environmentObject(network)
                        .dailyBlessing()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: auth.isAuthenticated)
            .animation(.easeInOut(duration: 0.25), value: profile.loadState)
            .onOpenURL { url in
                if GIDSignIn.sharedInstance.handle(url) { return }
                DeepLinkRouter.shared.handle(url: url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    DeepLinkRouter.shared.handle(url: url)
                }
            }
            .task {
                await SyncService.shared.configure(container: container)

                // Bind profile loading to auth state changes. Safe to call
                // multiple times — `bind` only adds the subscription once.
                profile.bind(to: auth)

                // Notification permission is requested contextually from
                // settings or reminder flows, not on first launch.
            }
            .onChange(of: reminderRepo.reminders) {
                notifications.reschedule(reminders: reminderRepo.reminders)
            }
        }
        .modelContainer(container)
    }
}
