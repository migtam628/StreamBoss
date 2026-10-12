' StreamBoss for Roku: Xtream / M3U player with tabs, categories, search,
' My List, resume and channel zapping. Registry data stays small (32 KB cap).

sub init()
    m.tabs = m.top.findNode("tabs")
    m.cats = m.top.findNode("cats")
    m.items = m.top.findNode("items")
    m.setup = m.top.findNode("setup")
    m.setupTitle = m.top.findNode("setupTitle")
    m.status = m.top.findNode("status")
    m.video = m.top.findNode("video")
    m.osd = m.top.findNode("osd")
    m.fetch = m.top.findNode("fetch")
    m.syncTask = m.top.findNode("syncTask")

    m.lib = { live: [], movies: [], series: [], liveCats: [], movieCats: [], seriesCats: [] }
    m.tabIdx = 0
    m.curCats = []
    m.curItems = []
    m.savedItems = invalid ' list to restore after leaving an episode view
    m.playIndex = -1
    m.connected = false
    m.playItem = invalid
    m.lastSaved = 0
    initFavs()
    m.resume = regReadJson("pos", {})
    m.syncCfg = regReadJson("sync", { server: "", email: "", token: "" })
    m.syncBase = regReadJson("syncbase", {})
    m.syncSources = []
    m.syncing = false
    m.localRev = 0
    m.syncSentRev = 0
    m.cfg = regReadJson("cfg", { kind: "", url: "", user: "", pass: "" })

    buildTabs()
    applyStaticText()
    m.tabs.observeField("itemFocused", "onTabFocus")
    m.tabs.observeField("itemSelected", "onTabSelect")
    m.cats.observeField("itemFocused", "onCatFocus")
    m.cats.observeField("itemSelected", "onCatSelect")
    m.items.observeField("itemSelected", "onItemSelect")
    m.setup.observeField("itemSelected", "onSetupSelect")
    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onVideoPosition")
    m.fetch.observeField("result", "onFetchResult")
    m.syncTask.observeField("result", "onSyncResult")
    m.top.findNode("syncTimer").observeField("fire", "onSyncTimer")
    m.top.findNode("osdTimer").observeField("fire", "onOsdTimer")

    if m.cfg.kind = "" then
        showSetup()
    else
        connect()
    end if
    syncNow()
end sub

' ---- generic helpers -------------------------------------------------------

function makeList(titles as Object) as Object
    root = CreateObject("roSGNode", "ContentNode")
    for each t in titles
        c = root.createChild("ContentNode")
        c.title = t
    end for
    return root
end function

sub setStatus(text as String)
    m.status.text = text
end sub

sub buildTabs()
    m.tabs.content = makeList([L("Live"), L("Movies"), L("Series"), L("My List"), L("Search"), L("Settings")])
end sub

sub applyStaticText()
    m.setupTitle.text = L("Connect your provider")
    m.top.findNode("hint").text = L("OK select   *  add to My List   Left/Right switch columns")
end sub

function languageName() as String
    pref = langPref()
    if pref = "en" then return "English"
    if pref = "es" then return "Español"
    if pref = "it" then return "Italiano"
    if pref = "pt" then return "Português"
    return L("Device language")
end function

' Settings > Language: Device language, English, Spanish, Italian, Portuguese, round again. Shown at once.
sub cycleLanguage()
    order = ["", "en", "es", "it", "pt"]
    cur = langPref()
    nextIdx = 0
    for i = 0 to order.count() - 1
        if order[i] = cur then nextIdx = (i + 1) mod order.count()
    end for
    setLang(order[nextIdx])
    saved = m.tabIdx
    m.keepCursor = 4
    buildTabs()
    applyStaticText()
    m.tabs.jumpToItem = saved
    showTab(saved)
    if m.connected then setStatus(librarySummary()) else setStatus("")
    m.items.setFocus(true)
end sub

' ---- setup screen ----------------------------------------------------------

