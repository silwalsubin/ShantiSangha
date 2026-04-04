import SwiftUI

struct DeleteTaskView: View {
    let task: AppTask
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Warning icon
                Image(systemName: "trash")
                    .font(.sacredHero)
                    .foregroundColor(.sacredRed)
                    .frame(width: 64, height: 64)
                    .background(Color.sacredRed.opacity(0.08))
                    .clipShape(Circle())

                // Task info
                VStack(spacing: 8) {
                    Text(task.title)
                        .font(.sacredHeading)
                        .foregroundColor(.sacredText)
                        .multilineTextAlignment(.center)

                    Text(task.type == .recurring ? "Daily Practice" : "Commitment")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                        .textCase(.uppercase)
                        .tracking(2)
                }

                // Warning message
                Text("This will permanently delete this task and all its history. This action cannot be undone.")
                    .font(.sacredText)
                    .foregroundColor(.sacredTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Spacer()

            // Delete button
            VStack(spacing: 12) {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Task")
                            .font(.sacredTextSemibold)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 14)
                    .background(Color.sacredRed)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredTextSecondary)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("Delete Task")
        .navigationBarTitleDisplayMode(.inline)
    }
}
