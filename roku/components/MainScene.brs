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

    m.lib = { live: [], movies: [], series: [], liveCats: [], movieCats: [], seriesCats: [] }
    m.tabNames = ["Live", "Movies", "Series", "My List", "Search", "Settings"]
    m.tab = 0
    m.curCats = []
    m.curItems = []
    m.savedItems = invalid ' list to restore after leaving an episode view
    m.playIndex = -1
    m.connected = false
    m.playItem = invalid
    m.lastSaved = 0
    m.favs = regReadJson("fav", [])
    m.pos = regReadJson("pos", {})
    m.cfg = regReadJson("cfg", { type: "", url: "", user: "", pass: "" })

    buildTabs()
    m.tabs.observeField("itemFocused", "onTabFocus")
    m.tabs.observeField("itemSelected", "onTabSelect")
    m.cats.observeField("itemFocused", "onCatFocus")
    m.cats.observeField("itemSelected", "onCatSelect")
    m.items.observeField("itemSelected", "onItemSelect")
    m.setup.observeField("itemSelected", "onSetupSelect")
    m.video.observeField("state", "onVideoState")
    m.video.observeField("position", "onVideoPosition")
    m.fetch.observeField("result", "onFetchResult")
    m.top.findNode("osdTimer").observeField("fire", "onOsdTimer")

    if m.cfg.type = "" then
        showSetup()
    else
        connect()
    end if
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
    m.tabs.content = makeList(m.tabNames)
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
    typeName = "Xtream"
    if m.cfg.type = "m3u" then typeName = "M3U playlist"
    rows = ["Source type: " + typeName]
    if m.cfg.type = "m3u" then
        rows.push("Playlist URL: " + m.cfg.url)
    else
        rows.push("Server URL: " + m.cfg.url)
        rows.push("Username: " + m.cfg.user)
        stars = ""
        for i = 1 to Len(m.cfg.pass)
            stars = stars + "*"
        end for
        rows.push("Password: " + stars)
    end if
    rows.push("Connect")
    rows.push("Try demo mode")
    m.setupRows = rows
    m.setup.content = makeList(rows)
end sub

sub onSetupSelect()
    row = m.setupRows[m.setup.itemSelected]
    if Left(row, 11) = "Source type" then
        if m.cfg.type = "m3u" then m.cfg.type = "xtream" else m.cfg.type = "m3u"
        refreshSetup()
    else if Left(row, 12) = "Playlist URL" or Left(row, 10) = "Server URL" then
        askText("URL", "url", false)
    else if Left(row, 8) = "Username" then
        askText("Username", "user", false)
    else if Left(row, 8) = "Password" then
        askText("Password", "pass", true)
    else if row = "Connect" then
        if m.cfg.type = "" then m.cfg.type = "xtream"
        regWrite("cfg", FormatJson(m.cfg))
        connect()
    else if row = "Try demo mode" then
        m.cfg = { type: "demo", url: "", user: "", pass: "" }
        connect()
    end if
end sub

sub askText(title as String, field as String, secret as Boolean)
    m.kbField = field
    m.kbMode = "setup"
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = title
    if field <> "" and m.cfg[field] <> invalid then dlg.text = m.cfg[field]
    dlg.textEditBox.secureMode = secret
    dlg.buttons = ["OK", "Cancel"]
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
        if m.kbMode = "setup" then m.setup.setFocus(true) else m.items.setFocus(true)
        return
    end if
    if m.kbMode = "setup" then
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
    setStatus("Loading your library...")
    if m.cfg.type = "demo" then
        applyLibrary(demoLibrary())
        return
    end if
    m.fetch.request = { type: m.cfg.type, cfg: m.cfg }
    m.fetch.control = "RUN"
end sub

sub onFetchResult()
    res = m.fetch.result
    if res = invalid then return

    if res.type = "episodes" then
        if res.ok then showEpisodes(res.episodes) else setStatus("Episodes failed: " + res.error)
        return
    end if

    if res.ok then
        applyLibrary(res)
    else
        setStatus("Could not connect: " + res.error)
        showSetup()
    end if
end sub

sub applyLibrary(res as Object)
    m.lib = res
    m.connected = true
    srcName = "Demo"
    if m.cfg.type <> "demo" then srcName = m.cfg.url
    setStatus(srcName + "   " + m.lib.live.count().ToStr() + " channels, " + m.lib.movies.count().ToStr() + " movies, " + m.lib.series.count().ToStr() + " series")
    m.tabs.jumpToItem = 0
    showTab(0)
    m.tabs.setFocus(true)
end sub

' ---- tabs / categories / items --------------------------------------------

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
    m.tab = idx
    m.savedItems = invalid
    if idx = 0 then
        setCats(m.lib.liveCats)
    else if idx = 1 then
        setCats(m.lib.movieCats)
    else if idx = 2 then
        setCats(m.lib.seriesCats)
    else if idx = 3 then
        setCats([])
        setItems(m.favs)
    else if idx = 4 then
        setCats([])
        setItems([])
        setStatus("Press OK to search")
    else
        setCats([])
        showSettingsItems()
    end if
