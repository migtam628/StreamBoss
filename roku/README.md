# StreamBoss for Roku

Roku does not run Flutter, so this is a small native SceneGraph/BrightScript channel
that plays an M3U playlist you provide.

1. Edit `PLAYLIST_URL()` in `components/MainScene.brs`.
2. Add real icon/splash PNGs to `images/` (`icon_hd.png` 290x218, `icon_sd.png` 246x140, `splash_hd.png` 1280x720).
3. Enable developer mode on the Roku (Home x3, Up x2, Right, Left, Right, Left, Right), then zip and sideload:

```sh
cd roku && zip -r ../streamboss-roku.zip manifest source components images
# upload the zip at http://<roku-ip> (user: rokudev)
```

Publishing to the Roku Channel Store requires a Roku developer account and certification.
