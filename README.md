# StreamBoss

A cross-platform IPTV player for the Xtream or M3U service **you already have**. It ships with
no content. Inspired by apps like Lumen, with its own UI.

## Platform support

| Platform | How |
|---|---|
| Windows, macOS, Linux | Flutter desktop |
| Android, Android TV, Google TV, Fire TV | Flutter Android (D-pad focus supported) |
| iOS | Flutter iOS |
| Web | Flutter web (see note) |
| Roku | Separate native channel in [`roku/`](roku/) (Roku can't run Flutter) |

Note: browsers block mixed-content (http) streams and most IPTV servers lack CORS headers,
so web works best with https + CORS-enabled providers.

## Features

- Xtream Codes and M3U sources, multiple saved sources, offline demo mode
- Passwords stored in the platform keystore (flutter_secure_storage), not in plain prefs
- Live TV, Movies, Series (with episodes), categories, search
- Home shelves: Continue watching, My List (long-press / hold select to favorite)
- TMDB metadata (optional key in Settings): backdrop, overview, rating, cast, trailer link
- Xtream now/next EPG in the live player
- Player (media_kit / libmpv: MKV, TS, HLS, MP4), designed around remote use like mpvNova:
  - controls hidden: OK = pause, Left/Right = seek 10s, Up/Down = next/previous channel
  - controls visible: arrows move between buttons, Back hides them
  - audio and subtitle track pickers, speed, sleep timer, skip-intro (+90s), stats overlay
  - resume position for movies and episodes, per-episode "continue watching"
- Settings: hardware/software decoder, network buffer presets (low/normal/high),
  subtitle size/color/background with live preview, default speed
- Keyboard / D-pad / remote navigation with visible focus rings

## Develop

Platform folders are generated, not committed:

```sh
flutter create . --project-name streamboss --org com.streamboss
dart run tool/patch_android.dart   # Android TV / Google TV / Fire TV manifest (leanback launcher, INTERNET, cleartext http)
flutter pub get
flutter run -d <device>
flutter test
```

Linux desktop needs `libmpv-dev libsecret-1-dev` installed.

## Status / roadmap

Not done yet: tvOS, Roku feature parity (the Roku channel is a minimal M3U list + player),
full XMLTV program guide grid, picture-in-picture, settings backup/restore, shader management,
intro/outro detection (skip-intro is a fixed +90s jump).
