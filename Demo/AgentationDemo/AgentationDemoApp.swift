import SwiftUI
import Agentation

@main
struct AgentationDemoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Start `npx -y agentation-mcp server` on your Mac to sync annotations to your agent.
                // Without it, everything still works locally; the toolbar's sync dot turns red.
                .agentation(endpoint: "http://localhost:4747", appName: "Agentation Demo")
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                CheckoutView()
            }
            .tabItem { Label("Checkout", systemImage: "cart") }

            SettingsScreen()
                .ignoresSafeArea()
                .tabItem { Label("Settings (UIKit)", systemImage: "gearshape") }
        }
    }
}
