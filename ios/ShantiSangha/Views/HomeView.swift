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
    /// How many days into the future to show on Home. Anything beyond
    /// this is quietly held back until it enters the window. Overdue
    /// items always show regardless. User adjusts in Settings.
    @AppStorage("reminders.horizonDays") private var horizonDays = 30
    /// The secondary surfaces (Chats / Reflect / Circles / Profile) live in
    /// HubView, presented over Home by the atom icon. `hubTab` picks which
    /// tab opens — the atom defaults to Chats; deep links target a specific one.
    @State private var showHub = false
    @State private var hubTab: HubTab = .chats
    @State private var showChatSheet = false
    @State private var showCalendar = false
    @StateObject private var friendsBadge = FriendsBadgeService.shared
    /// Transcript captured from a share/voice hand-off. Passed through to
    /// AgentChatView when the chat opens; cleared on dismiss so the next
    /// session starts from an empty slate.
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
                        hubButton
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        hubButton
                    }
                }
            }
            .fullScreenCover(isPresented: $showHub) {
                HubView(initialTab: hubTab, unreadNotifications: notifications.unreadCount)
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
            // A photo shared to the assistant → open the chat with it
            // staged in the composer so the user can add a question.
            .onChange(of: deepLinks.pendingAssistantImage) { _, payload in
                guard let payload, let image = UIImage(data: payload.data) else { return }
                sharedAssistantImage = image
                showChatSheet = true
                deepLinks.clearAssistantImage()
            }
            // A "new message" push → open the hub on Chats; ChatsTabView
            // resolves the friendship id to the thread once it's on screen.
            .onChange(of: deepLinks.pendingChatFriendshipId) { _, newValue in
                if newValue != nil {
                    hubTab = .chats
                    showHub = true
                }
            }

            // The single assistant affordance, where the tab bar used to
            // sit: a calm vajra glyph. Tap opens the chat.
            vajraButton
                .padding(.bottom, 20)
        }
        .navigationDestination(isPresented: $showChatSheet) {
            AgentChatView(prefill: voicePrefill, prefillImage: sharedAssistantImage)
        }
        .navigationDestination(isPresented: $showCalendar) {
            CalendarView(showsNavigationBar: true)
        }
        // Accepting an invitation deep link → open the hub on Circles.
        // Bound directly to the router so a cold-launch invite is caught.
        .sheet(item: inviteBinding) { token in
            AcceptInvitationView(token: token.value) { _ in
                hubTab = .circles
                showHub = true
            }
        }
        .onChange(of: showChatSheet) { _, isShown in
            if !isShown {
                voicePrefill = ""
                sharedAssistantImage = nil
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

    // MARK: - Assistant affordance

    /// The single entry to the assistant, sitting where the tab bar used
    /// to. A calm vajra glyph — the app's mark for the AI — on a soft gold
    /// disc. No animation: Home stays quiet, the assistant is one tap away.
    private var vajraButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showChatSheet = true
        } label: {
            Image("tab.vajra")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundColor(.sacredGold)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(Color.sacredBgCard)
                        .overlay(Circle().stroke(Color.sacredGold.opacity(0.30), lineWidth: 1))
                )
                .shadow(color: .sacredMuted.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open assistant")
    }

    /// Mirrors the router's invite token into a `.sheet(item:)` source.
    /// Reading the current value (vs. observing a change) means a cold-launch
    /// invite is presented too; clearing the router on dismiss closes it.
    private var inviteBinding: Binding<InviteTokenItem?> {
        Binding(
            get: { deepLinks.pendingInviteToken.map { InviteTokenItem(value: $0) } },
            set: { newValue in
                if newValue == nil { deepLinks.clear() }
            }
        )
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

    // MARK: - Hub entry

    /// Top-right atom icon — the doorway to the secondary surfaces (Chats,
    /// Reflect, Circles, Profile) hosted in HubView. A bindi-style gold dot
    /// lights when anything in there wants attention (unread notifications
    /// or messages, or a pending request) so the signal survives the move
    /// off Home.
    private var hubButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            hubTab = .chats
            showHub = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "atom")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.sacredGold)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())

                if hubHasAttention {
                    Circle()
                        .fill(LinearGradient.sacredGoldShinyVertical)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.sacredBg, lineWidth: 2))
                        .shadow(color: .sacredGold.opacity(0.45), radius: 3)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(hubHasAttention ? "Menu, new activity" : "Menu")
    }

    private var hubHasAttention: Bool {
        notifications.unreadCount > 0
            || friendsBadge.unreadMessagesCount > 0
            || friendsBadge.requestsCount > 0
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

// MARK: - Profile menu sheet

/// Identity-scoped surface: account, notifications, settings, sign out.
/// Hosted as the "Profile" tab inside HubView, which supplies the
/// NavigationStack and the vajra back-to-Home button.
struct ProfileView: View {
    /// Passed in from Home so the Notifications row can show the same
    /// unread count that drives Home's atom-icon bindi dot. Single source
    /// of truth (HomeView's NotificationsViewModel); the tab just renders it.
    let unreadNotifications: Int
    @EnvironmentObject var auth: AuthService
    @EnvironmentObject var profile: ProfileService
    @State private var activeAccountEdit: AccountEdit?
    @State private var showSignOutConfirmation = false

    var body: some View {
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
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
