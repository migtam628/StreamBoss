import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct XtreamClient {
    let base: String
    let user: String
    let pass: String

    init(server: String, user: String, pass: String) {
        var b = server.trimmingCharacters(in: .whitespaces)
        while b.hasSuffix("/") { b.removeLast() }
        self.base = b
        self.user = user
        self.pass = pass
    }

    func apiURL(_ action: String?, extra: [String: String] = [:]) -> URL? {
        var comps = URLComponents(string: "\(base)/player_api.php")
        var items = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { items.append(URLQueryItem(name: k, value: v)) }
        comps?.queryItems = items
        return comps?.url
    }

    private func get(_ action: String?, extra: [String: String] = [:]) async throws -> Any {
        guard let url = apiURL(action, extra: extra) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// JSON ids arrive as numbers or strings depending on the panel.
    static func str(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    func authenticate() async throws {
        let j = try await get(nil)
        let info = (j as? [String: Any])?["user_info"] as? [String: Any]
        guard XtreamClient.str(info?["auth"]) == "1" else {
            throw NSError(domain: "StreamBoss", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }
    }

    func loadLibrary() async throws -> Library {
        async let lc = get("get_live_categories")
        async let ls = get("get_live_streams")
        async let vc = get("get_vod_categories")
        async let vs = get("get_vod_streams")
        async let sc = get("get_series_categories")
        async let ss = get("get_series")
        let (liveCats, live, vodCats, vod, serCats, ser) = try await (lc, ls, vc, vs, sc, ss)

        func cats(_ a: Any) -> [MediaCategory] {
            (a as? [[String: Any]] ?? []).compactMap {
                guard let id = XtreamClient.str($0["category_id"]), let n = XtreamClient.str($0["category_name"]) else { return nil }
                return MediaCategory(id: id, name: n)
            }
        }

        var lib = Library()
        lib.liveCategories = cats(liveCats)
        lib.movieCategories = cats(vodCats)
        lib.seriesCategories = cats(serCats)
        lib.live = (live as? [[String: Any]] ?? []).compactMap {
            guard let id = XtreamClient.str($0["stream_id"]) else { return nil }
            return MediaItem(id: id, name: XtreamClient.str($0["name"]) ?? "Channel", kind: .live,
                             url: "\(base)/live/\(user)/\(pass)/\(id).m3u8",
                             poster: XtreamClient.str($0["stream_icon"]),
                             categoryId: XtreamClient.str($0["category_id"]) ?? "")
        }
        lib.movies = (vod as? [[String: Any]] ?? []).compactMap {
            guard let id = XtreamClient.str($0["stream_id"]) else { return nil }
            let ext = XtreamClient.str($0["container_extension"]) ?? "mp4"
            return MediaItem(id: id, name: XtreamClient.str($0["name"]) ?? "Movie", kind: .movie,
                             url: "\(base)/movie/\(user)/\(pass)/\(id).\(ext)",
                             poster: XtreamClient.str($0["stream_icon"]),
                             categoryId: XtreamClient.str($0["category_id"]) ?? "")
        }
        lib.series = (ser as? [[String: Any]] ?? []).compactMap {
            guard let id = XtreamClient.str($0["series_id"]) else { return nil }
            return MediaItem(id: id, name: XtreamClient.str($0["name"]) ?? "Series", kind: .series,
                             poster: XtreamClient.str($0["cover"]),
                             categoryId: XtreamClient.str($0["category_id"]) ?? "",
                             plot: XtreamClient.str($0["plot"]))
        }
        return lib
    }

    func episodes(seriesId: String) async throws -> [Episode] {
        let j = try await get("get_series_info", extra: ["series_id": seriesId])
        let eps = (j as? [String: Any])?["episodes"] as? [String: Any] ?? [:]
        var out: [Episode] = []
        for (season, list) in eps {
            for e in list as? [[String: Any]] ?? [] {
                guard let id = XtreamClient.str(e["id"]) else { continue }
                let ext = XtreamClient.str(e["container_extension"]) ?? "mp4"
                let num = Int(XtreamClient.str(e["episode_num"]) ?? "") ?? 0
                out.append(Episode(id: id,
                                   title: XtreamClient.str(e["title"]) ?? "Episode \(num)",
                                   season: Int(season) ?? 0, number: num,
                                   url: "\(base)/series/\(user)/\(pass)/\(id).\(ext)"))
            }
        }
        return out.sorted { $0.season != $1.season ? $0.season < $1.season : $0.number < $1.number }
    }
}
