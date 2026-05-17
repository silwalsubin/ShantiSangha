import SwiftUI

/// Dev-only inspector for self-reported agent feedback. The in-app agent
/// quietly calls `report_feedback` when it notices friction, an improvement
/// idea, or a noteworthy observation; this view lists those entries.
/// Reachable from the DEBUG section of SettingsView. The server side is
/// also gated to the maintainer's email, so non-dev accounts cannot read
/// these regardless of how they reach this screen.
struct AgentFeedbackView: View {
    @State private var loading = true
    @State private var error: String?
    @State private var entries: [AgentFeedbackEntry] = []
    @State private var typeFilter: TypeFilter = .all
    @State private var severityFilter: SeverityFilter = .all
    @State private var expandedId: String?

    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading && entries.isEmpty {
                    ProgressView()
                        .tint(.sacredGold)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error, entries.isEmpty {
                    errorCard(error)
                } else {
                    overviewCard
                    filtersCard
                    if filtered.isEmpty {
                        emptyCard
                    } else {
                        entriesCard
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .sacredBackground()
        .navigationTitle("Agent Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await fetch() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .refreshable {
            await Task { await fetch() }.value
        }
        .task { await fetch() }
    }

    // MARK: - Cards

    private var overviewCard: some View {
        card(title: "OVERVIEW") {
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 12) {
                statBadge("Issues", value: count(of: .issue), color: .sacredRed)
                statBadge("Ideas", value: count(of: .improvement), color: .sacredGold)
                statBadge("Notes", value: count(of: .observation), color: .sacredMuted)
            }
            Divider().background(Color.sacredGold.opacity(0.12)).padding(.vertical, 6)
            HStack(spacing: 16) {
                statBadge("High", value: countSeverity(.high), color: .sacredRed)
                statBadge("Medium", value: countSeverity(.medium), color: .sacredGold)
                statBadge("Low", value: countSeverity(.low), color: .sacredMuted)
            }
        }
    }

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FILTER")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)

            Picker("Type", selection: $typeFilter) {
                ForEach(TypeFilter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)

            Picker("Severity", selection: $severityFilter) {
                ForEach(SeverityFilter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxCardChrome()
    }

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filtered) { entry in
                entryRow(entry)
                if entry.id != filtered.last?.id {
                    Divider()
                        .background(Color.sacredGold.opacity(0.12))
                        .padding(.horizontal, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxCardChrome()
    }

    private var emptyCard: some View {
        card(title: "NOTHING YET") {
            Text(entries.isEmpty
                ? "The agent hasn't recorded any feedback. Try a conversation that nudges it — an ambiguous reminder, an unsupported request — and pull to refresh."
                : "No entries match the current filters."
            )
            .font(.sacredSmall)
            .foregroundColor(.sacredMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ message: String) -> some View {
        card(title: "ERROR") {
            Text(message)
                .font(.sacredSmall)
                .foregroundColor(.sacredRed)
            Button {
                Task { await fetch() }
            } label: {
                Text("Retry")
                    .font(.sacredSmallMedium)
                    .foregroundColor(.sacredGold)
            }
        }
    }

    // MARK: - Entry row

    @ViewBuilder
    private func entryRow(_ entry: AgentFeedbackEntry) -> some View {
        let isExpanded = expandedId == entry.id

        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                expandedId = isExpanded ? nil : entry.id
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    typeBadge(entry.typeEnum)
                    severityBadge(entry.severityEnum)
                    Spacer()
                    Text(relativeDate(entry.createdAt))
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
                Text(entry.title)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        labelledBlock("Context", entry.context)
                        if let suggestion = entry.suggestion, !suggestion.isEmpty {
                            labelledBlock("Suggestion", suggestion)
                        }
                        if let triggeringMessageId = entry.triggeringMessageId {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.sacredMicro)
                                    .foregroundColor(.sacredMuted)
                                Text(triggeringMessageId)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.sacredMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func labelledBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.sacredSectionLabel)
                .tracking(2)
                .foregroundColor(.sacredLabel)
            Text(value)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Badges

    private func typeBadge(_ type: FeedbackType) -> some View {
        let (label, color): (String, Color) = {
            switch type {
            case .issue: return ("Issue", .sacredRed)
            case .improvement: return ("Idea", .sacredGold)
            case .observation: return ("Note", .sacredMuted)
            case .unknown: return ("Other", .sacredMuted)
            }
        }()
        return Text(label.uppercased())
            .font(.sacredMicroBold)
            .tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.1)))
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func severityBadge(_ severity: FeedbackSeverity) -> some View {
        let (label, color): (String, Color) = {
            switch severity {
            case .low: return ("Low", .sacredMuted)
            case .medium: return ("Med", .sacredGold)
            case .high: return ("High", .sacredRed)
            case .unknown: return ("?", .sacredMuted)
            }
        }()
        return Text(label.uppercased())
            .font(.sacredMicroBold)
            .tracking(1.5)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.06)))
    }

    // MARK: - Helpers

    private var filtered: [AgentFeedbackEntry] {
        entries.filter { e in
            if let t = typeFilter.match, e.typeEnum != t { return false }
            if let s = severityFilter.match, e.severityEnum != s { return false }
            return true
        }
    }

    private func count(of type: FeedbackType) -> Int {
        entries.filter { $0.typeEnum == type }.count
    }

    private func countSeverity(_ severity: FeedbackSeverity) -> Int {
        entries.filter { $0.severityEnum == severity }.count
    }

    private func relativeDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: raw) ?? isoBasic.date(from: raw) else { return raw }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func statBadge(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.sacredBodyBold)
                .foregroundColor(value > 0 ? color : .sacredMuted.opacity(0.5))
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .serif))
                .foregroundColor(.sacredMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxCardChrome()
    }

    // MARK: - API

    private func fetch() async {
        loading = true
        error = nil
        do {
            let result: [AgentFeedbackEntry] = try await api.get("/agent-feedback")
            entries = result
        } catch is CancellationError {
            // refreshable cancellation — ignore
        } catch let err as URLError where err.code == .cancelled {
            // session cancellation — ignore
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Filter enums

private enum TypeFilter: String, CaseIterable {
    case all, issue, improvement, observation
    var label: String {
        switch self {
        case .all: return "All"
        case .issue: return "Issues"
        case .improvement: return "Ideas"
        case .observation: return "Notes"
        }
    }
    var match: FeedbackType? {
        switch self {
        case .all: return nil
        case .issue: return .issue
        case .improvement: return .improvement
        case .observation: return .observation
        }
    }
}

private enum SeverityFilter: String, CaseIterable {
    case all, low, medium, high
    var label: String {
        switch self {
        case .all: return "All"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        }
    }
    var match: FeedbackSeverity? {
        switch self {
        case .all: return nil
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

// MARK: - Model

enum FeedbackType: String { case issue, improvement, observation, unknown }
enum FeedbackSeverity: String { case low, medium, high, unknown }

struct AgentFeedbackEntry: Codable, Identifiable {
    let id: String
    let userId: String
    let type: String
    let severity: String
    let title: String
    let context: String
    let suggestion: String?
    let triggeringMessageId: String?
    let createdAt: String

    var typeEnum: FeedbackType { FeedbackType(rawValue: type.lowercased()) ?? .unknown }
    var severityEnum: FeedbackSeverity { FeedbackSeverity(rawValue: severity.lowercased()) ?? .unknown }
}
