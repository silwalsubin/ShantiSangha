import Foundation

/// A single line of wisdom shown on the once-a-day blessing splash.
struct DailyQuote: Identifiable, Equatable {
    let id: Int
    let text: String
    let source: String
}

/// Owns the daily blessing's content and its once-per-day gate.
///
/// Quotes are bundled locally on purpose: the splash must paint the
/// instant the app opens, with no spinner and no network wait. The
/// selection is deterministic per calendar day, so it stays stable if
/// the splash is re-rendered within the day and advances by one each
/// day — never the same two mornings running.
///
/// This is intentionally NOT the old AI daily-reflection feature: it's a
/// fixed, curated set of wisdom, not generated per user.
enum DailyBlessing {
    /// Curated, on-mission wisdom — stillness, discipline, presence,
    /// letting go. Gentle and non-preachy; attributions kept to
    /// well-known sources or the tradition itself.
    static let quotes: [DailyQuote] = [
        .init(id: 0,  text: "You have the right to your work, but never to the fruit of your work.", source: "Bhagavad Gita"),
        .init(id: 1,  text: "The mind is everything. What you think, you become.", source: "The Buddha"),
        .init(id: 2,  text: "When meditation is mastered, the mind is unwavering, like the flame of a lamp in a windless place.", source: "Bhagavad Gita"),
        .init(id: 3,  text: "When you let go of what you are, you become what you might be.", source: "Lao Tzu"),
        .init(id: 4,  text: "Peace comes from within. Do not seek it without.", source: "The Buddha"),
        .init(id: 5,  text: "Arise, awake, and stop not until the goal is reached.", source: "Swami Vivekananda"),
        .init(id: 6,  text: "Breathing in, I calm my body. Breathing out, I smile.", source: "Thich Nhat Hanh"),
        .init(id: 7,  text: "Yoga is the stilling of the fluctuations of the mind.", source: "Patanjali, Yoga Sutras"),
        .init(id: 8,  text: "What you seek is seeking you.", source: "Rumi"),
        .init(id: 9,  text: "The wound is the place where the light enters you.", source: "Rumi"),
        .init(id: 10, text: "He who knows others is wise; he who knows himself is enlightened.", source: "Lao Tzu"),
        .init(id: 11, text: "Do not dwell in the past, do not dream of the future; concentrate the mind on the present moment.", source: "The Buddha"),
        .init(id: 12, text: "From the unreal, lead me to the real. From darkness, lead me to light.", source: "Brihadaranyaka Upanishad"),
        .init(id: 13, text: "The soul is neither born, nor does it ever die.", source: "Bhagavad Gita"),
        .init(id: 14, text: "Silence is the language of the divine; all else is poor translation.", source: "Rumi"),
        .init(id: 15, text: "The quieter you become, the more you are able to hear.", source: "Rumi"),
        .init(id: 16, text: "Nature does not hurry, yet everything is accomplished.", source: "Tao Te Ching"),
        .init(id: 17, text: "Drop by drop is the water pot filled; little by little the wise grow whole.", source: "The Dhammapada"),
        .init(id: 18, text: "The whole secret of existence is to have no fear.", source: "Swami Vivekananda"),
        .init(id: 19, text: "Set your heart on doing good. Do it over and over, and you will be filled with joy.", source: "The Buddha"),
        .init(id: 20, text: "When the mind is calm, how clearly, how beautifully you perceive everything.", source: "Paramahansa Yogananda"),
        .init(id: 21, text: "Be still. Stillness reveals the secrets of eternity.", source: "Lao Tzu"),
    ]

    /// The quote for a given day. Stable within the day, advances daily.
    static func quote(for date: Date = Date(), calendar: Calendar = .current) -> DailyQuote {
        let day = daysSinceReference(date, calendar: calendar)
        let count = quotes.count
        let index = ((day % count) + count) % count
        return quotes[index]
    }

    private static func daysSinceReference(_ date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let reference = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: reference, to: start).day ?? 0
    }

    // MARK: - Once-per-day gate

    private static let lastShownKey = "dailyBlessing.lastShownDay"

    /// True when the blessing hasn't been shown yet today (local day).
    /// Stored as a day stamp in `UserDefaults` so it survives cold
    /// launches — the blessing is a once-a-morning moment, not a
    /// per-session one.
    static func shouldShow(now: Date = Date(), calendar: Calendar = .current,
                           defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: lastShownKey) != dayStamp(now, calendar: calendar)
    }

    static func markShown(now: Date = Date(), calendar: Calendar = .current,
                          defaults: UserDefaults = .standard) {
        defaults.set(dayStamp(now, calendar: calendar), forKey: lastShownKey)
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