end sub

sub setCats(cats as Object)
    m.curCats = [{ id: "", name: "All" }]
    for each c in cats
        m.curCats.push(c)
    end for
    if m.tab >= 3 then m.curCats = []
    titles = []
    for each c in m.curCats
        titles.push(c.name)
    end for
    m.cats.content = makeList(titles)
    m.cats.jumpToItem = 0
    if m.tab < 3 then showCategory(0)
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
    if m.tab = 1 then source = m.lib.movies
    if m.tab = 2 then source = m.lib.series
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
    m.items.content = makeList(["Reload library", "Change source", "Clear My List", "Clear resume history", "About StreamBoss"])
    m.settingsMode = true
end sub

sub onItemSelect()
    idx = m.items.itemSelected
    if m.tab = 5 then
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
    if idx = 0 then
        connect()
    else if idx = 1 then
        showSetup()
    else if idx = 2 then
        m.favs = []
        regWrite("fav", "[]")
        setStatus("My List cleared")
    else if idx = 3 then
        m.pos = {}
        regWrite("pos", "{}")
        setStatus("Resume history cleared")
    else
        setStatus("StreamBoss: a player only. Bring your own licensed provider.")
    end if
end sub

' ---- search ----------------------------------------------------------------

sub askSearch()
    m.kbField = ""
    m.kbMode = "search"
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = "Search"
    dlg.buttons = ["Search", "Cancel"]
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
    setStatus(found.count().ToStr() + " results for """ + q + """")
    m.items.setFocus(true)
end sub

' ---- series ----------------------------------------------------------------

sub openSeries(item as Object)
    if m.cfg.type <> "xtream" then
        setStatus("Series are only available on Xtream sources")
        return
    end if
    m.savedItems = m.curItems
    m.seriesTitle = item.name
    setStatus("Loading episodes...")
    m.fetch.request = { type: "episodes", cfg: m.cfg, seriesId: item.id }
    m.fetch.control = "RUN"
end sub

sub showEpisodes(eps as Object)
    setItems(eps)
    setStatus(m.seriesTitle + ": " + eps.count().ToStr() + " episodes   (Back returns)")
    m.items.setFocus(true)
end sub

' ---- favourites / resume ---------------------------------------------------

function isFav(item as Object) as Boolean
    k = itemKey(item)
    for each f in m.favs
        if itemKey(f) = k then return true
    end for
    return false
end function

sub toggleFavorite(item as Object)
    k = itemKey(item)
    kept = []
    removed = false
    for each f in m.favs
        if itemKey(f) = k then
            removed = true
        else
            kept.push(f)
        end if
    end for
    if not removed then
        ' store only what's needed to replay it; keep the registry small
        kept.push({ id: item.id, name: item.name, kind: item.kind, url: item.url, poster: "", cat: item.cat, plot: "" })
        if kept.count() > 40 then kept.shift()
    end if
    m.favs = kept
    regWrite("fav", FormatJson(kept))
    if removed then setStatus("Removed from My List") else setStatus("Added to My List")
    if m.tab = 3 then setItems(m.favs)
end sub

sub savePosition(item as Object, secs as Integer, total as Integer)
    if item.kind = "live" or total < 120 then return
    k = itemKey(item)
    if secs > total * 0.97 then
        m.pos.Delete(k)
    else if secs > 10 then
        m.pos[k] = secs
    end if
    if m.pos.Count() > 80 then
        keys = m.pos.Keys()
        m.pos.Delete(keys[0])
    end if
    regWrite("pos", FormatJson(m.pos))
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
    if item.kind <> "live" and m.pos[k] <> invalid then content.PlayStart = m.pos[k]
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
        m.pos.Delete(itemKey(m.playItem))
        regWrite("pos", FormatJson(m.pos))
        closeVideo()
    else if state = "error" then
        setStatus("Playback error: " + m.video.errorMsg)
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

    if key = "options" and m.items.hasFocus() and m.tab <> 5 then
        idx = m.items.itemFocused
        if idx >= 0 and idx < m.curItems.count() then toggleFavorite(m.curItems[idx])
        return true
    end if

    if key = "back" then
        if m.savedItems <> invalid and m.items.hasFocus() then
            setItems(m.savedItems)
            m.savedItems = invalid
            return true
        else if m.items.hasFocus() and m.tab < 3 then
            m.cats.setFocus(true)
            return true
        else if m.items.hasFocus() or m.cats.hasFocus() then
            m.tabs.setFocus(true)
            return true
        end if
        return false
    end if

    if key = "right" then
        if m.tabs.hasFocus() and m.tab < 3 then
            m.cats.setFocus(true)
            return true
        else if m.tabs.hasFocus() or m.cats.hasFocus() then
            m.items.setFocus(true)
            return true
        end if
    else if key = "left" then
        if m.items.hasFocus() and m.tab < 3 then
            m.cats.setFocus(true)
            return true
        else if m.items.hasFocus() or m.cats.hasFocus() then
            m.tabs.setFocus(true)
            return true
        end if
    end if

    return false
end function
