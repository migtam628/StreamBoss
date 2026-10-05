import Foundation

enum Demo {
    static var library: Library {
        var lib = Library()
        lib.liveCategories = [MediaCategory(id: "demo", name: "Demo Channels")]
        lib.movieCategories = [MediaCategory(id: "demo", name: "Open Movies")]
        lib.live = [
            MediaItem(id: "l1", name: "Demo Channel 1", kind: .live,
                      url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", categoryId: "demo"),
            MediaItem(id: "l2", name: "Demo Channel 2", kind: .live,
                      url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8", categoryId: "demo"),
        ]
        lib.movies = [
            MediaItem(id: "m1", name: "Big Buck Bunny", kind: .movie,
                      url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", categoryId: "demo"),
            MediaItem(id: "m2", name: "Sintel", kind: .movie,
                      url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4", categoryId: "demo"),
        ]
        return lib
    }
}
