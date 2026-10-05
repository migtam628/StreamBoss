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
- Live TV, Movies, Series (with episodes), categories, search
- Home shelves: Continue watching, My List (long-press / hold select to favorite)
- Playback via media_kit (libmpv): MKV, TS, HLS, MP4
- Keyboard / D-pad / remote navigation with visible focus rings

## Develop

Platform folders are generated, not committed:

```sh
flutter create . --project-name streamboss --org com.streamboss
flutter pub get
flutter run -d <device>
flutter test
```

Android TV / Fire TV: add `<uses-feature android:name="android.software.leanback" android:required="false"/>`,
`<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>` and a
`android.intent.category.LEANBACK_LAUNCHER` intent filter to `android/app/src/main/AndroidManifest.xml`.
Android/Fire TV also need the INTERNET permission in release builds (flutter create adds it for debug only).

## Status / roadmap

This is a first scaffold, written without a Flutter SDK available, so it has **not been compiled or run yet**.
CI (`.github/workflows/build.yml`) will be the first real check. Next: TMDB metadata, subtitle/audio track
picker, channel zapping, EPG, secure credential storage (credentials are currently in shared_preferences),
tvOS, Roku parity.
