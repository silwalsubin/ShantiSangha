import Foundation
import WidgetKit

extension Notification.Name {
    static let silentPushReceived = Notification.Name("silentPushReceived")
}

/// Handles silent push notifications — refreshes local data and reloads widget timelines.
enum SilentPushHandler {
    static func handle(userInfo: [AnyHashable: Any]) async {
        let type = userInfo["type"] as? String ?? "unknown"
        await AppLogger.shared.info("Push", "Silent push received: type=\(type)")

        let api = ApiService.shared
        let dateStr = formatDate(Date())

        switch type {
        case "reflection":
            await refreshReflection(api: api, dateStr: dateStr)
        case "voice":
            // Voice transcription completed — no widget data to update,
            // but reload timelines in case we add voice data to widget later
            break
        case "friend_message":
            // Extract Sendable values BEFORE the MainActor hop — the raw
            // `userInfo` dict is `[AnyHashable: Any]`, which is not Sendable
            // under Swift 6 strict concurrency.
            let friendshipId = userInfo["friendshipId"] as? String ?? ""
            let messageId = userInfo["messageId"] as? String ?? ""
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .friendMessageReceived,
                    object: nil,
                    userInfo: [
                        "friendshipId": friendshipId,
                        "messageId": messageId
                    ])
                NotificationCenter.default.post(name: .friendsUpdated, object: nil)
            }
        case "friendship_created":
            await MainActor.run {
                NotificationCenter.default.post(name: .friendsUpdated, object: nil)
            }
        case "friend_request_received":
            // New incoming friend request. Tell the inbox + bell badge to
            // refresh; if the user is on Home or in the inbox right now,
            // both will repaint without them having to do anything.
            await MainActor.run {
                NotificationCenter.default.post(name: .notificationsRefreshNeeded, object: nil)
            }
        case "friend_request_accepted":
            // Sender just got their request accepted. Refresh the inbox
            // (so the "X accepted you" row appears) AND the friends list
            // (so the new friendship is in scope) without forcing them to
            // pull-to-refresh either surface.
            await MainActor.run {
                NotificationCenter.default.post(name: .notificationsRefreshNeeded, object: nil)
                NotificationCenter.default.post(name: .friendsUpdated, object: nil)
            }
        case "trading_signal":
            // Strong-conviction Wise Cat call. Posts a local notification
            // any view can observe; currently unwired on the receiver
            // side since WiseCatViewModel was retired, but the post is
            // cheap and future-friendly.
            let ticker = userInfo["ticker"] as? String ?? ""
            let action = userInfo["action"] as? String ?? ""
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .tradingSignalReceived,
                    object: nil,
                    userInfo: ["ticker": ticker, "action": action]
                )
            }
        default:
            break
        }

        // Always refresh reminders since they're in the widget
        await refreshReminders(api: api)

        // Force UserDefaults to flush to disk before telling WidgetKit to reload —
        // the widget runs in a separate process and needs to see the updated values
        UserDefaults(suiteName: WidgetData.appGroupId)?.synchronize()

        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaReflection")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaDashboard")

        // Notify in-app views to refresh
        await MainActor.run {
            NotificationCenter.default.post(name: .silentPushReceived, object: nil, userInfo: ["type": type])
        }

        await AppLogger.shared.info("Push", "Widget timelines reloaded after silent push")
    }

    private static func refreshReflection(api: ApiService, dateStr: String) async {
        do {
            let response: DailyReflectionResponse = try await api.get("/reflection/today?date=\(dateStr)")
            if let content = response.content, !content.isEmpty {
                WidgetData.reflection = content
                await AppLogger.shared.info("Push", "Reflection updated: \(content.prefix(40))...")
            } else {
                await AppLogger.shared.info("Push", "Reflection response empty, keeping existing")
            }
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Push", "Failed to refresh reflection: \(error.localizedDescription)")
            }
        }
    }

    private static func refreshReminders(api: ApiService) async {
        do {
            let reminders: [Reminder] = try await api.get("/reminders")
            let pending = reminders.filter { $0.completedAt == nil }
            WidgetData.remindersOverdue = pending.filter { $0.daysRemaining < 0 }.count
            WidgetData.remindersDueToday = pending.filter { $0.daysRemaining == 0 }.count
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Push", "Failed to refresh reminders: \(error.localizedDescription)")
            }
        }

        WidgetData.lastUpdated = Date()
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

private struct DailyReflectionResponse: Decodable {
    let content: String?
}

extension Notification.Name {
    /// Fired by the silent-push handler when a "trading_signal" push
    /// arrives (high-conviction Wise Cat call on a held ticker). Any
    /// view that wants to refresh in response can observe this name.
    static let tradingSignalReceived = Notification.Name("tradingSignalReceived")
}
