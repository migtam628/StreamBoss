' Sync with a StreamBoss sync server (see server/): My List and resume positions, kept in step with the other apps.
' The wire format and the merge rules are the same as the Flutter app's (lib/services/sync/), so a My List or a resume
' position made on a phone arrives here and back. Only the address, the e-mail and a token are ever sent; nothing about
' the provider but its address and login name. Included by the scene and by the fetch task; the logic is tested with
' brs-cli (tests/sync.test.brs) against a stand-in server.

' ---- the wire format --------------------------------------------------------
' A synced value is JSON text: {"t":"l","v":["a","b"]} for a list, {"t":"s","v":"<json text>"} for a map of resume positions
' (item key -> milliseconds).

function syncIsType(v as Dynamic, name as String) as Boolean
    if v = invalid then return false
    return LCase(type(v)) = name
end function

function syncParseWire(wire as Dynamic) as Dynamic
    if not (syncIsType(wire, "string") or syncIsType(wire, "rostring")) then return invalid
    parsed = ParseJson(wire)
    if not syncIsType(parsed, "roassociativearray") then return invalid
    return parsed
end function

function syncWireList(items as Object) as String
    return FormatJson({ t: "l", v: items })
end function

function syncUnwireList(wire as Dynamic) as Dynamic
    j = syncParseWire(wire)
    if j = invalid then return invalid
    if not syncIsType(j.v, "roarray") then return invalid
    out = []
    for each e in j.v
        out.push(toStr(e))
    end for
    return out
end function

function syncWireMap(data as Object) as String
    return FormatJson({ t: "s", v: FormatJson(data) })
end function

function syncUnwireMap(wire as Dynamic) as Dynamic
    j = syncParseWire(wire)
    if j = invalid then return invalid
    out = {}
    if not (syncIsType(j.v, "string") or syncIsType(j.v, "rostring")) then return invalid
    parsed = ParseJson(j.v)
    if not syncIsType(parsed, "roassociativearray") then return out
    for each k in parsed
        n = parsed[k]
        if n <> invalid then out[k] = Int(n)
    end for
    return out
end function

' ---- merging -----------------------------------------------------------------
' Three-way merge of one synced preference. baseVal is what this device saw at its last sync, localVal what it holds
' now, serverVal what the server holds; invalid means it does not exist there. hadBase is false for a device that never
' synced the key (it is joining): then the server wins where the two disagree and the two sides are joined.

function syncSetOf(items as Object) as Object
    out = {}
    for each e in items
        out[e] = true
    end for
    return out
end function

function syncMergeList(baseVal as Dynamic, localVal as Dynamic, serverVal as Dynamic, hadBase as Boolean) as Dynamic
    if serverVal = invalid then
        if localVal = invalid then return invalid
    end if
    s = []
    if serverVal <> invalid then s = serverVal
    mine = []
    if localVal <> invalid then mine = localVal
    b = []
    if baseVal <> invalid then b = baseVal
    inServer = syncSetOf(s)
    inLocal = syncSetOf(mine)
    inBase = syncSetOf(b)
    out = []
    kept = {}
    if not hadBase then
        for each e in s
            out.push(e)
            kept[e] = true
        end for
        for each e in mine
            if not kept.DoesExist(e) then
                out.push(e)
                kept[e] = true
            end if
        end for
        return out
    end if
    for each e in s
        removedHere = inBase.DoesExist(e) and not inLocal.DoesExist(e)
        if not removedHere then
            out.push(e)
            kept[e] = true
        end if
    end for
    for each e in mine
        if not inBase.DoesExist(e) and not kept.DoesExist(e) then
            out.push(e)
            kept[e] = true
        end if
    end for
    return out
end function

function syncMergeMap(baseVal as Dynamic, localVal as Dynamic, serverVal as Dynamic, hadBase as Boolean) as Dynamic
    if serverVal = invalid then
        if localVal = invalid then return invalid
    end if
    s = {}
    if serverVal <> invalid then s = serverVal
    mine = {}
    if localVal <> invalid then mine = localVal
    b = {}
    if baseVal <> invalid then b = baseVal
    out = {}
    if not hadBase then
        for each k in mine
            out[k] = mine[k]
        end for
        for each k in s
            out[k] = s[k]
        end for
        return out
    end if
    for each k in s
        out[k] = s[k]
    end for
    for each k in mine
        if b[k] = invalid then
            out[k] = mine[k]
        else if b[k] <> mine[k] then
            out[k] = mine[k]
        end if
    end for
    for each k in b
        if mine[k] = invalid then out.Delete(k)
    end for
    return out
end function

function syncSameList(a as Dynamic, b as Dynamic) as Boolean
    if a = invalid then return b = invalid
    if b = invalid then return false
    if a.count() <> b.count() then return false
    for i = 0 to a.count() - 1
        if a[i] <> b[i] then return false
    end for
    return true
end function

function syncSameMap(a as Dynamic, b as Dynamic) as Boolean
    if a = invalid then return b = invalid
    if b = invalid then return false
    if a.count() <> b.count() then return false
    for each k in a
        if b[k] = invalid then return false
        if b[k] <> a[k] then return false
    end for
    return true
