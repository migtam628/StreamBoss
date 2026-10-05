' Set PLAYLIST_URL to your own legal M3U playlist before sideloading.
function PLAYLIST_URL() as String
    return "https://example.com/playlist.m3u"
end function

sub init()
    m.list = m.top.findNode("list")
    m.status = m.top.findNode("status")
    m.video = m.top.findNode("video")
    m.channels = []
    m.list.observeField("itemSelected", "onSelect")
    m.video.observeField("state", "onVideoState")
    fetch()
end sub

sub fetch()
    xfer = CreateObject("roUrlTransfer")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.InitClientCertificates()
    xfer.SetUrl(PLAYLIST_URL())
    body = xfer.GetToString()
    if body = "" then
        m.status.text = "Could not load playlist. Edit PLAYLIST_URL in MainScene.brs."
        return
    end if
    parse(body)
end sub

sub parse(body as String)
    root = CreateObject("roSGNode", "ContentNode")
    name = ""
    for each line in body.Split(chr(10))
        line = line.Trim()
        if Left(line, 7) = "#EXTINF" then
            comma = Instr(1, line, ",")
            if comma > 0 then name = Mid(line, comma + 1)
        else if line <> "" and Left(line, 1) <> "#" then
            item = root.createChild("ContentNode")
            item.title = name
            item.url = line
            item.streamFormat = "hls"
            m.channels.push(item)
        end if
    end for
    m.list.content = root
    m.status.text = Str(m.channels.count()).Trim() + " channels"
    m.list.setFocus(true)
end sub

sub onSelect()
    idx = m.list.itemSelected
    if idx < 0 or idx >= m.channels.count() then return
    m.video.content = m.channels[idx]
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
end sub

sub onVideoState()
    if m.video.state = "finished" or m.video.state = "error" then closeVideo()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if press and key = "back" and m.video.visible then
        closeVideo()
        return true
    end if
    return false
end function

sub closeVideo()
    m.video.control = "stop"
    m.video.visible = false
    m.list.setFocus(true)
end sub
