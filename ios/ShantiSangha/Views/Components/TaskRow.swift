import SwiftUI

/// Task row — mirrors frontend/src/components/TaskItem.vue
struct TaskRow: View {
    let task: AppTask
    let onDone: () -> Void
    let onSkip: () -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void
    let onProgressUpdate: (Int) -> Void
    var onDueDateUpdate: ((String) -> Void)? = nil
    var neutralStyle: Bool = false
    var activeSwipeId: Binding<String?>?

    @State private var showMenu = false
    @State private var showProgress = false
    @State private var navigateToDueDate = false
    @State private var progressValue: Double = 0
    @State private var navigateToDelete = false

    var isOverdue: Bool {
        task.type == .oneTime && (task.daysRemaining ?? 1) <= 0
    }

    @State private var offset: CGFloat = 0
    @State private var activeSwipe: SwipeDirection? = nil
    @State private var navigateToDetail = false

    private var swipeActive: Bool {
        activeSwipeId?.wrappedValue == task.id
    }
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
                    Image(systemName: "moon.fill")
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
                    ? LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            activeSwipeId?.wrappedValue = task.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .sequenced(before:
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    guard swipeActive else { return }
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
                                    activeSwipeId?.wrappedValue = nil
                                }
                        )
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
                NavigationLink(destination: ChangeDueDateView(task: task, onSave: { date in onDueDateUpdate?(date) }), isActive: $navigateToDueDate) {
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
                Image(systemName: task.type == .recurring ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                    .font(.sacredText)
                    .foregroundColor(task.type == .recurring ? .sacredMutedLight : .sacredGold)
                    .frame(width: 24, height: 24)

                // Title
                Text(task.title)
                    .font(.sacredTextMedium)
                    .foregroundColor(!neutralStyle && task.checkedIn && task.completedToday == true ? .sacredGreen : .sacredText)
                    .strikethrough(!neutralStyle && task.checkedIn && task.completedToday == true, color: .sacredGreen.opacity(0.4))

                Spacer()

                // Streak heat dots for recurring tasks
                if task.type == .recurring {
                    HeatDotsView(streak: task.currentStreak)
                }

                // Milestone due date
                if task.type == .oneTime, let days = task.daysRemaining {
                    Text(dueDateLabel(daysRemaining: days))
                        .font(days <= 0 ? .sacredSmallSemibold : .sacredSmall)
                        .foregroundColor(days < 0 ? .sacredRed : days == 0 ? .sacredGold : .sacredMuted)
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
                                Button {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        navigateToDueDate = true
                                    }
                                } label: {
                                    Label("Change due date", systemImage: "calendar")
                                }
                            }
                            Button { onSkip() } label: {
                                Label("Skip for today", systemImage: "moon.fill")
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
            Group {
                if swipeActive || neutralStyle {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(neutralStyle ? Color.sacredBgCard : Color.sacredBgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
    }
}

// MARK: - Heartbeat — 7-day streak as ECG-style pulse line

private struct HeatDotsView: View {
    let streak: Int

    private let width: CGFloat = 56
    private let height: CGFloat = 20
    private let days = 7

    @State private var trimEnd: CGFloat = 0

    var body: some View {
        HeartbeatShape(streak: streak, days: days)
            .trim(from: 0, to: trimEnd)
            .stroke(
                LinearGradient(
                    colors: [Color.sacredGold.opacity(0.3), Color.sacredGold],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 1.5
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                    trimEnd = 1
                }
            }
    }
}

private struct HeartbeatShape: Shape {
    let streak: Int
    let days: Int

    func path(in rect: CGRect) -> Path {
        let stepX = rect.width / CGFloat(days - 1)
        let baseline = rect.height * 0.7
        let peakHeight = rect.height * 0.55

        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        for day in 0..<days {
            let daysAgo = (days - 1) - day
            let isLit = daysAgo < streak
            let x = CGFloat(day) * stepX

            if isLit {
                let riseStart = x - stepX * 0.25
                let fallEnd = x + stepX * 0.25
                path.addLine(to: CGPoint(x: max(riseStart, 0), y: baseline))
                path.addQuadCurve(
                    to: CGPoint(x: min(fallEnd, rect.width), y: baseline),
                    control: CGPoint(x: x, y: baseline - peakHeight)
                )
            } else {
                path.addLine(to: CGPoint(x: x, y: baseline))
            }
        }

        return path
    }
}

// MARK: - Overdue pulse — subtle breathing glow on overdue milestones

// MARK: - Due date label — shows "Apr 5" style date from daysRemaining

private func dueDateLabel(daysRemaining days: Int) -> String {
    if days == 0 { return "Today" }
    if days == 1 { return "Tomorrow" }
    if days < 0 {
        let overdue = abs(days)
        if overdue >= 30 {
            let months = overdue / 30
            return "\(months) month\(months == 1 ? "" : "s") overdue"
        }
        return "\(overdue) day\(overdue == 1 ? "" : "s") overdue"
    }
    let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

private struct OverduePulseModifier: ViewModifier {
    let isOverdue: Bool
    @State private var pulsing = false

    func body(content: Content) -> some View {
        if isOverdue {
            content
                .shadow(color: .sacredRed.opacity(pulsing ? 0.2 : 0.05), radius: pulsing ? 8 : 2, y: 0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
        } else {
            content
        }
    }
}
