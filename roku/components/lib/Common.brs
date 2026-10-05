' Shared helpers, included by both the scene and the fetch task.

' ---- registry (32 KB limit per channel: keep what we store small) ----------

function regRead(key as String) as String
    sec = CreateObject("roRegistrySection", "StreamBoss")
    if sec.Exists(key) then return sec.Read(key)
    return ""
end function

sub regWrite(key as String, value as String)
    sec = CreateObject("roRegistrySection", "StreamBoss")
    sec.Write(key, value)
    sec.Flush()
end sub

function regReadJson(key as String, fallback as Object) as Object
    raw = regRead(key)
    if raw = "" then return fallback
    parsed = ParseJson(raw)
    if parsed = invalid then return fallback
    return parsed
end function

' ---- small utils -----------------------------------------------------------

function toStr(v as Dynamic) as String
    if v = invalid then return ""
    if type(v) = "roString" or type(v) = "String" then return v
    if type(v) = "roInt" or type(v) = "Integer" or type(v) = "roFloat" or type(v) = "Float" or type(v) = "Double" or type(v) = "roDouble" or type(v) = "LongInteger" then return v.ToStr()
    return ""
end function

function esc(s as String) as String
    return CreateObject("roUrlTransfer").Escape(s)
end function

function trimSlash(s as String) as String
    while Len(s) > 0 and Right(s, 1) = "/"
        s = Left(s, Len(s) - 1)
    end while
    return s
end function

function guessFormat(url as String) as String
    u = LCase(url)
    q = Instr(1, u, "?")
    if q > 0 then u = Left(u, q - 1)
    if Right(u, 5) = ".m3u8" then return "hls"
    if Right(u, 4) = ".mkv" then return "mkv"
    if Right(u, 4) = ".mp4" or Right(u, 4) = ".m4v" then return "mp4"
    if Right(u, 3) = ".ts" then return "ts"
    return "hls"
end function

function itemKey(item as Object) as String
    return item.kind + ":" + item.id
end function

' ---- HTTP (call from a Task thread only: it blocks) ------------------------

function httpGet(url as String, timeoutMs as Integer) as Object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.SetUrl(url)
    if not xfer.AsyncGetToString() then return { ok: false, body: "", error: "request failed" }
    msg = wait(timeoutMs, port)
    if type(msg) = "roUrlEvent" then
        code = msg.GetResponseCode()
        if code = 200 then return { ok: true, body: msg.GetString(), error: "" }
        return { ok: false, body: "", error: "HTTP " + code.ToStr() }
    end if
    xfer.AsyncCancel()
    return { ok: false, body: "", error: "timed out" }
end function

' ---- M3U -------------------------------------------------------------------

