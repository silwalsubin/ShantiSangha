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
            VStack(spacing: 12) {
                Button {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    onSave(f.string(from: selectedDate))
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Save")
                            .font(.sacredTextSemibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .background(LinearGradient.sacredGoldShiny)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shimmer()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Change Due Date")
        .navigationBarTitleDisplayMode(.inline)
    }
}
