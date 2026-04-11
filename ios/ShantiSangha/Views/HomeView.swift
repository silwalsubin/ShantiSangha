import SwiftUI
import FirebaseAuth

/// Home screen — daily practices and goals
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showNewTask = false
    @State private var showRecurringSummary = false
    @State private var showMilestoneSummary = false
    @State private var mantra: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Daily mantra
                    if let mantra {
                        Text(mantra)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .italic()
                            .foregroundColor(.sacredTextSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 6)
                    }

                    // Greeting
                    Text(timeGreeting)
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    // Gentle evening nudge
                    if shouldShowNudge {
                        nudgeCard
                            .padding(.top, 16)
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
                            Text("You haven't set any practices yet.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)

                            Button { showNewTask = true } label: {
                                Text("Set your first practice")
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
                        if vm.totalRecurring > 0 {
                            Button { showRecurringSummary = true } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 18))
                                        .foregroundColor(.sacredGold)
                                    Rectangle()
                                        .fill(Color.sacredMuted.opacity(0.15))
                                        .frame(height: 1)
                                    progressRing
                                }
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                            if !vm.pendingRecurring.isEmpty {
                                taskList(vm.pendingRecurring)
                            }
                        }

                        // Commitments
                        if vm.totalMilestones > 0 {
                            MilestoneTimelineView(
                                milestones: vm.filteredCommitments,
                                onDone: { id in Task { await vm.checkIn(id: id, completed: true) } },
                                onSkip: { id in Task { await vm.checkIn(id: id, completed: false) } },
                                onDelete: { id in Task { await vm.deleteTask(id: id) } },
                                onProgressUpdate: { id, val in Task { await vm.updateProgress(id: id, value: val) } },
                                onDueDateUpdate: { id, date in Task { await vm.updateDueDate(id: id, date: date) } },
                                onShowAll: { showMilestoneSummary = true },
                                filter: $vm.commitmentFilter,
                                activeSwipeId: $vm.activeSwipeId,
                                totalMilestones: vm.filteredTotal,
                                doneMilestones: vm.filteredDone,
                                hasOverdue: vm.filteredOverdue
                            )
                            .padding(.top, 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable { await vm.load() }
            .task {
                await vm.load()
                await loadMantra()
            }

            // Floating add button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showNewTask = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.sacredHeading)
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .cymbalGold()
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
        .navigationDestination(isPresented: $showRecurringSummary) {
            RecurringSummaryView(vm: vm)
        }
        .navigationDestination(isPresented: $showMilestoneSummary) {
            MilestoneSummaryView(vm: vm, initialFilter: vm.commitmentFilter)
        }
    }

    // MARK: - Gentle nudge

    private static let nudgeMessages = [
        "Your practices are here when you're ready.",
        "No rush. Just a quiet reminder that you showed up by opening the app.",
        "Even a small step counts. What feels doable right now?",
        "The day isn't over yet. You're here — that matters.",
        "A moment of stillness is still a practice.",
        "You opened the app. That's the hardest part.",
        "Whatever you can do today is enough.",
    ]

    @State private var nudgeMessage = nudgeMessages.randomElement()!

    private var shouldShowNudge: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && !vm.loading && vm.totalRecurring > 0 && vm.doneRecurring == 0
    }

    private var nudgeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "leaf")
                .font(.sacredIcon)
                .foregroundColor(.sacredGold)
                .padding(.top, 2)

            Text(nudgeMessage)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sacredGold.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sacredGold.opacity(0.1)))
        )
    }

    // MARK: - Mantra

    private func loadMantra() async {
        do {
            let response: MantraResponse = try await ApiService.shared.get("/mantra/today")
            if let content = response.content, !content.isEmpty {
                mantra = content
            } else {
                // Generation triggered — retry after a few seconds
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let retry: MantraResponse = try await ApiService.shared.get("/mantra/today")
                if let content = retry.content, !content.isEmpty {
                    mantra = content
                }
            }
        } catch {
            // Mantra is non-critical — fail silently
        }
    }

    // MARK: - Time greeting

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = Auth.auth().currentUser?.displayName?
            .components(separatedBy: " ").first
        let name = firstName.map { ", \($0)" } ?? ""
        if hour < 12 { return "Good morning\(name)" }
        if hour < 17 { return "Good afternoon\(name)" }
        return "Good evening\(name)"
    }

    // MARK: - Progress ring

    private var progressRing: some View {
        let total = vm.totalRecurring
        let done = vm.doneRecurring
        let progress = total > 0 ? Double(done) / Double(total) : 0

        return ZStack {
            Circle()
                .stroke(Color.sacredMuted.opacity(0.15), lineWidth: 4)
            if done > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient.sacredGoldShiny,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: progress)
            }

            if done > 0 {
                VStack(spacing: 0) {
                    Text("\(done)")
                        .font(.sacredTextSemibold)
                        .foregroundColor(.sacredGold)
                    Text("of \(total)")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
            }
        }
        .frame(width: 48, height: 48)
    }

    // MARK: - Task list

    private func taskList(_ tasks: [AppTask]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    onDone: { Task { await vm.checkIn(id: task.id, completed: true) } },
                    onSkip: { Task { await vm.checkIn(id: task.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: task.id) } },
                    onDelete: { Task { await vm.deleteTask(id: task.id) } },
                    onProgressUpdate: { val in Task { await vm.updateProgress(id: task.id, value: val) } },
                    onDueDateUpdate: { date in Task { await vm.updateDueDate(id: task.id, date: date) } },
                    activeSwipeId: $vm.activeSwipeId
                )

                if index < tasks.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                        .padding(.trailing, 16)
                }
            }
        }
    }
}

// MARK: - Mantra response

private struct MantraResponse: Decodable {
    let content: String?
}
