import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var source = Source()
    @Published var library: Library?
    @Published var loading = false
    @Published var error: String?
    @Published var favorites: [MediaItem] = []

    private let defaults = UserDefaults.standard
    private var positions: [String: Double] = [:]
    private(set) var xtream: XtreamClient?

    init() {
        if let d = defaults.data(forKey: "source"),
           var s = try? JSONDecoder().decode(Source.self, from: d) {
            s.password = Keychain.get("password") ?? ""
            source = s
        }
        if let d = defaults.data(forKey: "favorites"),
           let f = try? JSONDecoder().decode([MediaItem].self, from: d) { favorites = f }
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

    func isFavorite(_ item: MediaItem) -> Bool { favorites.contains { $0.key == item.key } }

    func toggleFavorite(_ item: MediaItem) {
        if let i = favorites.firstIndex(where: { $0.key == item.key }) {
            favorites.remove(at: i)
        } else {
            favorites.append(item)
        }
        if let d = try? JSONEncoder().encode(favorites) { defaults.set(d, forKey: "favorites") }
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
