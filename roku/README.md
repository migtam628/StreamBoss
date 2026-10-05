# StreamBoss for Roku

Roku does not run Flutter, so this is a native SceneGraph / BrightScript channel.
It is a player only: you supply your own Xtream or M3U provider.

## Features
- Xtream Codes or M3U playlist, entered with the on-screen keyboard (stored in the channel registry)
- Tabs: Live, Movies, Series (episodes), My List, Search, Settings, with category columns
- `*` (Options button) adds/removes My List entries
- Resume position for movies/episodes; Up/Down zap channels while watching live TV
- Demo mode with public test streams

## Limits (compared with the Flutter app)
- No TMDB metadata, EPG guide, subtitle styling or shaders
- Roku's registry caps a channel at 32 KB, so My List holds 40 items and resume history 80
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
