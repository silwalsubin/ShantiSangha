import Foundation

struct ChartBar: Codable, Identifiable, Hashable {
    let date: String     // "yyyy-MM-dd"
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int

    var id: String { date }

    var parsedDate: Date {
        ChartBar.dateFormatter.date(from: date) ?? .distantPast
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct ChartAggregates: Codable, Hashable {
    let currentPrice: Double
    let previousClose: Double?
    let weekHigh52: Double?
    let weekLow52: Double?
    let allTimeHigh: Double
    let allTimeLow: Double
    let firstDate: String
    let latestDate: String
}

struct ChartHistory: Codable, Hashable {
    let ticker: String
    let period: String
    let bars: [ChartBar]
    let aggregates: ChartAggregates?
}

enum ChartRange: String, CaseIterable, Identifiable {
    case oneMonth = "1mo"
    case sixMonth = "6mo"
    case ytd = "ytd"
    case oneYear = "1y"
    case fiveYear = "5y"
    case max = "max"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMonth: return "1M"
        case .sixMonth: return "6M"
        case .ytd: return "YTD"
        case .oneYear: return "1Y"
        case .fiveYear: return "5Y"
        case .max: return "All"
        }
    }
}