sub showSetup()
    m.tabs.visible = false
    m.cats.visible = false
    m.items.visible = false
    m.top.findNode("hint").visible = false
    m.setup.visible = true
    m.setupTitle.visible = true
    refreshSetup()
    m.setup.setFocus(true)
end sub

sub hideSetup()
    m.setup.visible = false
    m.setupTitle.visible = false
    m.tabs.visible = true
    m.cats.visible = true
    m.items.visible = true
    m.top.findNode("hint").visible = true
end sub

sub refreshSetup()
    typeName = L("Xtream")
    if m.cfg.kind = "m3u" then typeName = L("M3U playlist")
    rows = [LF("Source type: {name}", { name: typeName })]
    ids = ["type"]
    if m.cfg.kind = "m3u" then
        rows.push(LF("Playlist URL: {url}", { url: m.cfg.url }))
        ids.push("url")
    else
        rows.push(LF("Server URL: {url}", { url: m.cfg.url }))
        ids.push("url")
        rows.push(LF("Username: {name}", { name: m.cfg.user }))
        ids.push("user")
        stars = ""
        for i = 1 to Len(m.cfg.pass)
            stars = stars + "*"
        end for
        rows.push(LF("Password: {pass}", { pass: stars }))
        ids.push("pass")
    end if
    rows.push(L("Connect"))
    ids.push("connect")
    rows.push(L("Try demo mode"))
    ids.push("demo")
    if m.syncCfg.token = "" then
        rows.push(L("Use my sync account"))
        ids.push("syncin")
    else
        for i = 0 to m.syncSources.count() - 1
            if i < 5 then
                rows.push(LF("From sync: {name}", { name: m.syncSources[i].name }))
                ids.push("src" + i.ToStr())
            end if
        end for
    end if
    m.setupIds = ids
    m.setup.content = makeList(rows)
end sub

sub onSetupSelect()
    id = m.setupIds[m.setup.itemSelected]
    if id = "type" then
        if m.cfg.kind = "m3u" then m.cfg.kind = "xtream" else m.cfg.kind = "m3u"
        refreshSetup()
    else if id = "url" then
        askText(L("URL"), "url", false)
    else if id = "user" then
        askText(L("Username"), "user", false)
    else if id = "pass" then
        askText(L("Password"), "pass", true)
    else if id = "connect" then
        if m.cfg.kind = "" then m.cfg.kind = "xtream"
        regWrite("cfg", FormatJson(m.cfg))
        connect()
    else if id = "demo" then
        m.cfg = { kind: "demo", url: "", user: "", pass: "" }
        connect()
    else if id = "syncin" then
        startSyncSignIn(false)
    else if Left(id, 3) = "src" then
        ' a source saved on another device: its address and login name arrive, the password is typed here
        src = m.syncSources[Int(Val(Mid(id, 4)))]
        m.cfg = { kind: src.kind, url: src.url, user: src.user, pass: "" }
        refreshSetup()
    end if
end sub

sub askText(title as String, field as String, secret as Boolean)
    m.kbField = field
    m.kbMode = "setup"
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = title
    if field <> "" and m.cfg[field] <> invalid then dlg.text = m.cfg[field]
    dlg.textEditBox.secureMode = secret
    dlg.buttons = [L("OK"), L("Cancel")]
    dlg.observeFieldScoped("buttonSelected", "onKeyboardButton")
    m.kbDialog = dlg
    m.top.dialog = dlg
end sub

sub onKeyboardButton()
    dlg = m.kbDialog
    pressed = dlg.buttonSelected
    text = dlg.text
    m.top.dialog = invalid
    if pressed <> 0 then
        if m.kbMode = "setup" or (m.kbMode = "sync" and m.setup.visible) then m.setup.setFocus(true) else m.items.setFocus(true)
        return
    end if
    if m.kbMode = "sync" then
        nextSyncStep(text)
    else if m.kbMode = "setup" then
        m.cfg[m.kbField] = text.Trim()
        refreshSetup()
        m.setup.setFocus(true)
    else if m.kbMode = "search" then
        runSearch(text.Trim())
    end if
