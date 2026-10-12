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

    func testTextsStayEnglishWhereThereIsNoTranslation() {
        // Without a translation file (here, on Linux) tr() gives back the English text it was asked for.
        XCTAssertEqual(tr("Other"), "Other")
        XCTAssertEqual(trf("Channel %lld", 3), "Channel 3")
        let lib = M3UParser.parse("#EXTINF:-1,\nhttp://h/live/1.m3u8\n")
        XCTAssertEqual(lib.live.first?.name, "Channel 1")
        XCTAssertEqual(lib.liveCategories.map(\.id), ["Other"])
        XCTAssertEqual(Demo.library.live.first?.name, "Demo Channel 1")
        XCTAssertEqual(Demo.library.liveCategories.first?.name, "Demo Channels")
    }

    func testMediaKeyIsKindScoped() {
        let a = MediaItem(id: "1", name: "A", kind: .live)
        let b = MediaItem(id: "1", name: "B", kind: .movie)
        XCTAssertNotEqual(a.key, b.key)
    }

    // MARK: Sync

    func testSyncWireFormatMatchesTheFlutterApp() {
        XCTAssertEqual(SyncCodec.decodeList("{\"t\":\"l\",\"v\":[\"movie:1\",\"series:2\"]}"), ["movie:1", "series:2"])
        XCTAssertEqual(SyncCodec.decodeMap("{\"t\":\"s\",\"v\":\"{\\\"movie:1\\\":90000}\"}"), ["movie:1": 90000])
        XCTAssertEqual(SyncCodec.decodeList(SyncCodec.encodeList(["a", "b"])), ["a", "b"])
        XCTAssertEqual(SyncCodec.decodeMap(SyncCodec.encodeMap(["movie:1": 5])), ["movie:1": 5])
        XCTAssertNil(SyncCodec.decodeList(nil))
        XCTAssertNil(SyncCodec.decodeMap("not json"))
    }

    func testListMergeKeepsBothAdditionsAndRemovals() {
        // Joining: the server's list, plus what only this device has.
        XCTAssertEqual(SyncMerge.list(base: nil, local: ["b", "c"], server: ["a", "b"], hadBase: false), ["a", "b", "c"])
        // Synced before: this device added c and removed a; the server gained d meanwhile.
        XCTAssertEqual(SyncMerge.list(base: ["a", "b"], local: ["b", "c"], server: ["a", "b", "d"], hadBase: true), ["b", "d", "c"])
        XCTAssertNil(SyncMerge.list(base: nil, local: nil, server: nil, hadBase: false))
    }

    func testMapMergeKeepsChangesToDifferentEntries() {
        XCTAssertEqual(SyncMerge.map(base: nil, local: ["a": 1, "b": 2], server: ["b": 9], hadBase: false), ["a": 1, "b": 9])
        XCTAssertEqual(
            SyncMerge.map(base: ["a": 1, "b": 2], local: ["a": 5, "b": 2], server: ["a": 1, "b": 2, "c": 3], hadBase: true),
            ["a": 5, "b": 2, "c": 3])
        // Finished here (removed): gone on the server too.
        XCTAssertEqual(SyncMerge.map(base: ["a": 1], local: [:], server: ["a": 1], hadBase: true), [:])
    }

    func testSyncedSourcesComeWithoutPasswords() {
        let wire = SyncCodec.encodeList([
            "{\"name\":\"Home\",\"type\":\"xtream\",\"url\":\"http://h:80\",\"user\":\"me\",\"pass\":\"\"}",
            "{\"name\":\"Demo\",\"type\":\"demo\"}",
            "garbage",
        ])
        XCTAssertEqual(SyncedSource.decode(wire), [SyncedSource(name: "Home", type: .xtream, url: "http://h:80", username: "me")])
        XCTAssertEqual(SyncedSource.decode(nil), [])
    }

    func testServerAddressIsNormalized() {
        XCTAssertEqual(SyncServer.normalize(" sync.example.com/ "), "https://sync.example.com")
        XCTAssertEqual(SyncServer.normalize("http://192.168.1.5:8787"), "http://192.168.1.5:8787")
        XCTAssertNil(SyncServer.normalize(""))
        XCTAssertNil(SyncServer.normalize("ftp://x"))
    }

    func testEngineJoinsThenPushesThenPullsWhatAnotherDeviceDid() async throws {
        let server = FakeServer()
        server.items["favorites"] = SyncRemoteItem(value: SyncCodec.encodeList(["movie:1"]), rev: 3)
        let engine = SyncEngine()

        // First sync: joins the server's list with this device's, and sends the result.
        var out = try await engine.run(local: SyncState(favorites: ["series:9"], positions: ["movie:1": 60000]), api: server)
        XCTAssertEqual(out.state.favorites, ["movie:1", "series:9"])
        XCTAssertEqual(SyncCodec.decodeList(server.items["favorites"]?.value), ["movie:1", "series:9"])
        XCTAssertEqual(SyncCodec.decodeMap(server.items["positions"]?.value), ["movie:1": 60000])
        XCTAssertEqual(engine.base["favorites"]?.rev, server.items["favorites"]?.rev)

        // Nothing changed anywhere: nothing is sent.
        let puts = server.puts
        out = try await engine.run(local: out.state, api: server)
        XCTAssertEqual(server.puts, puts)
        XCTAssertEqual(out.pulled, 0)

        // Another device removes movie:1 from My List and moves the position on.
        server.items["favorites"] = SyncRemoteItem(value: SyncCodec.encodeList(["series:9"]), rev: 10)
        server.items["positions"] = SyncRemoteItem(value: SyncCodec.encodeMap(["movie:1": 120000]), rev: 8)
        out = try await engine.run(local: out.state, api: server)
        XCTAssertEqual(out.state.favorites, ["series:9"])
        XCTAssertEqual(out.state.positions, ["movie:1": 120000])
        XCTAssertEqual(out.pulled, 2)
    }

    func testEngineMergesAndRetriesWhenAnotherDeviceWritesFirst() async throws {
        let server = FakeServer()
        let engine = SyncEngine(base: [
            "favorites": SyncBaseEntry(rev: 1, value: SyncCodec.encodeList(["a"])),
        ])
        server.items["favorites"] = SyncRemoteItem(value: SyncCodec.encodeList(["a"]), rev: 1)
        server.conflictOnce = ("favorites", SyncRemoteItem(value: SyncCodec.encodeList(["a", "z"]), rev: 2))
        let out = try await engine.run(local: SyncState(favorites: ["a", "b"]), api: server)
        XCTAssertEqual(Set(out.state.favorites), ["a", "b", "z"])
        XCTAssertEqual(Set(SyncCodec.decodeList(server.items["favorites"]?.value) ?? []), ["a", "b", "z"])
    }

    func testEngineReportsTheServersSources() async throws {
        let server = FakeServer()
        let wire = SyncCodec.encodeList(["{\"name\":\"Home\",\"type\":\"m3u\",\"url\":\"http://h/p.m3u\"}"])
        server.items["sources"] = SyncRemoteItem(value: wire, rev: 1)
        let out = try await SyncEngine().run(local: SyncState(), api: server)
        XCTAssertEqual(SyncedSource.decode(out.sourcesWire).map(\.name), ["Home"])
    }
}

/// A stand-in for the sync server.
final class FakeServer: SyncTransport {
    var items: [String: SyncRemoteItem] = [:]
    var puts = 0
    /// The next write to this key finds that another device has written first.
    var conflictOnce: (String, SyncRemoteItem)?

    func fetch() async throws -> [String: SyncRemoteItem] { items }

    func put(key: String, value: String?, base: Int) async throws -> SyncPutResult {
        if let c = conflictOnce, c.0 == key {
            conflictOnce = nil
            items[key] = c.1
            return .conflict(c.1)
        }
        let cur = items[key]?.rev ?? 0
        if cur != base { return .conflict(items[key] ?? SyncRemoteItem(value: nil, rev: 0)) }
        puts += 1
        items[key] = SyncRemoteItem(value: value, rev: cur + 1)
        return .ok(cur + 1)
    }
}
