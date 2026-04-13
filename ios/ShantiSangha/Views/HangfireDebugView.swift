import SwiftUI

/// Temporary debug view to inspect Hangfire job status from the iOS app.
/// Accessible from Settings page.
struct HangfireDebugView: View {
    @State private var loading = true
    @State private var error: String?
    @State private var stats: HangfireStats?
    @State private var recentSucceeded: [JobEntry] = []
    @State private var recentFailed: [FailedJobEntry] = []
    @State private var processing: [JobEntry] = []
    @State private var queues: [QueueEntry] = []
    @State private var triggeringMantra = false
    @State private var triggerResult: String?
    @State private var testingPush = false
    @State private var testPushResult: String?

    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Stats overview
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let error = error {
                    errorCard(error)
                } else if let stats = stats {
                    statsCard(stats)
                    queuesCard
                    processingCard
                    succeededCard
                    failedCard
                }

                // Actions
                actionsCard

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Hangfire Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await fetchStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .task { await fetchStatus() }
    }

    // MARK: - Stats card

    private func statsCard(_ stats: HangfireStats) -> some View {
        card(title: "OVERVIEW") {
            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 12) {
                statBadge("Enqueued", value: stats.enqueued, color: .sacredGold)
                statBadge("Processing", value: stats.processing, color: .sacredGold)
                statBadge("Succeeded", value: stats.succeeded, color: .sacredGreen)
                statBadge("Failed", value: stats.failed, color: .sacredRed)
                statBadge("Scheduled", value: stats.scheduled, color: .sacredMuted)
                statBadge("Deleted", value: stats.deleted, color: .sacredMuted)
                statBadge("Servers", value: stats.servers, color: .sacredGreen)
                statBadge("Recurring", value: stats.recurring, color: .sacredMuted)
            }
        }
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

    // MARK: - Queues

    private var queuesCard: some View {
        card(title: "QUEUES") {
            if queues.isEmpty {
                Text("No queues")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            } else {
                ForEach(queues, id: \.name) { q in
                    HStack {
                        Text(q.name)
                            .font(.sacredSmallMedium)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Text("\(q.length) pending")
                            .font(.sacredSmall)
                            .foregroundColor(q.length > 0 ? .sacredGold : .sacredMuted)
                    }
                }
            }
        }
    }

    // MARK: - Processing

    private var processingCard: some View {
        card(title: "PROCESSING") {
            if processing.isEmpty {
                Text("No jobs running")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            } else {
                ForEach(processing, id: \.key) { job in
                    jobRow(type: job.typeName, method: job.methodName, detail: "Started \(job.startedAt ?? "")")
                }
            }
        }
    }

    // MARK: - Succeeded

    private var succeededCard: some View {
        card(title: "RECENT SUCCEEDED") {
            if recentSucceeded.isEmpty {
                Text("No recent jobs")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            } else {
                ForEach(recentSucceeded, id: \.key) { job in
                    jobRow(
                        type: job.typeName,
                        method: job.methodName,
                        detail: job.duration.map { "\(Int($0))ms" } ?? "",
                        color: .sacredGreen
                    )
                }
            }
        }
    }

    // MARK: - Failed

    private var failedCard: some View {
        card(title: "RECENT FAILED") {
            if recentFailed.isEmpty {
                Text("No failures")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGreen)
            } else {
                ForEach(recentFailed, id: \.key) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        jobRow(type: job.typeName, method: job.methodName, detail: job.failedAt ?? "", color: .sacredRed)
                        if let reason = job.reason {
                            Text(reason)
                                .font(.system(size: 9, design: .serif))
                                .foregroundColor(.sacredRed.opacity(0.7))
                                .lineLimit(2)
                        }
                        if let ex = job.exceptionMessage {
                            Text(ex)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.sacredMuted)
                                .lineLimit(3)
                        }
                    }
                    if job.key != recentFailed.last?.key {
                        Divider().padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        card(title: "TEST ACTIONS") {
            Button {
                Task { await triggerMantraJob() }
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.sacredSmall)
                    Text("Trigger Mantra Generation")
                        .font(.sacredSmallMedium)
                    Spacer()
                    if triggeringMantra {
                        ProgressView().tint(.sacredGold)
                    }
                }
                .foregroundColor(.sacredGold)
            }
            .disabled(triggeringMantra)

            if let result = triggerResult {
                Text(result)
                    .font(.system(size: 10, design: .serif))
                    .foregroundColor(.sacredGreen)
            }

            Divider().padding(.vertical, 4)

            Button {
                Task { await testDirectPush() }
            } label: {
                HStack {
                    Image(systemName: "bell.badge")
                        .font(.sacredSmall)
                    Text("Test Direct Push (visible notification)")
                        .font(.sacredSmallMedium)
                    Spacer()
                    if testingPush {
                        ProgressView().tint(.sacredGold)
                    }
                }
                .foregroundColor(.sacredGold)
            }
            .disabled(testingPush)

            if let pushResult = testPushResult {
                Text(pushResult)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.sacredMuted)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Helpers

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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
    }

    private func jobRow(type: String?, method: String?, detail: String, color: Color = .sacredText) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(type ?? "Unknown")
                    .font(.sacredSmallMedium)
                    .foregroundColor(color)
                if let method = method {
                    Text(method)
                        .font(.system(size: 9, design: .serif))
                        .foregroundColor(.sacredMuted)
                }
            }
            Spacer()
            Text(detail)
                .font(.system(size: 9, design: .serif))
                .foregroundColor(.sacredMuted)
        }
    }

    private func errorCard(_ message: String) -> some View {
        card(title: "ERROR") {
            Text(message)
                .font(.sacredSmall)
                .foregroundColor(.sacredRed)
            Button {
                Task { await fetchStatus() }
            } label: {
                Text("Retry")
                    .font(.sacredSmallMedium)
                    .foregroundColor(.sacredGold)
            }
        }
    }

    // MARK: - API

    private func fetchStatus() async {
        loading = true
        error = nil
        do {
            let response: HangfireResponse = try await api.get("/debug/hangfire")
            stats = response.stats
            recentSucceeded = response.recentSucceeded
            recentFailed = response.recentFailed
            processing = response.processing
            queues = response.queues
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func triggerMantraJob() async {
        triggeringMantra = true
        triggerResult = nil
        do {
            let result: TriggerResult = try await api.post("/debug/hangfire/test-mantra")
            triggerResult = "Triggered \(result.triggered)"
            // Refresh stats after a short delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await fetchStatus()
        } catch {
            triggerResult = "Error: \(error.localizedDescription)"
        }
        triggeringMantra = false
    }

    private func testDirectPush() async {
        testingPush = true
        testPushResult = nil
        do {
            let result: TestPushResult = try await api.post("/debug/hangfire/test-push")
            var lines = ["Tokens: \(result.tokenCount)"]
            if let dryRun = result.dryRunCheck {
                lines.append("DryRun: \(dryRun)")
            }
            for r in result.results {
                var parts = ["\(r.status)"]
                if let code = r.errorCode { parts.append("code=\(code)") }
                if let http = r.httpStatus { parts.append("http=\(http)") }
                if let mid = r.messageId { parts.append("id=\(mid)") }
                if let err = r.error { parts.append(err) }
                if let prefix = r.tokenPrefix { parts.append("token=\(prefix)") }
                if let updated = r.updatedAt { parts.append("updated=\(updated)") }
                lines.append(parts.joined(separator: "\n  "))
            }
            testPushResult = lines.joined(separator: "\n")
        } catch {
            testPushResult = "Error: \(error.localizedDescription)"
        }
        testingPush = false
    }
}

// MARK: - Response models

private struct HangfireResponse: Codable {
    let stats: HangfireStats
    let queues: [QueueEntry]
    let recentSucceeded: [JobEntry]
    let recentFailed: [FailedJobEntry]
    let processing: [JobEntry]
}

private struct HangfireStats: Codable {
    let enqueued: Int
    let scheduled: Int
    let processing: Int
    let succeeded: Int
    let failed: Int
    let deleted: Int
    let servers: Int
    let recurring: Int
}

private struct QueueEntry: Codable {
    let name: String
    let length: Int
    let fetched: Int?
}

private struct JobEntry: Codable {
    let key: String
    let typeName: String?
    let methodName: String?
    let succeededAt: String?
    let startedAt: String?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case key
        case typeName = "name"
        case methodName
        case succeededAt, startedAt, duration
    }
}

private struct FailedJobEntry: Codable {
    let key: String
    let typeName: String?
    let methodName: String?
    let reason: String?
    let failedAt: String?
    let exceptionMessage: String?

    enum CodingKeys: String, CodingKey {
        case key
        case typeName = "name"
        case methodName, reason, failedAt, exceptionMessage
    }
}

private struct TriggerResult: Codable {
    let triggered: String
    let userId: String
}

private struct TestPushResult: Codable {
    let tokenCount: Int
    let dryRunCheck: String?
    let results: [PushSendResult]
}

private struct PushSendResult: Codable {
    let status: String
    let messageId: String?
    let error: String?
    let errorCode: String?
    let httpStatus: String?
    let tokenPrefix: String?
    let updatedAt: String?
}
