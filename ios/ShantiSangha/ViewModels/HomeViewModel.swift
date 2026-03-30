import Foundation
import Combine

/// ViewModel for the Home screen — "What needs your attention today?"
/// Mirrors frontend/src/composables/useGoals.ts
@MainActor
class HomeViewModel: ObservableObject {
    @Published var tasks: [AppTask] = []
    @Published var loading = true

    var recurringTasks: [AppTask] { tasks.filter { !$0.checkedIn && $0.type == .recurring } }
    var milestoneTasks: [AppTask] { tasks.filter { !$0.checkedIn && $0.type == .oneTime } }
    var completedTasks: [AppTask] { tasks.filter { $0.checkedIn && $0.completedToday == true } }
    var skippedTasks: [AppTask] { tasks.filter { $0.checkedIn && $0.completedToday == false } }
    var hasTasks: Bool { !tasks.isEmpty }

    private let api = ApiService.shared

    private var localDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func load() async {
        loading = true
        do {
            // Load recurring tasks
            let todayItems: [AppTask] = try await api.get("/goals/today?date=\(localDate)")

            // Generate feedback for pre-checked tasks
            var recurring = todayItems
            for i in recurring.indices where recurring[i].checkedIn {
                let streak = recurring[i].completedToday == true ? recurring[i].currentStreak - 1 : 0
                recurring[i].feedbackMessage = FeedbackService.generate(
                    currentStreak: streak,
                    longestStreak: recurring[i].longestStreak,
                    completed: recurring[i].completedToday ?? false
                )
            }

            // Load milestones
            let allGoals: [AppTask] = try await api.get("/goals")
            tasks = recurring + allGoals.filter { $0.type == .oneTime }
        } catch {
            print("Failed to load tasks: \(error)")
            tasks = []
        }
        loading = false
    }

    func checkIn(id: String, completed: Bool) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].saving = true

        do {
            let body = CheckInBody(completed: completed, date: localDate)
            let _: CheckInResponse = try await api.post("/goals/\(id)/checkin", body: body)

            tasks[index].feedbackMessage = FeedbackService.generate(
                currentStreak: tasks[index].currentStreak,
                longestStreak: tasks[index].longestStreak,
                completed: completed
            )
            tasks[index].checkedIn = true
            tasks[index].completedToday = completed
            if completed { tasks[index].currentStreak += 1 }
            else { tasks[index].currentStreak = 0 }
        } catch {
            print("Check-in failed: \(error)")
        }

        tasks[index].saving = false
    }

    func undoCheckIn(id: String) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].saving = true

        do {
            try await api.delete("/goals/\(id)/checkin?date=\(localDate)")
            tasks[index].checkedIn = false
            tasks[index].completedToday = nil
            tasks[index].feedbackMessage = nil
        } catch {
            print("Undo failed: \(error)")
        }

        tasks[index].saving = false
    }

    func updateProgress(id: String, value: Int) async {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].saving = true

        do {
            let _: EmptyResponse = try await api.patch("/goals/\(id)", body: ["progress": value])
            tasks[index].progress = value
        } catch {
            print("Progress update failed: \(error)")
        }

        tasks[index].saving = false
    }

    func deleteTask(id: String) async {
        do {
            try await api.delete("/goals/\(id)")
            tasks.removeAll { $0.id == id }
        } catch {
            print("Delete failed: \(error)")
        }
    }

    func createTask(title: String, type: TaskType, targetDate: String? = nil) async {
        do {
            var body: [String: String] = ["title": title, "type": type.rawValue]
            if let date = targetDate { body["targetDate"] = date }
            let _: AppTask = try await api.post("/goals", body: body)
            await load()
        } catch {
            print("Create failed: \(error)")
        }
    }
}

// MARK: - Request/Response types

private struct CheckInBody: Encodable {
    let completed: Bool
    let date: String
}

private struct CheckInResponse: Decodable {
    let id: String
    let date: String
    let completed: Bool
}
