import SwiftUI

struct ChangeDueDateView: View {
    let task: AppTask
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(task: AppTask, onSave: @escaping (String) -> Void) {
        self.task = task
        self.onSave = onSave
        // Pre-select current due date
        if let days = task.daysRemaining {
            _selectedDate = State(initialValue: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
        } else {
            _selectedDate = State(initialValue: Date())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DUE DATE")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)
                        Text(task.title)
                            .font(.sacredTitle)
                            .foregroundColor(.sacredText)
                    }
                    .padding(.top, 24)

                    // Calendar
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.sacredGold)
                }
                .padding(.horizontal, 16)
            }

            // Save button
            SacredPrimaryButton("Save", style: .commit) {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                onSave(f.string(from: selectedDate))
                dismiss()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .sacredBackground()
        .navigationTitle("Change Due Date")
        .navigationBarTitleDisplayMode(.inline)
    }
}
