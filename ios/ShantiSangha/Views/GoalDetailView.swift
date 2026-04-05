import SwiftUI

/// Goal detail — mirrors frontend/src/pages/app/goal-detail.vue
struct GoalDetailView: View {
    let goalId: String
    @Environment(\.dismiss) private var dismiss
    @State private var goal: Goal?
    @State private var activities: [GoalActivityItem] = []
    @State private var checkIns: [GoalCheckIn] = []
    @State private var loading = true
    @State private var historyExpanded = false
    @State private var historyLoading = false
    @State private var togglingDate: String?
    @State private var selectMode = false
    @State private var selectedDates: Set<String> = []
    @State private var bulkDeleting = false
    @State private var showWhyEditor = false
    @State private var whyText = ""
    @State private var showTitleEditor = false
    @State private var titleText = ""
    @State private var nudge: String?
    @State private var showProgress = false
    @State private var progressValue: Double = 0
    @State private var navigateToDueDate = false
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let goal = goal {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Button {
                        titleText = goal.title
                        showTitleEditor = true
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: goal.type == .recurring ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                                .font(.system(size: 28))
                                .foregroundColor(.sacredGold)
                            Text(goal.title)
                                .font(.sacredHeading)
                                .foregroundColor(.sacredText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)

                    // Stats
                    if goal.type == .recurring {
                        HStack(spacing: 12) {
                            statCard(value: "\(goal.currentStreak ?? 0)", label: "Current Streak")
                            statCard(value: "\(goal.longestStreak ?? 0)", label: "Longest Streak")
                        }
                    } else {
                        HStack(spacing: 12) {
                            if let days = goal.daysRemaining {
                                statCard(
                                    value: goal.completedAt != nil ? "Done" : days < 0 ? "Overdue" : "\(days)",
                                    label: goal.completedAt != nil ? "Completed" : days < 0 ? "\(abs(days))d over" : "Days Left"
                                )
                            }
                            statCard(value: "\(goal.progress ?? 0)%", label: "Progress")
                        }

                        // Due date row — tappable
                        if let targetDate = goal.targetDate {
                            Button { navigateToDueDate = true } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .font(.sacredSmall)
                                        .foregroundColor(.sacredGold)
                                    Text("Due \(formatDate(targetDate))")
                                        .font(.sacredTextMedium)
                                        .foregroundColor(.sacredText)
                                    Spacer()
                                    Image(systemName: "pencil")
                                        .font(.sacredMicro)
                                        .foregroundColor(.sacredMuted)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // AI nudge
                    if let nudge = nudge {
                        Text(nudge)
                            .font(.sacredBody)
                            .italic()
                            .foregroundColor(.sacredText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredGold.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredGold.opacity(0.12)))
                    }

                    // Deeper Why
                    Button {
                        whyText = goal.deeperWhy ?? ""
                        showWhyEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "leaf")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredGold)
                                Text("THE DEEPER WHY")
                                    .font(.sacredSectionLabel)
                                    .tracking(3)
                                    .foregroundColor(.sacredLabel)
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.sacredMicro)
                                    .foregroundColor(.sacredMuted)
                            }
                            if let why = goal.deeperWhy, !why.isEmpty {
                                Text("\"\(why)\"")
                                    .font(.sacredBody)
                                    .italic()
                                    .foregroundColor(.sacredText)
                                    .multilineTextAlignment(.leading)
                            } else {
                                Text("Tap to add your deeper intention...")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredMuted)
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    // Daily Record (recurring) or Activity timeline (one-time)
                    if goal.type == .recurring {
                        dailyRecordSection(goal: goal)
                    } else {
                        activityTimelineSection()
                    }

