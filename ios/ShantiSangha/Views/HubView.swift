import SwiftUI

/// The destinations that live behind Home's atom icon.
enum HubTab: Hashable {
    case chats
    case reflect
    case circles
    case profile
}

/// The secondary surfaces, hosted in a tab bar and presented over Home via
/// the atom icon. Home itself is the landing; everything else lives here.
/// Each tab carries a vajra button in its top-right that returns to Home
/// (dismisses the cover).
struct HubView: View {
    let unreadNotifications: Int
    @State private var selectedTab: HubTab
    @StateObject private var friendsBadge = FriendsBadgeService.shared
    @Environment(\.dismiss) private var dismiss

    init(initialTab: HubTab = .chats, unreadNotifications: Int) {
        _selectedTab = State(initialValue: initialTab)
        self.unreadNotifications = unreadNotifications
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            hubTab(.chats, image: "tab.dialogue", title: "Chats", badge: friendsBadge.unreadMessagesCount) {
                ChatsTabView()
            }

            hubTab(.reflect, image: "tab.peepal", title: "Reflect") {
                ReflectView()
            }

            hubTab(.circles, systemImage: "atom", title: "Circles", badge: friendsBadge.requestsCount) {
                FriendsTabView()
            }

            hubTab(.profile, image: "tab.diya", title: "Profile") {
                ProfileView(unreadNotifications: unreadNotifications)
            }
        }
        .tint(.sacredGold)
        .task { await friendsBadge.refresh() }
    }

    // MARK: - Tab builder

    @ViewBuilder
    private func hubTab<Content: View>(
        _ tab: HubTab,
        image: String? = nil,
        systemImage: String? = nil,
        title: String,
        badge: Int = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        vajraHomeButton
                    }
                }
        }
        .tabItem {
            if let image { Image(image) } else if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .badge(badge)
        .tag(tab)
    }

    /// Returns to Home by dismissing the hub cover. The vajra is the app's
    /// mark for its center — tapping it anywhere brings you back to it.
    private var vajraHomeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        } label: {
            Image("tab.vajra")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundColor(.sacredGold)
        }
        .accessibilityLabel("Back to home")
    }
}
