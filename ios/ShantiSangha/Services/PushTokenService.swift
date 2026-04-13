import Foundation

/// Manages FCM device token registration with the backend.
actor PushTokenService {
    static let shared = PushTokenService()

    private var lastRegisteredToken: String?

    func registerToken(_ token: String) async {
        guard token != lastRegisteredToken else { return }
        lastRegisteredToken = token
        do {
            struct Req: Encodable { let token: String; let platform = "ios" }
            let _: EmptyResponse = try await ApiService.shared.post("/me/device-token", body: Req(token: token))
            await AppLogger.shared.info("Push", "Device token registered")
        } catch {
            lastRegisteredToken = nil
            await AppLogger.shared.error("Push", "Failed to register token: \(error.localizedDescription)")
        }
    }

    func unregisterToken() async {
        guard let token = lastRegisteredToken else { return }
        do {
            try await ApiService.shared.delete("/me/device-token?token=\(token)")
            lastRegisteredToken = nil
            await AppLogger.shared.info("Push", "Device token unregistered")
        } catch {
            await AppLogger.shared.error("Push", "Failed to unregister token: \(error.localizedDescription)")
        }
    }
}
