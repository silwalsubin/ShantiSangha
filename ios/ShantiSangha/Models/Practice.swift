import Foundation

/// Mirrors backend `PracticeResponse`. The recurring practice — daily intention
/// with streak tracking. (Was `AppTask`/recurring goal before the OneTime split.)
struct Practice: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var frequency: String?
    var frequencyTarget: Int?
    var createdAt: String?
    var currentStreak: Int
    var longestStreak: Int
    var checkIn: CheckInData?

    // View-derived
    var checkedIn: Bool
    var completedToday: Bool?

    // Internal — not from API, computed locally
    var saving: Bool = false
    var hasPendingChanges: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, frequency, frequencyTarget, createdAt
        case currentStreak, longestStreak, checkIn
    }

    /// Create from local cache
    static func local(id: String, title: String,
                      currentStreak: Int = 0, longestStreak: Int = 0,
                      checkedIn: Bool = false, completedToday: Bool? = nil) -> Practice {
        Practice(
            id: id, title: title,
            frequency: nil, frequencyTarget: nil, createdAt: nil,
            currentStreak: currentStreak, longestStreak: longestStreak,
            checkIn: nil,
            checkedIn: checkedIn, completedToday: completedToday
        )
    }

    init(id: String = "", title: String = "",
         frequency: String? = nil, frequencyTarget: Int? = nil,
         createdAt: String? = nil,
         currentStreak: Int = 0, longestStreak: Int = 0,
         checkIn: CheckInData? = nil,
         checkedIn: Bool = false, completedToday: Bool? = nil) {
        self.id = id
        self.title = title
        self.frequency = frequency
        self.frequencyTarget = frequencyTarget
        self.createdAt = createdAt
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.checkIn = checkIn
        self.checkedIn = checkedIn
        self.completedToday = completedToday
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency)
        frequencyTarget = try c.decodeIfPresent(Int.self, forKey: .frequencyTarget)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        checkIn = try c.decodeIfPresent(CheckInData.self, forKey: .checkIn)
        checkedIn = checkIn != nil
        completedToday = checkIn?.completed
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try c.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
    }
}

struct CheckInData: Codable, Equatable {
    let completed: Bool
    let note: String?
}

/// Practice detail — from GET /api/practices/{id}
struct PracticeDetail: Codable, Identifiable {
    let id: String
    let title: String
    let deeperWhy: String?
    let currentStreak: Int?
    let longestStreak: Int?
    let frequency: String?
    let frequencyTarget: Int?
    let createdAt: String
}

struct PracticeCheckIn: Codable, Identifiable {
    let id: String
    let date: String
    let completed: Bool
    let note: String?
}

struct CheckIn: Codable, Identifiable {
    let id: String
    let date: String
    let completed: Bool
    let note: String?
    let createdAt: String
}

struct PracticeActivityItem: Codable, Identifiable {
    let id: String
    let action: String   // Created, Completed, Skipped, Undone
    let detail: String?
    let createdAt: String
}
