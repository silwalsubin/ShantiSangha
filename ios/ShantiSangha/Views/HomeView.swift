import SwiftUI
import FirebaseAuth
import WidgetKit

/// Home screen — daily dashboard with progress circles
struct HomeView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var vm = HomeViewModel()
    @StateObject private var health = HealthKitService.shared
    @StateObject private var weather = WeatherService.shared
    @State private var showNewTask = false
    @State private var reflection: String?
    @State private var reflectionDate: String?
    /// True when `reflection` is a prior day's reflection shown while today's
    /// is still being composed. Drives the "TODAY'S IS BEING WRITTEN" chip.
    @State private var reflectionIsFallback: Bool = false
    @State private var showFAB = true
    @State private var practicesCompleted = false
    @State private var ringPulse = false
    @State private var showProfileMenu = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 0) {
                    // Greeting
                    Text(timeGreeting)
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)

                    // Whole-day context strip — sleep, steps, weather. Only
                    // appears when the user has enabled Health / Weather in
                    // Settings AND the relevant data is available. Silent
                    // otherwise so Home stays uncluttered.
                    WholeDayContextStrip(health: health, weather: weather)
                        .padding(.top, 10)

                    // Daily reflection. Today's if ready, else yesterday's (or
                    // day-before's) as a fallback with a subtle chip. Home is
                    // never empty — the server returns a fallback reflection
                    // when today's hasn't been composed yet.
                    if let reflection {
                        ReflectionCardView(
                            content: reflection,
                            caption: reflectionIsFallback ? "TODAY'S IS BEING WRITTEN" : nil
                        )
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
                                progressCircle(
                                    label: "Practices",
                                    done: vm.doneRecurring,
                                    total: vm.totalRecurring,
                                    color: .sacredGold,
                                    isComplete: vm.allPracticesDone,
                                    almostDone: vm.totalRecurring > 1 && vm.doneRecurring == vm.totalRecurring - 1
                                )
                                .frame(maxWidth: .infinity)
                            }

                            if vm.filteredTotal > 0 {
                                progressCircle(
                                    label: "Goals",
                                    done: vm.filteredDone,
                                    total: vm.filteredTotal,
                                    color: .sacredGoldDark,
                                    detail: vm.goalsSummaryDetail
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                        .padding(.bottom, 20)

                        // Inline practice list — swipe to check in without leaving Home
                        if !vm.pendingRecurring.isEmpty {
                            inlinePractices
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showProfileMenu = true } label: {
                        Circle()
                            .fill(RadialGradient.sacredGoldShiny)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Text(profileInitial)
                                    .font(.system(size: 13, weight: .semibold, design: .serif))
                                    .foregroundColor(.white)
                            )
                            .overlay(
                                Circle().stroke(Color.sacredGold.opacity(0.3), lineWidth: 0.5)
                            )
                    }
                    .accessibilityLabel("Profile menu")
                }
            }
            .fullScreenCover(isPresented: $showProfileMenu) {
                ProfileMenuSheet()
                    .environmentObject(auth)
            }
            .refreshable {
                await vm.load()
                await loadReflection(force: true)
                updateWidgetData()
                await refreshWholeDayContext()
            }
            .task {
                await vm.load()
                await loadReflection()
                updateWidgetData()
                // Sync completion state on initial load (no haptic)
                practicesCompleted = vm.allPracticesDone
                await refreshWholeDayContext()
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
            NewTaskView { title, type, targetDate, deeperWhy in
                await vm.createTask(title: title, type: type, targetDate: targetDate, deeperWhy: deeperWhy)
            }
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

            SacredPrimaryButton("Set your first practice") {
                showNewTask = true
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

        // Hydrate from persistent cache first so Home is never empty on tab
        // switch / relaunch. Only today's real reflection is cached — fallbacks
        // aren't persisted so we always re-check the server for the real one.
        if !force, reflection == nil {
            let defaults = UserDefaults.standard
            if let cachedDate = defaults.string(forKey: Self.cachedReflectionDateKey),
               cachedDate == dateStr,
               let cachedContent = defaults.string(forKey: Self.cachedReflectionKey),
               !cachedContent.isEmpty {
                reflection = cachedContent
                reflectionDate = cachedDate
                reflectionIsFallback = false
                return
            }
        }

        // In-memory fast path — already have today's real reflection. If the
        // state is a fallback we still re-check the server in case today's
        // has been composed since the last fetch.
        if !force, reflection != nil, reflectionDate == dateStr, !reflectionIsFallback { return }

        do {
            let response: DailyReflectionResponse = try await ApiService.shared.get("/reflection/today?date=\(dateStr)")

            if let content = response.content, !content.isEmpty {
                // Today's is ready — persist and end the fallback state if any.
                persistReflection(content, date: dateStr)
                return
            }

            // Today's isn't ready yet. The server enqueued generation and
            // returned the most recent prior reflection as a fallback. Show
            // it with a caption; when the silent push "type: reflection"
            // arrives, loadReflection(force: true) swaps in the real one.
            if let fallback = response.fallback, !fallback.content.isEmpty {
                reflection = fallback.content
                reflectionDate = fallback.date
                reflectionIsFallback = true
                return
            }

            // Brand-new user with no prior reflections at all. Leave the card
            // hidden; generation will catch up, silent push will wake us.
            reflection = nil
            reflectionDate = nil
            reflectionIsFallback = false
        } catch {
            if !error.isCancellation {
                AppLogger.shared.error("Reflection", "Failed: \(error.localizedDescription)")
            }
        }
    }

    private func persistReflection(_ content: String, date: String) {
        reflection = content
        reflectionDate = date
        reflectionIsFallback = false
        let defaults = UserDefaults.standard
        defaults.set(content, forKey: Self.cachedReflectionKey)
        defaults.set(date, forKey: Self.cachedReflectionDateKey)
    }

    // MARK: - Profile

    private var profileInitial: String {
        let source = auth.user?.displayName?.trimmingCharacters(in: .whitespaces)
            ?? auth.user?.email
            ?? "?"
        return String(source.prefix(1)).uppercased()
    }

    // MARK: - Whole-day context

    /// Pulls fresh Health + Weather data in parallel. No-op for disabled
    /// services — each one guards itself internally.
    private func refreshWholeDayContext() async {
        async let h: () = health.refreshWholeDayContext()
        async let w: Bool = weather.refreshIfStale()
        _ = await (h, w)
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
    let fallback: FallbackReflection?

    struct FallbackReflection: Decodable {
        let content: String
        let date: String
    }
}

// MARK: - Whole-day context strip

/// Thin, muted row under the greeting showing any "whole day context" the
/// user has enabled — sleep, steps, weather. Stays silent (empty view) when
/// nothing is available, so Home remains uncluttered for users who haven't
/// turned on Health or Weather in Settings.
private struct WholeDayContextStrip: View {
    @ObservedObject var health: HealthKitService
    @ObservedObject var weather: WeatherService

    var body: some View {
        let items = buildItems()
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { i in
                    if i > 0 {
                        Circle()
                            .fill(Color.sacredMuted.opacity(0.4))
                            .frame(width: 2, height: 2)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: items[i].symbol)
                            .font(.system(size: 11))
                            .foregroundColor(.sacredMuted)
                        Text(items[i].label)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredTextSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private struct Item {
        let symbol: String
        let label: String
    }

    private func buildItems() -> [Item] {
        var items: [Item] = []

        if weather.isEnabled, let snap = weather.snapshot {
            items.append(Item(symbol: snap.conditionSymbol, label: snap.temperatureLabel))
        }

        if health.isEnabled {
            if let hours = health.sleepHoursLastNight, hours > 0 {
                let rounded = (hours * 10).rounded() / 10
                let label = rounded.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(rounded))h"
                    : String(format: "%.1fh", rounded)
                items.append(Item(symbol: "moon.zzz", label: label))
            }
            if let steps = health.stepsToday, steps > 0 {
                items.append(Item(symbol: "figure.walk", label: stepsLabel(steps)))
            }
        }

        return items
    }

    private func stepsLabel(_ steps: Int) -> String {
        if steps >= 1000 {
            let k = Double(steps) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(steps)"
    }
}

// MARK: - Profile menu sheet

/// Identity-scoped surface on Home: birth chart, settings, sign out.
/// Owns its own NavigationStack so pushes stay inside the sheet.
struct ProfileMenuSheet: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    menuList
                    signOutButton
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .background(Color.sacredBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.sacredTextMedium)
                        .foregroundColor(.sacredGold)
                }
            }
            .confirmationDialog(
                "Are you sure you want to sign out?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(RadialGradient.sacredGoldShiny)
                .frame(width: 72, height: 72)
                .overlay(
                    Text(initial)
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                )
                .overlay(Circle().stroke(Color.sacredGold.opacity(0.3), lineWidth: 0.5))
            if let email = auth.user?.email {
                Text(email)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var menuList: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: VedicChartView()) {
                menuRow(icon: "moon.stars", label: "Birth chart", subtitle: "Your Jyotish context")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            NavigationLink(destination: SettingsView()) {
                menuRow(icon: "gearshape", label: "Settings", subtitle: "Your sacred space")
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredGold.opacity(0.08)))
    }

    private func menuRow(icon: String, label: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.sacredGold.opacity(0.75))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                Text(subtitle)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.sacredMuted.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var signOutButton: some View {
        Button { showSignOutConfirmation = true } label: {
            HStack {
                Spacer()
                Text("Sign Out")
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredRed)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.sacredRed.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredRed.opacity(0.15)))
        }
    }

    private var initial: String {
        let source = auth.user?.displayName?.trimmingCharacters(in: .whitespaces)
            ?? auth.user?.email
            ?? "?"
        return String(source.prefix(1)).uppercased()
    }
}