                    // Progress slider (shown inline when triggered from menu)
                    if showProgress {
                        VStack(spacing: 8) {
                            Slider(value: $progressValue, in: 0...100, step: 5)
                                .tint(.sacredGold)
                            HStack {
                                Text("\(Int(progressValue))%")
                                    .font(.sacredSmallMedium)
                                    .foregroundColor(.sacredGold)
                                Spacer()
                                Button("Cancel") {
                                    showProgress = false
                                }
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                                Button("Save") {
                                    showProgress = false
                                    Task { await updateProgress(Int(progressValue)) }
                                }
                                .font(.sacredSmallSemibold)
                                .foregroundColor(.sacredGold)
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                    }

                }
                .padding(16)
            } else {
                Text("Task not found.")
                    .foregroundColor(.sacredTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .background(
            Group {
                if let goal = goal, goal.type == .oneTime {
                    NavigationLink(
                        destination: ChangeDueDateView(
                            task: AppTask(id: goal.id, title: goal.title, type: .oneTime, daysRemaining: goal.daysRemaining, progress: goal.progress ?? 0),
                            onSave: { date in Task { await updateDueDate(date) } }
                        ),
                        isActive: $navigateToDueDate
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let goal = goal {
                    Menu {
                        if goal.completedAt == nil {
                            Button {
                                Task { await markComplete() }
                            } label: {
                                Label(
                                    goal.type == .recurring ? "Complete for today" : "Complete",
                                    systemImage: "checkmark.circle"
                                )
                            }

                            Button {
                                Task { await skipForToday() }
                            } label: {
                                Label("Skip for today", systemImage: "moon.fill")
                            }

                            if goal.type == .oneTime {
                                Button {
                                    progressValue = Double(goal.progress ?? 0)
                                    showProgress = true
                                } label: {
                                    Label("Update progress", systemImage: "chart.bar.fill")
                                }

                                Button {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        navigateToDueDate = true
                                    }
                                } label: {
                                    Label("Change due date", systemImage: "calendar")
                                }
                            }
                        }

                        Button(role: .destructive) {
                            Task { await deleteGoal() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.sacredText)
                            .foregroundColor(.sacredMuted)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showTitleEditor) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("Task name", text: $titleText)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                        .multilineTextAlignment(.center)
                        .padding(16)

                    Spacer()
                }
                .background(Color.sacredBg.ignoresSafeArea())
                .navigationTitle("Rename")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTitleEditor = false }
                            .foregroundColor(.sacredMuted)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showTitleEditor = false
                            Task { await saveTitle() }
                        }
                        .foregroundColor(.sacredGold)
                        .disabled(titleText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .sheet(isPresented: $showWhyEditor) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What draws you to this task? Understanding the deeper intention behind your commitments can transform discipline into devotion.")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)

                    TextEditor(text: $whyText)
                        .font(.sacredBody)
                        .foregroundColor(.sacredText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))

                    Spacer()
                }
                .padding(16)
                .background(Color.sacredBg.ignoresSafeArea())
                .navigationTitle("The Deeper Why")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showWhyEditor = false }
                            .foregroundColor(.sacredMuted)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            showWhyEditor = false
                            Task { await saveDeeperWhy() }
                        }
                        .foregroundColor(.sacredGold)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            let g: Goal = try await api.get("/goals/\(goalId)")
            goal = g
            nudge = g.aiNudge
            checkIns = g.checkIns ?? []
        } catch {
            print("Failed to load goal: \(error)")
        }
        loading = false

