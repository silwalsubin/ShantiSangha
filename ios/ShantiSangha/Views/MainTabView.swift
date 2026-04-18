import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
/// Custom sacred icons matching the web app's SacredIcons.vue
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedTab = 0

    init() {
        // Tab bar appearance — blur background + serif labels
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.5)

        let tabFont = Self.serifFont(ofSize: 10, weight: .medium)
        let tabLabelAttrs: [NSAttributedString.Key: Any] = [.font: tabFont]
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = tabLabelAttrs
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = tabLabelAttrs
        tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes = tabLabelAttrs
        tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes = tabLabelAttrs
        tabAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes = tabLabelAttrs
        tabAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = tabLabelAttrs

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar appearance — serif inline + large titles everywhere
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.titleTextAttributes = [
            .font: Self.serifFont(ofSize: 17, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: Self.serifFont(ofSize: 34, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    /// Builds a New-York-serif UIFont matching the SwiftUI `design: .serif` tokens.
    private static func serifFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
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
                Image("tab.peepal")
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
        .onAppear { MotionManager.shared.start() }
        .onDisappear { MotionManager.shared.stop() }
    }
}