end sub

' ---- connecting ------------------------------------------------------------

sub connect()
    hideSetup()
    setStatus(L("Loading your library..."))
    if m.cfg.kind = "demo" then
        applyLibrary(demoLibrary())
        return
    end if
    m.fetch.request = { kind: m.cfg.kind, cfg: m.cfg }
    m.fetch.control = "RUN"
end sub

sub onFetchResult()
    res = m.fetch.result
    if res = invalid then return

    if res.kind = "episodes" then
        if res.ok then showEpisodes(res.episodes) else setStatus(LF("Episodes failed: {error}", { error: res.error }))
        return
    end if

    if res.ok then
        applyLibrary(res)
    else
        setStatus(LF("Could not connect: {error}", { error: res.error }))
        showSetup()
    end if
end sub

sub applyLibrary(res as Object)
    m.lib = res
    m.connected = true
    resolveFavs()
    setStatus(librarySummary())
    m.tabs.jumpToItem = 0
    showTab(0)
    m.tabs.setFocus(true)
end sub

' ---- tabs / categories / items --------------------------------------------

function librarySummary() as String
    srcName = L("Demo")
    if m.cfg.kind <> "demo" then srcName = m.cfg.url
    return LF("{src}   {live} channels, {movies} movies, {series} series", { src: srcName, live: m.lib.live.count(), movies: m.lib.movies.count(), series: m.lib.series.count() })
end function

sub onTabFocus()
    showTab(m.tabs.itemFocused)
end sub

sub onTabSelect()
    idx = m.tabs.itemSelected
    if idx = 4 then
        askSearch()
    else if m.cats.visible and m.curCats.count() > 0 then
        m.cats.setFocus(true)
    else
        m.items.setFocus(true)
    end if
end sub

sub showTab(idx as Integer)
    m.tabIdx = idx
    m.savedItems = invalid
    if idx = 0 then
        setCats(m.lib.liveCats)
    else if idx = 1 then
        setCats(m.lib.movieCats)
    else if idx = 2 then
        setCats(m.lib.seriesCats)
    else if idx = 3 then
        setCats([])
        setItems(favList())
    else if idx = 4 then
        setCats([])
        setItems([])
        setStatus(L("Press OK to search"))
    else
        setCats([])
        showSettingsItems()
    end if
end sub

sub setCats(cats as Object)
    m.curCats = [{ id: "", name: L("All") }]
    for each c in cats
        m.curCats.push(c)
    end for
    if m.tabIdx >= 3 then m.curCats = []
    titles = []
    for each c in m.curCats
        titles.push(c.name)
    end for
    m.cats.content = makeList(titles)
    m.cats.jumpToItem = 0
    if m.tabIdx < 3 then showCategory(0)
end sub

sub onCatFocus()
    showCategory(m.cats.itemFocused)
end sub

sub onCatSelect()
    m.items.setFocus(true)
end sub

sub showCategory(idx as Integer)
    if m.curCats.count() = 0 then return
    if idx < 0 or idx >= m.curCats.count() then return
    source = m.lib.live
    if m.tabIdx = 1 then source = m.lib.movies
    if m.tabIdx = 2 then source = m.lib.series
    catId = m.curCats[idx].id
    if catId = "" then
        setItems(source)
    else
        filtered = []
        for each it in source
            if it.cat = catId then filtered.push(it)
        end for
        setItems(filtered)
    end if
end sub

sub setItems(arr as Object)
    m.curItems = arr
    titles = []
    cap = arr.count()
    if cap > 3000 then cap = 3000
    for i = 0 to cap - 1
        t = arr[i].name
        if isFav(arr[i]) then t = "* " + t
        titles.push(t)
    end for
    m.items.content = makeList(titles)
end sub

