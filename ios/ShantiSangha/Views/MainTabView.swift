import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
/// Custom sacred icons matching the web app's SacredIcons.vue
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Image("tab.vajra")
                Text("Home")
            }
            .tag(0)

            NavigationStack {
                ReflectView()
            }
            .tabItem {
                Image("tab.dialogue")
                Text("Reflect")
            }
            .tag(1)

            NavigationStack {
                JourneyView()
            }
            .tabItem {
                Image("tab.diya")
                Text("Journey")
            }
            .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Image("tab.chakra")
                Text("Settings")
            }
            .tag(3)
        }
        .tint(.sacredGold)
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