end function

' ---- the engine ----------------------------------------------------------------
' api has two methods: fetch() -> { ok, items: { key: { value, rev } }, error, signedOut } and
' put(key, wire, base) -> { ok, rev, conflict, value, error, signedOut } (value = null/invalid removes the key).
' local = { favs: [item keys], resume: { item key: milliseconds } }. baseState holds, per key, what was agreed at the last
' sync: { rev, has, value }. Returns { ok, state, base, pulled, pushed, sources (wire text) } or { ok: false, error, signedOut }.

function syncKeys() as Object
    return ["favorites", "positions"]
end function

function syncWireOf(key as String, value as Dynamic) as Dynamic
    if value = invalid then return invalid
    if key = "favorites" then return syncWireList(value)
    return syncWireMap(value)
end function

function syncValueOf(key as String, wire as Dynamic) as Dynamic
    if key = "favorites" then return syncUnwireList(wire)
    return syncUnwireMap(wire)
end function

function syncSame(key as String, a as Dynamic, b as Dynamic) as Boolean
    if key = "favorites" then return syncSameList(a, b)
    return syncSameMap(a, b)
end function

function syncStateValue(ctx as Object, key as String) as Dynamic
    value = ctx.state.favs
    if key <> "favorites" then value = ctx.state.resume
    hadValue = false
    entry = ctx.base[key]
    if entry <> invalid then hadValue = entry.has
    if value.count() = 0 and not hadValue then return invalid
    return value
end function

' One key: merge, store here what changed, and say whether the server needs the result.
function syncSettle(ctx as Object, key as String) as Object
    remoteItem = ctx.remote[key]
    serverVal = invalid
    if remoteItem <> invalid then serverVal = syncValueOf(key, remoteItem.value)
    entry = ctx.base[key]
    baseVal = invalid
    if entry <> invalid then
        if entry.has then baseVal = entry.value
    end if
    localVal = syncStateValue(ctx, key)
    if key = "favorites" then
        merged = syncMergeList(baseVal, localVal, serverVal, entry <> invalid)
    else
        merged = syncMergeMap(baseVal, localVal, serverVal, entry <> invalid)
    end if
    if not syncSame(key, merged, localVal) then
        if key = "favorites" then
            ctx.state.favs = []
            if merged <> invalid then ctx.state.favs = merged
        else
            ctx.state.resume = {}
            if merged <> invalid then ctx.state.resume = merged
        end if
        ctx.pulled = ctx.pulled + 1
    end if
    need = not syncSame(key, merged, serverVal)
    if not need then
        rev = 0
        if remoteItem <> invalid then rev = remoteItem.rev
        ctx.base[key] = { rev: rev, has: merged <> invalid, value: merged }
    end if
    return { send: need, value: merged }
end function

function syncRun(api as Object, local as Object, baseState as Object) as Object
    fetched = api.fetch()
    if not fetched.ok then return { ok: false, error: fetched.error, signedOut: fetched.signedOut = true }
    ctx = {
        remote: fetched.items,
        base: baseState,
        state: { favs: local.favs, resume: local.resume },
        pulled: 0,
        pushed: 0
    }
    sends = []
    for each key in syncKeys()
        r = syncSettle(ctx, key)
        if r.send then sends.push({ key: key, value: r.value })
    end for
    for each item in sends
        value = item.value
        for round = 1 to 4
            rev = 0
            if ctx.remote[item.key] <> invalid then rev = ctx.remote[item.key].rev
            res = api.put(item.key, syncWireOf(item.key, value), rev)
            if res.ok then
                ctx.base[item.key] = { rev: res.rev, has: value <> invalid, value: value }
                ctx.pushed = ctx.pushed + 1
                exit for
            else if res.conflict = true then
                ' Another device wrote in the meantime: merge with what is there now and try again.
                ctx.remote[item.key] = { value: res.value, rev: res.rev }
                again = syncSettle(ctx, item.key)
                if not again.send then exit for
                value = again.value
            else
                return { ok: false, error: res.error, signedOut: res.signedOut = true }
            end if
        end for
    end for
    sources = invalid
    if ctx.remote["sources"] <> invalid then sources = ctx.remote["sources"].value
    return { ok: true, state: ctx.state, base: ctx.base, pulled: ctx.pulled, pushed: ctx.pushed, sources: sources }
end function

' The sources saved on other devices (name, kind, url, user; never a password), from the wire text of "sources".
function syncSources(wire as Dynamic) as Object
    out = []
    texts = syncUnwireList(wire)
    if texts = invalid then return out
    for each text in texts
        j = ParseJson(text)
        if syncIsType(j, "roassociativearray") then
            kind = LCase(toStr(j["type"]))
            if toStr(j.name) <> "" and (kind = "xtream" or kind = "m3u") then
                out.push({ name: toStr(j.name), kind: kind, url: toStr(j.url), user: toStr(j.user) })
            end if
        end if
    end for
    return out
end function

