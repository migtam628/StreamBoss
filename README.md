# StreamBoss

A cross-platform IPTV player for the Xtream or M3U service **you already have**. It ships with
no content. Inspired by apps like Lumen, with its own UI.

## Screenshots

The 21 layouts on a TV (Settings > Appearance > Layout; every one also has a phone version). Titles and channels are a made-up demo library.

<table>
<tr><td align="center"><img src="docs/screenshots/marquee.jpg" width="300" alt="Marquee layout on a TV"><br><sub><b>Marquee</b></sub></td><td align="center"><img src="docs/screenshots/control.jpg" width="300" alt="Control Room layout on a TV"><br><sub><b>Control Room</b></sub></td><td align="center"><img src="docs/screenshots/spotlight.jpg" width="300" alt="Spotlight layout on a TV"><br><sub><b>Spotlight</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/prime.jpg" width="300" alt="Prime Time layout on a TV"><br><sub><b>Prime Time</b></sub></td><td align="center"><img src="docs/screenshots/hub.jpg" width="300" alt="Hub layout on a TV"><br><sub><b>Hub</b></sub></td><td align="center"><img src="docs/screenshots/daylight.jpg" width="300" alt="Daylight layout on a TV"><br><sub><b>Daylight</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/cable.jpg" width="300" alt="Cable Box layout on a TV"><br><sub><b>Cable Box</b></sub></td><td align="center"><img src="docs/screenshots/indexList.jpg" width="300" alt="Index layout on a TV"><br><sub><b>Index</b></sub></td><td align="center"><img src="docs/screenshots/glass.jpg" width="300" alt="Glass layout on a TV"><br><sub><b>Glass</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/bento.jpg" width="300" alt="Bento layout on a TV"><br><sub><b>Bento</b></sub></td><td align="center"><img src="docs/screenshots/mosaic.jpg" width="300" alt="Mosaic layout on a TV"><br><sub><b>Mosaic</b></sub></td><td align="center"><img src="docs/screenshots/tonight.jpg" width="300" alt="Tonight layout on a TV"><br><sub><b>Tonight</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/globe.jpg" width="300" alt="Globe layout on a TV"><br><sub><b>Globe</b></sub></td><td align="center"><img src="docs/screenshots/playground.jpg" width="300" alt="Playground layout on a TV"><br><sub><b>Playground</b></sub></td><td align="center"><img src="docs/screenshots/console.jpg" width="300" alt="Console layout on a TV"><br><sub><b>Console</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/deck.jpg" width="300" alt="Deck layout on a TV"><br><sub><b>Deck</b></sub></td><td align="center"><img src="docs/screenshots/lounge.jpg" width="300" alt="Lounge layout on a TV"><br><sub><b>Lounge</b></sub></td><td align="center"><img src="docs/screenshots/madlib.jpg" width="300" alt="Madlib layout on a TV"><br><sub><b>Madlib</b></sub></td></tr>
<tr><td align="center"><img src="docs/screenshots/matchday.jpg" width="300" alt="Matchday layout on a TV"><br><sub><b>Matchday</b></sub></td><td align="center"><img src="docs/screenshots/easy.jpg" width="300" alt="Easy layout on a TV"><br><sub><b>Easy</b></sub></td><td align="center"><img src="docs/screenshots/wall.jpg" width="300" alt="Wall layout on a TV"><br><sub><b>Wall</b></sub></td></tr>
</table>

On a phone:

