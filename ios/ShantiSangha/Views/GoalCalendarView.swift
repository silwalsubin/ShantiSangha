import SwiftUI

/// Calendar view for editing check-in history of a recurring goal.
/// Navigated to from GoalDetailView.
struct GoalCalendarView: View {
    let goalId: String
    let goalTitle: String
    let goalCreatedAt: String

    @State private var checkIns: [GoalCheckIn] = []
    @State private var currentStreak: Int = 0
    @State private var longestStreak: Int = 0
    @State private var calYear: Int = Calendar.current.component(.year, from: Date())
    @State private var calMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var togglingDate: String?
    @State private var bulkActioning = false
    @State private var showCheckAllConfirm = false
    @State private var showUncheckAllConfirm = false
    @State private var showResetConfirm = false
    @Environment(\.dismiss) private var dismiss
    private let api = ApiService.shared

    private static let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Streak summary
                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text("\(currentStreak)")
                            .font(.sacredDisplayNumber)
                            .foregroundColor(.sacredGold)
                        Text("CURRENT")
                            .font(.sacredSectionLabel)
                            .tracking(2)
                            .foregroundColor(.sacredMuted)
                    }
                    VStack(spacing: 2) {
                        Text("\(longestStreak)")
                            .font(.sacredDisplayNumber)
                            .foregroundColor(.sacredGold)
                        Text("LONGEST")
                            .font(.sacredSectionLabel)
                            .tracking(2)
                            .foregroundColor(.sacredMuted)
                    }
                }
                .padding(.top, 8)

                // Reset history
                Button { showResetConfirm = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Reset history")
                            .font(.sacredSmall)
                    }
                    .foregroundColor(.sacredMuted.opacity(0.6))
                }

                // Calendar card
                VStack(spacing: 16) {
                    // Month navigation
                    HStack {
                        Button { goPrev() } label: {
                            Image(systemName: "chevron.left")
                                .font(.sacredSmallMedium)
                                .foregroundColor(canGoPrev ? .sacredGold : .sacredMuted.opacity(0.3))
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!canGoPrev)

                        Spacer()

                        Text(monthLabel)
                            .font(.sacredTextMedium)
                            .foregroundColor(.sacredText)

                        Spacer()

                        Button { goNext() } label: {
                            Image(systemName: "chevron.right")
                                .font(.sacredSmallMedium)
                                .foregroundColor(canGoNext ? .sacredGold : .sacredMuted.opacity(0.3))
                                .frame(width: 44, height: 44)
                        }
                        .disabled(!canGoNext)
                    }

                    // Day-of-week labels
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                        ForEach(Self.dayLabels, id: \.self) { label in
                            Text(label)
                                .font(.sacredSectionLabel)
                                .tracking(1)
                                .foregroundColor(.sacredMuted)
                                .frame(height: 24)
                        }
                    }

                    // Calendar grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                        ForEach(calendarDays) { day in
                            if day.isCurrentMonth {
                                Button {
                                    guard !day.isFuture, !day.isBeforeCreation else { return }
                                    Task { await toggleDate(day.date, hasCheckin: day.checkin != nil) }
                                } label: {
                                    ZStack {
                                        if day.checkin?.completed == true {
                                            Circle()
                                                .fill(LinearGradient(
                                                    colors: [.sacredGold, .sacredGoldDark],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                                ))
                                        } else if day.checkin != nil {
                                            Circle()
                                                .fill(Color.sacredMuted.opacity(0.12))
                                        } else if day.isToday {
                                            Circle()
                                                .strokeBorder(Color.sacredGold.opacity(0.4), lineWidth: 1)
                                        }

                                        Text("\(day.day)")
                                            .font(.system(size: 13, weight: day.checkin?.completed == true ? .semibold : .regular, design: .serif))
                                            .foregroundColor(
                                                day.isFuture || day.isBeforeCreation
                                                    ? .sacredMuted.opacity(0.25)
                                                    : day.checkin?.completed == true
                                                        ? .white
                                                        : .sacredText
                                            )

                                        if day.isToday {
                                            Circle()
                                                .fill(Color.sacredGold)
                                                .frame(width: 4, height: 4)
                                                .offset(y: 14)
                                        }
                                    }
                                    .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                                .disabled(day.isFuture || day.isBeforeCreation)
                                .opacity(togglingDate == day.date ? 0.4 : 1)
                            } else {
                                Color.clear.frame(width: 40, height: 40)
                            }
                        }
                    }
                    .opacity(bulkActioning ? 0.4 : 1)
                    .allowsHitTesting(!bulkActioning)

                    // Footer
                    Divider()
                        .background(Color.sacredMuted.opacity(0.1))
                        .padding(.top, 8)

                    HStack {
                        Text("\(checkedInCount) / \(actionableDays.count) days")
                            .font(.sacredMicro)
                            .foregroundColor(.sacredMuted)

                        Spacer()

                        if checkedInCount < actionableDays.count {
                            Button { showCheckAllConfirm = true } label: {
                                Text("Check all")
                                    .font(.sacredSmallMedium)
                                    .foregroundColor(.sacredGold)
                            }
                            .disabled(bulkActioning)
                        }

                        if checkedInCount > 0 {
                            Button { showUncheckAllConfirm = true } label: {
                                Text("Uncheck all")
                                    .font(.sacredSmallMedium)
                                    .foregroundColor(.sacredTextSecondary)
                            }
                            .disabled(bulkActioning)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.08)))
            }
            .padding(16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle(goalTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Check All", isPresented: $showCheckAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Check All") {
                Task { await checkAllMonth() }
            }
        } message: {
            Text("Mark all remaining days in \(monthLabel) as completed?")
        }
        .alert("Uncheck All", isPresented: $showUncheckAllConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Uncheck All", role: .destructive) {
                Task { await uncheckAllMonth() }
            }
        } message: {
            Text("Remove all check-ins for \(monthLabel)?")
        }
        .alert("Reset History", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task { await resetHistory() }
            }
        } message: {
            Text("This will delete all check-in records and reset the start date to today. This cannot be undone.")
        }
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        do {
            let g: Goal = try await api.get(goalPath)
            currentStreak = g.currentStreak ?? 0
            longestStreak = g.longestStreak ?? 0
        } catch {
            print("Failed to load goal: \(error)")
        }
        await loadCheckIns()
    }

    private func loadCheckIns() async {
        let cal = Calendar.current
        let firstOfMonth = cal.date(from: DateComponents(year: calYear, month: calMonth, day: 1))!
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let from = String(format: "%04d-%02d-01", calYear, calMonth)
        let to = String(format: "%04d-%02d-%02d", calYear, calMonth, daysInMonth)

        do {
            checkIns = try await api.get("/goals/\(goalId)/checkins?from=\(from)&to=\(to)")
        } catch {
            print("Failed to load check-ins: \(error)")
            checkIns = []
        }
    }

    // MARK: - Calendar helpers

    private struct CalDay: Identifiable {
        let id: String
        let date: String
        let day: Int
        let checkin: GoalCheckIn?
        let isToday: Bool
        let isFuture: Bool
        let isBeforeCreation: Bool
        let isCurrentMonth: Bool
    }

    private var todayStr: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    private var goalPath: String {
        "/goals/\(goalId)?date=\(todayStr)"
    }

    private var createdDateStr: String {
        String(goalCreatedAt.prefix(10))
    }

    private var monthLabel: String {
        let df = DateFormatter(); df.dateFormat = "LLLL yyyy"
        let date = Calendar.current.date(from: DateComponents(year: calYear, month: calMonth, day: 1))!
        return df.string(from: date)
    }

    private var canGoPrev: Bool {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        guard let created = df.date(from: createdDateStr) else { return false }
        let y = Calendar.current.component(.year, from: created)
        let m = Calendar.current.component(.month, from: created)
        return calYear > y || (calYear == y && calMonth > m)
    }

    private var canGoNext: Bool {
        let now = Date()
        let y = Calendar.current.component(.year, from: now)
        let m = Calendar.current.component(.month, from: now)
        return calYear < y || (calYear == y && calMonth < m)
    }

    private var checkinMap: [String: GoalCheckIn] {
        Dictionary(uniqueKeysWithValues: checkIns.map { ($0.date, $0) })
    }

    private func actionButton(icon: String, label: String, color: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.sacredSectionLabel)
                    .tracking(1)
            }
            .foregroundColor(enabled ? color : color.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var calendarDays: [CalDay] {
        let cal = Calendar.current
        let firstOfMonth = cal.date(from: DateComponents(year: calYear, month: calMonth, day: 1))!
        let startDow = cal.component(.weekday, from: firstOfMonth) - 1
        let daysInMonth = cal.range(of: .day, in: .month, for: firstOfMonth)!.count
        let today = todayStr
        let created = createdDateStr
        let map = checkinMap

        var days: [CalDay] = []
        for i in 0..<startDow {
            days.append(CalDay(id: "blank-\(i)", date: "", day: 0, checkin: nil,
                               isToday: false, isFuture: true, isBeforeCreation: true, isCurrentMonth: false))
        }
        for d in 1...daysInMonth {
            let dateStr = String(format: "%04d-%02d-%02d", calYear, calMonth, d)
            days.append(CalDay(
                id: dateStr, date: dateStr, day: d,
                checkin: map[dateStr],
                isToday: dateStr == today,
                isFuture: dateStr > today,
                isBeforeCreation: dateStr < created,
                isCurrentMonth: true
            ))
        }
        return days
    }

    private var checkedInCount: Int {
        calendarDays.filter { $0.isCurrentMonth && $0.checkin != nil }.count
    }

    private var actionableDays: [CalDay] {
        calendarDays.filter { $0.isCurrentMonth && !$0.isFuture && !$0.isBeforeCreation }
    }

    // MARK: - Navigation

    private func goPrev() {
        if calMonth == 1 { calYear -= 1; calMonth = 12 }
        else { calMonth -= 1 }
        Task { await loadCheckIns() }
    }

    private func goNext() {
        if calMonth == 12 { calYear += 1; calMonth = 1 }
        else { calMonth += 1 }
        Task { await loadCheckIns() }
    }

    // MARK: - Actions

    private func toggleDate(_ date: String, hasCheckin: Bool) async {
        togglingDate = date
        defer { togglingDate = nil }

        do {
            if hasCheckin {
                try await api.delete("/goals/\(goalId)/checkin?date=\(date)")
                checkIns.removeAll { $0.date == date }
            } else {
                let body: [String: Any] = ["completed": true, "date": date]
                if let data = try? JSONSerialization.data(withJSONObject: body) {
                    let result: GoalCheckIn = try await api.postRaw("/goals/\(goalId)/checkin", body: data)
                    checkIns.append(result)
                }
            }
            await refreshStreaks()
        } catch {
            print("Failed to toggle check-in: \(error)")
        }
    }

    private func checkAllMonth() async {
        bulkActioning = true
        defer { bulkActioning = false }

        for day in actionableDays.filter({ $0.checkin == nil }) {
            let body: [String: Any] = ["completed": true, "date": day.date]
            if let data = try? JSONSerialization.data(withJSONObject: body) {
                if let result: GoalCheckIn = try? await api.postRaw("/goals/\(goalId)/checkin", body: data) {
                    checkIns.append(result)
                }
            }
        }
        await refreshStreaks()
    }

    private func uncheckAllMonth() async {
        bulkActioning = true
        defer { bulkActioning = false }

        for day in actionableDays.filter({ $0.checkin != nil }) {
            try? await api.delete("/goals/\(goalId)/checkin?date=\(day.date)")
            checkIns.removeAll { $0.date == day.date }
        }
        await refreshStreaks()
    }

    private func refreshStreaks() async {
        do {
            let g: Goal = try await api.get(goalPath)
            currentStreak = g.currentStreak ?? 0
            longestStreak = g.longestStreak ?? 0
        } catch {
            print("Failed to refresh streaks: \(error)")
        }
    }

    private func resetHistory() async {
        let body: [String: String] = [:]
        if let data = try? JSONSerialization.data(withJSONObject: body) {
            let _: EmptyResponse? = try? await api.postRaw("/goals/\(goalId)/reset", body: data)
        }
        let now = Date()
        calYear = Calendar.current.component(.year, from: now)
        calMonth = Calendar.current.component(.month, from: now)
        checkIns = []
        await refreshStreaks()
        await loadCheckIns()
    }
}