sub showSettingsItems()
    m.curItems = []
    m.settingIds = ["reload", "source", "clearlist", "clearresume", "language"]
    rows = [L("Reload library"), L("Change source"), L("Clear My List"), L("Clear resume history"), LF("Language: {name}", { name: languageName() })]
    if m.syncCfg.token = "" then
        m.settingIds.push("syncin")
        rows.push(L("Sign in to sync"))
        m.settingIds.push("synccreate")
        rows.push(L("Create a sync account"))
    else
        m.settingIds.push("syncnow")
        rows.push(L("Sync now"))
        m.settingIds.push("syncout")
        rows.push(L("Sign out of sync"))
    end if
    m.settingIds.push("about")
    rows.push(L("About StreamBoss"))
    m.items.content = makeList(rows)
    if m.keepCursor <> invalid then
        m.items.jumpToItem = m.keepCursor
        m.keepCursor = invalid
    end if
    m.settingsMode = true
end sub

sub onItemSelect()
    idx = m.items.itemSelected
    if m.tabIdx = 5 then
        runSetting(idx)
        return
    end if
    if idx < 0 or idx >= m.curItems.count() then return
    item = m.curItems[idx]
    if item.kind = "series" then
        openSeries(item)
    else
        play(m.curItems, idx)
    end if
end sub

sub runSetting(idx as Integer)
    id = m.settingIds[idx]
    if id = "reload" then
        connect()
    else if id = "source" then
        showSetup()
    else if id = "clearlist" then
        m.favKeys = []
        m.favItems = {}
        rebuildFavSet()
        saveFavs()
        bumpLocal()
        setStatus(L("My List cleared"))
    else if id = "clearresume" then
        m.resume = {}
        regWrite("pos", "{}")
        bumpLocal()
        setStatus(L("Resume history cleared"))
    else if id = "language" then
        cycleLanguage()
    else if id = "syncin" then
        startSyncSignIn(false)
    else if id = "synccreate" then
        startSyncSignIn(true)
    else if id = "syncnow" then
        setStatus(L("Syncing..."))
        syncNow()
    else if id = "syncout" then
        signOutSync()
    else
        setStatus(L("StreamBoss: a player only. Bring your own licensed provider."))
    end if
end sub

' ---- search ----------------------------------------------------------------

sub askSearch()
    m.kbField = ""
    m.kbMode = "search"
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = L("Search")
    dlg.buttons = [L("Search"), L("Cancel")]
    dlg.observeFieldScoped("buttonSelected", "onKeyboardButton")
    m.kbDialog = dlg
    m.top.dialog = dlg
end sub

sub runSearch(q as String)
    if q = "" then return
    needle = LCase(q)
    found = []
    for each group in [m.lib.live, m.lib.movies, m.lib.series]
        for each it in group
            if Instr(1, LCase(it.name), needle) > 0 then
                found.push(it)
                if found.count() >= 300 then exit for
            end if
        end for
    end for
    setItems(found)
    setStatus(LF("{n} results for ""{q}""", { n: found.count(), q: q }))
    m.items.setFocus(true)
end sub

' ---- series ----------------------------------------------------------------

sub openSeries(item as Object)
    if m.cfg.kind <> "xtream" then
        setStatus(L("Series are only available on Xtream sources"))
        return
    end if
    m.savedItems = m.curItems
    m.seriesTitle = item.name
    setStatus(L("Loading episodes..."))
    m.fetch.request = { kind: "episodes", cfg: m.cfg, seriesId: item.id }
    m.fetch.control = "RUN"
end sub

sub showEpisodes(eps as Object)
    setItems(eps)
    setStatus(LF("{title}: {n} episodes   (Back returns)", { title: m.seriesTitle, n: eps.count() }))
    m.items.setFocus(true)
end sub

' ---- favourites / resume ---------------------------------------------------

function isFav(item as Object) as Boolean
    return m.favSet.DoesExist(itemKey(item))
end function

