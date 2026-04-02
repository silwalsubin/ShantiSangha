import Foundation

/// In-memory log store for on-device debugging.
/// Captures sync events, API errors, and app lifecycle events.
@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published var entries: [LogEntry] = []
    private let maxEntries = 200

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let category: String
        let message: String

        enum Level: String {
            case info = "INFO"
            case warn = "WARN"
            case error = "ERROR"
        }

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: timestamp)
        }
    }

    func info(_ category: String, _ message: String) {
        append(.info, category, message)
    }

    func warn(_ category: String, _ message: String) {
        append(.warn, category, message)
    }

    func error(_ category: String, _ message: String) {
        append(.error, category, message)
    }

    func clear() {
        entries.removeAll()
    }

    private func append(_ level: LogEntry.Level, _ category: String, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        // Also print to Xcode console
        print("[\(level.rawValue)] [\(category)] \(message)")
    }
}
