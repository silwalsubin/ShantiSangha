import SwiftUI

/// Home screen — "What needs your attention today?"
/// Mirrors frontend/src/pages/app/home.vue
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showCompleted = false
    @State private var showSkipped = false
    @State private var showNewTask = false
    @State private var newTitle = ""
    @State private var newType: TaskType = .recurring
    @State private var newTargetDate = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("YOUR DHARMA")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundColor(.sacredLabel)

                Text("What needs your attention today?")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.sacredText)
                    .padding(.top, 12)

                if vm.loading {
                    // Skeleton
                    VStack(spacing: 12) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.sacredMuted.opacity(0.08))
                                .frame(height: 56)
                        }
                    }
                    .padding(.top, 24)
                } else if !vm.hasTasks && !showNewTask {
                    // Empty state
                    VStack(spacing: 16) {
                        Text("You haven't set any tasks yet.")
                            .font(.system(size: 14))
                            .foregroundColor(.sacredTextSecondary)

                        Button { showNewTask = true } label: {
                            Text("Set your first task")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .leading, endPoint: .trailing))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else {
                    // New task form
                    if showNewTask {
                        newTaskForm
                            .padding(.top, 24)
                    }

                    // Recurring tasks
                    if !vm.recurringTasks.isEmpty {
                        sectionHeader(icon: "arrow.triangle.2.circlepath", label: "RECURRING TASKS")
                        taskList(vm.recurringTasks)
                    }

                    // Milestones
                    if !vm.milestoneTasks.isEmpty {
                        sectionHeader(icon: "target", label: "MILESTONES")
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

                    // Add task button
                    if vm.hasTasks && !showNewTask {
                        Button { showNewTask = true } label: {
                            Text("+ Add task")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.sacredGold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .task { await vm.load() }
    }

    // MARK: - Section header

    private func sectionHeader(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.sacredLabel)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(3)
                .foregroundColor(.sacredLabel)
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Task list

    private func taskList(_ tasks: [AppTask]) -> some View {
        VStack(spacing: 12) {
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
                        .font(.system(size: 12))
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(color)
            }
            .padding(.top, 16)

            if isExpanded.wrappedValue {
                taskList(tasks)
            }
        }
    }

    // MARK: - New task form

    private var newTaskForm: some View {
        VStack(spacing: 12) {
            // Type picker
            HStack(spacing: 8) {
                typePill("Daily practice", icon: "flame.fill", type: .recurring)
                typePill("Milestone", icon: "target", type: .oneTime)
            }

            TextField(newType == .recurring ? "I want to practice..." : "I want to achieve...", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredBg))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12)))

            if newType == .oneTime {
                DatePicker("Target date", selection: $newTargetDate, displayedComponents: .date)
                    .font(.system(size: 14))
                    .foregroundColor(.sacredText)
            }

            HStack(spacing: 8) {
                Button {
                    guard !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let dateStr = newType == .oneTime ? formatDate(newTargetDate) : nil
                    Task {
                        await vm.createTask(title: newTitle.trimmingCharacters(in: .whitespaces), type: newType, targetDate: dateStr)
                        newTitle = ""
                        newType = .recurring
                        showNewTask = false
                    }
                } label: {
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                }

                Button {
                    showNewTask = false
                    newTitle = ""
                    newType = .recurring
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.sacredTextSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .overlay(Capsule().stroke(Color.sacredMuted.opacity(0.15)))
                }
            }
        }
    }

    private func typePill(_ label: String, icon: String, type: TaskType) -> some View {
        Button { newType = type } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(newType == type ? Color.sacredGold.opacity(0.06) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(newType == type ? Color.sacredGold : Color.sacredMuted.opacity(0.12)))
            )
            .foregroundColor(newType == type ? .sacredGold : .sacredTextSecondary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
