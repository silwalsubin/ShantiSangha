import SwiftUI

/// Main tab navigation — mirrors AppLayout.vue nav items
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
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
    }
}
