import SwiftUI

@main
struct StreamBossApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.loading {
            VStack(spacing: 24) {
                ProgressView()
                Text("Loading your library…")
            }
        } else if model.library == nil {
            SetupView()
        } else {
            TabView {
                BrowseView(kind: .live).tabItem { Text("Live") }
                BrowseView(kind: .movie).tabItem { Text("Movies") }
                BrowseView(kind: .series).tabItem { Text("Series") }
                FavoritesView().tabItem { Text("My List") }
                SettingsView().tabItem { Text("Settings") }
            }
        }
    }
}
