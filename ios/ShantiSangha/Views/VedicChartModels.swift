import Foundation

// MARK: - Chart response models

struct VedicChart: Decodable {
    let available: Bool
    let reason: String?
    let birth: Birth?
    let nakshatra: NakshatraAttrs?
    let lagna: Lagna?
    let planets: [Planet]?
    let dasha: DashaInfo?

    struct Birth: Decodable {
        let date: String
        let time: String?
        let place: String?
        let hasCoordinates: Bool
    }
}

struct Interpretation: Decodable {
    let content: String
    let source: String
    let polarity: String
    let themes: [String]
}

struct NakshatraAttrs: Decodable {
    let name: String
    let quality: String
    let pada: Int
    let yoni: String
    let nadi: String
    let gana: String
    let deity: String
    let lord: String
    let interpretation: Interpretation?
}

struct Lagna: Decodable {
    let rashi: String
    let degree: Double
    let nakshatra: String
    let nakshatraQuality: String
    let pada: Int
    let interpretation: Interpretation?
}

struct Planet: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let rashi: String
    let degree: Double
    let nakshatra: String
    let nakshatraQuality: String
    let pada: Int
    let house: Int?
    /// deep_exalted | exalted | moolatrikona | own_sign | debilitated | neutral
    let dignity: String
    let drekkanaRashi: String?
    let chaturthamsaRashi: String?
    let saptamsaRashi: String?
    let navamsaRashi: String?
    let dasamsaRashi: String?
    let dvadasamsaRashi: String?
    let shodasamsaRashi: String?
    let vimsamsaRashi: String?
    let chaturvimsamsaRashi: String?
    /// True when the planet's D1 sign == D9 sign — classically very strong
    let vargottama: Bool?
    let retrograde: Bool?
    let combust: Bool?
    let sandhi: Bool?
    let interpretation: Interpretation?
}

struct DashaInfo: Decodable {
    let mahadasha: String
    let antardasha: String
    let antardashaStart: String
    let antardashaEnd: String
    let mahadashaStart: String
    let mahadashaEnd: String
    let interpretation: Interpretation?
}

// MARK: - Chart reading (GET /api/jyotish/reading)

/// Response from GET /api/jyotish/reading.
struct ChartReadingResponse: Decodable {
    let sections: [String: String]
    let generatedAt: String
    let isComplete: Bool
}

/// The six sections of the pre-composed chart reading, in display order.
/// Keys match the backend's ChartReadingSection constants.
enum ChartReadingSectionKey {
    static let ordered: [(key: String, title: String)] = [
        ("essence", "Your essence"),
        ("emotional_nature", "Your emotional nature"),
        ("mind_and_voice", "Your mind and voice"),
        ("drive_and_action", "Your drive and action"),
        ("path_of_growth", "Your path of growth"),
        ("season", "This season of your life"),
    ]
}

// MARK: - Profile fetch (for birth details on the chart page)

struct MeResponse: Decodable {
    let profile: MeProfileData?
}

struct MeProfileData: Decodable {
    let birthDate: String?
    let birthTime: String?
    let birthPlace: String?
}