function parseM3u(body as String) as Object
    attrRe = CreateObject("roRegex", "([\w-]+)=""([^""]*)""", "")
    live = []
    movies = []
    catNames = {}
    liveCats = {}
    movieCats = {}
    attrs = {}
    name = ""
    n = 0

    for each raw in body.Split(chr(10))
        line = raw.Trim()
        if line = "" then
            ' skip
        else if Left(line, 7) = "#EXTINF" then
            attrs = {}
            for each m in attrRe.MatchAll(line)
                attrs[LCase(m[1])] = m[2]
            end for
            ' the title follows the first comma that is outside quotes
            comma = 0
            inQuote = false
            for i = 1 to Len(line)
                ch = Mid(line, i, 1)
                if ch = """" then
                    inQuote = not inQuote
                else if ch = "," and not inQuote then
                    comma = i
                    exit for
                end if
            end for
            name = ""
            if comma > 0 then name = Mid(line, comma + 1).Trim()
            if name = "" then name = "Channel " + (n + 1).ToStr()
        else if Left(line, 1) <> "#" then
            group = "Other"
            if attrs["group-title"] <> invalid and attrs["group-title"] <> "" then group = attrs["group-title"]
            isVod = Instr(1, line, "/movie/") > 0 or Instr(1, line, "/series/") > 0
            item = { id: n.ToStr(), name: name, kind: "live", url: line, poster: "", cat: group, plot: "" }
            if attrs["tvg-logo"] <> invalid then item.poster = attrs["tvg-logo"]
            n = n + 1
            if isVod then
                item.kind = "movie"
                movies.push(item)
                movieCats[group] = group
            else
                live.push(item)
                liveCats[group] = group
            end if
            attrs = {}
            name = ""
        end if
    end for

    return {
        ok: true,
        live: live, movies: movies, series: [],
        liveCats: catList(liveCats), movieCats: catList(movieCats), seriesCats: []
    }
end function

function catList(assoc as Object) as Object
    out = []
    keys = assoc.Keys()
    keys.Sort()
    for each k in keys
        out.push({ id: k, name: k })
    end for
    return out
end function

' ---- Xtream ----------------------------------------------------------------

function xtreamUrl(cfg as Object, action as String) as String
    u = trimSlash(cfg.url) + "/player_api.php?username=" + esc(cfg.user) + "&password=" + esc(cfg.pass)
    if action <> "" then u = u + "&action=" + action
    return u
end function

function xtreamGet(cfg as Object, action as String) as Object
    r = httpGet(xtreamUrl(cfg, action), 60000)
    if not r.ok then return invalid
    return ParseJson(r.body)
end function

function xtreamCats(arr as Object) as Object
    out = []
    if type(arr) = "roArray" then
        for each c in arr
            out.push({ id: toStr(c.category_id), name: toStr(c.category_name) })
        end for
    end if
    return out
end function

function loadXtream(cfg as Object) as Object
    base = trimSlash(cfg.url)
    auth = xtreamGet(cfg, "")
    if auth = invalid or type(auth) <> "roAssociativeArray" or auth.user_info = invalid then
        return { ok: false, error: "Could not reach server" }
    end if
    if toStr(auth.user_info.auth) <> "1" then return { ok: false, error: "Invalid credentials" }

    liveCats = xtreamCats(xtreamGet(cfg, "get_live_categories"))
    vodCats = xtreamCats(xtreamGet(cfg, "get_vod_categories"))
    serCats = xtreamCats(xtreamGet(cfg, "get_series_categories"))

    live = []
    streams = xtreamGet(cfg, "get_live_streams")
    if type(streams) = "roArray" then
        for each s in streams
            sid = toStr(s.stream_id)
            live.push({ id: sid, name: toStr(s.name), kind: "live", url: base + "/live/" + cfg.user + "/" + cfg.pass + "/" + sid + ".m3u8", poster: toStr(s.stream_icon), cat: toStr(s.category_id), plot: "" })
        end for
    end if

    movies = []
    vod = xtreamGet(cfg, "get_vod_streams")
    if type(vod) = "roArray" then
        for each s in vod
            sid = toStr(s.stream_id)
            ext = toStr(s.container_extension)
            if ext = "" then ext = "mp4"
            movies.push({ id: sid, name: toStr(s.name), kind: "movie", url: base + "/movie/" + cfg.user + "/" + cfg.pass + "/" + sid + "." + ext, poster: toStr(s.stream_icon), cat: toStr(s.category_id), plot: "" })
        end for
    end if

    series = []
    ser = xtreamGet(cfg, "get_series")
    if type(ser) = "roArray" then
        for each s in ser
            series.push({ id: toStr(s.series_id), name: toStr(s.name), kind: "series", url: "", poster: toStr(s.cover), cat: toStr(s.category_id), plot: toStr(s.plot) })
        end for
    end if

    return { ok: true, live: live, movies: movies, series: series, liveCats: liveCats, movieCats: vodCats, seriesCats: serCats }
end function

function loadEpisodes(cfg as Object, seriesId as String) as Object
    base = trimSlash(cfg.url)
    j = httpGet(xtreamUrl(cfg, "get_series_info") + "&series_id=" + esc(seriesId), 60000)
    if not j.ok then return { ok: false, error: j.error }
    info = ParseJson(j.body)
    out = []
    if info <> invalid and info.episodes <> invalid then
        seasons = info.episodes.Keys()
        seasons.Sort()
        for each sn in seasons
            for each e in info.episodes[sn]
                ext = toStr(e.container_extension)
                if ext = "" then ext = "mp4"
                eid = toStr(e.id)
                title = toStr(e.title)
                if title = "" then title = "Episode " + toStr(e.episode_num)
                out.push({ id: "ep" + eid, name: "S" + sn + " E" + toStr(e.episode_num) + "  " + title, kind: "movie", url: base + "/series/" + cfg.user + "/" + cfg.pass + "/" + eid + "." + ext, poster: "", cat: "", plot: "" })
            end for
        end for
    end if
    return { ok: true, episodes: out }
end function

' ---- demo ------------------------------------------------------------------

function demoLibrary() as Object
    live = [
        { id: "l1", name: "Demo Channel 1", kind: "live", url: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", poster: "", cat: "demo", plot: "" },
        { id: "l2", name: "Demo Channel 2", kind: "live", url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8", poster: "", cat: "demo", plot: "" }
    ]
    movies = [
        { id: "m1", name: "Big Buck Bunny", kind: "movie", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4", poster: "", cat: "demo", plot: "" },
        { id: "m2", name: "Sintel", kind: "movie", url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4", poster: "", cat: "demo", plot: "" }
    ]
    return { ok: true, live: live, movies: movies, series: [], liveCats: [{ id: "demo", name: "Demo Channels" }], movieCats: [{ id: "demo", name: "Open Movies" }], seriesCats: [] }
end function
