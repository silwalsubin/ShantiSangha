import SwiftUI

/// About — version info. Mirrors frontend/src/pages/app/about.vue
struct AboutView: View {
    @State private var serverVersion: ServerVersion?
    private let api = ApiService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Logo
                HStack(spacing: 12) {
                    Circle()
                        .fill(RadialGradient.sacredGoldShiny)
                        .frame(width: 40, height: 40)
                        .shimmer()
                        .clipShape(Circle())
                        .overlay(VajraIcon(size: 28, color: .white))
                    VStack(alignment: .leading) {
                        Text("ShantiSangha")
                            .font(.sacredSubheading)
                            .foregroundColor(.sacredText)
                        Text("Version info")
                            .font(.sacredSmall)
                            .foregroundColor(.sacredMuted)
                    }
                }

                // iOS Client
                infoCard(title: "IOS CLIENT") {
                    infoRow("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    infoRow("Build", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                // App Server
                infoCard(title: "APP SERVER") {
                    if let sv = serverVersion {
                        infoRow("Git hash", sv.gitHash)
                        infoRow("Built", sv.buildTime)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.sacredBg.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                serverVersion = try await api.get("/version")
            } catch {}
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
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

struct ServerVersion: Codable {
    let gitHash: String
    let gitHashFull: String
    let buildTime: String
}
