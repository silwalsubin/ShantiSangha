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
                            Button {
                                showAccountMenu = true
                            } label: {
                                Image(systemName: "person.circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(.sacredGold)
                            }
                        }
                    }
            }
            .tabItem {
                Image(systemName: "square.grid.2x2")
                Text("Home")
            }

            Text("Reflect")
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Reflect")
                }

            Text("Journey")
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
            Button("Sign out", role: .destructive) {
                auth.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
