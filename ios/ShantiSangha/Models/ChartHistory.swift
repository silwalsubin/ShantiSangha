import Foundation

struct ChartBar: Codable, Identifiable, Hashable {
    let date: String     // "yyyy-MM-dd" for daily, full ISO timestamp for intraday
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int

    var id: String { date }

    /// Parses both date-only ("yyyy-MM-dd") and full ISO 8601 timestamps.
    /// Daily bars come back as the former; intraday (1D) bars as the latter.
    var parsedDate: Date {
        if date.contains("T"), let d = ChartBar.isoFormatter.date(from: date) { return d }
        if let d = ChartBar.dateFormatter.date(from: date) { return d }
        // Fallback: ISO formatter without fractional seconds
        if let d = ChartBar.isoNoFracFormatter.date(from: date) { return d }
        return .distantPast
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoNoFracFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
    case intraday = "1d"
    case oneWeek = "1w"
    case oneMonth = "1mo"
    case threeMonth = "3mo"
    case ytd = "ytd"
    case oneYear = "1y"
    case fiveYear = "5y"
    case max = "max"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .intraday: return "1D"
        case .oneWeek: return "1W"
        case .oneMonth: return "1M"
        case .threeMonth: return "3M"
        case .ytd: return "YTD"
        case .oneYear: return "1Y"
        case .fiveYear: return "5Y"
        case .max: return "All"
        }
    }

    var isIntraday: Bool { self == .intraday }
}
