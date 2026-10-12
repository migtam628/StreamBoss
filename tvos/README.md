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
categories, My List (long-press), resume position, sync with your own sync server (see below), demo mode, native Siri Remote player with
audio + subtitle menus. The app speaks English, Spanish, Italian and Portuguese and follows the Apple TV's
language (Settings > General > Language). The texts are in `i18n/strings.json`; `python3 tool/tvos_i18n.py` turns
them into the `App/Resources/<lang>.lproj/Localizable.strings` files and CI checks that every text has all three
translations. In code, SwiftUI's `Text("...")` / `Button("...")` translate by themselves; for a plain string in
`Core/` use `tr("...")` or `trf("... %lld ...", n)`.

## Sync
Settings > Sync signs in to the same sync server the other StreamBoss apps use (`server/`). **My List** and **where you
stopped watching** are kept in step with your phone, tablet and computer apps, in both directions, with the same merge rules
(a title added on one device and another removed on a second both stay applied). On the first screen, **Use my sync
account** lists the sources saved on your other devices; pick one and type its password (passwords never leave a device).
Only the address, the login name and the sync token are sent, never a provider password. The logic is in `Core/Sync.swift`
(tested with `swift test`, with a stand-in server); `App/SyncApi.swift` is the HTTP part.

## Limits
- AVPlayer plays HLS and MP4 only. MKV and raw MPEG-TS streams will not play on Apple TV.
- No TMDB metadata, EPG, search, channel zapping or shaders yet.
- The SwiftUI layer is built in CI for the tvOS simulator and the Core logic is tested on Linux, but nobody has run it on an Apple TV yet.
