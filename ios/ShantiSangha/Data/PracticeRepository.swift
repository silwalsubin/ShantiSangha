import Foundation
import SwiftData

/// Repository for the user's recurring practices.
/// Reads from local SwiftData, writes locally + queues sync.
@MainActor
class PracticeRepository: ObservableObject {
    static let shared = PracticeRepository()

    @Published var practices: [Practice] = []
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
        let descriptor = FetchDescriptor<CachedPractice>(sortBy: [SortDescriptor(\.title)])
        guard let cached = try? ctx.fetch(descriptor) else { return }
        practices = cached.map { $0.toPractice() }
        if !practices.isEmpty { loading = false }
    }

    // MARK: - Sync (pull from server)

    func refreshFromServer() async {
        let dateStr = localDateStr()

        do {
            let items: [Practice] = try await api.get("/practices/today?date=\(dateStr)")

            guard let ctx = modelContext else { return }
            for practice in items {
                let id = practice.id
                let descriptor = FetchDescriptor<CachedPractice>(
                    predicate: #Predicate { $0.id == id }
                )
                if let existing = try? ctx.fetch(descriptor).first {
                    if !existing.hasPendingChanges {
                        existing.update(from: practice)
                    }
                } else {
                    let cached = CachedPractice(
                        id: practice.id, title: practice.title,
                        currentStreak: practice.currentStreak,
                        longestStreak: practice.longestStreak,
                        checkedIn: practice.checkedIn,
                        completedToday: practice.completedToday
                    )
                    ctx.insert(cached)
                }
            }

            let serverIds = Set(items.map(\.id))
            let allLocal = FetchDescriptor<CachedPractice>()
            if let localPractices = try? ctx.fetch(allLocal) {
                for local in localPractices where !serverIds.contains(local.id) {
                    if !local.hasPendingChanges {
                        ctx.delete(local)
                    }
                }
            }

            try? ctx.save()

            var result = items

            // Merge with any local-only practices (pending creates with temp IDs)
            let serverResultIds = Set(result.map(\.id))
            if let localPractices = try? ctx.fetch(FetchDescriptor<CachedPractice>()) {
                for local in localPractices where !serverResultIds.contains(local.id) && local.hasPendingChanges {
                    result.append(local.toPractice())
                }
            }

            practices = result
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("PracticeRepo", "Refresh failed: \(error)")
            }
        }

        loading = false
    }

    // MARK: - Writes (local first + queue sync)

    func checkIn(id: String, completed: Bool) async {
        var mindfulTitle: String?

        if let idx = practices.firstIndex(where: { $0.id == id }) {
            practices[idx].checkedIn = true
            practices[idx].completedToday = completed
            if completed { practices[idx].currentStreak += 1 }
            else { practices[idx].currentStreak = 0 }
            updateLocal(practices[idx], pending: true)

            if completed && HealthKitService.countsAsMindful(title: practices[idx].title) {
                mindfulTitle = practices[idx].title
            }
        }

        let body: [String: Any] = ["completed": completed, "note": NSNull(), "date": localDateStr()]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "POST", path: "/practices/\(id)/checkin", body: RawData(data: data))
        }

        if mindfulTitle != nil {
            await HealthKitService.shared.logMindfulSession()
        }
    }

    func undoCheckIn(id: String) async {
        if let idx = practices.firstIndex(where: { $0.id == id }) {
            practices[idx].checkedIn = false
            practices[idx].completedToday = nil
            updateLocal(practices[idx], pending: true)
        }

        await sync.enqueue(method: "DELETE", path: "/practices/\(id)/checkin?date=\(localDateStr())")
    }

    func deletePractice(id: String) async {
        practices.removeAll { $0.id == id }
        deleteLocal(id: id)
        await sync.enqueue(method: "DELETE", path: "/practices/\(id)")
    }

    func createPractice(title: String, deeperWhy: String? = nil) async {
        let tempId = UUID().uuidString

        let new = Practice(id: tempId, title: title)
        practices.append(new)
        insertLocal(new, pending: true)

        var body: [String: String] = ["title": title]
        if let deeperWhy, !deeperWhy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["deeperWhy"] = deeperWhy.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            await sync.enqueue(method: "POST", path: "/practices", body: RawData(data: data), tempId: tempId)
        }
    }

    // MARK: - Sync callbacks

    /// Called by SyncService after a create operation resolves the real server ID
    func replaceTempWithReal(tempId: String, real: Practice) {
        if let idx = practices.firstIndex(where: { $0.id == tempId }) {
            practices[idx] = real
            deleteLocal(id: tempId)
            insertLocal(real, pending: false)
        } else {
            deleteLocal(id: tempId)
            insertLocal(real, pending: false)
        }
    }

    /// Called by SyncService after a successful sync to clear pending flag
    func markSynced(id: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CachedPractice>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.hasPendingChanges = false
            existing.lastSyncedAt = Date()
            try? ctx.save()
        }
        if let idx = practices.firstIndex(where: { $0.id == id }) {
            practices[idx].hasPendingChanges = false
        }
    }

    // MARK: - Local DB helpers

    private func updateLocal(_ practice: Practice, pending: Bool) {
        guard let ctx = modelContext else { return }
        let id = practice.id
        let descriptor = FetchDescriptor<CachedPractice>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(descriptor).first {
            existing.update(from: practice)
            if pending { existing.hasPendingChanges = true }
            try? ctx.save()
        }
    }

    private func insertLocal(_ practice: Practice, pending: Bool) {
        guard let ctx = modelContext else { return }
        let cached = CachedPractice(
            id: practice.id, title: practice.title,
            currentStreak: practice.currentStreak, longestStreak: practice.longestStreak,
            checkedIn: practice.checkedIn, completedToday: practice.completedToday,
            hasPendingChanges: pending
        )
        ctx.insert(cached)
        try? ctx.save()
    }

    private func deleteLocal(id: String) {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<CachedPractice>(predicate: #Predicate { $0.id == id })
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