        // Fetch fresh nudge in background
        Task {
            do {
                let result: NudgeResponse = try await api.get("/goals/\(goalId)/nudge")
                if let fresh = result.nudge {
                    withAnimation(.easeIn(duration: 0.3)) { nudge = fresh }
                }
            } catch {
                print("Failed to load nudge: \(error)")
            }
        }
    }

    private func markComplete() async {
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let body: [String: Any] = ["completed": true, "date": dateStr]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            let _: EmptyResponse? = try? await api.postRaw("/goals/\(goalId)/checkin", body: data)
        }
        // Reload to reflect new state
        goal = try? await api.get("/goals/\(goalId)")
    }

    private func skipForToday() async {
        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()
        let body: [String: Any] = ["completed": false, "date": dateStr]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            let _: EmptyResponse? = try? await api.postRaw("/goals/\(goalId)/checkin", body: data)
        }
        goal = try? await api.get("/goals/\(goalId)")
    }

    private func updateProgress(_ value: Int) async {
        let body: [String: Int] = ["progress": value]
        do {
            let _: EmptyResponse = try await api.patch("/goals/\(goalId)", body: body)
            goal = try await api.get("/goals/\(goalId)")
        } catch {
            print("Failed to update progress: \(error)")
        }
    }

    private func updateDueDate(_ date: String) async {
        let body: [String: String] = ["targetDate": date]
        do {
            let _: EmptyResponse = try await api.patch("/goals/\(goalId)", body: body)
            goal = try await api.get("/goals/\(goalId)")
        } catch {
            print("Failed to update due date: \(error)")
        }
    }

    private func deleteGoal() async {
        do {
            try await api.delete("/goals/\(goalId)")
            dismiss()
        } catch {
            print("Failed to delete goal: \(error)")
        }
    }

    private func saveTitle() async {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let body: [String: String] = ["title": trimmed]
            let _: EmptyResponse = try await api.patch("/goals/\(goalId)", body: body)
            goal = try await api.get("/goals/\(goalId)")
        } catch {
            print("Failed to save title: \(error)")
        }
    }

    private func saveDeeperWhy() async {
        let trimmed = whyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let body: [String: String] = ["deeperWhy": trimmed]
            let _: EmptyResponse = try await api.patch("/goals/\(goalId)", body: body)
            goal = try await api.get("/goals/\(goalId)")
        } catch {
            print("Failed to save deeper why: \(error)")
        }
    }

    private func loadHistory() async {
        historyLoading = true
        do {
            activities = try await api.get("/goals/\(goalId)/history")
        } catch {
            print("Failed to load history: \(error)")
        }
        historyLoading = false
    }

    // MARK: - Daily Record

    private struct DayEntry: Identifiable {
        let id: String  // date string
        let date: String
        let label: String
        let checkin: GoalCheckIn?
        let isToday: Bool
    }

    private func buildDayEntries() -> [DayEntry] {
        guard let goal = goal else { return [] }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d, yyyy"

        let createdDateStr = String(goal.createdAt.prefix(10))
        guard let startDate = df.date(from: createdDateStr) else { return [] }
        let today = Date()
        let todayStr = df.string(from: today)

        let checkinMap = Dictionary(
            uniqueKeysWithValues: checkIns.map { ($0.date, $0) }
        )

        var entries: [DayEntry] = []
        var cursor = Calendar.current.startOfDay(for: today)
        let start = Calendar.current.startOfDay(for: startDate)

        while cursor >= start {
            let dateStr = df.string(from: cursor)
            entries.append(DayEntry(
                id: dateStr,
                date: dateStr,
                label: displayFmt.string(from: cursor),
                checkin: checkinMap[dateStr],
                isToday: dateStr == todayStr
            ))
            cursor = Calendar.current.date(byAdding: .day, value: -1, to: cursor)!
        }

        return entries
    }

    @ViewBuilder
    private func dailyRecordSection(goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAILY RECORD")
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)
                Spacer()
                if selectMode {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectMode = false
                            selectedDates.removeAll()
                        }
                    } label: {
                        Text("Cancel")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                } else if checkIns.contains(where: { _ in true }) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectMode = true
                            selectedDates.removeAll()
                        }
                    } label: {
                        Text("Select")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredGold)
                    }
                }
            }

            let entries = buildDayEntries()
            if entries.isEmpty {
                Text("No days recorded yet.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(entries) { day in
                        Button {
                            if selectMode {
                                // Only allow selecting days that have check-ins
                                guard day.checkin != nil else { return }
                                if selectedDates.contains(day.date) {
                                    selectedDates.remove(day.date)
                                } else {
                                    selectedDates.insert(day.date)
                                }
                            } else {
                                Task { await toggleDay(day) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if selectMode {
                                    // Selection checkbox (only for days with check-ins)
                                    if day.checkin != nil {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(
                                                    selectedDates.contains(day.date)
                                                        ? Color.sacredGold
                                                        : Color.sacredMuted.opacity(0.3),
                                                    lineWidth: 1.5
                                                )
                                            if selectedDates.contains(day.date) {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.sacredGold)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .frame(width: 22, height: 22)
                                    } else {
                                        Color.clear.frame(width: 22, height: 22)
                                    }
                                }

                                // Status circle
                                ZStack {
                                    if day.checkin?.completed == true {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [.sacredGold, .sacredGoldDark],
                                                startPoint: .topLeading, endPoint: .bottomTrailing
                                            ))
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    } else if day.checkin != nil {
                                        Circle()
                                            .strokeBorder(Color.sacredMuted.opacity(0.3), lineWidth: 1)
                                        Image(systemName: "moon.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.sacredMuted.opacity(0.5))
                                    } else {
                                        Circle()
                                            .strokeBorder(Color.sacredMuted.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        Text("--")
                                            .font(.system(size: 8))
                                            .foregroundColor(.sacredMuted.opacity(0.4))
                                    }
                                }
                                .frame(width: 28, height: 28)

                                // Date label
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(day.label)
                                            .font(.sacredSmallMedium)
                                            .foregroundColor(.sacredText)
                                        if day.isToday {
                                            Text("TODAY")
                                                .font(.sacredSectionLabel)
                                                .tracking(2)
                                                .foregroundColor(.sacredGold)
                                        }
                                    }
                                    if let note = day.checkin?.note {
                                        Text(note)
                                            .font(.sacredSmall)
                                            .foregroundColor(.sacredTextSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        selectMode && selectedDates.contains(day.date)
                                            ? Color.sacredGold.opacity(0.06)
                                            : day.isToday ? Color.sacredMuted.opacity(0.06) : Color.clear
                                    )
                            )
                            .opacity(togglingDate == day.date ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(!selectMode && togglingDate != nil)
                        .disabled(selectMode && day.checkin == nil)
                    }
                }

                // Bulk delete bar
                if selectMode && !selectedDates.isEmpty {
                    Button {
                        Task { await bulkDeleteSelected() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .font(.sacredSmall)
                            Text("Remove \(selectedDates.count) \(selectedDates.count == 1 ? "entry" : "entries")")
                                .font(.sacredSmallMedium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.red.opacity(0.85))
                        )
                    }
                    .disabled(bulkDeleting)
                    .opacity(bulkDeleting ? 0.5 : 1)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func toggleDay(_ day: DayEntry) async {
        togglingDate = day.date
        defer { togglingDate = nil }

        do {
            if day.checkin != nil {
                // Remove existing check-in
                try await api.delete("/goals/\(goalId)/checkin?date=\(day.date)")
                checkIns.removeAll { $0.date == day.date }
            } else {
                // Add as completed
                let body: [String: Any] = ["completed": true, "date": day.date]
                if let data = try? JSONSerialization.data(withJSONObject: body) {
                    let result: GoalCheckIn = try await api.postRaw("/goals/\(goalId)/checkin", body: data)
                    checkIns.append(result)
                }
            }
            // Refresh goal to update streaks
            let refreshed: Goal = try await api.get("/goals/\(goalId)")
            goal = refreshed
            checkIns = refreshed.checkIns ?? []
        } catch {
            print("Failed to toggle check-in: \(error)")
        }
    }

    private func bulkDeleteSelected() async {
        bulkDeleting = true
        defer {
            bulkDeleting = false
            selectMode = false
            selectedDates.removeAll()
        }

        for date in selectedDates {
            do {
                try await api.delete("/goals/\(goalId)/checkin?date=\(date)")
                checkIns.removeAll { $0.date == date }
            } catch {
                print("Failed to delete check-in for \(date): \(error)")
            }
        }

        // Refresh goal for updated streaks
        do {
            let refreshed: Goal = try await api.get("/goals/\(goalId)")
            goal = refreshed
            checkIns = refreshed.checkIns ?? []
        } catch {
            print("Failed to refresh goal: \(error)")
        }
    }

    @ViewBuilder
    private func activityTimelineSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    historyExpanded.toggle()
                }
                if historyExpanded && activities.isEmpty {
                    Task { await loadHistory() }
                }
            } label: {
                HStack {
                    Text("HISTORY")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Image(systemName: historyExpanded ? "chevron.up" : "chevron.down")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                    Spacer()
                }
            }

            if historyExpanded {
                if historyLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                } else if activities.isEmpty {
                    Text("No activity yet.")
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                        .padding(.top, 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                            let isLast = index == activities.count - 1

                            HStack(alignment: .top, spacing: 14) {
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(dotColor(for: activity.action))
                                        .frame(width: 12, height: 12)
                                        .overlay(
                                            Circle()
                                                .stroke(dotColor(for: activity.action).opacity(0.3), lineWidth: 3)
                                        )
                                    if !isLast {
                                        Rectangle()
                                            .fill(Color.sacredMuted.opacity(0.15))
                                            .frame(width: 1.5)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(actionLabel(activity.action))
                                            .font(.sacredSmallMedium)
                                            .foregroundColor(.sacredText)
                                        Spacer()
                                        Image(systemName: actionIcon(activity.action))
                                            .font(.sacredMicro)
                                            .foregroundColor(dotColor(for: activity.action))
                                    }
                                    if let detail = activity.detail {
                                        Text(detail)
                                            .font(.sacredSmall)
                                            .foregroundColor(.sacredTextSecondary)
                                    }
                                    Text(formatDateTime(activity.createdAt))
                                        .font(.sacredMicro)
                                        .foregroundColor(.sacredMuted)
                                }
                                .padding(.bottom, isLast ? 0 : 20)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Activity helpers

    private func dotColor(for action: String) -> Color {
        switch action {
        case "Completed": return .sacredGreen
        case "Skipped": return .sacredMuted.opacity(0.4)
        case "ProgressUpdated": return .sacredGold
        case "DueDateChanged": return .sacredGold
        case "Created": return .sacredGold
        case "Undone": return .sacredMuted.opacity(0.4)
        default: return .sacredMuted
        }
    }

    private func actionIcon(_ action: String) -> String {
        switch action {
        case "Completed": return "checkmark"
        case "Skipped": return "moon.fill"
        case "ProgressUpdated": return "chart.bar.fill"
        case "DueDateChanged": return "calendar"
        case "Created": return "plus"
        case "Undone": return "arrow.uturn.backward"
        default: return "circle"
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "Completed": return "Completed"
        case "Skipped": return "Skipped"
        case "ProgressUpdated": return "Progress updated"
        case "DueDateChanged": return "Due date changed"
        case "Created": return "Created"
        case "Undone": return "Undone"
        default: return action
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.sacredDisplayNumber)
                .foregroundColor(.sacredGold)
            Text(label)
                .font(.sacredSectionLabel)
                .tracking(2)
                .foregroundColor(.sacredMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.08)))
    }

    private func formatDate(_ dateStr: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let date = f.date(from: dateStr.prefix(10).description) {
            f.dateFormat = "MMM d, yyyy"
            return f.string(from: date)
        }
        return dateStr
    }

    private func formatDateTime(_ dateStr: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        if let date = iso.date(from: dateStr) ?? isoBasic.date(from: dateStr) {
            let f = DateFormatter()
            f.dateFormat = "MMM d, yyyy 'at' h:mm a"
            return f.string(from: date)
        }
        return dateStr
    }
}
