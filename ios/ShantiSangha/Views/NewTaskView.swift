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
            VStack(alignment: .leading, spacing: 28) {
                // Question 1: What
                VStack(alignment: .leading, spacing: 10) {
                    Text("What would you like to work on?")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    TextField("Meditate, exercise, read...", text: $title)
                        .textFieldStyle(.plain)
                        .font(.sacredText)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                }
                .padding(.top, 24)

                // Question 2: How often
                VStack(alignment: .leading, spacing: 12) {
                    Text("How would you approach this?")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredText)

                    HStack(spacing: 10) {
                        approachButton("Every day", icon: "arrow.triangle.2.circlepath", selected: type == .recurring) {
                            withAnimation(.easeInOut(duration: 0.2)) { type = .recurring }
                        }
                        approachButton("By a date", icon: "calendar.badge.clock", selected: type == .oneTime) {
                            withAnimation(.easeInOut(duration: 0.2)) { type = .oneTime }
                        }
                    }
                }

                // Date picker — only when "By a date"
                if type == .oneTime {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When would you like to achieve this?")
                            .font(.sacredTextSemibold)
                            .foregroundColor(.sacredText)
                        DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(.sacredGold)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Save
                SacredPrimaryButton(
                    type == .recurring ? "Start this practice" : "Set this goal",
                    style: .commit,
                    isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: saving
                ) {
                    saving = true
                    let dateStr = type == .oneTime ? formatDate(targetDate) : nil
                    Task {
                        await onCreate(title.trimmingCharacters(in: .whitespaces), type, dateStr)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Approach button

    private func approachButton(_ label: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.sacredSmall)
                Text(label)
                    .font(.sacredTextSemibold)
            }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selected ? Color.sacredGold.opacity(0.08) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(selected ? Color.sacredGold : Color.sacredMuted.opacity(0.15), lineWidth: selected ? 1.5 : 1))
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