<p>
<img src="docs/screenshots/phone-marquee.jpg" width="150" alt="marquee on a phone"> <img src="docs/screenshots/phone-tonight.jpg" width="150" alt="tonight on a phone"> <img src="docs/screenshots/phone-lounge.jpg" width="150" alt="lounge on a phone"> <img src="docs/screenshots/phone-madlib.jpg" width="150" alt="madlib on a phone"> <img src="docs/screenshots/phone-wall.jpg" width="150" alt="wall on a phone"> <img src="docs/screenshots/phone-easy.jpg" width="150" alt="easy on a phone"> 
</p>

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
   **Settings > About**, and **Check for updates** compares against it and installs the update from inside the
   app (Android's installer, or the desktop app replacing its own files). Stable builds are only offered stable
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

Notes: macOS and Windows builds are not code-signed (macOS may need right-click > Open, Windows may show a
SmartScreen prompt). Android APKs are signed with your own key, see "Android signing" below. tvOS is not shipped as a release asset because it needs
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

The APKs are signed for sideloading, not the Play Store (see "Android signing" below).
On a TV the app appears in the apps row with its own banner; use the D-pad to navigate, OK to select,
Back to go up. Android picture-in-picture is available from the player's controls.

### Android signing

Android only installs an APK over an installed copy when both are signed with the **same key**. Without a key of
your own, every CI run signs with a throwaway debug key, so each release has a different signature and Android
says "App not installed" (you would have to uninstall first and lose your saved sources). Create a key once and
give it to the repository:

```sh
keytool -genkeypair -v -keystore streamboss.jks -alias streamboss -keyalg RSA -keysize 2048 -validity 10000
base64 -i streamboss.jks | pbcopy        # macOS (Linux: base64 -w0 streamboss.jks)
```

Then in the repo: Settings > Secrets and variables > Actions > New repository secret:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the base64 text you just copied |
| `ANDROID_KEYSTORE_PASSWORD` | the password you chose |
| `ANDROID_KEY_ALIAS` | `streamboss` |

Keep `streamboss.jks` and its password somewhere safe and never commit them: if the key is lost, installed apps
can't be updated, only replaced. CI prints the signing certificate's SHA-256 for each APK; it must be the same in
every release. The first build signed with your key has to be installed after uninstalling the old app once.

## Features

- Xtream Codes and M3U sources, multiple saved sources, offline demo mode
- Passwords stored in the platform keystore (flutter_secure_storage), not in plain prefs
- Live TV, Movies, Series (with episodes), categories, search
- Home shelves: Continue watching, My List (long-press to favorite; on TV use the button on the movie page)
- TMDB metadata (optional key in Settings): backdrop, overview, rating, cast, trailer link
- Xtream now/next EPG in the live player, plus a Guide tab: an 8-hour XMLTV time grid (Xtream `xmltv.php` or the M3U `url-tvg` header, plain or gzipped `.xml.gz`; D-pad friendly) with a now/next list fallback
- Four app icons (Crown, Bold B, Signal, Screen) to switch between at will: Settings > Appearance > App icon (Android, Android TV
  and macOS; other platforms use the Crown icon). Drawings and generator in `design/`
- Xtream account details (status, expiry, connections in use) under Settings > Source & library
- Search: several words in any order, word starts, accents ignored, small typos forgiven, results grouped by kind and ranked,
  filters (kind, category, rating, sort) and recent searches
- Duplicate channels (HD, SD, backups) are merged into one entry; if the best copy fails the player tries the next
- Live TV: pause and rewind within the player's cache (Left/Right), a "behind live" indicator and Back to live; Xtream
  catch-up from the player and the guide for channels that keep an archive; a quick channel switcher (Channels button / C)
- Guide programme details (description, time, catch-up) on any programme that is not on now, or by long-press
- Chapters: a chapter list, plus Skip intro / Skip credits when the chapter is named so. A skip you make early in an episode
  (Skip ahead, or Skip intro) is remembered for that series, so the next episodes offer it too even without chapters. When the
  credits start, "Next episode" is offered (Settings > Playback)
- My lists: My list and your collections in one screen, each in an order you set (move a title to the top, earlier or later,
  or view it A to Z); collections are included in backups
- Channel tools: press and hold a live channel to rename it, hide it, pin it to the top of the channel lists or move it among
  the pinned ones, per profile and without touching the provider; Settings > Source & library > Edited channels undoes any of it
- Collections (your own named lists, per profile) and a "Picked for you" shelf from your history; missing posters are
  filled in from TMDB when a key is set
- Channel check: Settings > Source & library tests every live channel (two at a time on a provider login, ten at a time on a
  public list, only the start of each stream is read) and flags the ones that do not answer; a switch hides them. Apps only
- Profiles and a PIN lock: each profile has its own My List, history and resume positions; a Kids profile shows only
  categories that look made for children; a four-digit PIN (stored salted and hashed, five wrong tries lock it for 30
  seconds) locks Settings while a Kids profile is in use, guards leaving a Kids profile and any profile marked "Needs PIN".
  A family lock for a shared screen, not high security. Settings > Profiles & PIN
- Profiles can have their own settings (layout, colours, languages, subtitles, filters); several saved sources can be
  shown in the library at once; custom accent colour and background; an idle screensaver of drifting posters
  (Auto: 10 minutes on a TV); subtitle search from the player with your own OpenSubtitles key
- A mini player: picture-in-picture inside the app, a small draggable window that keeps playing while you browse and
  opens the full player again with the same stream. The Guide, the Control Room and Prime Time play the selected channel
  in a preview. Live, the Guide and the Control Room share channel filters (words, quality, country, favorites, guide data, order)
- Cast to TV (experimental): the player's Cast button finds Chromecasts and TVs with Chromecast built in on your Wi-Fi and
  plays the stream there (not on the web build; untested on real hardware). On iPhone and iPad the player also has the system AirPlay
  button: sound goes to the speaker or TV picked, and the picture follows when the screen is mirrored (untested on real hardware)
- Rich movie, series and channel pages: a big picture, facts, tabs for the plot, cast, similar titles and details (file
  format, other copies in your library), a Continue button that knows the next episode, per-episode progress and watched
  marks, Play options (audio, subtitles, speed, which copy), and a quick look when you press and hold a title. Settings >
  About > Check for updates downloads and installs the new version without leaving the app.
- Quick start: the library is saved on the device and shown at once on the next start while the provider's current one is
  fetched behind it, and big libraries are read off the screen's thread. Copy diagnostics reports the timings.
- On a TV the on-screen keyboard only opens when you press OK on a text box. In the player the star adds a channel to My list and
  Menu/Info open its options (rename, pin, hide). Settings > Startup can open the app when the Fire TV / Android TV starts and
  reopen the last screen or live channel.
- Movies, Series and the Anime page each have a filter: words, rating (6+, 7+, 8+), year (read from the title), language, favorites,
  not watched yet, and an order. Live, Guide and Search filter by language too, and countries and languages can be picked several at once. Anime is its own page (Settings > Open on can start there) that gathers the categories named anime, manga,
  donghua, shonen and similar, and titles tagged "(Anime)", across series, movies and channels. The page is in the menus only when
  the library has some (Settings > Appearance > Anime page: Auto, Always, Hidden)
- Big libraries: what a title says about itself (year, rating, search words) is worked out once, filter and anime results are
  kept while the library and the filter stay the same, and a 100,000 title library filters and sorts in about a second
- Backup / restore (clipboard JSON; passwords are never included)
- Player (media_kit / libmpv: MKV, TS, HLS, MP4), designed around remote use like mpvNova:
  - controls hidden: OK = pause, Left/Right = seek 10s, Up/Down = next/previous channel
  - controls visible: arrows move between buttons, Back hides them
  - audio and subtitle track pickers, speed, sleep timer, skip-intro (+90s), stats overlay
  - resume position for movies and episodes, per-episode "continue watching"
  - type a channel number to jump to it, a Last channel button, "Up next" after an episode (auto-plays the next one),
    and a picture shape button (Auto, 16:9, 4:3, Fill, Stretch)
- Settings: hardware/software decoder, network buffer presets (low/normal/high),
  subtitle size/color/background with live preview, default speed
- Picture-in-picture on Android (button in the player)
- Shader library (libmpv user shaders): built-in Sharpen, Vibrance, Night warm, Film grain, plus your own pasted GLSL; toggle live in the player, reorder in Settings
- Keyboard / D-pad / remote navigation with visible focus rings
- Phone setup: on the connect screen, "Set up from your phone" shows a QR code and a 4-digit PIN; the phone opens a small
  page served by the app on your home network and sends the login back, so no typing with a remote. The server runs only
  while that screen is open, locks after 5 wrong PINs, and nothing leaves the local network (native apps only)
- Twenty-one layouts (grouped in the picker, with a one-press way back to the one you had), chosen in Settings > Appearance > Layout (the choice is per device): **Marquee** (a featured title on Home, a
  slim icon rail, rows of posters), **Control Room** (categories, a numbered channel list with what is on now, and a
  details pane; built for flipping live channels), **Spotlight** (a poster wall where the focused title gets a details
  panel, with a single navigation pill), **Prime Time** (the TV guide is Home, with the highlighted programme's details
  above it), **Hub** (a launcher of big colored
  tiles), **Daylight** (the light one: white cards, one green accent), **Cable Box** (opens on a channel with a
  now/next banner; Up and Down change channel), **Index** (big type, almost no posters, the lightest to run), **Glass** (frosted panels over a soft
  backdrop, with a dock), **Bento** (a board of flat colored tiles), **Mosaic** (four channel tiles at once with the sound on one), **Tonight** (an evening planner: one timeline of what is on now, what starts later, what you are halfway through and what you saved), **Globe** (live TV by country on a dotted world map), **Playground** (big colored tiles for a Kids profile, with a bedtime and a PIN-guarded Grown-ups button), **Console** (a prompt that finds things as you type, with slash commands) and **Deck** (a deck of picks to skip, save or play), **Lounge** (a live channel in the top half and a strip to surf), **Madlib** (a sentence you fill in: "Tonight I feel like a movie that is funny..."), **Matchday** (today's sport by kick-off, with the channels that carry each event), **Easy** (three huge buttons, high contrast) and **Wall** (the whole library as one poster wall, with zoom). Layouts from earlier versions that were retired (Coverflow, Library, Orbit, Mood) open as Marquee. Each has its own colors and a phone version.
  Cable Box and Mosaic play their channels live on the home screen (muted, except the Mosaic tile that has the sound; only
  while visible; Settings > Appearance > Live pictures turns it off)
- Free public channels: Settings > Source (or the connect screen) can browse the public iptv-org and Free-TV playlist
  directories by category, country, language or the full index, and save any number of them as one combined source. The
  app does not host or vouch for these lists; you can still paste any M3U link you choose
- First-run setup wizard (screen, layout, playback defaults, then connecting a provider); skippable, and repeatable from
  Settings > About > Run setup again
- TV mode (automatic on Android TV, Google TV and Fire TV; Settings > Appearance > TV mode forces it on or off):
  the screen is laid out on a fixed canvas about 1280 px wide whatever the device reports (Settings > Appearance > TV
  zoom changes how much fits), a bold white focus ring with glow, overscan-safe margins, the cursor starting on Play,
  an "Add to My list" button on movie pages (no long-press on a remote), and Back returning to Home before it leaves the app
- Video output on Android TV: hardware surface by default (smoother movies on weak sticks; no embedded subtitles or
  shaders), switchable in Settings > Playback > Video output

## Develop

Platform folders are generated, not committed:

```sh
flutter create . --project-name streamboss --org com.streamboss
dart run tool/patch_macos.dart     # macOS: network entitlement (the sandboxed app can't connect without it)
dart run tool/patch_ios.dart       # iOS: Bonjour + local-network text so Cast can find TVs
dart run tool/patch_android.dart   # Android TV / Google TV / Fire TV manifest (leanback launcher, INTERNET, cleartext http, the switchable icons)
dart run tool/patch_icons.dart     # the StreamBoss icon in the generated iOS, macOS, Windows and web projects
flutter pub get
flutter run -d <device>
flutter test
```

Linux desktop needs `libmpv-dev libsecret-1-dev` installed.

## Status / roadmap

Not done yet: tvOS and Roku are leaner than the Flutter app (no TMDB, EPG or shaders; see their READMEs),
iOS picture-in-picture, shader file import,
intro/outro detection (skip-intro is a fixed +90s jump).
