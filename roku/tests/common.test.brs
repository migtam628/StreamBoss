' Run with:  brs-cli components/lib/Common.brs tests/common.test.brs
' (brs-node interpreter; no Roku device needed)

sub Main()
    failures = 0

    body = "#EXTM3U" + chr(10)
    body = body + "#EXTINF:-1 tvg-id=""a.b"" tvg-logo=""http://x/l.png"" group-title=""News"",Channel One" + chr(10)
    body = body + "http://h/live/1.m3u8" + chr(10)
    body = body + "#EXTINF:-1 group-title=""Films"",Some, Movie" + chr(10)
    body = body + "http://h/movie/u/p/9.mkv" + chr(10)
    r = parseM3u(body)

    failures = failures + check("m3u ok", r.ok, true)
    failures = failures + check("live count", r.live.count(), 1)
    failures = failures + check("live name", r.live[0].name, "Channel One")
    failures = failures + check("live logo", r.live[0].poster, "http://x/l.png")
    failures = failures + check("movie count", r.movies.count(), 1)
    failures = failures + check("movie name keeps comma", r.movies[0].name, "Some, Movie")
    failures = failures + check("movie kind", r.movies[0].kind, "movie")
    failures = failures + check("live cats", r.liveCats[0].id, "News")
    failures = failures + check("movie cats", r.movieCats[0].id, "Films")

    failures = failures + check("fmt hls", guessFormat("http://h/a.m3u8?x=1"), "hls")
    failures = failures + check("fmt mkv", guessFormat("http://h/a.MKV"), "mkv")
    failures = failures + check("fmt mp4", guessFormat("http://h/a.mp4"), "mp4")
    failures = failures + check("fmt default", guessFormat("http://h/live/1"), "hls")
    failures = failures + check("trimSlash", trimSlash("http://h:80//"), "http://h:80")
    failures = failures + check("toStr int", toStr(42), "42")
    failures = failures + check("toStr str", toStr("x"), "x")
    failures = failures + check("toStr invalid", toStr(invalid), "")
    failures = failures + check("itemKey", itemKey({ kind: "movie", id: "7" }), "movie:7")

    if failures = 0 then
        print "ALL PASSED"
    else
        print "FAILED: " + failures.ToStr()
    end if
end sub

function check(label as String, actual as Dynamic, expected as Dynamic) as Integer
    if actual = expected then return 0
    print "FAIL " + label + ": got " + FormatJson(actual) + " expected " + FormatJson(expected)
    return 1
end function
