import Foundation

/// Spiritual feedback generator — matches frontend useGoals composable.
enum FeedbackService {
    static func generate(currentStreak: Int, longestStreak: Int, completed: Bool) -> String {
        let streak = completed ? currentStreak + 1 : 0

        if completed {
            if streak == 1 {
                return ["A single step. That is all it ever takes.",
                        "The seed has been planted. Trust the process.",
                        "Today you chose yourself. That matters."].randomElement()!
            }
            if streak == 3 { return "Three days. A pattern is forming. Stay with it." }
            if streak == 7 { return "One full week. Your discipline is becoming devotion." }
            if streak == 14 { return "Two weeks of showing up. This is no longer effort — it is who you are becoming." }
            if streak == 21 { return "Twenty-one days. What began as intention is now dharma." }
            if streak == 30 { return "A full month. You have proven something to yourself that no one can take away." }
            if streak > 30 && streak % 10 == 0 { return "\(streak) days. Your consistency speaks louder than any intention ever could." }
            if streak > longestStreak && longestStreak > 0 { return "A new personal record — \(streak) days. You have surpassed your past self." }
            return ["\(streak) days and counting. Keep showing up.",
                    "Another day honored. The practice deepens.",
                    "Consistency is the quiet form of courage.",
                    "You showed up again. That is the whole practice."].randomElement()!
        } else {
            if longestStreak >= 7 {
                return "A pause is not a failure. Even the river rests in still pools before flowing on."
            }
            return ["Rest is also practice. Tomorrow is a new beginning.",
                    "Not today — and that is honest. Honesty is the first discipline.",
                    "The path does not disappear because you paused. It waits.",
                    "Be gentle with yourself. Even the moon wanes before it grows full again."].randomElement()!
        }
    }
}
