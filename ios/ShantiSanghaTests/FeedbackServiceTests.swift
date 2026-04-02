import XCTest
@testable import ShantiSangha

final class FeedbackServiceTests: XCTestCase {

    // MARK: - Completed streaks

    func testStreak1_returnsFirstDayMessage() {
        let msg = FeedbackService.generate(currentStreak: 0, longestStreak: 0, completed: true)
        let expected = [
            "A single step. That is all it ever takes.",
            "The seed has been planted. Trust the process.",
            "Today you chose yourself. That matters."
        ]
        XCTAssertTrue(expected.contains(msg), "Unexpected first day message: \(msg)")
    }

    func testStreak3_returnsPatternMessage() {
        let msg = FeedbackService.generate(currentStreak: 2, longestStreak: 0, completed: true)
        XCTAssertEqual(msg, "Three days. A pattern is forming. Stay with it.")
    }

    func testStreak7_returnsWeekMessage() {
        let msg = FeedbackService.generate(currentStreak: 6, longestStreak: 0, completed: true)
        XCTAssertEqual(msg, "One full week. Your discipline is becoming devotion.")
    }

    func testStreak14_returnsTwoWeekMessage() {
        let msg = FeedbackService.generate(currentStreak: 13, longestStreak: 0, completed: true)
        XCTAssertEqual(msg, "Two weeks of showing up. This is no longer effort — it is who you are becoming.")
    }

    func testStreak21_returnsDharmaMessage() {
        let msg = FeedbackService.generate(currentStreak: 20, longestStreak: 0, completed: true)
        XCTAssertEqual(msg, "Twenty-one days. What began as intention is now dharma.")
    }

    func testStreak30_returnsMonthMessage() {
        let msg = FeedbackService.generate(currentStreak: 29, longestStreak: 0, completed: true)
        XCTAssertEqual(msg, "A full month. You have proven something to yourself that no one can take away.")
    }

    func testStreak40_returnsConsistencyMessage() {
        let msg = FeedbackService.generate(currentStreak: 39, longestStreak: 50, completed: true)
        XCTAssertEqual(msg, "40 days. Your consistency speaks louder than any intention ever could.")
    }

    func testNewPersonalRecord_returnsRecordMessage() {
        let msg = FeedbackService.generate(currentStreak: 10, longestStreak: 10, completed: true)
        XCTAssertEqual(msg, "A new personal record — 11 days. You have surpassed your past self.")
    }

    func testGenericCompleted_returnsEncouragement() {
        let msg = FeedbackService.generate(currentStreak: 4, longestStreak: 20, completed: true)
        let expected = [
            "5 days and counting. Keep showing up.",
            "Another day honored. The practice deepens.",
            "Consistency is the quiet form of courage.",
            "You showed up again. That is the whole practice."
        ]
        XCTAssertTrue(expected.contains(msg), "Unexpected generic message: \(msg)")
    }

    // MARK: - Skipped

    func testSkipped_withLongStreak_returnsPauseMessage() {
        let msg = FeedbackService.generate(currentStreak: 10, longestStreak: 10, completed: false)
        XCTAssertEqual(msg, "A pause is not a failure. Even the river rests in still pools before flowing on.")
    }

    func testSkipped_withShortStreak_returnsGentle() {
        let msg = FeedbackService.generate(currentStreak: 2, longestStreak: 3, completed: false)
        let expected = [
            "Rest is also practice. Tomorrow is a new beginning.",
            "Not today — and that is honest. Honesty is the first discipline.",
            "The path does not disappear because you paused. It waits.",
            "Be gentle with yourself. Even the moon wanes before it grows full again."
        ]
        XCTAssertTrue(expected.contains(msg), "Unexpected skip message: \(msg)")
    }
}
