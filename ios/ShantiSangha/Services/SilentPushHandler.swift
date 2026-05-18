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

        switch type {
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
        case "reminder_shared":
            // The user was just added as a collaborator on someone else's
            // reminder. Refresh the bell inbox so the new row appears,
            // and let the always-on reminders refresh below pull the
            // shared row onto Home.
            await MainActor.run {
                NotificationCenter.default.post(name: .notificationsRefreshNeeded, object: nil)
            }
        case "reminder_changed":
            // A shared reminder this user has access to was edited,
            // completed, or deleted by another participant. The always-on
            // reminders refresh below picks up the change (or its absence
            // on delete) — no additional dispatch needed.
            break
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

    private static func refreshReminders(api: ApiService) async {
        do {
            // Pull reminders + connections together so we can stamp each
            // widget summary with the owner's nickname ("Didi · Birthday")
            // rather than just the bare label. Connection fetch is allowed
            // to fail quietly — the widget still works without the prefix.
            let reminders: [Reminder] = try await api.get("/reminders")
            let connections: [Connection] = (try? await ConnectionsAPI.list()) ?? []
            let connectionsById = Dictionary(
                uniqueKeysWithValues: connections.map { ($0.id, $0) })

            let summaries = reminders
                .filter { $0.completedAt == nil }
                .sorted { $0.localDaysRemaining < $1.localDaysRemaining }
                .prefix(5)
                .compactMap { r in
                    WidgetData.makeSummary(
                        id: r.id.uuidString,
                        label: r.label,
                        date: r.date,
                        daysRemaining: r.localDaysRemaining,
                        recurrence: r.recurrence.rawValue,
                        connectionLabel: r.connectionId.flatMap { connectionsById[$0]?.displayLabel })
                }
            WidgetData.upcomingReminders = Array(summaries)
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Push", "Failed to refresh reminders: \(error.localizedDescription)")
            }
        }

        WidgetData.lastUpdated = Date()
    }
}

extension Notification.Name {
    /// Fired by the silent-push handler when a "trading_signal" push
    /// arrives (high-conviction Wise Cat call on a held ticker). Any
    /// view that wants to refresh in response can observe this name.
    static let tradingSignalReceived = Notification.Name("tradingSignalReceived")
}
