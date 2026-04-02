import Foundation

/// Mirrors frontend/src/types/index.ts — Task interface
struct AppTask: Codable, Identifiable {
    var id: String
    var title: String
    var type: TaskType
    var checkedIn: Bool
    var completedToday: Bool?
    var daysRemaining: Int?
    var progress: Int
    var checkIn: CheckInData?

    // Internal — not from API, computed locally
    var feedbackMessage: String?
    var saving: Bool = false
    var hasPendingChanges: Bool = false

    // Streak data from /goals/today
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, title, type, checkedIn, completedToday, daysRemaining, progress, checkIn
        case currentStreak, longestStreak
    }

    /// Create from local cache
    static func local(id: String, title: String, type: String,
                      currentStreak: Int = 0, longestStreak: Int = 0,
                      daysRemaining: Int? = nil, progress: Int = 0,
                      checkedIn: Bool = false, completedToday: Bool? = nil) -> AppTask {
        AppTask(
            id: id, title: title,
            type: type == "OneTime" ? .oneTime : .recurring,
            checkedIn: checkedIn, completedToday: completedToday,
            daysRemaining: daysRemaining, progress: progress,
            checkIn: nil, currentStreak: currentStreak, longestStreak: longestStreak
        )
    }

    init(id: String = "", title: String = "", type: TaskType = .recurring,
         checkedIn: Bool = false, completedToday: Bool? = nil,
         daysRemaining: Int? = nil, progress: Int = 0,
         checkIn: CheckInData? = nil, currentStreak: Int = 0, longestStreak: Int = 0) {
        self.id = id
        self.title = title
        self.type = type
        self.checkedIn = checkedIn
        self.completedToday = completedToday
        self.daysRemaining = daysRemaining
        self.progress = progress
        self.checkIn = checkIn
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        type = try c.decodeIfPresent(TaskType.self, forKey: .type) ?? .recurring
        checkIn = try c.decodeIfPresent(CheckInData.self, forKey: .checkIn)
        checkedIn = checkIn != nil
        completedToday = checkIn?.completed
        daysRemaining = try c.decodeIfPresent(Int.self, forKey: .daysRemaining)
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
    }
}

enum TaskType: String, Codable {
    case recurring = "Recurring"
    case oneTime = "OneTime"
}

struct CheckInData: Codable {
    let completed: Bool
    let note: String?
}

/// Goal detail — from GET /api/goals/{id}
struct Goal: Codable, Identifiable {
    let id: String
    let title: String
    let type: TaskType
    let deeperWhy: String?
    let currentStreak: Int?
    let longestStreak: Int?
    let frequency: String?
    let targetDate: String?
    let completedAt: String?
    let daysRemaining: Int?
    let progress: Int?
    let noteCount: Int?
    let createdAt: String
}

struct CheckIn: Codable, Identifiable {
    let id: String
    let date: String
    let completed: Bool
    let note: String?
    let createdAt: String
}
