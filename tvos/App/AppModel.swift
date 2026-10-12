import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var source = Source()
    @Published var library: Library?
    @Published var loading = false
    @Published var error: String?
    /// My List as item keys (`movie:123`): the same keys the other apps use, so it can be synced.
    @Published var favoriteKeys: [String] = []

    /// Called after something that is synced changed here (My List, the end of a video).
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private var positions: [String: Double] = [:]
    private var itemCache: [String: MediaItem] = [:] // the items added to My List on this device
    private(set) var xtream: XtreamClient?

    init() {
        if let d = defaults.data(forKey: "source"),
           var s = try? JSONDecoder().decode(Source.self, from: d) {
            s.password = Keychain.get("password") ?? ""
            source = s
        }
        if let keys = defaults.stringArray(forKey: "favoriteKeys") {
            favoriteKeys = keys
            if let d = defaults.data(forKey: "favoriteItems"),
               let c = try? JSONDecoder().decode([String: MediaItem].self, from: d) { itemCache = c }
        } else if let d = defaults.data(forKey: "favorites"),
                  let f = try? JSONDecoder().decode([MediaItem].self, from: d) {
            // From before My List could be synced: it was a list of items.
            favoriteKeys = f.map(\.key)
            itemCache = Dictionary(f.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            persistFavorites()
        }
        positions = (defaults.dictionary(forKey: "positions") as? [String: Double]) ?? [:]
        if source.type == .demo || !source.url.isEmpty { Task { await connect() } }
    }

    func connect() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            switch source.type {
            case .demo:
                library = Demo.library
                xtream = nil
            case .m3u:
                guard let url = URL(string: source.url) else { throw URLError(.badURL) }
                let (data, _) = try await URLSession.shared.data(from: url)
                library = M3UParser.parse(String(decoding: data, as: UTF8.self))
                xtream = nil
            case .xtream:
                let c = XtreamClient(server: source.url, user: source.username, pass: source.password)
                try await c.authenticate()
                library = try await c.loadLibrary()
                xtream = c
            }
            persistSource()
        } catch {
            library = nil
            self.error = error.localizedDescription
        }
    }

    func useDemo() async {
        source = Source(type: .demo)
        await connect()
    }

    func signOut() {
        library = nil
        xtream = nil
        source = Source()
        defaults.removeObject(forKey: "source")
        Keychain.set("", for: "password")
    }

    private func persistSource() {
        var s = source
        s.password = ""
        if let d = try? JSONEncoder().encode(s) { defaults.set(d, forKey: "source") }
        Keychain.set(source.password, for: "password")
    }

    // MARK: Favorites

    /// My List as items: the ones added here, and the ones added on another device that this library has.
    var favorites: [MediaItem] {
        favoriteKeys.compactMap { itemCache[$0] ?? lookup($0) }
    }

    private func lookup(_ key: String) -> MediaItem? {
        guard let lib = library, let colon = key.firstIndex(of: ":"),
              let kind = MediaKind(rawValue: String(key[..<colon])) else { return nil }
        let id = String(key[key.index(after: colon)...])
        return lib.items(for: kind).first { $0.id == id }
    }

    func isFavorite(_ item: MediaItem) -> Bool { favoriteKeys.contains(item.key) }

    func toggleFavorite(_ item: MediaItem) {
        if let i = favoriteKeys.firstIndex(of: item.key) {
            favoriteKeys.remove(at: i)
            itemCache.removeValue(forKey: item.key)
        } else {
            favoriteKeys.append(item.key)
            itemCache[item.key] = item
        }
        persistFavorites()
        onChange?()
    }

    private func persistFavorites() {
        defaults.set(favoriteKeys, forKey: "favoriteKeys")
        if let d = try? JSONEncoder().encode(itemCache) { defaults.set(d, forKey: "favoriteItems") }
    }

    // MARK: Sync

    /// What is synced, as the other apps keep it: item keys, and positions in milliseconds.
    func syncState() -> SyncState {
        SyncState(favorites: favoriteKeys, positions: positions.mapValues { Int(($0 * 1000).rounded()) })
    }

    /// Takes what the server brought.
    func apply(_ s: SyncState) {
        favoriteKeys = s.favorites
        itemCache = itemCache.filter { s.favorites.contains($0.key) }
        persistFavorites()
        positions = s.positions.mapValues { Double($0) / 1000 }
        defaults.set(positions, forKey: "positions")
    }

    // MARK: Resume

    func resume(for key: String) -> Double { positions[key] ?? 0 }

    func save(position: Double, duration: Double, key: String, live: Bool) {
        guard !live, duration > 120 else { return }
        if position > duration * 0.97 { positions.removeValue(forKey: key) }
        else if position > 10 { positions[key] = position }
        defaults.set(positions, forKey: "positions")
    }
}
