import SwiftUI
import FirebaseAuth
import WidgetKit

/// Home screen — daily dashboard with progress circles
struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showNewTask = false
    @State private var showRecurringSummary = false
    @State private var showMilestoneSummary = false
    @State private var reflection: String?
    @State private var reflectionDate: String?
    @State private var reflectionLoading = true
    @State private var showFAB = true
    @State private var practicesCompleted = false
    @State private var ringPulse = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Greeting
                    Text(timeGreeting)
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    // Daily reflection
                    if let reflection {
                        ReflectionCardView(content: reflection)
                            .padding(.top, 16)
                    } else if reflectionLoading {
                        ReflectionCardView(content: "Preparing your reflection...", isLoading: true)
                            .padding(.top, 16)
                    }

                    // Evening nudge
                    if shouldShowNudge {
                        nudgeCard
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                    }

                    if vm.loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if !vm.hasTasks {
                        emptyState
                    } else {
                        // Dashboard circles
                        HStack(spacing: 0) {
                            if vm.totalRecurring > 0 {
                                Button { showRecurringSummary = true } label: {
                                    progressCircle(
                                        label: "Practices",
                                        done: vm.doneRecurring,
                                        total: vm.totalRecurring,
                                        color: .sacredGold,
                                        isComplete: vm.allPracticesDone,
                                        almostDone: vm.totalRecurring > 1 && vm.doneRecurring == vm.totalRecurring - 1
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }

                            if vm.filteredTotal > 0 {
                                Button { showMilestoneSummary = true } label: {
                                    progressCircle(
                                        label: "Goals",
                                        done: vm.filteredDone,
                                        total: vm.filteredTotal,
                                        color: .sacredGoldDark,
                                        detail: vm.goalsSummaryDetail
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                        .padding(.bottom, 20)

                        // All done message
                        if practicesCompleted {
                            Text("All practices complete. You showed up today.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.bottom, 100)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .refreshable {
                await vm.load()
                await loadReflection(force: true)
                updateWidgetData()
            }
            .task {
                await vm.load()
                await loadReflection()
                updateWidgetData()
                // Sync completion state on initial load (no haptic)
                practicesCompleted = vm.allPracticesDone
            }
            .onChange(of: vm.doneRecurring) { updateWidgetData() }
            .onChange(of: vm.doneMilestones) { updateWidgetData() }
            .onChange(of: vm.allPracticesDone) { _, allDone in
                if allDone {
                    // Haptic + animate in the completion state
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeOut(duration: 0.5)) {
                        practicesCompleted = true
                    }
                    // Pulse the ring glow
                    withAnimation(.easeInOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                        ringPulse = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        ringPulse = false
                    }
                } else {
                    withAnimation { practicesCompleted = false }
                    ringPulse = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .silentPushReceived)) { notification in
                let type = notification.userInfo?["type"] as? String
                Task {
                    if type == "reflection" { await loadReflection(force: true) }
                }
            }
            .onAppear { withAnimation(.easeOut(duration: 0.25)) { showFAB = true } }
            .onDisappear { showFAB = false }

            // FAB
            if showFAB {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showNewTask = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.sacredHeading)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .goldShine()
                        .clipShape(Circle())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
            MilestoneSummaryView(vm: vm)
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
        .padding(.top, 40)
    }

    // MARK: - Progress circle

    private func progressCircle(label: String, done: Int, total: Int, color: Color, detail: String? = nil, isComplete: Bool = false, almostDone: Bool = false) -> some View {
        let progress = total > 0 ? Double(done) / Double(total) : 0
        // Warm the stroke when one away from completion
        let strokeColor = almostDone ? Color.sacredGold : color

        return VStack(spacing: 14) {
            ZStack {
                // Completion glow — soft radial behind the ring
                if isComplete && ringPulse {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 150, height: 150)
                        .blur(radius: 12)
                }

                // Track
                Circle()
                    .stroke(Color.sacredMuted.opacity(0.12), lineWidth: 10)

                // Progress arc
                if done > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(
                                colors: [strokeColor.opacity(0.7), strokeColor, strokeColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: progress)
                }

                // Motion-reactive gold shine — follows the filled arc
                if done > 0 {
                    GoldShineRing(size: 130, lineWidth: 10, progress: progress)
                }

                // Count
                VStack(spacing: 2) {
                    if let detail = detail {
                        Text(detail)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("\(done)")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundColor(done > 0 ? strokeColor : .sacredMuted)
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .foregroundColor(color.opacity(0.7))
                        } else {
                            Text("of \(total)")
                                .font(.sacredCaption)
                                .foregroundColor(.sacredMuted)
                        }
                    }
                }
            }
            .frame(width: 130, height: 130)

            HStack(spacing: 6) {
                Image(systemName: label == "Practices" ? "arrow.triangle.2.circlepath" : "calendar.badge.clock")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                Text(label)
                    .font(.sacredTextSemibold)
                    .foregroundColor(.sacredTextSecondary)
            }
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

    @State private var nudgeMessage = Self.nudgeMessages.randomElement()!

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

    // MARK: - Widget data sync

    private func updateWidgetData() {
        let pending = vm.tasks.filter { $0.type == .oneTime && $0.completedAt == nil }
        WidgetData.update(
            reflection: reflection,
            practicesDone: vm.doneRecurring,
            practicesTotal: vm.totalRecurring,
            goalsOverdue: pending.filter { ($0.daysRemaining ?? 1) < 0 }.count,
            goalsDueToday: pending.filter { $0.daysRemaining == 0 }.count,
            userName: Auth.auth().currentUser?.displayName?.components(separatedBy: " ").first
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaReflection")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaDashboard")
    }

    // MARK: - Reflection

    private func loadReflection(force: Bool = false) async {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())

        // Skip refetch on tab switch if we already have today's reflection
        if !force, reflection != nil, reflectionDate == dateStr { return }

        reflectionLoading = true
        defer { reflectionLoading = false }

        do {
            let response: DailyReflectionResponse = try await ApiService.shared.get("/reflection/today?date=\(dateStr)")
            if let content = response.content, !content.isEmpty {
                reflection = content
                reflectionDate = dateStr
                return
            }

            // Generation triggered — poll for result
            for i in 1...5 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let retry: DailyReflectionResponse = try await ApiService.shared.get("/reflection/today?date=\(dateStr)")
                if let content = retry.content, !content.isEmpty {
                    reflection = content
                    reflectionDate = dateStr
                    return
                }
            }
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Reflection", "Failed: \(error.localizedDescription)")
            }
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
}

private struct DailyReflectionResponse: Decodable {
    let content: String?
}

