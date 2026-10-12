' Run with:  brs-cli components/lib/Common.brs components/lib/Strings.brs components/lib/Sync.brs tests/sync.test.brs
' (brs-node interpreter; no Roku device needed). A stand-in server replaces the real one.

sub Main()
    failures = 0
    useLang("en")

    ' ---- the wire format matches the Flutter app's
    failures = failures + check("list decodes", FormatJson(syncUnwireList("{""t"":""l"",""v"":[""movie:1"",""series:2""]}")), "[""movie:1"",""series:2""]")
    failures = failures + check("list round trip", FormatJson(syncUnwireList(syncWireList(["a", "b"]))), "[""a"",""b""]")
    m1 = syncUnwireMap("{""t"":""s"",""v"":""{\""movie:1\"":90000}""}")
    failures = failures + check("map decodes", m1["movie:1"], 90000)
    failures = failures + check("map round trip", syncUnwireMap(syncWireMap({ "movie:1": 5 }))["movie:1"], 5)
    failures = failures + check("list: nothing", syncUnwireList(invalid), invalid)
    failures = failures + check("map: not json", syncUnwireMap("not json"), invalid)

    ' ---- merging
    j = syncMergeList(invalid, ["b", "c"], ["a", "b"], false)
    failures = failures + check("joining a list", FormatJson(j), "[""a"",""b"",""c""]")
    j = syncMergeList(["a", "b"], ["b", "c"], ["a", "b", "d"], true)
    failures = failures + check("this device added c and removed a", FormatJson(j), "[""b"",""d"",""c""]")
    failures = failures + check("both empty", syncMergeList(invalid, invalid, invalid, false), invalid)
    j = syncMergeMap(invalid, { a: 1, b: 2 }, { b: 9 }, false)
    failures = failures + check("joining a map: the server wins", j.a * 100 + j.b, 109)
    j = syncMergeMap({ a: 1, b: 2 }, { a: 5, b: 2 }, { a: 1, b: 2, c: 3 }, true)
    failures = failures + check("different entries both stay", j.a * 100 + j.b * 10 + j.c, 523)
    j = syncMergeMap({ a: 1 }, {}, { a: 1 }, true)
    failures = failures + check("finished here: gone there", j.count(), 0)

    ' ---- the engine against a stand-in server
    server = fakeServer()
    server.items["favorites"] = { value: syncWireList(["movie:1"]), rev: 3 }
    api = { fetch: fakeFetch, put: fakePut, store: server }
    baseState = {}
    r = syncRun(api, { favs: ["series:9"], resume: { "movie:1": 60000 } }, baseState)
    failures = failures + check("first sync ok", r.ok, true)
    failures = failures + check("joined list", FormatJson(r.state.favs), "[""movie:1"",""series:9""]")
    failures = failures + check("server list", FormatJson(syncUnwireList(server.items["favorites"].value)), "[""movie:1"",""series:9""]")
    failures = failures + check("server positions", syncUnwireMap(server.items["positions"].value)["movie:1"], 60000)
    failures = failures + check("base follows the server", r.base["favorites"].rev, server.items["favorites"].rev)

    puts = server.puts
    r2 = syncRun(api, r.state, r.base)
    failures = failures + check("nothing changed: nothing sent", server.puts, puts)
    failures = failures + check("nothing changed: nothing pulled", r2.pulled, 0)

    server.items["favorites"] = { value: syncWireList(["series:9"]), rev: 10 }
    server.items["positions"] = { value: syncWireMap({ "movie:1": 120000 }), rev: 8 }
    r3 = syncRun(api, r2.state, r2.base)
    failures = failures + check("pulls the removal", FormatJson(r3.state.favs), "[""series:9""]")
    failures = failures + check("pulls the position", r3.state.resume["movie:1"], 120000)
    failures = failures + check("two things pulled", r3.pulled, 2)

    ' a write that loses the race is merged and tried again
    server = fakeServer()
    server.items["favorites"] = { value: syncWireList(["a"]), rev: 1 }
    server.conflictKey = "favorites"
    server.conflictItem = { value: syncWireList(["a", "z"]), rev: 2 }
    api = { fetch: fakeFetch, put: fakePut, store: server }
    baseState = { favorites: { rev: 1, has: true, value: ["a"] } }
    r4 = syncRun(api, { favs: ["a", "b"], resume: {} }, baseState)
    failures = failures + check("race: merged", FormatJson(r4.state.favs), "[""a"",""z"",""b""]")
    failures = failures + check("race: server has all", FormatJson(syncUnwireList(server.items["favorites"].value)), "[""a"",""z"",""b""]")

    ' an expired token
    api = { fetch: fakeSignedOut, put: fakePut, store: server }
    r5 = syncRun(api, { favs: [], resume: {} }, {})
    failures = failures + check("signed out", r5.signedOut, true)

    ' sources arrive without passwords
    server = fakeServer()
    server.items["sources"] = { value: syncWireList(["{""name"":""Home"",""type"":""xtream"",""url"":""http://h:80"",""user"":""me"",""pass"":""""}", "{""name"":""Demo"",""type"":""demo""}", "garbage"]), rev: 1 }
    api = { fetch: fakeFetch, put: fakePut, store: server }
    r6 = syncRun(api, { favs: [], resume: {} }, {})
    src = syncSources(r6.sources)
    failures = failures + check("one real source", src.count(), 1)
    failures = failures + check("source name", src[0].name, "Home")
    failures = failures + check("source kind", src[0].kind, "xtream")
    failures = failures + check("source user", src[0].user, "me")

    ' ---- small helpers
    failures = failures + check("address: bare host", syncServerUrl(" sync.example.com/ "), "https://sync.example.com")
    failures = failures + check("address: http kept", syncServerUrl("http://192.168.1.5:8787"), "http://192.168.1.5:8787")
    failures = failures + check("address: empty", syncServerUrl(""), "")
    failures = failures + check("address: ftp", syncServerUrl("ftp://x"), "")
    failures = failures + check("cap list keeps the newest", FormatJson(syncCapList(["a", "b", "c"], 2)), "[""b"",""c""]")
    failures = failures + check("cap map", syncCapMap({ a: 1, b: 2, c: 3 }, 2).count(), 2)

    if failures = 0 then
        print "ALL PASSED"
    else
        print "FAILED: " + failures.ToStr()
    end if
end sub

function fakeServer() as Object
    return { items: {}, puts: 0, conflictKey: "", conflictItem: invalid }
end function

function fakeFetch() as Object
    return { ok: true, items: m.store.items, error: "", signedOut: false }
end function

function fakeSignedOut() as Object
    return { ok: false, items: {}, error: "x", signedOut: true }
end function

function fakePut(key as String, wire as Dynamic, base as Integer) as Object
    store = m.store
    if store.conflictKey = key and store.conflictItem <> invalid then
        store.items[key] = store.conflictItem
        store.conflictKey = ""
        return { ok: false, rev: store.conflictItem.rev, conflict: true, value: store.conflictItem.value, error: "", signedOut: false }
    end if
    cur = 0
    if store.items[key] <> invalid then cur = store.items[key].rev
    if cur <> base then
        return { ok: false, rev: cur, conflict: true, value: store.items[key].value, error: "", signedOut: false }
    end if
    store.puts = store.puts + 1
    store.items[key] = { value: wire, rev: cur + 1 }
    return { ok: true, rev: cur + 1, conflict: false, value: invalid, error: "", signedOut: false }
end function

function check(label as String, actual as Dynamic, expected as Dynamic) as Integer
    if actual = expected then return 0
    print "FAIL " + label + ": got " + FormatJson(actual) + " expected " + FormatJson(expected)
    return 1
end function
