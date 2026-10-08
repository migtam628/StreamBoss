# StreamBoss icons

The four app icons (Crown, Bold B, Signal, Screen) are drawn in `make_icons.mjs`: every mark, the stroked
"STREAMBOSS" wordmark, the TV banners and the output sizes for each platform. The result is committed, so a
normal build never runs it:

```sh
NODE_PATH=<folder containing playwright> node design/make_icons.mjs
```

It needs Node and Playwright (Chromium renders the SVGs). `design/icons/*.svg` are the drawings, for people.

| Output | Used by |
|---|---|
| `tool/android_res/` | Android: adaptive launcher icons (with a one-color layer for themed icons), round icons and the TV banner for each icon; `ic_launcher` and `banner` are the default (Crown). Copied into the generated project by `tool/patch_android.dart`. |
| `tool/icons/ios`, `mac`, `windows`, `web` | The Flutter default icon is replaced in those generated projects by `tool/patch_icons.dart`. |
| `assets/app_icons/` | The picker in Settings > Appearance > App icon, and the macOS Dock icon. |
| `roku/images/` | The Roku channel icons and splash screen. |

To add a fifth icon: add it to `MARKS` here, to `_iconNames` and `iconNames` in `tool/patch_android.dart`, and to
`AppIcon` in `lib/services/app_icon.dart`; `test/app_icon_test.dart` fails if any of them disagree.
