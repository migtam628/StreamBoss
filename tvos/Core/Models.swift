import Foundation

enum MediaKind: String, Codable {
    case live, movie, series
}

struct MediaCategory: Hashable {
    let id: String
    let name: String
}

struct MediaItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let kind: MediaKind
    var url: String?
    var poster: String?
    var categoryId: String = ""
    var plot: String?

    /// Stable key across kinds (ids can repeat between live/movie/series).
    var key: String { "\(kind.rawValue):\(id)" }
}

struct Library {
    var live: [MediaItem] = []
    var movies: [MediaItem] = []
    var series: [MediaItem] = []
    var liveCategories: [MediaCategory] = []
    var movieCategories: [MediaCategory] = []
    var seriesCategories: [MediaCategory] = []

    func items(for kind: MediaKind) -> [MediaItem] {
        switch kind {
        case .live: return live
        case .movie: return movies
        case .series: return series
        }
    }

    func categories(for kind: MediaKind) -> [MediaCategory] {
        switch kind {
        case .live: return liveCategories
        case .movie: return movieCategories
        case .series: return seriesCategories
        }
    }
}

enum SourceType: String, Codable {
    case xtream, m3u, demo
}

struct Source: Codable, Equatable {
    var type: SourceType = .xtream
    var url: String = ""
    var username: String = ""
    var password: String = ""
}

struct Episode: Identifiable, Hashable {
    let id: String
    let title: String
    let season: Int
    let number: Int
    let url: String
}
