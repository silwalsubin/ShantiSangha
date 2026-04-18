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
    @State private var reflectionFallback = false
    @State private var dailyReadingContent: String?
    @State private var dailyReadingOpened: Bool = false
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
                    } else if reflectionFallback {
                        ReflectionCardView(
                            content: "Your reflection is still arriving. Pull down to refresh in a moment.",
                            isLoading: true
                        )
                        .padding(.top, 16)
                    }

                    // Daily Vedic reading — sealed note; user taps to open.
                    if let dailyReadingContent {
                        DailyReadingCardView(
                            content: dailyReadingContent,
                            isOpened: Binding(
                                get: { dailyReadingOpened },
                                set: { newValue in
                                    dailyReadingOpened = newValue
                                    persistDailyReadingOpened(newValue)
                                }
                            )
                        )
                        .padding(.top, 20)
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

                        // Inline practice list — swipe to check in without leaving Home
                        if !vm.pendingRecurring.isEmpty {
                            inlinePractices
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

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
                await loadDailyReading()
                updateWidgetData()
            }
            .task {
                await vm.load()
                await loadReflection()
                await loadDailyReading()
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

    // MARK: - Inline practice list

    private var inlinePractices: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.pendingRecurring.enumerated()), id: \.element.id) { index, task in
                TaskRow(
                    task: task,
                    onDone: {
                        Task {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            await vm.checkIn(id: task.id, completed: true)
                        }
                    },
                    onSkip: { Task { await vm.checkIn(id: task.id, completed: false) } },
                    onUndo: { Task { await vm.undoCheckIn(id: task.id) } },
                    onDelete: { Task { await vm.deleteTask(id: task.id) } },
                    onProgressUpdate: { _ in },
                    activeSwipeId: Binding(
                        get: { vm.activeSwipeId },
                        set: { vm.activeSwipeId = $0 }
                    )
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                if index < vm.pendingRecurring.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: vm.pendingRecurring.map(\.id))
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

    private static let cachedReflectionKey = "home.reflection.content"
    private static let cachedReflectionDateKey = "home.reflection.date"

    private func loadReflection(force: Bool = false) async {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let dateStr = df.string(from: Date())

        // Hydrate from persistent cache first so Home is never empty on tab switch/relaunch
        if !force, reflection == nil {
            let defaults = UserDefaults.standard
            if let cachedDate = defaults.string(forKey: Self.cachedReflectionDateKey),
               cachedDate == dateStr,
               let cachedContent = defaults.string(forKey: Self.cachedReflectionKey),
               !cachedContent.isEmpty {
                reflection = cachedContent
                reflectionDate = cachedDate
                reflectionLoading = false
                reflectionFallback = false
                return
            }
        }

        // In-memory fast path — already have today's reflection
        if !force, reflection != nil, reflectionDate == dateStr { return }

        reflectionLoading = true
        reflectionFallback = false
        defer { reflectionLoading = false }

        do {
            let response: DailyReflectionResponse = try await ApiService.shared.get("/reflection/today?date=\(dateStr)")
            if let content = response.content, !content.isEmpty {
                persistReflection(content, date: dateStr)
                return
            }

            // Generation triggered — poll for result
            for _ in 1...5 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let retry: DailyReflectionResponse = try await ApiService.shared.get("/reflection/today?date=\(dateStr)")
                if let content = retry.content, !content.isEmpty {
                    persistReflection(content, date: dateStr)
                    return
                }
            }

            // Timed out — show a warm fallback so Home is never empty
            reflectionFallback = true
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Reflection", "Failed: \(error.localizedDescription)")
            }
            reflectionFallback = true
        }
    }

    private func persistReflection(_ content: String, date: String) {
        reflection = content
        reflectionDate = date
        reflectionFallback = false
        let defaults = UserDefaults.standard
        defaults.set(content, forKey: Self.cachedReflectionKey)
        defaults.set(date, forKey: Self.cachedReflectionDateKey)
    }

    // MARK: - Daily Reading

    private static let dailyReadingOpenedKeyPrefix = "home.daily_reading.opened."

    private var todayDateString: String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return df.string(from: Date())
    }

    private func loadDailyReading() async {
        let dateStr = todayDateString

        do {
            let response: DailyReadingResponse = try await ApiService.shared.get("/daily-reading/today?date=\(dateStr)")
            if let content = response.content, !content.isEmpty {
                dailyReadingContent = content
                dailyReadingOpened = UserDefaults.standard.bool(forKey: Self.dailyReadingOpenedKeyPrefix + dateStr)
                return
            }

            // Null — job may still be running. Poll a few times.
            for _ in 1...3 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let retry: DailyReadingResponse = try await ApiService.shared.get("/daily-reading/today?date=\(dateStr)")
                if let content = retry.content, !content.isEmpty {
                    dailyReadingContent = content
                    dailyReadingOpened = UserDefaults.standard.bool(forKey: Self.dailyReadingOpenedKeyPrefix + dateStr)
                    return
                }
            }

            // Still null (no birth data, or generation failed) — don't show the card.
            dailyReadingContent = nil
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("DailyReading", "Failed: \(error.localizedDescription)")
            }
            dailyReadingContent = nil
        }
    }

    private func persistDailyReadingOpened(_ opened: Bool) {
        UserDefaults.standard.set(opened, forKey: Self.dailyReadingOpenedKeyPrefix + todayDateString)
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

private struct DailyReadingResponse: Decodable {
    let content: String?
    let date: String
}

