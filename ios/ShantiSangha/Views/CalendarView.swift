import SwiftUI

/// Calendar tab — month grid with a dot per reminder on each day, plus
/// a detail pane for the currently selected date. Tap a date to focus
/// it, tap a reminder to edit, tap "+ Add" to create one pre-filled
/// with the selected date.
struct CalendarView: View {
    @StateObject private var reminderRepo = ReminderRepository.shared
    @StateObject private var connections = ConnectionsRepository.shared
    @EnvironmentObject var profile: ProfileService

    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    @State private var navTarget: ReminderEditTarget?
    @State private var activeSwipeId: String?

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            SacredBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    MonthCalendarPicker(
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        dotCount: { remindersForDate($0).count })
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
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $navTarget) { target in
            ReminderEditView(
                target: target,
                onSave: { label, date, recurrence in
                    switch target {
                    case .new(_, _, let connId):
                        do {
                            _ = try await reminderRepo.create(
                                label: label,
                                date: date,
                                recurrence: recurrence,
                                remindersEnabled: true,
                                connectionId: connId)
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
                                recurrence: recurrence)
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
                }()
            )
        }
        .task {
            await reminderRepo.refresh()
            await connections.refresh()
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
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)
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
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, r in
                    ReminderRow(
                        reminder: r,
                        showDateStamp: true,
                        avatarUrl: avatarUrl(for: r),
                        connectionLabel: connectionLabel(for: r),
                        onTap: { navTarget = .edit(r) },
                        activeSwipeId: Binding(
                            get: { activeSwipeId },
                            set: { activeSwipeId = $0 }
                        )
                    )
                    if idx < items.count - 1 {
                        Divider()
                            .padding(.leading, 104)
                            .padding(.trailing, 16)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func longDateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f.string(from: date).uppercased()
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

    private func avatarUrl(for reminder: Reminder) -> String? {
        if let cid = reminder.connectionId,
           let c = connections.connection(for: cid) {
            return c.ownerVisibleAvatarUrl
        }
        return profile.profile?.avatarUrl
    }

    private func connectionLabel(for reminder: Reminder) -> String? {
        guard let cid = reminder.connectionId else { return nil }
        return connections.connection(for: cid)?.displayLabel
    }
}
