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
    @State private var navigateToDelete = false

    var isOverdue: Bool {
        task.type == .oneTime && (task.daysRemaining ?? 1) <= 0
    }

    @State private var offset: CGFloat = 0
    @State private var activeSwipe: SwipeDirection? = nil
    @State private var navigateToDetail = false
    private let swipeThreshold: CGFloat = 80

    private enum SwipeDirection {
        case left, right
    }

    var body: some View {
        ZStack {
            // Swipe background — single layer behind the card
            if offset > 0 {
                HStack {
                    Image(systemName: "checkmark")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.white)
                    Text("Done")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredGreen))
            } else if offset < 0 {
                HStack {
                    Spacer()
                    Text("Skip")
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                    Image(systemName: "forward.fill")
                        .font(.sacredSmall)
                        .foregroundColor(.white)
                }
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredMuted))
            }

            // Card content
            taskContent
                .onTapGesture {
                    if activeSwipe == nil {
                        navigateToDetail = true
                    }
                }
                .offset(x: offset)
                .gesture(
                    !task.checkedIn && !task.saving
                    ? DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            offset = value.translation.width
                            if offset > swipeThreshold {
                                activeSwipe = .right
                            } else if offset < -swipeThreshold {
                                activeSwipe = .left
                            } else {
                                activeSwipe = nil
                            }
                        }
                        .onEnded { _ in
                            if let swipe = activeSwipe {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.easeOut(duration: 0.2)) {
                                    offset = swipe == .right ? 300 : -300
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    if swipe == .right { onDone() } else { onSkip() }
                                    offset = 0
                                    activeSwipe = nil
                                }
                            } else {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = 0
                                }
                            }
                        }
                    : nil
                )
        }
        .background(
            Group {
                NavigationLink(destination: GoalDetailView(goalId: task.id), isActive: $navigateToDetail) {
                    EmptyView()
                }
                NavigationLink(destination: DeleteTaskView(task: task, onDelete: onDelete), isActive: $navigateToDelete) {
                    EmptyView()
                }
            }
            .hidden()
        )
    }

    private var taskContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: task.type == .recurring ? "arrow.triangle.2.circlepath" : "target")
                    .font(.sacredText)
                    .foregroundColor(task.type == .recurring ? .sacredMutedLight : .sacredGold)
                    .frame(width: 24, height: 24)

                // Title
                Text(task.title)
                    .font(.sacredTextMedium)
                    .foregroundColor(task.checkedIn && task.completedToday == true ? .sacredGreen : .sacredText)
                    .strikethrough(task.checkedIn && task.completedToday == true, color: .sacredGreen.opacity(0.4))

                Spacer()

                // Streak heat dots for recurring tasks
                if task.type == .recurring {
                    HeatDotsView(streak: task.currentStreak)
                }

                // Milestone days remaining
                if task.type == .oneTime, let days = task.daysRemaining {
                    Text(days > 0 ? "\(days)d" : days == 0 ? "Today" : "\(abs(days))d over")
                        .font(days <= 0 ? .sacredSmallSemibold : .sacredSmall)
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

                        Button {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigateToDelete = true
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.sacredText)
                            .foregroundColor(.sacredMuted)
                            .frame(width: 28, height: 28)
                    }
                }
            }

            // Progress bar for milestones (only show when progress > 0)
            if task.type == .oneTime && !showProgress && task.progress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.sacredMuted.opacity(0.15))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient.sacredGoldShiny)
                                .frame(width: geo.size.width * CGFloat(task.progress) / 100, height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.leading, 36)

                    Text("\(task.progress)% complete")
                        .font(.sacredMicro)
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
                            .font(.sacredSmallMedium)
                            .foregroundColor(.sacredGold)
                        Spacer()
                        Button("Cancel") { showProgress = false }
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        Button("Save") {
                            showProgress = false
                            onProgressUpdate(Int(progressValue))
                        }
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.sacredGold)
                    }
                }
                .padding(.leading, 36)
            }

            // Spiritual feedback
            if task.checkedIn, let msg = task.feedbackMessage {
                Text(msg)
                    .font(.sacredCaption)
                    .italic()
                    .foregroundColor(.sacredMuted)
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
    }
}

// MARK: - Heat dots — 7-day streak visualization

private struct HeatDotsView: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { day in
                let daysAgo = 6 - day // leftmost = 6 days ago, rightmost = today
                let isLit = daysAgo < streak
                Circle()
                    .fill(isLit ? colorForDay(daysAgo: daysAgo) : Color.sacredMuted.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// More recent days glow brighter
    private func colorForDay(daysAgo: Int) -> Color {
        let intensity = 1.0 - (Double(daysAgo) * 0.1)
        return Color.sacredGold.opacity(max(0.4, intensity))
    }
}
