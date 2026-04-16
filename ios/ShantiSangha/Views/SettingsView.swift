import SwiftUI
import CoreLocation

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var notifications = NotificationService.shared
    @State private var showSignOutConfirmation = false
    @State private var showErrorDetail = false
    @State private var showTimePicker = false
    @State private var serverStatus: ServerStatus = .loading

    // Birth details
    @State private var birthDate: Date?
    @State private var birthTime: Date?
    @State private var birthPlace: String = ""
    @State private var birthPlaceQuery: String = ""
    @State private var showBirthDatePicker = false
    @State private var showBirthTimePicker = false
    @State private var birthDetailsLoaded = false
    @State private var savingBirth = false
    @State private var showBirthPlacePicker = false

    private let api = ApiService.shared

    enum ServerStatus {
        case loading
        case connected(ServerVersion)
        case unreachable(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTINGS")
                        .font(.sacredSectionLabel)
                        .tracking(3)
                        .foregroundColor(.sacredLabel)
                    Text("Your sacred space")
                        .font(.sacredTitle)
                        .foregroundColor(.sacredText)
                }
                .padding(.top, 24)

                // Account card
                if let email = auth.user?.email {
                    settingsCard(title: "ACCOUNT") {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(RadialGradient.sacredGoldShiny)
                                .frame(width: 40, height: 40)
                                .shimmer()
                                .clipShape(Circle())
                                .overlay(
                                    Text(String(email.prefix(1)).uppercased())
                                        .font(.sacredButtonLabel)
                                        .foregroundColor(.white)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(.sacredSmall)
                                    .foregroundColor(.sacredMuted)
                                Text(email)
                                    .font(.sacredTextMedium)
                                    .foregroundColor(.sacredText)
                            }
                        }
                    }
                }

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

                // Birth details — feeds invisible Vedic context into reflections
                settingsCard(title: "YOUR DHARMA") {
                    // Birth date
                    Button { showBirthDatePicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Date of birth")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                            Spacer()
                            Text(birthDate.map { formatBirthDate($0) } ?? "Not set")
                                .font(.sacredTextMedium)
                                .foregroundColor(birthDate != nil ? .sacredGold : .sacredMuted)
                        }
                    }
                    .buttonStyle(.plain)

                    // Birth time
                    Button { showBirthTimePicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Time of birth")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                            Spacer()
                            Text(birthTime.map { formatBirthTime($0) } ?? "Not set")
                                .font(.sacredTextMedium)
                                .foregroundColor(birthTime != nil ? .sacredGold : .sacredMuted)
                        }
                    }
                    .buttonStyle(.plain)

                    // Birth place
                    Button { showBirthPlacePicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin")
                                .font(.sacredSmall)
                                .foregroundColor(.sacredMuted)
                            Text("Place of birth")
                                .font(.sacredText)
                                .foregroundColor(.sacredTextSecondary)
                            Spacer()
                            Text(birthPlaceQuery.isEmpty ? "Not set" : birthPlaceQuery)
                                .font(.sacredTextMedium)
                                .foregroundColor(birthPlaceQuery.isEmpty ? .sacredMuted : .sacredGold)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)

                    if birthDate != nil {
                        Text("This helps the app understand you more deeply.")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                            .padding(.top, 4)
                    }
                }

                // iOS Client
                settingsCard(title: "IOS CLIENT") {
                    infoRow(icon: "square.stack", label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    infoRow(icon: "hammer", label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                // App Server
                serverCard

                // Hangfire debug
                NavigationLink(destination: HangfireDebugView()) {
                    HStack {
                        Image(systemName: "gearshape.2")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        Text("Hangfire Jobs")
                            .font(.sacredText)
                            .foregroundColor(.sacredText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.1)))
                }

                // Logs
                NavigationLink(destination: LogsView()) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                        Text("Logs")
                            .font(.sacredText)
                            .foregroundColor(.sacredText)
                        Spacer()
                        if SyncStatus.shared.pendingCount > 0 {
                            Text("\(SyncStatus.shared.pendingCount)")
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
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.1)))
                }

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
        .background(Color.sacredBg.ignoresSafeArea())
        .refreshable {
            serverStatus = .loading
            // Run in a detached task so the network request isn't cancelled
            // when the pull-to-refresh gesture ends.
            await Task { await fetchServerVersion() }.value
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await fetchServerVersion() }
        .task { await loadBirthDetails() }
        .alert("Server Error", isPresented: $showErrorDetail) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .unreachable(let msg) = serverStatus {
                Text(msg)
            }
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
                .background(Color.sacredBg.ignoresSafeArea())
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
        .sheet(isPresented: $showBirthDatePicker) {
            NavigationStack {
                DatePicker(
                    "Date of birth",
                    selection: Binding(
                        get: { birthDate ?? Calendar.current.date(byAdding: .year, value: -25, to: Date())! },
                        set: { birthDate = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .background(Color.sacredBg.ignoresSafeArea())
                .navigationTitle("Date of birth")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if birthDate == nil {
                        birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date())
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showBirthDatePicker = false
                            Task { await saveBirthDetails() }
                        }
                        .foregroundColor(.sacredGold)
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showBirthTimePicker) {
            NavigationStack {
                DatePicker(
                    "Time of birth",
                    selection: Binding(
                        get: { birthTime ?? Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())! },
                        set: { birthTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .background(Color.sacredBg.ignoresSafeArea())
                .navigationTitle("Time of birth")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Ensure birthTime has a value so "Done" without spinning still saves
                    if birthTime == nil {
                        birthTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showBirthTimePicker = false
                            Task { await saveBirthDetails() }
                        }
                        .foregroundColor(.sacredGold)
                    }
                }
            }
            .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showBirthPlacePicker) {
            BirthPlacePickerView(
                selectedPlace: birthPlaceQuery,
                onSelect: { name, lat, lng in
                    birthPlaceQuery = name
                    birthPlace = "\(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
                    showBirthPlacePicker = false
                    Task { await saveBirthDetails() }
                }
            )
        }
    }

    // MARK: - Birth details

    private func loadBirthDetails() async {
        guard !birthDetailsLoaded else { return }
        do {
            let response: MeResponse = try await api.get("/me")
            if let profile = response.profile {
                if let dateStr = profile.birthDate {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    birthDate = df.date(from: dateStr)
                }
                if let timeStr = profile.birthTime {
                    let df = DateFormatter()
                    df.dateFormat = "HH:mm"
                    birthTime = df.date(from: timeStr)
                }
                if let place = profile.birthPlace, !place.isEmpty {
                    birthPlace = place
                    // Reverse geocode to show city name
                    let parts = place.split(separator: ",")
                    if parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]) {
                        let location = CLLocation(latitude: lat, longitude: lng)
                        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                            birthPlaceQuery = [placemark.locality, placemark.country].compactMap { $0 }.joined(separator: ", ")
                        }
                    }
                }
            }
        } catch {
            if !error.isCancellation {
                await AppLogger.shared.error("Settings", "Failed to load birth details: \(error)")
            }
        }
        birthDetailsLoaded = true
    }

    private func saveBirthDetails() async {
        savingBirth = true
        defer { savingBirth = false }

        var body: [String: Any] = [:]

        if let date = birthDate {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            body["birthDate"] = df.string(from: date)
        }

        if let time = birthTime {
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            body["birthTime"] = df.string(from: time)
        }

        if !birthPlace.isEmpty {
            body["birthPlace"] = birthPlace
        }

        guard !body.isEmpty, let data = try? JSONSerialization.data(withJSONObject: body) else {
            await AppLogger.shared.error("Settings", "Birth save: body empty or serialization failed")
            return
        }
        do {
            let _: EmptyResponse = try await api.patchRaw("/me", body: data)
            await AppLogger.shared.info("Settings", "Birth details saved: \(body.keys.joined(separator: ", "))")
        } catch let ApiError.httpError(statusCode, responseData) {
            let responseBody = String(data: responseData, encoding: .utf8) ?? "unreadable"
            await AppLogger.shared.error("Settings", "Birth save \(statusCode): \(responseBody)")
        } catch {
            await AppLogger.shared.error("Settings", "Birth save failed: \(error)")
        }
    }

    private func formatBirthDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func formatBirthTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Server card with status dot

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
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
                VStack(spacing: 8) {
                    Text("Unable to reach server")
                        .font(.sacredSmall)
                        .foregroundColor(.sacredRed)
                    HStack(spacing: 16) {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.1)))
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

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.sacredSectionLabel)
                .tracking(3)
                .foregroundColor(.sacredLabel)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.sacredBgCard))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.sacredMuted.opacity(0.1)))
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

// MARK: - Profile response model

private struct MeResponse: Decodable {
    let profile: MeProfileData?
}

private struct MeProfileData: Decodable {
    let birthDate: String?
    let birthTime: String?
    let birthPlace: String?
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
