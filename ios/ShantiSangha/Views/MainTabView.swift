import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @State private var showAccountMenu = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            accountButton
                        }
                    }
            }
            .tabItem {
                Image(systemName: "square.grid.2x2")
                Text("Home")
            }

            NavigationStack {
                ReflectView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            accountButton
                        }
                    }
            }
            .tabItem {
                Image(systemName: "bubble.left.and.bubble.right")
                Text("Reflect")
            }

            NavigationStack {
                JourneyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            accountButton
                        }
                    }
            }
            .tabItem {
                Image(systemName: "flame")
                Text("Journey")
            }
        }
        .tint(.sacredGold)
        .confirmationDialog("Account", isPresented: $showAccountMenu) {
            if let email = auth.user?.email {
                Button(email) {}
            }
            NavigationLink("About") {
                AboutView()
            }
            Button("Sign out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var accountButton: some View {
        Button {
            showAccountMenu = true
        } label: {
            Image(systemName: "person.circle")
                .font(.system(size: 22))
                .foregroundColor(.sacredGold)
        }
    }
}
