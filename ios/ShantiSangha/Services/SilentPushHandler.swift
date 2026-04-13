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
        case "mantra":
            await refreshMantra(api: api)
        case "voice":
            // Voice transcription completed — no widget data to update,
            // but reload timelines in case we add voice data to widget later
            break
        case "insight", "summary":
            // Insights don't currently surface in widget, but refresh anyway
            break
        default:
            break
        }

        // Always refresh goals/practices since they're in the widget
        await refreshGoalsAndPractices(api: api, dateStr: dateStr)

        // Force UserDefaults to flush to disk before telling WidgetKit to reload —
        // the widget runs in a separate process and needs to see the updated values
        UserDefaults(suiteName: WidgetData.appGroupId)?.synchronize()

        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaMantra")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaDashboard")

        // Notify in-app views to refresh
        await MainActor.run {
            NotificationCenter.default.post(name: .silentPushReceived, object: nil, userInfo: ["type": type])
        }

        await AppLogger.shared.info("Push", "Widget timelines reloaded after silent push")
    }

    private static func refreshMantra(api: ApiService) async {
        do {
            let response: MantraResponse = try await api.get("/mantra/today")
            if let content = response.content, !content.isEmpty {
                WidgetData.mantra = content
                await AppLogger.shared.info("Push", "Mantra updated: \(content.prefix(40))...")
            } else {
                await AppLogger.shared.info("Push", "Mantra response empty, keeping existing")
            }
        } catch {
            await AppLogger.shared.error("Push", "Failed to refresh mantra: \(error.localizedDescription)")
        }
    }

    private static func refreshGoalsAndPractices(api: ApiService, dateStr: String) async {
        // Fetch goals
        do {
            let goals: [AppTask] = try await api.get("/goals?date=\(dateStr)")
            let milestones = goals.filter { $0.type == .oneTime }
            let pending = milestones.filter { $0.completedAt == nil }
            WidgetData.goalsOverdue = pending.filter { ($0.daysRemaining ?? 1) < 0 }.count
            WidgetData.goalsDueToday = pending.filter { $0.daysRemaining == 0 }.count
        } catch {
            await AppLogger.shared.error("Push", "Failed to refresh goals: \(error.localizedDescription)")
        }

        // Fetch practices
        do {
            let tasks: [AppTask] = try await api.get("/goals/today?date=\(dateStr)")
            let recurring = tasks.filter { $0.type == .recurring }
            WidgetData.practicesDone = recurring.filter { $0.checkedIn }.count
            WidgetData.practicesTotal = recurring.count
        } catch {
            await AppLogger.shared.error("Push", "Failed to refresh practices: \(error.localizedDescription)")
        }

        WidgetData.lastUpdated = Date()
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// Reuse the same response type from HomeView
private struct MantraResponse: Decodable {
    let content: String?
}
