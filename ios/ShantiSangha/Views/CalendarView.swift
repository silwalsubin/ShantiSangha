import SwiftUI

/// Calendar screen — month grid with a dot per reminder on each day,
/// plus a detail pane for the currently selected date. It is opened
/// from Home, not kept as a primary tab.
struct CalendarView: View {
    @StateObject private var reminderRepo = ReminderRepository.shared
    @StateObject private var connections = ConnectionsRepository.shared
    @EnvironmentObject var profile: ProfileService

    @State private var displayedMonth: Date
    @State private var selectedDate: Date
    @State private var navTarget: ReminderEditTarget?
    @State private var activeSwipeId: String?
    /// Set when we push to the reminder editor so we know the next
    /// `onAppear` is a return from that push (not a tab activation) and
    /// should preserve the user's selection instead of snapping to today.
    @State private var returningFromEdit = false

    private let showsNavigationBar: Bool
    private let calendar = Calendar.current

    init(initialDate: Date = Date(), showsNavigationBar: Bool = false) {
        self.showsNavigationBar = showsNavigationBar
        _displayedMonth = State(initialValue: initialDate)
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        ZStack {
            SacredBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    MonthCalendarPicker(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        dotStates: { remindersForDate($0).map { $0.completedAt != nil } })
                        .padding(.top, 8)
                        .onChange(of: displayedMonth) { _, new in
                            selectedDate = pinSelection(to: new)
                        }
                    MonthCalendarPicker.goldRule
                        .padding(.top, 22)
                    selectedDateDetail
                        .padding(.top, 22)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
            .background(Color.clear)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
        .navigationDestination(item: $navTarget) { target in
            ReminderEditView(
                target: target,
                onSave: { label, date, recurrence, collaboratorIds in
                    switch target {
                    case .new(_, _, let connId):
                        do {
                            _ = try await reminderRepo.create(
                                label: label,
                                date: date,
                                recurrence: recurrence,
                                remindersEnabled: true,
                                connectionId: connId,
                                collaboratorUserIds: collaboratorIds)
                        } catch {
                            if !error.isCancellation {
                                AppLogger.shared.error("Calendar", "Create failed: \(error)")
                            }
                        }
                    case .edit(let reminder):
                        do {
                            _ = try await reminderRepo.update(
                                id: reminder.id,
                                label: label,
                                date: date,
                                recurrence: recurrence,
                                collaboratorUserIds: collaboratorIds)
                        } catch {
                            if !error.isCancellation {
                                AppLogger.shared.error("Calendar", "Update failed: \(error)")
                            }
                        }
                    }
                },
                onDelete: {
                    if case .edit(let r) = target {
                        return {
                            do {
                                try await reminderRepo.delete(id: r.id)
                            } catch {
                                if !error.isCancellation {
                                    AppLogger.shared.error("Calendar", "Delete failed: \(error)")
                                }
                            }
                        }
                    }
                    return nil
                }(),
                onLivePatch: {
                    if case .edit(let r) = target {
                        return { patch in
                            try? await reminderRepo.update(
                                id: r.id,
                                label: patch.label,
                                date: patch.date,
                                recurrence: patch.recurrence,
                                collaboratorUserIds: patch.collaboratorUserIds,
                                notes: patch.notes)
                        }
                    }
                    return nil
                }()
            )
        }
        .task {
            await reminderRepo.refresh()
            await connections.refresh()
        }
        .onAppear {
            if returningFromEdit {
                returningFromEdit = false
            } else {
                let today = Date()
                selectedDate = today
                displayedMonth = today
            }
        }
        .onDisappear {
            if navTarget != nil { returningFromEdit = true }
        }
    }

    /// Returns a date guaranteed to live inside `month` — today when today
    /// falls in that month, otherwise the 1st. Used after month / year
    /// navigation so the detail pane below the grid always reflects what
    /// the user is currently looking at.
    private func pinSelection(to month: Date) -> Date {
        let today = Date()
        if calendar.isDate(today, equalTo: month, toGranularity: .month) {
            return today
        }
        return calendar.dateInterval(of: .month, for: month)?.start ?? month
    }

    // MARK: - Selected date detail

    private var selectedDateDetail: some View {
        let items = remindersForDate(selectedDate)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(longDateLabel(selectedDate))
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .tracking(0.3)
                    .foregroundColor(.sacredText)
                Spacer()
                Button {
                    navTarget = .new(initialDate: selectedDate)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.sacredSmallMedium)
                    }
                    .foregroundColor(.sacredGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.sacredGold.opacity(0.1)))
                    .overlay(Capsule().stroke(Color.sacredGold.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)

            if items.isEmpty {
                HStack {
                    Text("Nothing scheduled.")
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            } else {
                let pending = items.filter { $0.completedAt == nil }
                let completed = items.filter { $0.completedAt != nil }
                if !pending.isEmpty {
                    section(items: pending, color: .sacredGold, label: "Pending")
                }
                if !completed.isEmpty {
                    section(items: completed, color: .sacredGreen, label: "Done")
                        .padding(.top, pending.isEmpty ? 0 : 20)
                }
            }
        }
    }

    /// Headed reminder section — dot + caps label, then the rows with the
    /// same hairline divider used everywhere else. Pulls double duty as
    /// both the visual grouping and the dot-color key for the grid above.
    @ViewBuilder
    private func section(items: [Reminder], color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .tracking(0.3)
                    .foregroundColor(.sacredText)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            ForEach(Array(items.enumerated()), id: \.element.id) { idx, r in
                ReminderRow(
                    reminder: r,
                    showDateStamp: true,
                    connectionLabel: connectionLabel(for: r),
                    currentUserId: profile.currentUserId,
                    onTap: { navTarget = .edit(r) },
                    activeSwipeId: Binding(
                        get: { activeSwipeId },
                        set: { activeSwipeId = $0 }
                    )
                )
                if idx < items.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                        .padding(.trailing, 16)
                }
            }
        }
    }

    // MARK: - Helpers

    private func longDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date)
    }

    /// Reminders matching `date`. Yearly recurrence matches on month + day
    /// regardless of anchor year, so a 1990-02-09 birthday lights up Feb 9
    /// in every year's calendar.
    private func remindersForDate(_ date: Date) -> [Reminder] {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let dateStr = String(format: "%04d-%02d-%02d", year, month, day)

        return reminderRepo.reminders.filter { r in
            switch r.recurrence {
            case .yearly:
                let parts = r.date.split(separator: "-")
                guard parts.count >= 3,
                      let m = Int(parts[1]),
                      let d = Int(parts[2]) else { return false }
                return m == month && d == day
            case .none:
                return r.date == dateStr
            }
        }
    }

    private func connectionLabel(for reminder: Reminder) -> String? {
        guard let cid = reminder.connectionId else { return nil }
        return connections.connection(for: cid)?.displayLabel
    }
}
