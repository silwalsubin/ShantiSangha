import SwiftUI

/// Reminders list — shows today's reminders and carried-over items.
/// Calendar is accessible via toolbar button.
struct RemindersView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var showCalendar = false
    @State private var showNewReminder = false
    @State private var editingReminder: Reminder?
    @State private var activeSwipeId: String?

    // MARK: - Section data

    /// Reminders due today.
    private var todayReminders: [Reminder] {
        vm.pendingReminders.filter { $0.daysRemaining == 0 }
    }

    /// Reminders that have slipped past their date and are still pending.
    private var carriedOverReminders: [Reminder] {
        vm.pendingReminders.filter { $0.daysRemaining < 0 }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if todayReminders.isEmpty && carriedOverReminders.isEmpty {
                    allClearView
                } else {
                    if !todayReminders.isEmpty {
                        sectionHeader("TODAY")
                        reminderList(todayReminders, allowSwipe: false)
                    }

                    if !carriedOverReminders.isEmpty {
                        sectionHeader("CARRIED OVER")
                        reminderList(carriedOverReminders, allowSwipe: true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .sacredBackground()
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCalendar = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.sacredSmallMedium)
                        .foregroundColor(.sacredGold)
                }
            }
        }
        .navigationDestination(isPresented: $showCalendar) {
            ReminderCalendarBrowseView(vm: vm)
        }
        .navigationDestination(isPresented: $showNewReminder) {
            QuickAddReminderView(targetDate: Date()) { label, date, recurrence, remindersEnabled in
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

    // MARK: - All clear celebration

    private var allClearView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "leaf.fill")
                .font(.system(size: 36))
                .foregroundColor(.sacredGreen)

            Text("You're all clear")
                .font(.sacredHeading)
                .foregroundColor(.sacredText)

            Text("Nothing waiting for you today.\nEnjoy the stillness.")
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                showNewReminder = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add a reminder")
                }
                .font(.sacredSmallSemibold)
                .foregroundColor(.sacredGold)
                .frame(minHeight: 44)
            }

            Spacer().frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section header

    private func sectionHeader(_ label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredMuted)
            Spacer()
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    // MARK: - Reminder list

    private func reminderList(_ items: [Reminder], allowSwipe: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, reminder in
                ReminderRow(
                    reminder: reminder,
                    allowSwipeToComplete: allowSwipe,
                    showDateStamp: true,
                    onTap: { editingReminder = reminder },
                    onComplete: {
                        Task { await vm.completeReminder(id: reminder.id) }
                    },
                    activeSwipeId: $activeSwipeId
                )

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 64)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}
