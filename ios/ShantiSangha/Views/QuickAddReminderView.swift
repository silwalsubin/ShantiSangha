import SwiftUI

/// Minimal reminder creation — label, date (pre-set), recurrence, reminders toggle.
/// Used from DateRemindersView where the context is already known.
struct QuickAddReminderView: View {
    let targetDate: Date
    /// (label, date(yyyy-MM-dd), recurrence, remindersEnabled)
    let onCreate: (String, String, ReminderRecurrence, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var date: Date
    @State private var recurrence: ReminderRecurrence = .none
    @State private var remindersEnabled = true
    @State private var saving = false
    @FocusState private var focused: Bool

    init(targetDate: Date,
         onCreate: @escaping (String, String, ReminderRecurrence, Bool) async -> Void) {
        self.targetDate = targetDate
        self.onCreate = onCreate
        _date = State(initialValue: targetDate)
    }

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's the reminder?")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    TextField("e.g. Mom's birthday, Pay rent", text: $label)
                        .textFieldStyle(.plain)
                        .font(.sacredText)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                        .focused($focused)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("When?")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.sacredGold)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Repeats?")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)

                    HStack(spacing: 10) {
                        recurrenceButton("Once", value: .none)
                        recurrenceButton("Every year", value: .yearly)
                    }
                }

                Toggle(isOn: $remindersEnabled) {
                    Text("Notify me")
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredText)
                }
                .tint(.sacredGold)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))

                SacredPrimaryButton(
                    "Set this reminder",
                    style: .commit,
                    isDisabled: label.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: saving
                ) {
                    saving = true
                    let trimmed = label.trimmingCharacters(in: .whitespaces)
                    let dateStr = formatDate(date)
                    Task {
                        await onCreate(trimmed, dateStr, recurrence, remindersEnabled)
                        dismiss()
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .sacredBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func recurrenceButton(_ title: String, value: ReminderRecurrence) -> some View {
        let selected = recurrence == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { recurrence = value }
        } label: {
            Text(title)
                .font(.sacredTextSemibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? Color.sacredGold.opacity(0.08) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? Color.sacredGold : Color.sacredMuted.opacity(0.15),
                                    lineWidth: selected ? 1.5 : 1))
                )
                .foregroundColor(selected ? .sacredGold : .sacredTextSecondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
