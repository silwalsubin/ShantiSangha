import SwiftUI

/// App shell. Home is the single root screen; the assistant is reached
/// from the vajra affordance on Home, and Reflect / Chats / Circles live
/// behind Home's top-right profile menu. This view keeps the app-level
/// concerns that aren't tied to any one screen: the sync banner, device
/// motion lifecycle, and the share-extension "send a photo to a friend"
/// sheet.
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var syncStatus = SyncStatus.shared
    @StateObject private var deepLinks = DeepLinkRouter.shared
    @StateObject private var friendsBadge = FriendsBadgeService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Tab bar appearance — blur background + serif labels. Applies to
        // the HubView tab bar reached from Home's atom icon.
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
            NavigationStack {
                HomeView()
            }
            .task { await friendsBadge.refresh() }
            // A photo shared in from another app → pick one connection
            // and send it into that chat.
            .sheet(item: sharedMediaBinding) { media in
                ShareToConnectionSheet(media: media) {
                    deepLinks.clearSharedMedia()
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
        .onAppear {
            MotionManager.shared.start()
            // Cold-launch hand-off: a share that launched the app may
            // arrive before/instead of `.onOpenURL`, so drain here too.
            deepLinks.consumeSharedMedia()
        }
        .onDisappear { MotionManager.shared.stop() }
        // Reopening after a share while backgrounded doesn't re-fire
        // `.onAppear`, so re-check when the scene becomes active.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { deepLinks.consumeSharedMedia() }
        }
    }

    private var sharedMediaBinding: Binding<SharedMediaPayload?> {
        Binding(
            get: { deepLinks.pendingSharedMedia },
            set: { newValue in
                if newValue == nil { deepLinks.clearSharedMedia() }
            }
        )
    }
}

/// Identifiable wrapper for `.sheet(item:)` driven by a token string.
struct InviteTokenItem: Identifiable, Equatable {
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
