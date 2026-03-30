import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showSignOutConfirmation = false
    @State private var serverVersion: ServerVersion?
    private let api = ApiService.shared

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
                settingsCard(title: "APP SERVER") {
                    if let sv = serverVersion {
                        infoRow(icon: "server.rack", label: "Git hash", value: sv.gitHash)
                        infoRow(icon: "clock", label: "Built", value: sv.buildTime)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                serverVersion = try await api.get("/version")
            } catch {}
        }
        .confirmationDialog("Are you sure you want to sign out?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
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
