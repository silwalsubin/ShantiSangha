import SwiftUI

/// Shows all reminders for a specific date with the ability to add new ones.
/// Navigated to from ReminderCalendarBrowseView when tapping a date.
struct DateRemindersView: View {
    @ObservedObject var vm: HomeViewModel
    let date: Date
    @State private var showNewReminder = false
    @State private var editingReminder: Reminder?

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool { calendar.isDate(date, inSameDayAs: today) }
    private var isPast: Bool { date < today }
    private var isFuture: Bool { date > today }

    // MARK: - Filtering

    private var remindersForDate: [Reminder] {
        vm.reminders.filter { reminder in
            guard let parsed = parseISODate(reminder.date) else { return false }
            return calendar.isDate(parsed, inSameDayAs: date)
        }
    }

    private var pendingReminders: [Reminder] {
        remindersForDate.filter { $0.completedAt == nil }
    }

    private var completedReminders: [Reminder] {
        remindersForDate.filter { $0.completedAt != nil }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dateHeader
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                if pendingReminders.isEmpty && completedReminders.isEmpty {
                    emptyState
                } else {
                    if !pendingReminders.isEmpty {
                        sectionLabel("ACTIVE")
                        reminderList(pendingReminders)
                    }

                    if !completedReminders.isEmpty {
                        sectionLabel("DONE")
                        reminderList(completedReminders)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .sacredBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewReminder = true
                } label: {
                    Image(systemName: "plus")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .navigationDestination(isPresented: $showNewReminder) {
            QuickAddReminderView(targetDate: date) { label, date, recurrence, remindersEnabled in
                await vm.createReminder(
                    label: label, date: date,
                    recurrence: recurrence,
                    remindersEnabled: remindersEnabled)
            }
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditSheet(
                target: .edit(reminder),
                onSave: { label, date, recurrence in
                    await vm.updateReminder(
                        id: reminder.id, label: label,
                        date: date, recurrence: recurrence)
                    editingReminder = nil
                },
                onDelete: {
                    await vm.deleteReminder(id: reminder.id)
                    editingReminder = nil
                })
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(isToday ? "Nothing today" : isFuture ? "Nothing scheduled" : "Nothing was due")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)

            Button {
                showNewReminder = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.sacredSmall)
                    Text("Add a reminder")
                        .font(.sacredSmallMedium)
                }
                .foregroundColor(.sacredGold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.sacredGold.opacity(0.1))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.sacredGold.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(dayOfWeekShort)
                    .font(.sacredSectionLabel)
                    .tracking(2)
                    .foregroundColor(.sacredMuted)
                Text("\(calendar.component(.day, from: date))")
                    .font(.sacredDisplayNumber)
                    .foregroundColor(isToday ? .sacredGold : .sacredText)
            }
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isToday ? Color.sacredGold.opacity(0.1) : Color.sacredBgCard)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(fullDateLabel)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)

                Text(summaryLabel)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }

    private var dayOfWeekShort: String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return df.string(from: date).uppercased()
    }

    private var fullDateLabel: String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: date)
    }

    private var summaryLabel: String {
        let total = remindersForDate.count
        let done = completedReminders.count
        if total == 0 { return "No reminders" }
        if done == total { return "All \(total) completed" }
        return "\(total - done) pending, \(done) done"
    }

    // MARK: - Section label & list

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.sacredSectionLabel)
            .tracking(3)
            .foregroundColor(.sacredLabel)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func reminderList(_ items: [Reminder]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, reminder in
                ReminderRow(
                    reminder: reminder,
                    onTap: { editingReminder = reminder }
                )

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 16)
                }
            }
        }
    }

    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}
