import SwiftUI

struct LogsView: View {
    @ObservedObject private var logger = AppLogger.shared
    @ObservedObject private var syncStatus = SyncStatus.shared
    @State private var filterLevel: AppLogger.LogEntry.Level? = nil

    var filteredEntries: [AppLogger.LogEntry] {
        let entries = filterLevel == nil ? logger.entries : logger.entries.filter { $0.level == filterLevel }
        return entries.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sync status bar
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncStatus.syncing ? Color.sacredGold : syncStatus.pendingCount > 0 ? Color.sacredRed : Color.sacredGreen)
                        .frame(width: 8, height: 8)
                    Text(syncStatus.syncing ? "Syncing..." : syncStatus.pendingCount > 0 ? "\(syncStatus.pendingCount) pending" : "Synced")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredText)
                }
                Spacer()
                Text("\(logger.entries.count) logs")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sacredBgCard)

            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", level: nil)
                    filterChip("Errors", level: .error)
                    filterChip("Warnings", level: .warn)
                    filterChip("Info", level: .info)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Log entries
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.sacredHero)
                        .foregroundColor(.sacredMutedLight)
                    Text("No logs yet")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                        }
                    }
                }
            }
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    logger.clear()
                }
                .font(.sacredSmall)
                .foregroundColor(.sacredGold)
            }
        }
    }

    private func logRow(_ entry: AppLogger.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Level indicator
            Circle()
                .fill(colorForLevel(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.timeString)
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                    Text(entry.category)
                        .font(.sacredMicroBold)
                        .foregroundColor(.sacredLabel)
                        .textCase(.uppercase)
                }
                Text(entry.message)
                    .font(.sacredSmall)
                    .foregroundColor(entry.level == .error ? .sacredRed : .sacredText)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(entry.level == .error ? Color.sacredRed.opacity(0.04) : Color.clear)
    }

    private func filterChip(_ label: String, level: AppLogger.LogEntry.Level?) -> some View {
        Button { filterLevel = level } label: {
            Text(label)
                .font(.sacredSmallSemibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(filterLevel == level ? Color.sacredGold.opacity(0.1) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(filterLevel == level ? Color.sacredGold : Color.sacredMuted.opacity(0.15)))
                )
                .foregroundColor(filterLevel == level ? .sacredGold : .sacredTextSecondary)
        }
    }

    private func colorForLevel(_ level: AppLogger.LogEntry.Level) -> Color {
        switch level {
        case .info: return .sacredGreen
        case .warn: return .sacredGold
        case .error: return .sacredRed
        }
    }
}
