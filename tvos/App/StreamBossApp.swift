import SwiftUI

@main
struct StreamBossApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var sync = SyncModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var sync: SyncModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        content
            .task {
                // A change here (My List, the end of a video) syncs soon; the app opening syncs at once.
                await sync.start(app: model)
            }
            .onChange(of: phase) { _, now in
                if now == .active { Task { await sync.sync(app: model) } }
            }
    }

    @ViewBuilder
    private var content: some View {
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
