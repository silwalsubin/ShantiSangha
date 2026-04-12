import Foundation

/// Manages FCM device token registration with the backend.
actor PushTokenService {
    static let shared = PushTokenService()

    private var lastRegisteredToken: String?

    func registerToken(_ token: String) async {
        guard token != lastRegisteredToken else { return }
        do {
            struct Req: Encodable { let token: String; let platform = "ios" }
            let _: EmptyResponse = try await ApiService.shared.post("/me/device-token", body: Req(token: token))
            lastRegisteredToken = token
            AppLogger.shared.info("Push", "Device token registered")
        } catch {
            AppLogger.shared.error("Push", "Failed to register token: \(error.localizedDescription)")
        }
    }

    func unregisterToken() async {
        guard let token = lastRegisteredToken else { return }
        do {
            try await ApiService.shared.delete("/me/device-token?token=\(token)")
            lastRegisteredToken = nil
            AppLogger.shared.info("Push", "Device token unregistered")
        } catch {
            AppLogger.shared.error("Push", "Failed to unregister token: \(error.localizedDescription)")
        }
    }
}
