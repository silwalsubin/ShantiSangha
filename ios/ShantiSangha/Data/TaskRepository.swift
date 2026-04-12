import Foundation
import SwiftData

/// Repository pattern — single interface for task data.
/// Reads from local SwiftData, writes locally + queues sync.
@MainActor
class TaskRepository: ObservableObject {
    static let shared = TaskRepository()

    @Published var tasks: [AppTask] = []
    @Published var loading = true

    private var modelContext: ModelContext?
    private let api = ApiService.shared
    private let sync = SyncService.shared

    func configure(context: ModelContext) {
        self.modelContext = context
        loadFromLocal()
    }

    // MARK: - Reads (always local)

    func loadFromLocal() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(sortBy: [SortDescriptor(\.title)])
        guard let cached = try? ctx.fetch(descriptor) else { return }
        tasks = cached.map { $0.toAppTask() }
        if !tasks.isEmpty { loading = false }
    }

    // MARK: - Sync (pull from server)

    func refreshFromServer() async {
        let dateStr = localDateStr()

        do {
            // Fetch recurring
            let todayItems: [AppTask] = try await api.get("/goals/today?date=\(dateStr)")

            // Fetch all (for milestones — include completed so they show in summary)
            let allGoals: [AppTask] = try await api.get("/goals?date=\(dateStr)")
            let milestones = allGoals.filter { $0.type == .oneTime }

            let allTasks = todayItems + milestones
            // Update local DB
            guard let ctx = modelContext else { return }
            for task in allTasks {
                let id = task.id
                let descriptor = FetchDescriptor<CachedTask>(
                    predicate: #Predicate { $0.id == id }
                )
                if let existing = try? ctx.fetch(descriptor).first {
                    // Don't overwrite if local has pending unsynced changes
                    if !existing.hasPendingChanges {
                        existing.update(from: task)
                    }
                } else {
                    let cached = CachedTask(
                        id: task.id, title: task.title,
                        type: task.type.rawValue,
                        currentStreak: task.currentStreak,
                        longestStreak: task.longestStreak,
                        daysRemaining: task.daysRemaining,
                        progress: task.progress,
                        checkedIn: task.checkedIn,
                        completedToday: task.completedToday
                    )
                    ctx.insert(cached)
                }
            }

            // Remove tasks that no longer exist on server
            // but keep tasks with pending changes (they may have temp IDs)
            let serverIds = Set(allTasks.map(\.id))
            let allLocal = FetchDescriptor<CachedTask>()
            if let localTasks = try? ctx.fetch(allLocal) {
                for local in localTasks where !serverIds.contains(local.id) {
                    if !local.hasPendingChanges {
                        ctx.delete(local)
                    }
                }
            }

            try? ctx.save()

            var result = allTasks

            // Merge with any local-only tasks (pending creates with temp IDs)
            let serverResultIds = Set(result.map(\.id))
            if let localTasks = try? ctx.fetch(FetchDescriptor<CachedTask>()) {
                for local in localTasks where !serverResultIds.contains(local.id) && local.hasPendingChanges {
                    result.append(local.toAppTask())
                }
            }

            tasks = result
        } catch {
            AppLogger.shared.error("Repo", "Refresh failed: \(error)")
            // Keep showing local data
        }

        loading = false
    }

    // MARK: - Writes (local first + queue sync)

    func checkIn(id: String, completed: Bool) async {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            let isMilestone = tasks[idx].type == .oneTime

            tasks[idx].checkedIn = true
            tasks[idx].completedToday = completed
            if isMilestone && completed {
                tasks[idx].completedAt = localDateStr()
            }
            if !isMilestone {
                if completed { tasks[idx].currentStreak += 1 }
                else { tasks[idx].currentStreak = 0 }
            }
            updateLocal(tasks[idx], pending: true)
        }

        // Queue sync
        let body: [String: Any] = ["completed": completed, "note": NSNull(), "date": localDateStr()]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "POST", path: "/goals/\(id)/checkin", body: RawData(data: data))
        }
    }

    func undoCheckIn(id: String) async {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].checkedIn = false
            tasks[idx].completedToday = nil
            updateLocal(tasks[idx], pending: true)
        }

        await sync.enqueue(method: "DELETE", path: "/goals/\(id)/checkin?date=\(localDateStr())")
    }

    func deleteTask(id: String) async {
        tasks.removeAll { $0.id == id }
        deleteLocal(id: id)
        await sync.enqueue(method: "DELETE", path: "/goals/\(id)")
    }

    func updateProgress(id: String, value: Int) async {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].progress = value
            updateLocal(tasks[idx], pending: true)
        }

        let body = ["progress": value]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "PATCH", path: "/goals/\(id)", body: RawData(data: data))
        }
    }

    func updateDueDate(id: String, date: String) async {
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            if let parsed = f.date(from: date) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: parsed).day
                tasks[idx].daysRemaining = days
            }
            updateLocal(tasks[idx], pending: true)
        }

        let body: [String: String] = ["targetDate": date]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "PATCH", path: "/goals/\(id)", body: RawData(data: data))
        }
    }

    func createTask(title: String, type: TaskType, targetDate: String? = nil) async {
        // Create locally with temp ID
        let tempId = UUID().uuidString

        // Compute daysRemaining from targetDate so it shows immediately in date-filtered views
        var daysRemaining: Int? = nil
        if let targetDate = targetDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            if let target = df.date(from: targetDate) {
                daysRemaining = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: target).day
            }
        }

        let newTask = AppTask(
            id: tempId, title: title, type: type,
            daysRemaining: daysRemaining, progress: 0
        )
        tasks.append(newTask)
        insertLocal(newTask, pending: true)

        // Queue sync — SyncService will replace temp ID with real ID on success
        var body: [String: String] = ["title": title, "type": type.rawValue]
        if let date = targetDate { body["targetDate"] = date }
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "POST", path: "/goals", body: RawData(data: data), tempId: tempId)
        }
    }

    // MARK: - Sync callbacks

    /// Called by SyncService after a create operation resolves the real server ID
    func replaceTempWithReal(tempId: String, real: AppTask) {
        // Update in-memory tasks, preserving locally-computed fields the server may not return
        if let idx = tasks.firstIndex(where: { $0.id == tempId }) {
            var merged = real
            if merged.daysRemaining == nil {
                merged.daysRemaining = tasks[idx].daysRemaining
            }
            tasks[idx] = merged
            // Update local DB
            deleteLocal(id: tempId)
            insertLocal(merged, pending: false)
        } else {
            deleteLocal(id: tempId)
            insertLocal(real, pending: false)
        }
    }

    /// Called by SyncService after a successful sync to clear pending flag
    func markSynced(id: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.hasPendingChanges = false
            existing.lastSyncedAt = Date()
            try? ctx.save()
        }
        // Update in-memory
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].hasPendingChanges = false
        }
    }

    // MARK: - Local DB helpers

    private func updateLocal(_ task: AppTask, pending: Bool) {
        guard let ctx = modelContext else { return }
        let id = task.id
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.update(from: task)
            if pending { existing.hasPendingChanges = true }
            try? ctx.save()
        }
    }

    private func insertLocal(_ task: AppTask, pending: Bool) {
        guard let ctx = modelContext else { return }
        let cached = CachedTask(
            id: task.id, title: task.title, type: task.type.rawValue,
            currentStreak: task.currentStreak, longestStreak: task.longestStreak,
            daysRemaining: task.daysRemaining, progress: task.progress,
            checkedIn: task.checkedIn, completedToday: task.completedToday,
            hasPendingChanges: pending
        )
        ctx.insert(cached)
        try? ctx.save()
    }

    private func deleteLocal(id: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            ctx.delete(existing)
            try? ctx.save()
        }
    }

    private func localDateStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// Wrapper to make raw Data conform to Encodable for SyncService
struct RawData: Encodable {
    let data: Data
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}
