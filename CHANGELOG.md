# Changelog

Every feature or fix gets its own version, newest first. The heading is the git tag without the `v`
(`## 0.2.3` is tag `v0.2.3`) and its section becomes that release's notes. Betas look like `0.3.0b2`
and sort before their final release. See "Versioning" in README.md.

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
