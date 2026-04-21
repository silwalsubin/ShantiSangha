import SwiftUI

/// Minimal goal creation — just a title. Type and date are pre-set.
/// Used from DateGoalsView where the context is already known.
struct QuickAddGoalView: View {
    let targetDate: Date
    let onCreate: (String, TaskType, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private let calendar = Calendar.current
    private let today = Calendar.current.startOfDay(for: Date())

    private var isToday: Bool { calendar.isDate(targetDate, inSameDayAs: today) }

    private var dateLabel: String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"
        return df.string(from: targetDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Context
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredGold)
                Text(dateLabel)
                    .font(.sacredSmallMedium)
                    .foregroundColor(.sacredGold)
            }
            .padding(.top, 24)

            // Title input
            VStack(alignment: .leading, spacing: 10) {
                Text("What would you like to accomplish?")
                    .font(.sacredTitle)
                    .foregroundColor(.sacredText)

                TextField("e.g. Finish reading chapter 3", text: $title)
                    .textFieldStyle(.plain)
                    .font(.sacredText)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBgCard))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))
                    .focused($focused)
            }

            // Save
            SacredPrimaryButton(
                "Set this goal",
                style: .commit,
                isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: saving
            ) {
                saving = true
                let dateStr = formatDate(targetDate)
                Task {
                    await onCreate(title.trimmingCharacters(in: .whitespaces), .oneTime, dateStr)
                    dismiss()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
