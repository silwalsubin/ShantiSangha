import SwiftUI

/// Task row — mirrors frontend/src/components/TaskItem.vue
struct TaskRow: View {
    let task: AppTask
    let onDone: () -> Void
    let onSkip: () -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void
    let onProgressUpdate: (Int) -> Void

    @State private var showMenu = false
    @State private var showProgress = false
    @State private var progressValue: Double = 0
    @State private var showDeleteConfirm = false

    var isOverdue: Bool {
        task.type == .oneTime && (task.daysRemaining ?? 1) <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: task.type == .recurring ? "arrow.triangle.2.circlepath" : "target")
                    .font(.system(size: 14))
                    .foregroundColor(task.type == .recurring ? .sacredMutedLight : .sacredGold)
                    .frame(width: 24, height: 24)

                // Title
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(task.checkedIn && task.completedToday == true ? .sacredGreen : .sacredText)
                    .strikethrough(task.checkedIn && task.completedToday == true, color: .sacredGreen.opacity(0.4))

                Spacer()

                // Milestone days remaining
                if task.type == .oneTime, let days = task.daysRemaining {
                    Text(days > 0 ? "\(days)d" : days == 0 ? "Today" : "\(abs(days))d over")
                        .font(.system(size: 12, weight: days <= 0 ? .bold : .regular))
                        .foregroundColor(days <= 0 ? .sacredRed : .sacredGold)
                }

                // Three-dot menu
                if !task.saving {
                    Menu {
                        if !task.checkedIn {
                            Button { onDone() } label: {
                                Label("Mark complete", systemImage: "checkmark.circle")
                            }
                            if task.type == .oneTime {
                                Button { showProgress = true; progressValue = Double(task.progress) } label: {
                                    Label("Update progress", systemImage: "chart.bar.fill")
                                }
                            }
                            Button { onSkip() } label: {
                                Label("Skip for today", systemImage: "forward.fill")
                            }
                        } else {
                            Button { onUndo() } label: {
                                Label("Move to pending", systemImage: "arrow.uturn.backward")
                            }
                        }

                        Divider()

                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.sacredMuted)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            // Progress bar for milestones
            if task.type == .oneTime && !showProgress {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.sacredMuted.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(task.progress) / 100, height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.leading, 36)

                    Text("\(task.progress)% complete")
                        .font(.system(size: 10))
                        .foregroundColor(.sacredMuted)
                        .padding(.leading, 36)
                }
            }

            // Progress slider
            if showProgress {
                VStack(spacing: 8) {
                    Slider(value: $progressValue, in: 0...100, step: 5)
                        .tint(.sacredGold)

                    HStack {
                        Text("\(Int(progressValue))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.sacredGold)
                        Spacer()
                        Button("Cancel") { showProgress = false }
                            .font(.system(size: 12))
                            .foregroundColor(.sacredMuted)
                        Button("Save") {
                            showProgress = false
                            onProgressUpdate(Int(progressValue))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.sacredGold)
                    }
                }
                .padding(.leading, 36)
            }

            // Spiritual feedback
            if task.checkedIn, let msg = task.feedbackMessage {
                Text(msg)
                    .font(.system(size: 12, design: .serif))
                    .italic()
                    .foregroundColor(.sacredMuted)
                    .padding(.leading, 36)
            }

            // Check-in buttons (not checked in)
            if !task.checkedIn {
                HStack(spacing: 12) {
                    Button { onDone() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(LinearGradient(colors: [.sacredGreen, .sacredGreenDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(Circle())
                    }

                    Button { onSkip() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.sacredMutedLight)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.sacredMuted.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(task.checkedIn
                      ? Color.sacredGreen.opacity(0.06)
                      : isOverdue
                      ? Color.sacredRed.opacity(0.06)
                      : Color.sacredBgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(task.checkedIn
                                ? Color.sacredGreen.opacity(0.25)
                                : isOverdue
                                ? Color.sacredRed.opacity(0.25)
                                : Color.sacredMuted.opacity(0.12), lineWidth: 1)
                )
        )
        .confirmationDialog("Delete this task and all its history?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
