# StreamBoss for Roku

**Install and use guide, wireframes and layout: [docs/ROKU.md](../docs/ROKU.md).**

Roku does not run Flutter, so this is a native SceneGraph / BrightScript channel.
It is a player only: you supply your own Xtream or M3U provider.

## Features
- Xtream Codes or M3U playlist, entered with the on-screen keyboard (stored in the channel registry)
- Tabs: Live, Movies, Series (episodes), My List, Search, Settings, with category columns
- `*` (Options button) adds/removes My List entries
- Resume position for movies/episodes; Up/Down zap channels while watching live TV
- Demo mode with public test streams
- Sync with your own sync server (Settings > Sign in to sync, or "Use my sync account" on the first screen): My List and
  resume positions are kept in step with the other StreamBoss apps, and the sources saved on your other devices are listed
  on the first screen (address and login name only, you type the password). The logic is in `components/lib/Sync.brs`,
  tested with `brs-cli components/lib/Common.brs components/lib/Strings.brs components/lib/Sync.brs tests/sync.test.brs`
- English, Spanish, Italian and Portuguese: it follows the Roku's language, or choose one in Settings > Language
  (Device language, English, Español, Italiano, Português). Texts are in `i18n/strings.json`;
  `python3 tool/roku_i18n.py` compiles them into `components/lib/Strings.brs` and CI checks every text has all three
  translations. In code write `L("English text")`, or `LF("{n} results", { n: 3 })` when it holds a value.

## Limits (compared with the Flutter app)
- No TMDB metadata, EPG guide, subtitle styling or shaders
- Roku's registry caps a channel at 32 KB, so My List keeps 200 entries (25 of them also stored whole, so it works before the library loads; the rest are found in the library) and resume history 150. When a synced list is longer, the newest entries are kept here and the others stay on the server
- Roku plays HLS, MP4 and (some) MKV/TS; formats it can't decode will show a playback error

## Develop
```sh
npm i -g brighterscript brs-node
bsc --project bsconfig.json --copyToStaging=false --createPackage=false     # compile + lint
brs-cli components/lib/Common.brs tests/common.test.brs                      # logic tests
```
The UI itself has not been exercised on a real device or emulator yet.

## Sideload
Enable developer mode on the Roku (Home x3, Up x2, Right, Left, Right, Left, Right), then:
```sh
zip -r ../streamboss-roku.zip manifest source components images
# upload the zip at http://<roku-ip> (user: rokudev)
```
The icon/splash PNGs in `images/` are plain placeholders; replace them before publishing.
Publishing to the Channel Store needs a Roku developer account and certification.