' My List is kept as item keys (movie:123, the same keys the other apps use, so it can be synced). The items to show come
' from the cache below (the last 25, so My List works before the library has loaded) and from the library itself.
sub initFavs()
    m.favItems = {}
    cache = regReadJson("fav", [])
    m.favKeys = regReadJson("favk", invalid)
    if m.favKeys = invalid then
        m.favKeys = []
        for each f in cache
            m.favKeys.push(itemKey(f))
        end for
    end if
    for each f in cache
        m.favItems[itemKey(f)] = f
    end for
    rebuildFavSet()
end sub

sub rebuildFavSet()
    m.favSet = syncSetOf(m.favKeys)
end sub

sub saveFavs()
    regWrite("favk", FormatJson(m.favKeys))
    cache = []
    i = m.favKeys.count() - 1
    while i >= 0 and cache.count() < 25
        it = m.favItems[m.favKeys[i]]
        if it <> invalid then cache.unshift(it)
        i = i - 1
    end while
    regWrite("fav", FormatJson(cache))
end sub

function favList() as Object
    out = []
    for each k in m.favKeys
        it = m.favItems[k]
        if it <> invalid then out.push(it)
    end for
    return out
end function

' Finds, in the library, the items of My List that came from another device.
sub resolveFavs()
    wanted = {}
    for each k in m.favKeys
        if not m.favItems.DoesExist(k) then wanted[k] = true
    end for
    if wanted.count() = 0 then return
    for each arr in [m.lib.live, m.lib.movies, m.lib.series]
        for each it in arr
            k = itemKey(it)
            if wanted.DoesExist(k) then m.favItems[k] = it
        end for
    end for
    saveFavs()
end sub

sub toggleFavorite(item as Object)
    k = itemKey(item)
    removed = m.favSet.DoesExist(k)
    kept = []
    for each f in m.favKeys
        if f <> k then kept.push(f)
    end for
    if removed then
        m.favItems.Delete(k)
    else
        ' store only what's needed to replay it; keep the registry small
        kept.push(k)
        m.favItems[k] = { id: item.id, name: item.name, kind: item.kind, url: item.url, poster: "", cat: item.cat, plot: "" }
        if kept.count() > 200 then kept.shift()
    end if
    m.favKeys = kept
    rebuildFavSet()
    saveFavs()
    bumpLocal()
    if removed then setStatus(L("Removed from My List")) else setStatus(L("Added to My List"))
    if m.tabIdx = 3 then setItems(favList())
end sub

sub savePosition(item as Object, secs as Integer, total as Integer)
    if item.kind = "live" or total < 120 then return
    k = itemKey(item)
    if secs > total * 0.97 then
        m.resume.Delete(k)
    else if secs > 10 then
        m.resume[k] = secs
    end if
    if m.resume.Count() > 150 then
        keys = m.resume.Keys()
        m.resume.Delete(keys[0])
    end if
    regWrite("pos", FormatJson(m.resume))
    bumpLocal()
end sub

' ---- playback --------------------------------------------------------------

sub play(list as Object, idx as Integer)
    m.queue = list
    startItem(idx)
    m.video.visible = true
    m.video.setFocus(true)
end sub

sub startItem(idx as Integer)
    item = m.queue[idx]
    m.playIndex = idx
    m.playItem = item
    content = CreateObject("roSGNode", "ContentNode")
    content.url = item.url
    content.title = item.name
    content.streamFormat = guessFormat(item.url)
    content.live = (item.kind = "live")
    k = itemKey(item)
    if item.kind <> "live" and m.resume[k] <> invalid then content.PlayStart = m.resume[k]
    m.lastSaved = 0
    m.video.content = content
    m.video.control = "play"
    m.osd.text = item.name
    m.osd.visible = true
    m.top.findNode("osdTimer").control = "start"
end sub

sub onOsdTimer()
    m.osd.visible = false
end sub

sub onVideoPosition()
    if m.playItem = invalid or m.playItem.kind = "live" then return
    secs = Int(m.video.position)
    if Abs(secs - m.lastSaved) >= 10 then
        m.lastSaved = secs
        savePosition(m.playItem, secs, Int(m.video.duration))
    end if
