import SwiftUI

struct BrowseView: View {
    @EnvironmentObject var model: AppModel
    let kind: MediaKind
    @State private var category: String?
    @State private var playing: MediaItem?

    private var items: [MediaItem] {
        let all = model.library?.items(for: kind) ?? []
        guard let c = category else { return all }
        return all.filter { $0.categoryId == c }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            Button("All") { category = nil }
                            ForEach(model.library?.categories(for: kind) ?? [], id: \.self) { c in
                                Button(c.name) { category = c.id }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: kind == .live ? 320 : 220), spacing: 40)], spacing: 40) {
                        ForEach(items.prefix(600)) { item in
                            if item.kind == .series {
                                NavigationLink(value: item) { Tile(item: item) }
                                    .buttonStyle(.card)
                                    .contextMenu { favButton(item) }
                            } else {
                                Button { playing = item } label: { Tile(item: item) }
                                    .buttonStyle(.card)
                                    .contextMenu { favButton(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
            }
            .navigationDestination(for: MediaItem.self) { EpisodesView(series: $0) }
            .fullScreenCover(item: $playing) { PlayerView(item: $0) }
        }
    }

    @ViewBuilder
    private func favButton(_ item: MediaItem) -> some View {
        Button(model.isFavorite(item) ? "Remove from My List" : "Add to My List") {
            model.toggleFavorite(item)
        }
    }
}

struct Tile: View {
    let item: MediaItem

    var body: some View {
        VStack {
            AsyncImage(url: item.poster.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default:
                    Image(systemName: item.kind == .live ? "tv" : "film")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
            Text(item.name).lineLimit(2).font(.callout).padding(.horizontal, 8).padding(.bottom, 8)
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject var model: AppModel
    @State private var playing: MediaItem?

    var body: some View {
        NavigationStack {
            if model.favorites.isEmpty {
                Text("Long-press an item and choose Add to My List.").foregroundStyle(.secondary)
            } else {
                List(model.favorites) { item in
                    if item.kind == .series {
                        NavigationLink(item.name, value: item)
                    } else {
                        Button(item.name) { playing = item }
                    }
                }
                .navigationDestination(for: MediaItem.self) { EpisodesView(series: $0) }
                .fullScreenCover(item: $playing) { PlayerView(item: $0) }
            }
        }
    }
}

struct EpisodesView: View {
    @EnvironmentObject var model: AppModel
    let series: MediaItem
    @State private var episodes: [Episode] = []
    @State private var loading = true
    @State private var playing: MediaItem?

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if episodes.isEmpty {
                Text("No episodes found").foregroundStyle(.secondary)
            } else {
                List(episodes) { e in
                    Button("S\(e.season) · E\(e.number)  \(e.title)") {
                        playing = MediaItem(id: "ep\(e.id)", name: "\(series.name) – \(e.title)",
                                            kind: .movie, url: e.url, poster: series.poster)
                    }
                }
            }
        }
        .navigationTitle(series.name)
        .task {
            episodes = (try? await model.xtream?.episodes(seriesId: series.id)) ?? []
            loading = false
        }
        .fullScreenCover(item: $playing) { PlayerView(item: $0) }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            let lib = model.library
            Text("Source: \(model.source.type.rawValue)")
            Text("\(lib?.live.count ?? 0) channels · \(lib?.movies.count ?? 0) movies · \(lib?.series.count ?? 0) series")
                .foregroundStyle(.secondary)
            Button("Reload library") { Task { await model.connect() } }
            Button("Switch source") { model.signOut() }
            Text("StreamBoss is a player only. No content is included.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(60)
    }
}
