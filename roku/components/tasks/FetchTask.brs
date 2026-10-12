sub init()
    m.top.functionName = "execute"
end sub

sub execute()
    req = m.top.request
    res = { ok: false, error: L("Bad request") }

    if req.kind = "xtream" then
        res = loadXtream(req.cfg)
    else if req.kind = "m3u" then
        r = httpGet(req.cfg.url, 90000)
        if r.ok then
            res = parseM3u(r.body)
        else
            res = { ok: false, error: r.error }
        end if
    else if req.kind = "episodes" then
        res = loadEpisodes(req.cfg, req.seriesId)
    else if req.kind = "syncsignin" then
        res = syncSignIn(req.cfg)
    else if req.kind = "sync" then
        res = syncRun(syncApi(req.cfg.server, req.cfg.token), req.local, req.base)
    else if req.kind = "synclogout" then
        syncCall(req.cfg.server, req.cfg.token, "POST", "/api/logout", "{}")
        res = { ok: true }
    end if

    res.kind = req.kind
    m.top.result = res
end sub
