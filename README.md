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
| Apple TV (tvOS) | Separate native SwiftUI app in [`tvos/`](tvos/) (Flutter doesn't support tvOS) |
| Roku | Separate native channel in [`roku/`](roku/) (Roku can't run Flutter) |

Note: browsers block mixed-content (http) streams and most IPTV servers lack CORS headers,
so web works best with https + CORS-enabled providers.

Web playback uses the browser's own decoders (hls.js is bundled for HLS), so what plays depends on
the browser; decoder, network-buffer and shader settings are hidden on web because they only affect
the native libmpv player. Web was exercised end to end in headless Chromium (M3U source, playback,
seek, pause, speed, resume, channel zapping, search, settings). That Chromium has no H.264, so the
test used VP9/WebM streams; the H.264 demo streams need a normal browser.

## Versioning

Every feature or fix gets its own version, so a build can always be traced to what it contains.

| Tag | Meaning |
|---|---|
| `v0.2.3` | a release: each new feature or fix bumps the patch (`0.2.3` -> `0.2.4`); a bigger milestone bumps the minor (`0.3.0`) |
| `v0.3.0b2` | beta build 2 on the way to `v0.3.0` (`v0.3.0-rc1` also works); published as a **pre-release** |

Order is `0.3.0b1` < `0.3.0b2` < `0.3.0-rc1` < `0.3.0` < `0.3.1b1`. For each version:

1. In the same commit as the feature, set `version:` in `pubspec.yaml` (`0.2.4+1`) and add a
   `## 0.2.4 - YYYY-MM-DD` section to `CHANGELOG.md`. A unit test fails if the two disagree or the changelog
   is out of order, and the release workflow refuses a tag that has no changelog section.
2. Tag that commit (below). The section becomes the release notes, the tag becomes the version shown in
   **Settings > About**, and **Check for updates** compares against it. Stable builds are only offered stable
   releases; beta builds are also offered newer betas.

## Releases

Tagged versions are published automatically to the repo's **Releases** page by
`.github/workflows/release.yml`:

```sh
git tag v0.2.3 && git push origin v0.2.3      # or v0.3.0b2 for a beta
```

Each release attaches Android APKs (per CPU type), Windows, Linux and macOS archives, the web build,
the Roku channel zip, and `SHA256SUMS.txt`. The notes are that version's `CHANGELOG.md` section.
To rehearse without publishing, run **Actions > Release > Run workflow** with "publish" unchecked:
it builds and packages everything and attaches the files to the run.

macOS: because the app is unsigned, Gatekeeper blocks the first launch. Right-click the app > Open, or run
`xattr -dr com.apple.quarantine StreamBoss.app` once.

Notes: builds are not code-signed. Android APKs use the debug key, macOS may need right-click > Open,
and Windows may show a SmartScreen prompt. tvOS is not shipped as a release asset because it needs
Apple signing; build it from `tvos/` (see its README).

## Install on Android, Android TV, Google TV and Fire TV

The CI run attaches three APKs (`android` artifact); pick the one that matches the device:

| APK | Devices |
|---|---|
| `app-arm64-v8a-release.apk` | most phones and newer TV boxes / Fire TV 4K Max |
| `app-armeabi-v7a-release.apk` | older phones, older Fire TV Sticks and TV boxes |
| `app-x86_64-release.apk` | emulators, Chromebooks |

```sh
adb connect <tv-ip>:5555        # TV / Fire TV: enable ADB debugging first (skip for a USB phone)
adb install -r app-arm64-v8a-release.apk
```

The APKs are signed with the debug key, which is fine for sideloading but not for the Play Store.
On a TV the app appears in the apps row with its own banner; use the D-pad to navigate, OK to select,
Back to go up. Android picture-in-picture is available from the player's controls.

## Features

- Xtream Codes and M3U sources, multiple saved sources, offline demo mode
- Passwords stored in the platform keystore (flutter_secure_storage), not in plain prefs
- Live TV, Movies, Series (with episodes), categories, search
- Home shelves: Continue watching, My List (long-press to favorite; on TV use the button on the movie page)
- TMDB metadata (optional key in Settings): backdrop, overview, rating, cast, trailer link
- Xtream now/next EPG in the live player, plus a Guide tab: an 8-hour XMLTV time grid (Xtream `xmltv.php` or the M3U `url-tvg` header; D-pad friendly) with a now/next list fallback
- Backup / restore (clipboard JSON; passwords are never included)
- Player (media_kit / libmpv: MKV, TS, HLS, MP4), designed around remote use like mpvNova:
  - controls hidden: OK = pause, Left/Right = seek 10s, Up/Down = next/previous channel
  - controls visible: arrows move between buttons, Back hides them
  - audio and subtitle track pickers, speed, sleep timer, skip-intro (+90s), stats overlay
  - resume position for movies and episodes, per-episode "continue watching"
- Settings: hardware/software decoder, network buffer presets (low/normal/high),
  subtitle size/color/background with live preview, default speed
- Picture-in-picture on Android (button in the player)
- Shader library (libmpv user shaders): built-in Sharpen, Vibrance, Night warm, Film grain, plus your own pasted GLSL; toggle live in the player, reorder in Settings
- Keyboard / D-pad / remote navigation with visible focus rings
- Phone setup: on the connect screen, "Set up from your phone" shows a QR code and a 4-digit PIN; the phone opens a small
  page served by the app on your home network and sends the login back, so no typing with a remote. The server runs only
  while that screen is open, locks after 5 wrong PINs, and nothing leaves the local network (native apps only)
- TV mode (automatic on Android TV, Google TV and Fire TV; Settings > Appearance > TV mode forces it on or off):
  20% larger text and posters, a bold white focus ring with glow, a side rail, overscan-safe margins,
  the cursor starting on Play, an "Add to My list" button on movie pages (no long-press on a remote),
  and Back returning to Home before it leaves the app

## Develop

Platform folders are generated, not committed:

```sh
flutter create . --project-name streamboss --org com.streamboss
dart run tool/patch_macos.dart     # macOS: network entitlement (the sandboxed app can't connect without it)
dart run tool/patch_android.dart   # Android TV / Google TV / Fire TV manifest (leanback launcher, INTERNET, cleartext http)
flutter pub get
flutter run -d <device>
flutter test
```

Linux desktop needs `libmpv-dev libsecret-1-dev` installed.

## Status / roadmap

Not done yet: tvOS and Roku are leaner than the Flutter app (no TMDB, EPG or shaders; see their READMEs),
gzipped (.xml.gz) XMLTV guides, iOS picture-in-picture, shader file import,
intro/outro detection (skip-intro is a fixed +90s jump).