end sub

sub onVideoState()
    state = m.video.state
    if state = "finished" and m.playItem <> invalid and m.playItem.kind <> "live" then
        m.resume.Delete(itemKey(m.playItem))
        regWrite("pos", FormatJson(m.resume))
        bumpLocal()
        closeVideo()
    else if state = "error" then
        setStatus(LF("Playback error: {error}", { error: m.video.errorMsg }))
        closeVideo()
    end if
end sub

sub closeVideo()
    if m.playItem <> invalid and m.playItem.kind <> "live" then
        savePosition(m.playItem, Int(m.video.position), Int(m.video.duration))
    end if
    m.video.control = "stop"
    m.video.visible = false
    m.osd.visible = false
    m.playItem = invalid
    m.items.setFocus(true)
    bumpLocal()
end sub

' ---- sync ------------------------------------------------------------------
' My List and resume positions are kept in step with the other StreamBoss apps through the sync server (components/lib/Sync.brs).
' The registry holds 32 KB for the whole channel, so at most 200 My List entries and 150 resume positions are kept here.

sub bumpLocal()
    m.localRev = m.localRev + 1
    if m.syncCfg.token <> "" then m.top.findNode("syncTimer").control = "start"
end sub

sub onSyncTimer()
    syncNow()
end sub

function resumeMs() as Object
    out = {}
    for each k in m.resume
        out[k] = m.resume[k] * 1000
    end for
    return out
end function

sub syncNow()
    if m.syncCfg.token = "" or m.syncing then return
    m.syncing = true
    m.syncSentRev = m.localRev
    m.syncTask.request = { kind: "sync", cfg: { server: m.syncCfg.server, token: m.syncCfg.token }, local: { favs: m.favKeys, resume: resumeMs() }, base: m.syncBase }
    m.syncTask.control = "RUN"
end sub

sub startSyncSignIn(create as Boolean)
    m.syncCreate = create
    m.syncDraft = { server: m.syncCfg.server, email: m.syncCfg.email, password: "" }
    askSyncText("server")
end sub

sub askSyncText(field as String)
    m.kbField = field
    m.kbMode = "sync"
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    if field = "server" then
        dlg.title = L("Sync server address")
    else if field = "email" then
        dlg.title = L("E-mail")
    else
        dlg.title = L("Password")
    end if
    if field <> "password" then dlg.text = m.syncDraft[field]
    dlg.textEditBox.secureMode = (field = "password")
    dlg.buttons = [L("OK"), L("Cancel")]
    dlg.observeFieldScoped("buttonSelected", "onKeyboardButton")
    m.kbDialog = dlg
    m.top.dialog = dlg
end sub

sub nextSyncStep(text as String)
    m.syncDraft[m.kbField] = text
    if m.kbField = "server" then
        askSyncText("email")
    else if m.kbField = "email" then
        askSyncText("password")
    else
        setStatus(L("Signing in..."))
        m.syncTask.request = { kind: "syncsignin", cfg: { server: m.syncDraft.server, email: m.syncDraft.email, password: m.syncDraft.password, create: m.syncCreate } }
        m.syncTask.control = "RUN"
        m.syncDraft.password = ""
    end if
end sub

sub signOutSync()
    if m.syncCfg.token <> "" and not m.syncing then
        m.syncTask.request = { kind: "synclogout", cfg: { server: m.syncCfg.server, token: m.syncCfg.token } }
        m.syncTask.control = "RUN"
    end if
    m.syncCfg = { server: m.syncCfg.server, email: m.syncCfg.email, token: "" }
    regWrite("sync", FormatJson(m.syncCfg))
    m.syncBase = {}
    regWrite("syncbase", "{}")
    m.syncSources = []
    m.syncing = false
    if m.setup.visible then refreshSetup()
    if m.tabIdx = 5 then showSettingsItems()
end sub

