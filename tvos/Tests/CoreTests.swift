import XCTest
@testable import StreamBoss

final class CoreTests: XCTestCase {
    func testM3UParsesLiveAndMovies() {
        let body = """
        #EXTM3U
        #EXTINF:-1 tvg-logo="http://x/l.png" group-title="News",Channel One
        http://h/live/1.m3u8
        #EXTINF:-1 group-title="Films",Some Movie
        http://h/movie/u/p/9.mkv
        """
        let lib = M3UParser.parse(body)
        XCTAssertEqual(lib.live.count, 1)
        XCTAssertEqual(lib.live[0].name, "Channel One")
        XCTAssertEqual(lib.live[0].poster, "http://x/l.png")
        XCTAssertEqual(lib.movies.count, 1)
        XCTAssertEqual(lib.liveCategories.map(\.id), ["News"])
        XCTAssertEqual(lib.movieCategories.map(\.id), ["Films"])
    }

    func testTitlesWithCommasStayWhole() {
        let lib = M3UParser.parse("#EXTINF:-1 group-title=\"Films, HD\",Some, Movie\nhttp://h/movie/u/p/9.mkv\n")
        XCTAssertEqual(lib.movies.first?.name, "Some, Movie")
        XCTAssertEqual(lib.movies.first?.categoryId, "Films, HD")
    }

    func testXtreamURLsAndIdCoercion() {
        let c = XtreamClient(server: "http://h:8080//", user: "u", pass: "p w")
        XCTAssertEqual(c.base, "http://h:8080")
        let url = c.apiURL("get_live_streams")?.absoluteString ?? ""
        XCTAssertTrue(url.contains("username=u"))
        XCTAssertTrue(url.contains("action=get_live_streams"))
        XCTAssertTrue(url.contains("password=p%20w"))
        XCTAssertEqual(XtreamClient.str(NSNumber(value: 5)), "5")
        XCTAssertEqual(XtreamClient.str("7"), "7")
        XCTAssertNil(XtreamClient.str(""))
    }

    func testMediaKeyIsKindScoped() {
        let a = MediaItem(id: "1", name: "A", kind: .live)
        let b = MediaItem(id: "1", name: "B", kind: .movie)
        XCTAssertNotEqual(a.key, b.key)
    }
}
