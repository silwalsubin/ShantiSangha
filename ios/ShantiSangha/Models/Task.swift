import Foundation

/// Mirrors frontend/src/types/index.ts — Task interface
struct AppTask: Codable, Identifiable {
    let id: String
    let title: String
    let type: TaskType
    var checkedIn: Bool
    var completedToday: Bool?
    var daysRemaining: Int?
    var progress: Int
    var checkIn: CheckInData?

    // Internal — not from API, computed locally
    var feedbackMessage: String?
    var saving: Bool = false

    // Streak data from /goals/today
    var currentStreak: Int = 0
    var longestStreak: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, title, type, checkedIn, completedToday, daysRemaining, progress, checkIn
        case currentStreak, longestStreak
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