sub onSyncResult()
    res = m.syncTask.result
    if res = invalid then return
    if res.kind = "synclogout" then return

    if res.kind = "syncsignin" then
        if res.ok then
            m.syncCfg = { server: res.server, email: res.email, token: res.token }
            regWrite("sync", FormatJson(m.syncCfg))
            m.syncBase = {}
            regWrite("syncbase", "{}")
            setStatus(LF("Signed in as {email}", { email: res.email }))
            if m.tabIdx = 5 then showSettingsItems()
            syncNow()
        else
            setStatus(LF("Sign-in failed: {error}", { error: res.error }))
        end if
        if m.setup.visible then
            refreshSetup()
            m.setup.setFocus(true)
        end if
        return
    end if

    m.syncing = false
    if not res.ok then
        if res.signedOut = true then
            signOutSync()
            setStatus(L("You were signed out. Sign in again."))
        else
            setStatus(LF("Sync failed: {error}", { error: res.error }))
        end if
        return
    end if
    if m.localRev <> m.syncSentRev then
        ' something changed here while the server was being asked: drop this answer and ask again, so nothing is overwritten
        syncNow()
        return
    end if

    if res.pulled > 0 then
        m.favKeys = syncCapList(res.state.favs, 200)
        rebuildFavSet()
        resume = {}
        capped = syncCapMap(res.state.resume, 150)
        for each k in capped
            resume[k] = Int(capped[k] / 1000)
        end for
        m.resume = resume
        regWrite("pos", FormatJson(m.resume))
        saveFavs()
        if m.connected then resolveFavs()
        if m.tabIdx = 3 and m.connected then setItems(favList())
    end if
    base = res.base
    if base["favorites"] <> invalid and base["favorites"].value <> invalid then base["favorites"].value = syncCapList(base["favorites"].value, 200)
    if base["positions"] <> invalid and base["positions"].value <> invalid then base["positions"].value = syncCapMap(base["positions"].value, 150)
    m.syncBase = base
    regWrite("syncbase", FormatJson(base))
    m.syncSources = syncSources(res.sources)
    if m.setup.visible then refreshSetup()
    setStatus(L("Synced"))
end sub

' ---- remote keys -----------------------------------------------------------

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    if m.video.visible then
        if key = "back" then
            closeVideo()
            return true
        end if
        ' channel zapping while watching live TV
        if m.playItem <> invalid and m.playItem.kind = "live" and m.queue.count() > 1 then
            if key = "up" then
                startItem((m.playIndex + 1) mod m.queue.count())
                return true
            else if key = "down" then
                startItem((m.playIndex - 1 + m.queue.count()) mod m.queue.count())
                return true
            end if
        end if
        return false
    end if

    if m.setup.visible then
        if key = "back" and m.connected then
            hideSetup()
            m.tabs.setFocus(true)
            return true
        end if
        return false
    end if

    if key = "options" and m.items.hasFocus() and m.tabIdx <> 5 then
        idx = m.items.itemFocused
        if idx >= 0 and idx < m.curItems.count() then toggleFavorite(m.curItems[idx])
        return true
    end if

    if key = "back" then
        if m.savedItems <> invalid and m.items.hasFocus() then
            setItems(m.savedItems)
            m.savedItems = invalid
            return true
        else if m.items.hasFocus() and m.tabIdx < 3 then
            m.cats.setFocus(true)
            return true
        else if m.items.hasFocus() or m.cats.hasFocus() then
            m.tabs.setFocus(true)
            return true
        end if
        return false
    end if

    if key = "right" then
        if m.tabs.hasFocus() and m.tabIdx < 3 then
            m.cats.setFocus(true)
            return true
        else if m.tabs.hasFocus() or m.cats.hasFocus() then
            m.items.setFocus(true)
            return true
        end if
    else if key = "left" then
        if m.items.hasFocus() and m.tabIdx < 3 then
            m.cats.setFocus(true)
            return true
        else if m.items.hasFocus() or m.cats.hasFocus() then
            m.tabs.setFocus(true)
            return true
        end if
    end if

    return false
end function
