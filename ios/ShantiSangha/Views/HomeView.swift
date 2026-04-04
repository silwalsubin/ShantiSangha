import SwiftUI

/// Home screen — "What needs your attention today?"
/// Mirrors frontend/src/pages/app/home.vue
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showCompleted = false
    @State private var showSkipped = false
    @State private var showNewTask = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with progress ring
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("YOUR DHARMA")
                                .font(.sacredMicroBold)
                                .tracking(3)
                                .foregroundColor(.sacredLabel)
                            Text("What needs your attention today?")
                                .font(.sacredTitle)
                                .foregroundColor(.sacredText)
                        }

                        Spacer()

                        if !vm.loading && vm.hasTasks {
                            progressRing
                        }
                    }

                    if vm.loading {
                        VStack(spacing: 12) {
                            ForEach(0..<2, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.sacredMuted.opacity(0.08))
                                    .frame(height: 56)
                            }
                        }
                        .padding(.top, 24)
                    } else if !vm.hasTasks {
                        VStack(spacing: 16) {
                            Text("You haven't set any tasks yet.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)

                            Button { showNewTask = true } label: {
                                Text("Set your first task")
                                    .font(.sacredTextSemibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(LinearGradient.sacredGoldShiny)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    } else {
                        // Recurring tasks
                        if !vm.recurringTasks.isEmpty {
                            sectionLabel("RECURRING")
                            taskList(vm.recurringTasks)
                        }

                        // Milestones
                        if !vm.milestoneTasks.isEmpty {
                            sectionLabel("MILESTONES")
                            taskList(vm.milestoneTasks)
                        }

                        // Completed
                        if !vm.completedTasks.isEmpty {
                            collapsibleSection(
                                icon: "checkmark",
                                label: "\(vm.completedTasks.count) completed",
                                color: .sacredGreen,
                                isExpanded: $showCompleted,
                                tasks: vm.completedTasks
                            )
                        }

                        // Skipped
                        if !vm.skippedTasks.isEmpty {
                            collapsibleSection(
                                icon: "forward.fill",
                                label: "\(vm.skippedTasks.count) skipped",
                                color: .sacredMuted,
                                isExpanded: $showSkipped,
                                tasks: vm.skippedTasks
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable { await vm.load() }
            .task { await vm.load() }

            // Floating add button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showNewTask = true
            } label: {
                Image(systemName: "plus")
                    .font(.sacredHeading)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(RadialGradient.sacredGoldShiny)
                    .clipShape(Circle())
                    .shimmer()
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate in
                await vm.createTask(title: title, type: type, targetDate: targetDate)
            }
        }
    }

    // MARK: - Progress ring

    private var progressRing: some View {
        let total = vm.totalRecurring
        let done = vm.doneRecurring
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient.sacredGoldShiny,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)

            VStack(spacing: 0) {
                Text("\(done)")
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredGold)
                Text("of \(total)")
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
        }
        .frame(width: 48, height: 48)
    }

    // MARK: - Compact section label

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.sacredSectionLabel)
            .tracking(3)
            .foregroundColor(.sacredLabel)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    // MARK: - Task list

    private func taskList(_ tasks: [AppTask]) -> some View {
        VStack(spacing: 8) {
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    onDone: { Task { await vm.checkIn(id: task.id, completed: true) } },
                    onSkip: { Task { await vm.checkIn(id: task.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: task.id) } },
                    onDelete: { Task { await vm.deleteTask(id: task.id) } },
                    onProgressUpdate: { val in Task { await vm.updateProgress(id: task.id, value: val) } }
                )
            }
        }
    }

    // MARK: - Collapsible section

    private func collapsibleSection(icon: String, label: String, color: Color, isExpanded: Binding<Bool>, tasks: [AppTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isExpanded.wrappedValue.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.sacredSmall)
                    Text(label)
                        .font(.sacredSmallMedium)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.sacredMicro)
                }
                .foregroundColor(color)
            }
            .padding(.top, 12)

            if isExpanded.wrappedValue {
                taskList(tasks)
            }
        }
    }
}
