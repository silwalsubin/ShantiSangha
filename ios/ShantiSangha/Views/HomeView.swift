import SwiftUI
import FirebaseAuth
import WidgetKit
import Pow

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
    /// How many days into the future to show on Home. Anything beyond
    /// this is quietly held back until it enters the window. Overdue
    /// items always show regardless. User adjusts in Settings.
    @AppStorage("reminders.horizonDays") private var horizonDays = 30
    @State private var showProfileMenu = false
    @State private var showChatSheet = false
    /// Increments only when the chat is summoned, so the sparkle spray
    /// fires on open but not when the sheet dismisses back to Home.
    @State private var sparkleTrigger = 0
    @State private var autoSendPrompt: String?
    @State private var showCalendar = false
    /// Text handed in from a share extension (or the shared sheet).
    /// Passed through to AgentChatView when the chat opens; cleared on
    /// dismiss so the next session starts from an empty slate.
    @State private var voicePrefill: String = ""
    /// A photo shared to the assistant — staged into AgentChatView's
    /// composer when the chat opens; cleared on dismiss.
    @State private var sharedAssistantImage: UIImage?
    @StateObject private var notifications = NotificationsViewModel()
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @Environment(\.scenePhase) private var scenePhase

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

                    // Quiet continuity — presence made visible. Hidden at 0
                    // days: we acknowledge what was done, never shame a gap.
                    if let presence = vm.presence, presence.daysReflected > 0 {
                        Text(continuityLine(presence))
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .padding(.top, 6)
                            .transition(.opacity)
                    }

                    // The assistant is the heart of Home (ChatGPT-style hero):
                    // composer directly under the greeting, with starter chips
                    // that auto-send so a tap delivers an answer, not a draft.
                    askPill
                        .padding(.horizontal, 16)
                        .padding(.top, SacredSpacing.l)

                    starterChips
                        .padding(.horizontal, 16)
                        .padding(.top, SacredSpacing.s)

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
                .padding(.bottom, SacredSpacing.tabBarSafe)
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
                await vm.loadPresence()
                await circleVM.refresh()
            }
            .task {
                // Kick off the Circle fetch up front so a friend's avatar
                // tap on the very first frame doesn't land before the
                // ConnectionDetailView can find its connection.
                async let circleLoad: () = circleVM.refresh()
                async let presenceLoad: () = vm.loadPresence()
                await vm.load()
                updateWidgetData()
                await refreshWholeDayContext()
                await notifications.refreshUnreadCount()
                await connections.refresh()
                await circleLoad
                await presenceLoad
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
            // A photo shared to the assistant → open the chat with it
            // staged in the composer so the user can add a question.
            .onChange(of: deepLinks.pendingAssistantImage) { _, payload in
                guard let payload, let image = UIImage(data: payload.data) else { return }
                sharedAssistantImage = image
                showChatSheet = true
                deepLinks.clearAssistantImage()
            }

        }
        .navigationDestination(isPresented: $showChatSheet) {
            AgentChatView(prefill: voicePrefill, prefillImage: sharedAssistantImage, autoSend: autoSendPrompt)
        }
        .navigationDestination(isPresented: $showCalendar) {
            CalendarView(showsNavigationBar: true)
        }
        .onChange(of: showChatSheet) { _, isShown in
            if !isShown {
                voicePrefill = ""
                sharedAssistantImage = nil
                autoSendPrompt = nil
            }
        }
        .navigationDestination(item: $navTarget) { target in
            ReminderEditView(
                target: target,
                onSave: { label, date, recurrence, collaboratorIds in
                    switch target {
                    case .new(_, _, let connId):
                        await vm.createReminder(
                            label: label, date: date,
                            recurrence: recurrence,
                            connectionId: connId,
                            collaboratorUserIds: collaboratorIds)
                    case .edit(let reminder):
                        await vm.updateReminder(
                            id: reminder.id,
                            label: label, date: date,
                            recurrence: recurrence,
                            collaboratorUserIds: collaboratorIds)
                    }
                },
                onDelete: {
                    if case .edit(let reminder) = target {
                        return { await vm.deleteReminder(id: reminder.id) }
                    }
                    return nil
                }(),
                onLivePatch: {
                    if case .edit(let reminder) = target {
                        return { patch in
                            try? await ReminderRepository.shared.update(
                                id: reminder.id,
                                label: patch.label,
                                date: patch.date,
                                recurrence: patch.recurrence,
                                collaboratorUserIds: patch.collaboratorUserIds,
                                notes: patch.notes)
                        }
                    }
                    return nil
                }()
            )
        }
    }

    // MARK: - Ask pill

    /// The assistant's front door: a quiet parchment pill docked above the
    /// tab bar. Reads as an invitation ("Ask anything…"), not a control —
    /// the vajra names who answers.
    private var askPill: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            sparkleTrigger += 1
            showChatSheet = true
        } label: {
            HStack(spacing: SacredSpacing.s) {
                SacredIconView(icon: .vajra, size: 18)
                    .foregroundColor(.sacredGold)
                Text("Ask anything…")
                    .font(.sacredText)
                    .foregroundColor(.sacredMuted)
                Spacer()
            }
            .padding(.horizontal, SacredSpacing.lux)
            .frame(height: 48)
            .background(Capsule().fill(Color.sacredBgCard.opacity(0.94)))
            .overlay(Capsule().stroke(Color.sacredGold.opacity(0.22), lineWidth: 1))
            .shadow(color: .sacredMuted.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(PillPressStyle())
        .accessibilityLabel("Open assistant")
        // Sparkles spray as the chat is summoned. Keyed to sparkleTrigger
        // (which only advances on open) so it never re-fires on dismiss.
        .changeEffect(
            .spray(origin: UnitPoint.center) {
                Image(systemName: "sparkle")
                    .foregroundStyle(Color.sacredGold)
            },
            value: sparkleTrigger
        )
    }

    /// Two quiet invitations under the composer. Tapping one opens the
    /// assistant and sends it immediately — an answer, not a staged draft.
    /// The pair is chosen by `HomeViewModel.starterPrompts` from the moment
    /// (overdue pile, due today, unreflected evening) so it changes with the
    /// user's day instead of repeating forever.
    private var starterChips: some View {
        // Horizontal scroll keeps long label pairs intact on 375pt screens
        // instead of truncating them.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SacredSpacing.xs) {
                ForEach(vm.starterPrompts) { chip in
                    starterChip(chip)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .animation(.easeIn(duration: 0.3), value: vm.starterPrompts)
    }

    private func starterChip(_ chip: StarterPrompt) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            autoSendPrompt = chip.prompt
            showChatSheet = true
        } label: {
            Text(chip.label)
                .font(.sacredSmall)
                .foregroundColor(.sacredTextSecondary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(Color.sacredBgCard.opacity(0.8)))
                .overlay(Capsule().stroke(Color.sacredMuted.opacity(0.18), lineWidth: 1))
                // Visual capsule stays slim; the tap target meets 44pt.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PillPressStyle())
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
                    connectionLabel: connectionLabel(for: reminder),
                    currentUserId: profile.currentUserId,
                    onTap: { navTarget = .edit(reminder) },
                    onComplete: { Task { await vm.completeReminder(id: reminder.id) } },
                    activeSwipeId: Binding(
                        get: { vm.activeSwipeId },
                        set: { vm.activeSwipeId = $0 }
                    )
                )

                if idx < items.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                        .padding(.trailing, 16)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: items.map(\.id))
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

    private func continuityLine(_ presence: MemoryPresence) -> String {
        if presence.daysReflected >= presence.windowDays {
            return "You've reflected every day this week."
        }
        let days = presence.daysReflected == 1 ? "1 day" : "\(presence.daysReflected) days"
        return "You've reflected \(days) of the last \(presence.windowDays)."
    }

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

/// Gentle press feedback for the ask pill — the sacred 0.97 scale-down
/// with a soft return. The default `.plain` style has no press feedback,
/// which makes the pill feel dead at the moment of tap.
private struct PillPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
