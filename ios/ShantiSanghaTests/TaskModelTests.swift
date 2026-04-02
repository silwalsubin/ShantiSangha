import XCTest
@testable import ShantiSangha

final class TaskModelTests: XCTestCase {

    // MARK: - JSON Decoding

    func testDecodeTask_fullPayload() throws {
        let json = """
        {
            "id": "abc-123",
            "title": "Exercise",
            "type": "Recurring",
            "checkIn": { "completed": true, "note": "Felt great" },
            "daysRemaining": null,
            "progress": 0,
            "currentStreak": 5,
            "longestStreak": 10
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(AppTask.self, from: json)

        XCTAssertEqual(task.id, "abc-123")
        XCTAssertEqual(task.title, "Exercise")
        XCTAssertEqual(task.type, .recurring)
        XCTAssertTrue(task.checkedIn)
        XCTAssertEqual(task.completedToday, true)
        XCTAssertEqual(task.currentStreak, 5)
        XCTAssertEqual(task.longestStreak, 10)
        XCTAssertEqual(task.checkIn?.note, "Felt great")
    }

    func testDecodeTask_minimalPayload() throws {
        let json = """
        {
            "id": "xyz",
            "title": "Meditate"
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(AppTask.self, from: json)

        XCTAssertEqual(task.id, "xyz")
        XCTAssertEqual(task.title, "Meditate")
        XCTAssertEqual(task.type, .recurring)
        XCTAssertFalse(task.checkedIn)
        XCTAssertNil(task.completedToday)
        XCTAssertEqual(task.progress, 0)
        XCTAssertEqual(task.currentStreak, 0)
        XCTAssertEqual(task.longestStreak, 0)
    }

    func testDecodeTask_oneTimeType() throws {
        let json = """
        {
            "id": "m1",
            "title": "File taxes",
            "type": "OneTime",
            "daysRemaining": 3,
            "progress": 40
        }
        """.data(using: .utf8)!

        let task = try JSONDecoder().decode(AppTask.self, from: json)

        XCTAssertEqual(task.type, .oneTime)
        XCTAssertEqual(task.daysRemaining, 3)
        XCTAssertEqual(task.progress, 40)
    }

    func testDecodeTask_checkedInDerivedFromCheckIn() throws {
        let withCheckIn = """
        { "id": "1", "title": "A", "checkIn": { "completed": false, "note": null } }
        """.data(using: .utf8)!

        let withoutCheckIn = """
        { "id": "2", "title": "B" }
        """.data(using: .utf8)!

        let taskA = try JSONDecoder().decode(AppTask.self, from: withCheckIn)
        let taskB = try JSONDecoder().decode(AppTask.self, from: withoutCheckIn)

        XCTAssertTrue(taskA.checkedIn)
        XCTAssertEqual(taskA.completedToday, false)
        XCTAssertFalse(taskB.checkedIn)
    }

    // MARK: - Local factory

    func testLocalFactory_recurring() {
        let task = AppTask.local(id: "t1", title: "Run", type: "Recurring", currentStreak: 3, longestStreak: 7)

        XCTAssertEqual(task.id, "t1")
        XCTAssertEqual(task.title, "Run")
        XCTAssertEqual(task.type, .recurring)
        XCTAssertEqual(task.currentStreak, 3)
        XCTAssertEqual(task.longestStreak, 7)
        XCTAssertFalse(task.checkedIn)
    }

    func testLocalFactory_oneTime() {
        let task = AppTask.local(id: "t2", title: "Ship v2", type: "OneTime", daysRemaining: 5, progress: 60)

        XCTAssertEqual(task.type, .oneTime)
        XCTAssertEqual(task.daysRemaining, 5)
        XCTAssertEqual(task.progress, 60)
    }

    // MARK: - TaskType

    func testTaskType_rawValues() {
        XCTAssertEqual(TaskType.recurring.rawValue, "Recurring")
        XCTAssertEqual(TaskType.oneTime.rawValue, "OneTime")
    }

    func testTaskType_decodesFromString() throws {
        let json = "\"OneTime\"".data(using: .utf8)!
        let type = try JSONDecoder().decode(TaskType.self, from: json)
        XCTAssertEqual(type, .oneTime)
    }

    // MARK: - Encoding

    func testEncodeTask_roundTrip() throws {
        let original = AppTask(id: "r1", title: "Read", type: .recurring, currentStreak: 2, longestStreak: 5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppTask.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.currentStreak, original.currentStreak)
        XCTAssertEqual(decoded.longestStreak, original.longestStreak)
    }
}
