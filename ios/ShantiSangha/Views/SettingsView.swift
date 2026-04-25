import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var notifications = NotificationService.shared
    @StateObject private var health = HealthKitService.shared
    @StateObject private var weather = WeatherService.shared
    @State private var showSignOutConfirmation = false
    @State private var showErrorDetail = false
    @State private var showTimePicker = false
    @State private var serverStatus: ServerStatus = .loading
    @State private var healthPermissionDenied = false
    @State private var weatherPermissionDenied = false

    private let api = ApiService.shared

    enum ServerStatus {
        case loading
        case connected(ServerVersion)
        case unreachable(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTINGS")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Text("Preferences")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)
                }
                .padding(.top, 24)

                // Reminders
                settingsCard(title: "REMINDERS") {
                    Toggle(isOn: $notifications.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "bell")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Daily reminders")
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                        }
                    }
                    .tint(.sacredGold)
                    .onChange(of: notifications.isEnabled) {
                        if notifications.isEnabled {
                            Task {
                                let granted = await notifications.checkPermission()
                                if !granted {
                                    let result = await notifications.requestPermission()
                                    if !result { notifications.isEnabled = false }
                                }
                                notifications.reschedule(tasks: TaskRepository.shared.tasks)
                            }
                        } else {
                            notifications.reschedule(tasks: [])
                        }
                    }

                    if notifications.isEnabled {
                        Button { showTimePicker = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                                Text("Remind me at")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredTextSecondary)
                                Spacer()
                                Text(formattedReminderTime)
                                    .font(.sacredTextMedium)
                                    .foregroundColor(.sacredGold)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Apple Health
                settingsCard(title: "APPLE HEALTH") {
                    Toggle(isOn: $health.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "heart")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Sync meditation to Health")
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                        }
                    }
                    .tint(.sacredGold)
                    .onChange(of: health.isEnabled) {
                        if health.isEnabled {
                            Task {
                                let granted = await health.requestAuthorization()
                                if !granted {
                                    health.isEnabled = false
                                    healthPermissionDenied = true
                                }
                            }
                        }
                    }

                    if health.isEnabled {
                        infoRow(
                            icon: "sparkles",
                            label: "Written today",
                            value: health.minutesWrittenToday == 0
                                ? "—"
                                : "\(health.minutesWrittenToday) min"
                        )
                        Text("Meditation check-ins will be recorded in the Health app alongside your other practices.")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Weather
                settingsCard(title: "WEATHER") {
                    Toggle(isOn: $weather.isEnabled) {
                        HStack(spacing: 10) {
                            Image(systemName: "cloud.sun")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Sense today's sky")
                                .font(.sacredText)
                                .foregroundColor(.sacredText)
                        }
                    }
                    .tint(.sacredGold)
                    .onChange(of: weather.isEnabled) {
                        if weather.isEnabled {
                            Task {
                                let ok = await weather.requestPermissionAndFetch()
                                if !ok {
                                    weather.isEnabled = false
                                    weatherPermissionDenied = true
                                }
                            }
                        }
                    }

                    if weather.isEnabled {
                        if let snap = weather.snapshot {
                            HStack(spacing: 10) {
                                Image(systemName: snap.conditionSymbol)
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                                Text("Now")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredTextSecondary)
                                Spacer()
                                Text("\(snap.temperatureLabel) · \(snap.conditionLabel)")
                                    .font(.sacredText)
                                    .foregroundColor(.sacredText)
                            }
                        } else {
                            infoRow(icon: "hourglass", label: "Fetching…", value: "")
                        }
                        Text("Your reflection will learn to sense the weather you're living under.")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // iOS Client
                settingsCard(title: "IOS CLIENT") {
                    infoRow(icon: "square.stack", label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    infoRow(icon: "hammer", label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                // App Server
                serverCard

                #if DEBUG
                debugLinks
                #endif

                // Sign out
                Button {
                    showSignOutConfirmation = true
                } label: {
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
            .padding(.horizontal, 16)
        }
        .sacredBackground()
        .refreshable {
            serverStatus = .loading
            // Run in a detached task so the network request isn't cancelled
            // when the pull-to-refresh gesture ends.
            await Task { await fetchServerVersion() }.value
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchServerVersion()
            if health.isEnabled { await health.refreshTodayMinutes() }
            if weather.isEnabled { await weather.refreshIfStale() }
        }
        .alert("Server Error", isPresented: $showErrorDetail) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .unreachable(let msg) = serverStatus {
                Text(msg)
            }
        }
        .alert("Health Access Needed", isPresented: $healthPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("ShantiSangha needs permission to write mindful sessions to Apple Health. Enable it under Settings → Privacy → Health → ShantiSangha.")
        }
        .alert("Location Access Needed", isPresented: $weatherPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("ShantiSangha needs your location to read today's weather. Enable it under Settings → Privacy → Location → ShantiSangha.")
        }
        .confirmationDialog("Are you sure you want to sign out?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: {
                            Calendar.current.date(bySettingHour: notifications.reminderHour, minute: notifications.reminderMinute, second: 0, of: Date()) ?? Date()
                        },
                        set: { newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notifications.reminderHour = components.hour ?? 20
                            notifications.reminderMinute = components.minute ?? 0
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .sacredBackground()
                .navigationTitle("Remind me at")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showTimePicker = false
                            notifications.reschedule(tasks: TaskRepository.shared.tasks)
                        }
                        .foregroundColor(.sacredGold)
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
    }

    // MARK: - Server card with status dot

    #if DEBUG
    private var debugLinks: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: HangfireDebugView()) {
                debugRow(icon: "gearshape.2", label: "Hangfire Jobs", badge: nil)
            }
            NavigationLink(destination: LogsView()) {
                debugRow(
                    icon: "doc.text",
                    label: "Logs",
                    badge: SyncStatus.shared.pendingCount > 0 ? "\(SyncStatus.shared.pendingCount)" : nil
                )
            }
        }
    }

    private func debugRow(icon: String, label: String, badge: String?) -> some View {
        LuxCard {
            HStack {
                Image(systemName: icon)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
                Text(label)
                    .font(.sacredText)
                    .foregroundColor(.sacredText)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.sacredSmallSemibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.sacredRed))
                }
                Image(systemName: "chevron.right")
                    .font(.sacredSmall)
                    .foregroundColor(.sacredMuted)
            }
            .padding(SacredSpacing.m)
        }
    }
    #endif

    private var serverCard: some View {
        LuxCard {
            VStack(alignment: .leading, spacing: SacredSpacing.s) {
                HStack(spacing: SacredSpacing.xs) {
                    statusDot
                    Text("APP SERVER")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                }

                switch serverStatus {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                case .connected(let sv):
                    infoRow(icon: "server.rack", label: "Git hash", value: sv.gitHash)
                    infoRow(icon: "clock", label: "Built", value: formatBuildTime(sv.buildTime))
                case .unreachable:
                    VStack(spacing: SacredSpacing.xs) {
                        Text("Unable to reach server")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredRed)
                        HStack(spacing: SacredSpacing.m) {
                            Button {
                                serverStatus = .loading
                                Task { await fetchServerVersion() }
                            } label: {
                                Text("Retry")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredGold)
                            }
                            Button {
                                showErrorDetail = true
                            } label: {
                                Text("View Error")
                                    .font(.sacredSmallSemibold)
                                    .foregroundColor(.sacredMuted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(SacredSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch serverStatus {
        case .loading:
            Circle()
                .fill(Color.sacredGold)
                .frame(width: 6, height: 6)
                .opacity(0.8)
                .modifier(PulseModifier())
        case .connected:
            Circle()
                .fill(Color.sacredGreen)
                .frame(width: 6, height: 6)
        case .unreachable(_):
            Circle()
                .fill(Color.sacredRed)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Helpers

    private var formattedReminderTime: String {
        let date = Calendar.current.date(bySettingHour: notifications.reminderHour, minute: notifications.reminderMinute, second: 0, of: Date()) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private func formatBuildTime(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        guard let date = iso.date(from: raw) ?? isoBasic.date(from: raw) else { return raw }

        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func fetchServerVersion() async {
        do {
            let version: ServerVersion = try await api.get("/version")
            serverStatus = .connected(version)
        } catch is CancellationError {
            // Task was cancelled (e.g. pull-to-refresh ended) — don't report as unreachable
        } catch let error as URLError where error.code == .cancelled {
            // URLSession cancellation — same reason, don't report as unreachable
        } catch {
            serverStatus = .unreachable(error.localizedDescription)
        }
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        LuxCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.sacredSectionLabel)
                    .tracking(3)
                    .foregroundColor(.sacredLabel)

                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.sacredSmall)
                .foregroundColor(.sacredMuted)
            Text(label)
                .font(.sacredText)
                .foregroundColor(.sacredTextSecondary)
            Spacer()
            Text(value)
                .font(.sacredText)
                .foregroundColor(.sacredText)
        }
    }
}

// MARK: - Pulse animation for loading dot

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.4 : 1.0)
            .opacity(pulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
