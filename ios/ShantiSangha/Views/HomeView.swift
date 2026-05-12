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
    @State private var reflection: String?
    @State private var reflectionDate: String?
    /// True when `reflection` is a prior day's reflection shown while today's
    /// is still being composed. Drives the "TODAY'S IS BEING WRITTEN" chip.
    @State private var reflectionIsFallback: Bool = false
    /// Hides the reflection card for the rest of the day after the user
    /// dismisses it. A new day or a different reflection will surface again.
    @State private var reflectionDismissed: Bool = false
    @State private var showProfileMenu = false
    @StateObject private var notifications = NotificationsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SacredBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    SacredHomeHeader(greeting: timeGreeting)

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
                await circleVM.refresh()
            }
            .task {
                // Kick off the Circle fetch up front so a friend's avatar
                // tap on the very first frame doesn't land before the
                // ConnectionDetailView can find its connection.
                async let circleLoad: () = circleVM.refresh()
                await vm.load()
                await loadReflection()
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
                }
            }
            .onChange(of: reflection) { _, _ in syncReflectionDismissedFlag() }
            .onReceive(NotificationCenter.default.publisher(for: .silentPushReceived)) { notification in
                let type = notification.userInfo?["type"] as? String
                Task {
                    if type == "reflection" { await loadReflection(force: true) }
                }
            }
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

    // MARK: - Reminders section

    /// Wraps the horizon picker + reminders list (or empty-horizon state)
    /// in a single VStack so the parent ViewBuilder stays shallow. Without
    /// this, the body's type-checker times out on the nested if/else +
    /// `let` binding.
    @ViewBuilder
    private var remindersSection: some View {
        let visible = vm.pendingReminders.filter { $0.daysRemaining <= horizonDays }
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

    private static let horizonOptions = [7, 14, 30, 60, 90, 180]

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
                            Text("\(days) days")
                            if horizonDays == days {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Next \(horizonDays) days")
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
                daysRemaining: r.daysRemaining,
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

}

private struct ProfileNavTarget: Identifiable, Hashable {
    let connectionId: UUID
    var id: UUID { connectionId }
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
