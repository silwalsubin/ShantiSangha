import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showSignOutConfirmation = false
    @State private var showErrorDetail = false
    @State private var serverStatus: ServerStatus = .loading
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
                                .fill(LinearGradient(colors: [.sacredGold, .sacredGoldDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 40, height: 40)
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

                // iOS Client
                settingsCard(title: "IOS CLIENT") {
                    infoRow(icon: "square.stack", label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    infoRow(icon: "hammer", label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                // App Server
                serverCard

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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await fetchServerVersion() }
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
                infoRow(icon: "clock", label: "Built", value: sv.buildTime)
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

    private func fetchServerVersion() async {
        do {
            let version: ServerVersion = try await api.get("/version")
            serverStatus = .connected(version)
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
