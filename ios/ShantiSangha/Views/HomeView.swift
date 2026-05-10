import SwiftUI
import FirebaseAuth
import WidgetKit

/// Home screen — daily dashboard with progress circles
struct HomeView: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var profile: ProfileService
    @StateObject private var vm = HomeViewModel()
    @StateObject private var health = HealthKitService.shared
    @StateObject private var weather = WeatherService.shared
    @State private var showNewTask = false
    @State private var showRecurringSummary = false
    @State private var showMilestoneSummary = false
    @State private var reflection: String?
    @State private var reflectionDate: String?
    /// True when `reflection` is a prior day's reflection shown while today's
    /// is still being composed. Drives the "TODAY'S IS BEING WRITTEN" chip.
    @State private var reflectionIsFallback: Bool = false
    /// Hides the reflection card for the rest of the day after the user
    /// dismisses it. A new day or a different reflection will surface again.
    @State private var reflectionDismissed: Bool = false
    @State private var practicesCompleted = false
    @State private var ringPulse = false
    @State private var showProfileMenu = false
    @StateObject private var notifications = NotificationsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    SacredHomeHeader(dateLabel: todayLabel, greeting: timeGreeting)

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
                    if let reflection, !reflectionDismissed {
                        ReflectionCardView(
                            content: reflection,
                            caption: reflectionIsFallback ? "TODAY'S IS BEING WRITTEN" : nil,
                            onClose: { dismissReflection() }
                        )
                        .padding(.top, SacredSpacing.l)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if shouldShowNudge {
                        SacredNudgeCard(icon: "leaf", message: nudgeMessage)
                            .padding(.top, SacredSpacing.m)
                            .padding(.horizontal, SacredSpacing.m)
                    }

                    if vm.loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if !vm.hasTasks {
                        emptyState
                    } else {
                        dailyRhythmCard
                            .padding(.horizontal, SacredSpacing.m)
                            .padding(.top, 34)
                            .padding(.bottom, 20)

                        // Inline practice list — swipe to check in without leaving Home
                        if !vm.pendingRecurring.isEmpty {
                            inlinePractices
                                .padding(.top, SacredSpacing.xs)
                        }

                        SacredGhostRow(icon: "plus", label: "Add task") {
                            showNewTask = true
                        }
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, vm.pendingRecurring.isEmpty ? SacredSpacing.xs : SacredSpacing.lux)

                        if practicesCompleted {
                            Text("All practices complete. You showed up today.")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, SacredSpacing.xs)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }

                    // Wise Cat — astro-aware trading signals. Quiet by default;
                    // the card shows what's there only if the user is using it.
                    WiseCatHomeCard()
                        .padding(.horizontal, SacredSpacing.m)
                        .padding(.top, SacredSpacing.l)
                }
                .padding(.top, SacredSpacing.xl)
                .padding(.bottom, SacredSpacing.tabBarSafe)
            }
            .background(Color.clear)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 14) {
                            notificationsBellButton
                            profileMenuButton
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 14) {
                            notificationsBellButton
                            profileMenuButton
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showProfileMenu) {
                ProfileMenuSheet()
                    .environmentObject(auth)
                    .environmentObject(profile)
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
                await notifications.refreshUnreadCount()
            }
            .onChange(of: vm.doneRecurring) { updateWidgetData() }
            .onChange(of: vm.doneMilestones) { updateWidgetData() }
            // Foreground refresh — pull truth from server when the app
            // returns from background. The `.task` modifier above only
            // fires when HomeView is mounted; foregrounding doesn't
            // re-run it, so the bell badge would otherwise drift while
            // pushes-while-backgrounded bumped the home-screen icon.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await notifications.refreshUnreadCount() }
                }
            }
            .onChange(of: reflection) { _, _ in syncReflectionDismissedFlag() }
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
        }
        .navigationDestination(isPresented: $showNewTask) {
            NewTaskView { title, type, targetDate, deeperWhy in
                await vm.createTask(title: title, type: type, targetDate: targetDate, deeperWhy: deeperWhy)
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

            SacredPrimaryButton("Set your first task") {
                showNewTask = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Today's rhythm

    private var dailyRhythmCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.lux) {
                HStack {
                    VStack(alignment: .leading, spacing: SacredSpacing.xxs) {
                        Text("TODAY'S RHYTHM")
                            .font(.sacredSectionLabel)
                            .tracking(3)
                            .foregroundColor(.sacredLabel)
                        Text(rhythmSubtitle)
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                    Spacer()
                }

                HStack(spacing: 0) {
                    if vm.totalRecurring > 0 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showRecurringSummary = true
                        } label: {
                            SacredProgressRing(
                                label: "Practices",
                                icon: "arrow.triangle.2.circlepath",
                                done: vm.doneRecurring,
                                total: vm.totalRecurring,
                                color: .sacredGold,
                                isComplete: vm.allPracticesDone,
                                almostDone: vm.totalRecurring > 1 && vm.doneRecurring == vm.totalRecurring - 1,
                                ringPulse: ringPulse
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }

                    if vm.filteredTotal > 0 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showMilestoneSummary = true
                        } label: {
                            SacredProgressRing(
                                label: "Goals",
                                icon: "calendar.badge.clock",
                                done: vm.filteredDone,
                                total: vm.filteredTotal,
                                color: .sacredGoldDark,
                                detail: vm.goalsSummaryDetail
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(SacredSpacing.lux)
        }
    }

    private var rhythmSubtitle: String {
        if vm.allPracticesDone { return "The circle is complete." }
        if vm.totalRecurring > 0 {
            let remaining = max(vm.totalRecurring - vm.doneRecurring, 0)
            if remaining == 1 { return "One quiet step remains." }
            if remaining > 1 { return "\(remaining) practices are waiting." }
        }
        if vm.filteredTotal > 0 { return "Your commitments are in view." }
        return "A clear day."
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

    // MARK: - Widget data sync

    private func updateWidgetData() {
        let pending = vm.tasks.filter { $0.type == .oneTime && $0.completedAt == nil }
        WidgetData.update(
            reflection: reflection,
            practicesDone: vm.doneRecurring,
            practicesTotal: vm.totalRecurring,
            goalsOverdue: pending.filter { ($0.daysRemaining ?? 1) < 0 }.count,
            goalsDueToday: pending.filter { $0.daysRemaining == 0 }.count,
            userName: preferredFirstName
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaReflection")
        WidgetCenter.shared.reloadTimelines(ofKind: "ShantiSanghaDashboard")
    }

    /// First word of the user's chosen display name when set, falling back
    /// to the Firebase displayName from Google Sign-In. Used by the
    /// greeting and the widget's user name.
    private var preferredFirstName: String? {
        let chosen = profile.profile?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let chosen, !chosen.isEmpty {
            return chosen.components(separatedBy: " ").first
        }
        return Auth.auth().currentUser?.displayName?
            .components(separatedBy: " ").first
    }

    // MARK: - Reflection

    private static let cachedReflectionKey = "home.reflection.content"
    private static let cachedReflectionDateKey = "home.reflection.date"
    /// Signature of the reflection the user dismissed — composed of today's
    /// calendar date and the reflection content. A new day or a different
    /// reflection produces a different signature and surfaces the card again.
    private static let dismissedReflectionKey = "home.reflection.dismissed.signature"

    private func reflectionSignature(_ content: String) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        return "\(df.string(from: Date()))::\(content)"
    }

    private func syncReflectionDismissedFlag() {
        guard let content = reflection else {
            reflectionDismissed = false
            return
        }
        let stored = UserDefaults.standard.string(forKey: Self.dismissedReflectionKey)
        reflectionDismissed = (stored == reflectionSignature(content))
    }

    private func dismissReflection() {
        guard let content = reflection else { return }
        UserDefaults.standard.set(reflectionSignature(content), forKey: Self.dismissedReflectionKey)
        withAnimation(.easeOut(duration: 0.3)) {
            reflectionDismissed = true
        }
    }

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

    private var profileMenuButton: some View {
        Button {
            showProfileMenu = true
        } label: {
            profileMenuAvatar
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Profile menu")
    }

    /// Bell-icon entry to the in-app notifications inbox.
    ///
    /// The bell sits inside a circular parchment chip whose geometry
    /// (36pt diameter, 2pt sacredGold-opacity-0.42 stroke) is identical
    /// to the profile avatar — so the two toolbar elements read as a
    /// paired set of circles, not "outline glyph next to filled image".
    /// The avatar carries a face, the bell carries a glyph; same form,
    /// different content.
    ///
    /// Two visual states, driven by content:
    ///   - empty inbox: outlined bell, calm and restrained
    ///   - unread > 0: filled bell + bindi-like gold dot anchored to
    ///     the chip's rim. The icon literally fills *because* there's
    ///     something waiting — no iOS-style red badge.
    private var notificationsBellButton: some View {
        NavigationLink(destination: NotificationsView()) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.sacredBgCard.opacity(0.72))
                    .overlay(
                        Image(systemName: notifications.unreadCount > 0 ? "bell.fill" : "bell")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.sacredGold)
                    )
                    .frame(width: 36, height: 36)
                    // Shared chrome — gold ring + drop shadow. Same
                    // modifier ProfileAvatarImage uses, so if the chip
                    // geometry ever changes there's only one place to
                    // update.
                    .sacredCircularChrome()
                    .frame(width: 44, height: 44)   // 44pt touch target

                if notifications.unreadCount > 0 {
                    // Bindi-like sacred dot now sits ON the chip's rim,
                    // not floating in space. Offset places it at the
                    // chip's ~1:30 position, overlapping the gold border.
                    Circle()
                        .fill(LinearGradient.sacredGoldShinyVertical)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                        .shadow(color: .sacredGold.opacity(0.45), radius: 3)
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            notifications.unreadCount > 0
                ? "Notifications, \(notifications.unreadCount) unread"
                : "Notifications"
        )
    }

    @ViewBuilder
    private var profileMenuAvatar: some View {
        ProfileAvatarImage(rawUrl: profile.profile?.avatarUrl, size: 36, shadow: true)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
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
        let name = preferredFirstName.map { ", \($0)" } ?? ""
        if hour < 12 { return "Good morning\(name)" }
        if hour < 17 { return "Good afternoon\(name)" }
        return "Good evening\(name)"
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date()).uppercased()
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

// MARK: - Profile menu sheet

/// Identity-scoped surface on Home: birth chart, settings, sign out.
/// Owns its own NavigationStack so pushes stay inside the sheet.
struct ProfileMenuSheet: View {
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var profile: ProfileService
    @Environment(\.dismiss) private var dismiss
    @State private var activeAccountEdit: AccountEdit?
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    accountTitle
                    accountAvatarButton
                    menuList
                    signOutButton
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .sacredBackground()
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
            .sheet(item: $activeAccountEdit) { edit in
                SacredFormSheet(
                    title: edit.title,
                    detent: edit.detent,
                    onCancel: { activeAccountEdit = nil }
                ) {
                    accountEditSheet(edit)
                }
            }
        }
    }

    private var accountTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNT")
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            Text("Your sacred space")
                .font(.sacredTitle)
                .foregroundColor(.sacredText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountHeader(email: String) -> some View {
        menuRow(icon: "envelope", label: "Email", subtitle: email, showsChevron: false)
    }

    @ViewBuilder
    private var accountAvatarButton: some View {
        Button {
            activeAccountEdit = .profilePicture
        } label: {
            accountAvatar
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Change profile picture")
    }

    @ViewBuilder
    private var accountAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            ProfileAvatarImage(rawUrl: profile.profile?.avatarUrl, size: 104, shadow: true)

            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .bold, design: .serif))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.sacredGold))
                .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
        .frame(width: 112, height: 112)
    }

    @ViewBuilder
    private func accountEditSheet(_ edit: AccountEdit) -> some View {
        switch edit {
        case .displayName:
            DisplayNameGateBody(submitLabel: "Save") {
                activeAccountEdit = nil
            }
            .environmentObject(auth)
            .environmentObject(profile)
        case .location:
            LocationGateBody(submitLabel: "Save") {
                activeAccountEdit = nil
            }
            .environmentObject(profile)
        case .profilePicture:
            ProfilePictureGateBody(submitLabel: "Save") {
                activeAccountEdit = nil
            }
            .environmentObject(profile)
        }
    }

    private var menuList: some View {
        VStack(spacing: 0) {
            if let email = auth.user?.email {
                accountHeader(email: email)

                Divider().padding(.leading, 52)
            }

            Button {
                activeAccountEdit = .displayName
            } label: {
                menuRow(icon: "person.text.rectangle", label: "Display name", subtitle: displayNameValue)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            Button {
                activeAccountEdit = .location
            } label: {
                menuRow(icon: "mappin.circle", label: "Location", subtitle: locationValue)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

            NavigationLink(destination: SettingsView()) {
                menuRow(icon: "gearshape", label: "Settings", subtitle: "Preferences")
            }
            .buttonStyle(.plain)
        }
        .luxCardChrome()
    }

    private func menuRow(icon: String, label: String, subtitle: String, showsChevron: Bool = true) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.sacredGold.opacity(0.75))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.sacredTextMedium)
                    .foregroundColor(.sacredText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.sacredMicro)
                    .foregroundColor(.sacredMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.sacredMuted.opacity(0.5))
            }
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

    private var displayNameValue: String {
        profile.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "Add"
    }

    private var locationValue: String {
        guard let profile = profile.profile,
              let city = profile.city?.nonEmpty,
              let state = profile.state?.nonEmpty
        else { return "Add" }
        return "\(city), \(state)"
    }

}

private enum AccountEdit: String, Identifiable {
    case displayName
    case location
    case profilePicture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .displayName: return "Display name"
        case .location: return "Location"
        case .profilePicture: return "Profile picture"
        }
    }

    var detent: PresentationDetent {
        switch self {
        case .displayName: return .height(260)
        case .location: return .large
        case .profilePicture: return .height(560)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
