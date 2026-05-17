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
    @StateObject private var connections = ConnectionsRepository.shared
    /// Owns the Connection list for friend-profile navigation from Home.
    /// `ConnectionDetailView` reads its model from this VM; the shared
    /// `ConnectionsRepository` above is only used for avatar/label lookup.
    @StateObject private var circleVM = CircleViewModel()
    @State private var navTarget: ReminderEditTarget?
    @State private var profileTarget: ProfileNavTarget?
    /// How many days into the future to show on Home. Anything beyond
    /// this is quietly held back until it enters the window. Overdue
    /// items always show regardless. User adjusts in Settings.
    @AppStorage("reminders.horizonDays") private var horizonDays = 30
    @State private var showProfileMenu = false
    @State private var showChatSheet = false
    @State private var showCalendar = false
    @State private var promptHintIndex = 0
    @State private var chatPillBreathing = false
    /// Transcript captured by the Home pill's mic. Passed through to
    /// AgentChatView when the sheet opens; cleared on dismiss so the
    /// next dictation starts from an empty slate.
    @State private var voicePrefill: String = ""
    @StateObject private var notifications = NotificationsViewModel()
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    private let promptHintTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()
    private static let promptHints = [
        "Ask anything...",
        "Reflect on today",
        "What is on your mind?",
        "Set an intention"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    SacredHomeHeader(greeting: timeGreeting) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showCalendar = true
                    }

                    // Whole-day context strip — sleep, steps, weather. Only
                    // appears when the user has enabled Health / Weather in
                    // Settings AND the relevant data is available. Silent
                    // otherwise so Home stays uncluttered.
                    WholeDayContextStrip(health: health, weather: weather)
                        .padding(.top, 10)

                    if vm.loading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if vm.reminders.isEmpty {
                        emptyState
                    } else {
                        remindersSection
                    }
                }
                .padding(.top, SacredSpacing.xl)
                .padding(.bottom, SacredSpacing.tabBarSafe + 56)
            }
            .background(Color.clear)
            .toolbar {
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        profileMenuButton
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        profileMenuButton
                    }
                }
            }
            .fullScreenCover(isPresented: $showProfileMenu) {
                ProfileMenuSheet(unreadNotifications: notifications.unreadCount)
                    .environmentObject(auth)
                    .environmentObject(profile)
            }
            .refreshable {
                await vm.load()
                updateWidgetData()
                await refreshWholeDayContext()
                await circleVM.refresh()
            }
            .task {
                // Kick off the Circle fetch up front so a friend's avatar
                // tap on the very first frame doesn't land before the
                // ConnectionDetailView can find its connection.
                async let circleLoad: () = circleVM.refresh()
                await vm.load()
                updateWidgetData()
                await refreshWholeDayContext()
                await notifications.refreshUnreadCount()
                await connections.refresh()
                await circleLoad
            }
            .onChange(of: vm.overdueRemindersCount) { updateWidgetData() }
            .onChange(of: vm.dueTodayRemindersCount) { updateWidgetData() }
            // Foreground refresh — pull truth from server when the app
            // returns from background. The `.task` modifier above only
            // fires when HomeView is mounted; foregrounding doesn't
            // re-run it, so the bell badge would otherwise drift while
            // pushes-while-backgrounded bumped the home-screen icon.
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await notifications.refreshUnreadCount() }
                    // Cold-launch hand-off from the share extension can
                    // land before `.onOpenURL` fires (or instead of it,
                    // if iOS swallows the URL). Draining on every
                    // foreground covers both paths.
                    deepLinks.consumeSharedText()
                }
            }
            .onAppear(perform: normalizeHomeHorizon)
            .onAppear { deepLinks.consumeSharedText() }
            .onChange(of: deepLinks.pendingSharedText) { _, text in
                guard let text, !text.isEmpty else { return }
                voicePrefill = text
                showChatSheet = true
                deepLinks.clearSharedText()
            }

            chatAffordance
                .padding(.horizontal, SacredSpacing.m)
                .padding(.bottom, SacredSpacing.s)
        }
        .navigationDestination(isPresented: $showChatSheet) {
            AgentChatView(prefill: voicePrefill)
        }
        .navigationDestination(isPresented: $showCalendar) {
            CalendarView(showsNavigationBar: true)
        }
        .onReceive(promptHintTimer) { _ in
            guard !showChatSheet else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                promptHintIndex = (promptHintIndex + 1) % Self.promptHints.count
            }
        }
        .onChange(of: showChatSheet) { _, isShown in
            if !isShown { voicePrefill = "" }
        }
        .navigationDestination(item: $navTarget) { target in
            ReminderEditView(
                target: target,
                onSave: { label, date, recurrence in
                    switch target {
                    case .new(_, _, let connId):
                        await vm.createReminder(
                            label: label, date: date,
                            recurrence: recurrence,
                            connectionId: connId)
                    case .edit(let reminder):
                        await vm.updateReminder(
                            id: reminder.id,
                            label: label, date: date,
                            recurrence: recurrence)
                    }
                },
                onDelete: {
                    if case .edit(let reminder) = target {
                        return { await vm.deleteReminder(id: reminder.id) }
                    }
                    return nil
                }()
            )
        }
        .navigationDestination(item: $profileTarget) { target in
            ConnectionDetailView(connectionId: target.connectionId, vm: circleVM)
        }
    }

    // MARK: - Chat affordance

    /// Floating pill above the tab bar. The mic dictates in place
    /// (press-and-hold) and on release opens the assistant sheet with
    /// the transcript pre-filled; tap anywhere else on the pill opens
    /// the sheet empty. The chat is a tool — Home is the landing.
    private var chatAffordance: some View {
        HStack(spacing: 12) {
            SacredVoiceInputButton(
                text: $voicePrefill,
                size: 28,
                onComplete: {
                    if !voicePrefill.trimmingCharacters(in: .whitespaces).isEmpty {
                        showChatSheet = true
                    }
                }
            )

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showChatSheet = true
            } label: {
                HStack(spacing: 0) {
                    Text(Self.promptHints[promptHintIndex])
                        .id(promptHintIndex)
                        .font(.sacredText)
                        .foregroundColor(.sacredMuted)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showChatSheet = true
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.sacredGold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.sacredBgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.sacredGold.opacity(chatPillBreathing ? 0.34 : 0.18), lineWidth: 1)
                )
        )
        .shadow(color: .sacredGold.opacity(chatPillBreathing ? 0.22 : 0.08), radius: chatPillBreathing ? 22 : 10, y: 6)
        .shadow(color: .sacredMuted.opacity(0.14), radius: 14, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                chatPillBreathing = true
            }
        }
    }

    // MARK: - Reminders section

    /// Wraps the horizon picker + reminders list (or empty-horizon state)
    /// in a single VStack so the parent ViewBuilder stays shallow. Without
    /// this, the body's type-checker times out on the nested if/else +
    /// `let` binding.
    @ViewBuilder
    private var remindersSection: some View {
        let visible = vm.pendingReminders.filter { $0.localDaysRemaining <= horizonDays }
        VStack(spacing: 0) {
            horizonPicker
                .padding(.top, 28)
                .padding(.horizontal, 16)
            if visible.isEmpty {
                emptyHorizonState
            } else {
                remindersList(visible)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Horizon picker

    private static let horizonOptions = [7, 14, 30]

    /// Right-aligned chip above the list that lets the user dial how far
    /// out Home reaches. Selection persists via @AppStorage so the next
    /// open remembers their preference.
    private var horizonPicker: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(Self.horizonOptions, id: \.self) { days in
                    Button {
                        horizonDays = days
                    } label: {
                        HStack {
                            Text("Next \(days) days")
                            if horizonDays == days {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Upcoming")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredGold.opacity(0.85))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.sacredGold.opacity(0.55))
                }
                .padding(.vertical, 10)
                .padding(.leading, 16)
                .contentShape(Rectangle())
            }
        }
    }

    private func normalizeHomeHorizon() {
        guard !Self.horizonOptions.contains(horizonDays) else { return }
        horizonDays = 30
    }

    // MARK: - Reminders list

    /// Flat list of every reminder within the user's chosen horizon
    /// (overdue + next N days). Anything beyond the horizon is quietly
    /// hidden — adjust via the chip above the list.
    private func remindersList(_ items: [Reminder]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, reminder in
                ReminderRow(
                    reminder: reminder,
                    allowSwipeToComplete: true,
                    showDateStamp: true,
                    avatarUrl: avatarUrl(for: reminder),
                    connectionLabel: connectionLabel(for: reminder),
                    onTap: { navTarget = .edit(reminder) },
                    onComplete: { Task { await vm.completeReminder(id: reminder.id) } },
                    onAvatarTap: reminder.connectionId.map { cid in
                        { profileTarget = ProfileNavTarget(connectionId: cid) }
                    },
                    activeSwipeId: Binding(
                        get: { vm.activeSwipeId },
                        set: { vm.activeSwipeId = $0 }
                    )
                )

                if idx < items.count - 1 {
                    Divider()
                        .padding(.leading, 104)
                        .padding(.trailing, 16)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: items.map(\.id))
    }

    /// Connection's avatar when the reminder belongs to someone in the
    /// user's circle; otherwise the viewer's own avatar. Keeps every row
    /// visually balanced — a face next to every label.
    private func avatarUrl(for reminder: Reminder) -> String? {
        if let cid = reminder.connectionId,
           let connection = connections.connection(for: cid) {
            return connection.ownerVisibleAvatarUrl
        }
        return profile.profile?.avatarUrl
    }

    /// Nickname (or display name) of the connection a reminder belongs
    /// to. Returns nil for personal reminders so the row label renders
    /// alone.
    private func connectionLabel(for reminder: Reminder) -> String? {
        guard let cid = reminder.connectionId else { return nil }
        return connections.connection(for: cid)?.displayLabel
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("Nothing on your plate yet.")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)

            SacredPrimaryButton("Add your first reminder") {
                navTarget = .new()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Shown when the user has reminders, but none fall within the
    /// configured `horizonDays` window. Calm copy + the same primary CTA
    /// so they can still add new ones without leaving Home.
    private var emptyHorizonState: some View {
        VStack(spacing: 16) {
            Text("The next \(horizonDays) days are quiet.")
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)

            SacredPrimaryButton("Add a reminder") {
                navTarget = .new()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Widget data sync

    private func updateWidgetData() {
        let summaries = vm.pendingReminders.prefix(5).compactMap { r in
            WidgetData.makeSummary(
                id: r.id.uuidString,
                label: r.label,
                date: r.date,
                daysRemaining: r.localDaysRemaining,
                recurrence: r.recurrence.rawValue,
                connectionLabel: connectionLabel(for: r))
        }
        WidgetData.update(
            upcomingReminders: Array(summaries),
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

    // MARK: - Profile

    private var profileMenuButton: some View {
        Button {
            showProfileMenu = true
        } label: {
            profileMenuAvatar
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(
            notifications.unreadCount > 0
                ? "Profile menu, \(notifications.unreadCount) unread notifications"
                : "Profile menu"
        )
    }

    /// Single toolbar chip — the user's avatar doubles as the notifications
    /// signal. Unread notifications light the same bindi-style gold dot
    /// that used to sit on the bell chip; tap opens the profile menu,
    /// which carries the notifications row at the top.
    @ViewBuilder
    private var profileMenuAvatar: some View {
        ZStack(alignment: .topTrailing) {
            ProfileAvatarImage(rawUrl: profile.profile?.avatarUrl, size: 36, shadow: true)
                .frame(width: 44, height: 44)
                .contentShape(Circle())

            if notifications.unreadCount > 0 {
                Circle()
                    .fill(LinearGradient.sacredGoldShinyVertical)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                    .shadow(color: .sacredGold.opacity(0.45), radius: 3)
                    .offset(x: -4, y: 4)
            }
        }
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

}

private struct ProfileNavTarget: Identifiable, Hashable {
    let connectionId: UUID
    var id: UUID { connectionId }
}

// MARK: - Profile menu sheet

/// Identity-scoped surface on Home: birth chart, settings, sign out.
/// Owns its own NavigationStack so pushes stay inside the sheet.
struct ProfileMenuSheet: View {
    /// Passed in from Home so the Notifications row can show the same
    /// unread count that drives the toolbar avatar's bindi dot. Single
    /// source of truth (HomeView's NotificationsViewModel); the sheet
    /// just renders it.
    let unreadNotifications: Int
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
            NavigationLink(destination: NotificationsView()) {
                menuRow(
                    icon: unreadNotifications > 0 ? "bell.fill" : "bell",
                    label: "Notifications",
                    subtitle: unreadNotifications > 0
                        ? "\(unreadNotifications) unread"
                        : "Inbox"
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 52)

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

            if isStocksAllowed(email: auth.user?.email) {
                Divider().padding(.leading, 52)

                NavigationLink(destination: WiseCatView()) {
                    menuRow(icon: "chart.line.uptrend.xyaxis", label: "Wise Cat", subtitle: "Trading signals")
                }
                .buttonStyle(.plain)
            }
        }
        .luxCardChrome()
    }

    /// Stocks (Wise Cat) is gated to a single email while in private use.
    /// Returns true only for that account; everyone else gets a clean
    /// profile menu without the stocks entry.
    private func isStocksAllowed(email: String?) -> Bool {
        guard let email else { return false }
        return email.lowercased() == "subinho09@gmail.com"
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