' `sync.example.com` becomes `https://sync.example.com`; a full address is kept (http is for a server on your own
' network). Empty when it cannot be an address.
function syncServerUrl(raw as String) as String
    s = raw.Trim()
    if s = "" then return ""
    if Instr(1, s, "://") = 0 then s = "https://" + s
    low = LCase(s)
    if Left(low, 8) <> "https://" and Left(low, 7) <> "http://" then return ""
    s = trimSlash(s)
    if Len(s) <= 8 then return ""
    return s
end function

' Keeps the newest n of a list, and n entries of a map: the registry holds 32 KB for the whole channel.
function syncCapList(items as Object, n as Integer) as Object
    if items.count() <= n then return items
    out = []
    for i = items.count() - n to items.count() - 1
        out.push(items[i])
    end for
    return out
end function

function syncCapMap(data as Object, n as Integer) as Object
    if data.count() <= n then return data
    out = {}
    kept = 0
    for each k in data
        if kept >= n then exit for
        out[k] = data[k]
        kept = kept + 1
    end for
    return out
end function

' ---- HTTP (call from a Task thread only: it blocks) -----------------------------

function syncCall(server as String, token as Dynamic, method as String, path as String, body as String) as Object
    xfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.EnableEncodings(true)
    xfer.SetUrl(server + path)
    xfer.AddHeader("Content-Type", "application/json")
    if token <> invalid then xfer.AddHeader("Authorization", "Bearer " + token)
    started = false
    if method = "GET" then
        started = xfer.AsyncGetToString()
    else
        xfer.SetRequest(method)
        started = xfer.AsyncPostFromString(body)
    end if
    if not started then return { status: 0, json: invalid, error: L("Could not reach the sync server. Check the address and that you are online.") }
    msg = wait(25000, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return { status: 0, json: invalid, error: L("The sync server did not answer.") }
    end if
    code = msg.GetResponseCode()
    if code <= 0 then return { status: 0, json: invalid, error: L("Could not reach the sync server. Check the address and that you are online.") }
    text = msg.GetString()
    parsed = invalid
    if text <> invalid and text <> "" then parsed = ParseJson(text)
    return { status: code, json: parsed, error: "" }
end function

function syncFailure(res as Object) as String
    if res.error <> "" then return res.error
    if syncIsType(res.json, "roassociativearray") then
        if toStr(res.json.error) <> "" then return toStr(res.json.error)
    end if
    return L("The sync server answered with an error.")
end function

' Signs in (or creates the account). cfg = { server, email, password, create }.
function syncSignIn(cfg as Object) as Object
    server = syncServerUrl(cfg.server)
    if server = "" then return { ok: false, error: L("That does not look like a server address.") }
    path = "/api/login"
    if cfg.create = true then path = "/api/register"
    body = FormatJson({ email: cfg.email.Trim(), password: cfg.password, device: "Roku" })
    res = syncCall(server, invalid, "POST", path, body)
    if res.status = 200 or res.status = 201 then
        if syncIsType(res.json, "roassociativearray") then
            if toStr(res.json.token) <> "" then
                return { ok: true, server: server, token: toStr(res.json.token), email: toStr(res.json.email) }
            end if
        end if
    end if
    return { ok: false, error: syncFailure(res) }
end function

function syncApiFetch() as Object
    res = syncCall(m.server, m.token, "GET", "/api/data", "")
    if res.status <> 200 then
        return { ok: false, items: {}, error: syncFailure(res), signedOut: res.status = 401 }
    end if
    if not syncIsType(res.json, "roassociativearray") then
        return { ok: false, items: {}, error: syncFailure(res), signedOut: res.status = 401 }
    end if
    items = {}
    raw = res.json.items
    if syncIsType(raw, "roassociativearray") then
        for each k in raw
            entry = raw[k]
            if syncIsType(entry, "roassociativearray") then
                if entry.rev <> invalid then items[k] = { value: entry.value, rev: Int(entry.rev) }
            end if
        end for
    end if
    return { ok: true, items: items, error: "", signedOut: false }
end function

function syncApiPut(key as String, wire as Dynamic, base as Integer) as Object
    body = "{""value"":null,""base"":" + base.ToStr() + "}"
    if wire <> invalid then body = FormatJson({ value: wire, base: base })
    res = syncCall(m.server, m.token, "PUT", "/api/data/" + esc(key), body)
    if res.status = 200 and syncIsType(res.json, "roassociativearray") then
        if res.json.rev <> invalid then return { ok: true, rev: Int(res.json.rev), conflict: false, value: invalid, error: "", signedOut: false }
    end if
    if res.status = 409 and syncIsType(res.json, "roassociativearray") then
        rev = 0
        if res.json.rev <> invalid then rev = Int(res.json.rev)
        return { ok: false, rev: rev, conflict: true, value: res.json.value, error: "", signedOut: false }
    end if
    return { ok: false, rev: 0, conflict: false, value: invalid, error: syncFailure(res), signedOut: res.status = 401 }
end function

function syncApi(server as String, token as String) as Object
    return { server: server, token: token, fetch: syncApiFetch, put: syncApiPut }
end function
