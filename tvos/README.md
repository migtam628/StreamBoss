# StreamBoss for Apple TV (tvOS)

Flutter and media_kit do not support tvOS, so this is a small native SwiftUI app using
AVPlayer. It is a player only: you supply your own Xtream or M3U provider.

- `Core/` platform-independent logic (models, M3U + Xtream clients). Tested with `swift test`.
- `App/` SwiftUI views, keychain, AVKit player.
- `project.yml` XcodeGen spec for the Xcode project.

## Build
```sh
brew install xcodegen
cd tvos && xcodegen generate
open StreamBoss.xcodeproj          # run on an Apple TV simulator or device
swift test                         # Core logic tests (works on Linux too)
```

## Features
Xtream / M3U sources (password in the keychain), Live / Movies / Series with episodes,
categories, My List (long-press), resume position, demo mode, native Siri Remote player with
audio + subtitle menus. The app speaks English, Spanish, Italian and Portuguese and follows the Apple TV's
language (Settings > General > Language). The texts are in `i18n/strings.json`; `python3 tool/tvos_i18n.py` turns
them into the `App/Resources/<lang>.lproj/Localizable.strings` files and CI checks that every text has all three
translations. In code, SwiftUI's `Text("...")` / `Button("...")` translate by themselves; for a plain string in
`Core/` use `tr("...")` or `trf("... %lld ...", n)`.

## Limits
- AVPlayer plays HLS and MP4 only. MKV and raw MPEG-TS streams will not play on Apple TV.
- No TMDB metadata, EPG, search, channel zapping or shaders yet.
- The SwiftUI layer is built in CI for the tvOS simulator and the Core logic is tested on Linux, but nobody has run it on an Apple TV yet.
