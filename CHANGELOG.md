# Changelog

Every feature or fix gets its own version, newest first. The heading is the git tag without the `v`
(`## 0.2.3` is tag `v0.2.3`) and its section becomes that release's notes. Betas look like `0.3.0b2`
and sort before their final release. See "Versioning" in README.md.

## 0.3.0b1 - 2026-10-05
- Three selectable layouts, in Settings > Appearance > Layout: Marquee, Control Room and Spotlight, each with its own navigation, Home and browse screens, colors and a phone version. The choice is kept per device and is not part of backups. This is a beta: tell me what feels wrong on your TV and phone.
  - Marquee: a featured title with Play focused, a slim icon rail on TV and a bottom bar on phones.
  - Control Room: a top bar with a clock; Live shows categories, a numbered channel list with what is on now and how far through it is, and a details pane for the highlighted channel or title.
  - Spotlight: one navigation pill, a poster wall with chips, and a panel with the details of the title you are on; on a phone a search pill and a resume bar.
- TV mode is zoomed out. The TV layout is drawn on a fixed 1280 px wide canvas and scaled to the screen, so it looks the same on every TV instead of zoomed in on some. The extra 20% text and posters TV mode used to add is gone. Settings > Appearance > TV zoom changes how much fits (Larger, Standard, Smaller, Smallest). Buttons are bigger on TV.
- Phones get a bottom bar of four screens plus a More sheet (Series, Search and Settings, or whichever your layout puts there).

## 0.2.6 - 2026-10-05
- Smoother video on Fire TV and Android TV, and a fix for movies closing the app. The player used to copy every decoded frame through the GPU, which a TV stick can't keep up with for movies (4K frames need a lot of memory), and it made live TV laggy. On a TV the video now goes straight from the hardware decoder to the screen ("Hardware surface"). Settings > Playback > Video output lets you switch back to Compatible (GPU), which is also what the app falls back to by itself if playback closes while starting. The surface output can't draw embedded subtitles or shaders.
- When a video can't start because the network can't look up the server that hosts it (common: the catalog loads but movies come from a different address that a carrier or filtering DNS blocks), the player now says so and what to try, instead of suggesting a different decoder.
- The player's memory buffer is smaller on TVs (16 MB instead of 32 MB each way).
- If playback closes while starting, the app now steps down one level at a time: first the standard video output, then software decoding (it used to jump straight to software, which made live TV slow after a crash).

## 0.2.5 - 2026-10-05
- Android releases can be signed with a permanent key (repository secrets, setup in README "Android signing"). Before this, every CI run signed with a new throwaway debug key, so a release could not be installed over the previous one ("App not installed"). CI now prints each APK's signing fingerprint, and warns when no key is configured.

## 0.2.4 - 2026-10-05
- Playback crash guard. If StreamBoss closes while a video or channel is starting, the next launch says so, shows the last steps the player recorded and turns on Safe playback (software decoding) automatically. Playback is recorded in a small log with stream addresses reduced to the host, so no logins are stored; Settings > About > Playback log shows it and can copy it.
- The player now shows an error panel when a stream can't be played (it used to spin forever), and ignores a system kill while the app is in the background.

## 0.2.3 - 2026-10-05
- Phone setup: on the connect screen, "Set up from your phone" shows a QR code and a 4-digit PIN. Your phone opens a small page served by the app on your home network and sends the login back, so there is no typing with a TV remote. The server stops when the screen closes or after 10 minutes and locks after 5 wrong PINs. Native apps only.
- macOS: adds the `network.server` entitlement the phone-setup page needs; CI checks for it.
- Versioning: betas (`v0.3.0b2`) and release candidates are accepted as tags and published as pre-releases; About shows the full version; "Check for updates" offers newer betas to beta builds and only stable releases to stable builds; release notes come from this file.

## 0.2.2 - 2026-10-05
- TV mode, on automatically for Android TV, Google TV and Fire TV (Settings > Appearance > TV mode forces it on or off): 20% larger text and posters, a bold white focus ring with glow, a side rail, safe screen margins, the cursor starting on Play, an "Add to My list" button on movie pages, first episode focused, and Back returning to Home before it leaves the app.

## 0.2.1 - 2026-10-05
- Connections try IPv4 first and report the real error. Dart used to show the first failure, which on networks without IPv6 is an instant "Network is unreachable" that hid what actually went wrong.
- Settings > Network > Test connection: a credential-free report of DNS, per-address connects and an HTTP request to your provider, with a Copy button.
- "Network is unreachable" and "No route to host" errors now explain themselves.

## 0.2.0 - 2026-10-05
- Settings area with eight sections: source and library, playback, subtitles, appearance, library and guide, network and metadata, data and backup, about. Every option changes behaviour: resume, seek and skip steps, controls auto-hide, audio and subtitle languages, decoder and buffer, subtitle styling, text and poster size, start screen, adult filter, A-Z sort, 24-hour clock, User-Agent, TMDB key, backup and restore, clearing history, update check.
- Fixed the player's on-screen back arrow, which only hid the controls.
- Movie and series pages show poster, plot, cast, runtime and trailer from the provider (merged with TMDB when a key is set).
- The guide downloads when you open the Guide tab instead of at login.
- A `get.php?username=..&password=..` link now uses the provider's Xtream API.

## 0.1.1 - 2026-10-05
- macOS: network access entitlement (the app could not resolve any host) and the regular keychain so saved passwords persist.
- A pasted `get.php?username=..&password=..` link works in the Xtream form; credentials are redacted from error messages.
- GitHub Actions publish a release (all platforms plus checksums) when a `v*` tag is pushed.

## 0.1.0 - 2026-10-05
- First release: Xtream Codes and M3U sources, live TV, movies, series, XMLTV guide, resume, My List, TMDB details, picture-in-picture, shader library, Android TV manifest, Roku channel and tvOS app.
