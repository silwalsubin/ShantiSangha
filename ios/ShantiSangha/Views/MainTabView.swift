import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
/// Custom sacred icons matching the web app's SacredIcons.vue
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Dharma", image: "tab.vajra")
            }
            .tag(0)

            NavigationStack {
                ReflectView()
            }
            .tabItem {
                Label("Reflect", image: "tab.dialogue")
            }
            .tag(1)

            NavigationStack {
                JourneyView()
            }
            .tabItem {
                Label("Journey", image: "tab.diya")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", image: "tab.chakra")
            }
            .tag(3)
        }
        .tint(.sacredGold)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
