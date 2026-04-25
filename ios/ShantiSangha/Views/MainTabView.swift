import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
/// Custom sacred icons matching the web app's SacredIcons.vue
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var syncStatus = SyncStatus.shared
    @StateObject private var deepLinks = DeepLinkRouter.shared
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
        ZStack(alignment: .top) {
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
                    FriendsTabView()
                }
                .tabItem {
                    Image("tab.union")
                    Text("Friends")
                }
                .tag(3)
            }
            .tint(.sacredGold)
            .sheet(item: deepLinkBinding) { token in
                AcceptInvitationView(token: token.value) { _ in
                    selectedTab = 3
                }
            }

            SyncBanner(
                isConnected: network.isConnected,
                syncing: syncStatus.syncing,
                pendingCount: syncStatus.pendingCount
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .onChange(of: selectedTab) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onAppear { MotionManager.shared.start() }
        .onDisappear { MotionManager.shared.stop() }
    }

    private var deepLinkBinding: Binding<InviteTokenItem?> {
        Binding(
            get: {
                deepLinks.pendingInviteToken.map { InviteTokenItem(value: $0) }
            },
            set: { newValue in
                if newValue == nil { deepLinks.clear() }
            }
        )
    }
}

/// Identifiable wrapper for `.sheet(item:)` driven by a token string.
struct InviteTokenItem: Identifiable {
    let value: String
    var id: String { value }
}

private struct SyncBanner: View {
    let isConnected: Bool
    let syncing: Bool
    let pendingCount: Int

    private var shouldShow: Bool {
        !isConnected || syncing || pendingCount > 0
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.sacredSmall)
                    .foregroundColor(accentColor)
                Text(message)
                    .font(.sacredSmall)
                    .foregroundColor(.sacredText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.sacredBgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.22), lineWidth: 1))
            .shadow(color: .sacredMuted.opacity(0.12), radius: 8, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.25), value: shouldShow)
        }
    }

    private var iconName: String {
        if !isConnected { return "wifi.slash" }
        if syncing { return "arrow.triangle.2.circlepath" }
        return "tray.and.arrow.up"
    }

    private var accentColor: Color {
        !isConnected ? .sacredRed : .sacredGold
    }

    private var message: String {
        if !isConnected {
            return "Offline. Your changes will wait here."
        }
        if syncing {
            return "Saving your changes..."
        }
        return "\(pendingCount) change\(pendingCount == 1 ? "" : "s") waiting to sync."
    }
}
