import SwiftUI
import FirebaseAuth

/// Home screen — daily practices and goals at a glance
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

                    // Evening nudge
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
                        emptyState
                    } else {
                        // ── Daily Practices ──
                        if vm.totalRecurring > 0 {
                            practicesSection
                        }

                        // ── Goals ──
                        if vm.pendingGoalCount > 0 {
                            goalsSection
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

            // FAB
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

    // MARK: - Empty state

    private var emptyState: some View {
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
    }

    // MARK: - Practices section

    private var practicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — tappable
            Button { showRecurringSummary = true } label: {
                HStack {
                    Text("Daily Practices")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Spacer()
                    Text("\(vm.doneRecurring) of \(vm.totalRecurring)")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                    Image(systemName: "chevron.right")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 12)

            // All done message
            if vm.allPracticesDone {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.sacredIcon)
                        .foregroundColor(.sacredGold)
                    Text("All practices complete. You showed up today.")
                        .font(.sacredText)
                        .foregroundColor(.sacredTextSecondary)
                }
                .padding(.vertical, 16)
            }

            // Practice rows — pending first, then completed (muted)
            VStack(spacing: 0) {
                ForEach(Array(vm.allRecurring.enumerated()), id: \.element.id) { index, task in
                    practiceRow(task)

                    if index < vm.allRecurring.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }

    private func practiceRow(_ task: AppTask) -> some View {
        let isDone = task.checkedIn

        return HStack(spacing: 12) {
            // Check circle — tappable
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if isDone {
                    Task { await vm.undoCheckIn(id: task.id) }
                } else {
                    Task { await vm.checkIn(id: task.id, completed: true) }
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isDone ? .sacredGold : .sacredMuted.opacity(0.4))
            }

            // Title
            Text(task.title)
                .font(.sacredText)
                .foregroundColor(isDone ? .sacredMuted : .sacredText)
                .strikethrough(isDone, color: .sacredMuted.opacity(0.3))

            Spacer()

            // Streak count
            if task.currentStreak > 0 {
                Text("\(task.currentStreak)d")
                    .font(.sacredSmall)
                    .foregroundColor(isDone ? .sacredMuted : .sacredGold)
            }
        }
        .padding(.vertical, 14)
        .animation(.easeOut(duration: 0.2), value: isDone)
    }

    // MARK: - Goals section

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header — tappable
            Button { showMilestoneSummary = true } label: {
                HStack {
                    Text("Goals")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Spacer()
                    Text("\(vm.pendingGoalCount)")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredMuted)
                    Image(systemName: "chevron.right")
                        .font(.sacredMicro)
                        .foregroundColor(.sacredMuted)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 12)

            // Urgent goal rows
            VStack(spacing: 0) {
                ForEach(Array(vm.urgentGoals.enumerated()), id: \.element.id) { index, task in
                    goalRow(task)

                    if index < vm.urgentGoals.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }

    private func goalRow(_ task: AppTask) -> some View {
        HStack(spacing: 12) {
            // Diamond icon
            Image(systemName: "diamond")
                .font(.system(size: 14))
                .foregroundColor(.sacredGold)

            // Title
            Text(task.title)
                .font(.sacredText)
                .foregroundColor(.sacredText)
                .lineLimit(2)

            Spacer()

            // Due date
            Text(goalDateLabel(task.daysRemaining))
                .font(.sacredSmall)
                .foregroundColor(goalDateColor(task.daysRemaining))
        }
        .padding(.vertical, 14)
    }

    private func goalDateLabel(_ days: Int?) -> String {
        guard let days else { return "" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 0 {
            let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "Past \(f.string(from: date))"
        }
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func goalDateColor(_ days: Int?) -> Color {
        guard let days else { return .sacredMuted }
        if days < 0 { return .sacredMuted }
        if days == 0 { return .sacredGold }
        return .sacredTextSecondary
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
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let retry: MantraResponse = try await ApiService.shared.get("/mantra/today")
                if let content = retry.content, !content.isEmpty {
                    mantra = content
                }
            }
        } catch {}
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
}

// MARK: - Mantra response

private struct MantraResponse: Decodable {
    let content: String?
}
