import SwiftUI

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, TaskType, String?) async -> Void

    @State private var title = ""
    @State private var type: TaskType = .recurring
    @State private var targetDate = Date()
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("NEW TASK")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Text("Set an intention")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)
                }
                .padding(.top, 24)

                // Type picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("TYPE")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    HStack(spacing: 8) {
                        typePill("Daily practice", icon: "flame.fill", taskType: .recurring)
                        typePill("Commitment", icon: "calendar.badge.clock", taskType: .oneTime)
                    }
                }

                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("INTENTION")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    TextField(type == .recurring ? "I want to practice..." : "I want to achieve...", text: $title)
                        .textFieldStyle(.plain)
                        .font(.sacredText)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                }

                // Target date for milestones
                if type == .oneTime {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET DATE")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)
                        DatePicker("", selection: $targetDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(.sacredGold)
                    }
                }

                // Save button
                Button {
                    guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    saving = true
                    let dateStr = type == .oneTime ? formatDate(targetDate) : nil
                    Task {
                        await onCreate(title.trimmingCharacters(in: .whitespaces), type, dateStr)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if saving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .font(.sacredTextSemibold)
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .background(LinearGradient.sacredGoldShiny)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shimmer()
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
            .padding(.horizontal, 16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("New Task")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func typePill(_ label: String, icon: String, taskType: TaskType) -> some View {
        Button { type = taskType } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.sacredSmall)
                Text(label)
                    .font(.sacredSmallSemibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(type == taskType ? Color.sacredGold.opacity(0.06) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(type == taskType ? Color.sacredGold : Color.sacredMuted.opacity(0.12)))
            )
            .foregroundColor(type == taskType ? .sacredGold : .sacredTextSecondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
