# Changelog

Every feature or fix gets its own version, newest first. The heading is the git tag without the `v`
(`## 0.2.3` is tag `v0.2.3`) and its section becomes that release's notes. Betas look like `0.3.0b2`
and sort before their final release. See "Versioning" in README.md.

## 0.3.0b12 - 2026-10-09
- **Better search.** Several words in any order, the start of a word, accents and punctuation ignored, and a small typo forgiven ("nigth" finds "Night"). Results are grouped into Channels, Movies and Series with counts and ranked by how well they match (your My List and recent watches edge ahead). A Filters panel sorts by best match, A to Z or rating, narrows to a rating, and to a category once you pick Channels, Movies or Series. Recent searches come back as chips, per profile.
- **Duplicate channel merging.** When a channel is listed several times (HD, SD, 4K, a backup), the app shows one entry, the best copy that is not known to be offline. If it will not play, or does not start within 15 seconds, the player moves on to the next copy by itself ("Trying another copy of ..."). "US: Fox" and "UK: Fox", and "Sports 1" and "Sports 2", stay separate. Settings > Library & guide > Merge duplicate channels turns it off.
- **Live rewind.** Pause and rewind a live channel as far as the player has kept (about a minute on a TV box, more on a phone or computer): Left and Right on the remote, or the buttons. The top of the controls shows how far behind live you are, and Back to live returns. A channel that keeps nothing says so.
- **Catch-up.** On Xtream channels that keep an archive, Catch-up in the live player lists the last programmes, and the guide offers "Watch from the start" or "Watch from the archive" on a programme. Times are written in the provider's own clock. Not tried against a real provider yet: tell me if a provider's archive does not play.
- **Programme details.** Selecting a programme in the guide that is not on now (or holding OK / long-pressing any) shows its description from the guide, its time and length, and what you can do with it. The guide now loads the last day, for catch-up.
- **Quick channel switcher.** The Channels button (or the C key) in the live player lists every channel in the list you are zapping through, with a filter by name or number.
- **Chapters.** Movies and episodes with chapters get a Chapters list, and a Skip intro or Skip credits button when the chapter playing is named like one (press OK to take it).
- **Collections.** Make your own lists like "Friday movie night" (Add to collection on a movie or series page; Settings > Library & guide > Collections to manage them). They show as shelves on Home. Per profile.
- **Picked for you.** A Home shelf of movies and series you have not seen, chosen from what you watched and saved: the same categories, sequels and titles that share a word, and a lift for good ratings ("Because you watched ...").
- **Real posters.** With a TMDB key, movies and series that came without a poster get one from TMDB (three lookups at a time, remembered). Settings > Network & metadata > Fill in missing posters.
- **Fix:** programme times in the guide and the layouts that show them were written in UTC. They now show in the device's time zone.

## 0.3.0b11 - 2026-10-09
- **Channel check.** Settings > Source & library > Check live channels tests every channel and remembers the ones that do not answer (an error page, a 404, nothing back, a timeout). They show as OFFLINE in the Live list, and "Hide offline channels" removes them everywhere. It reads only the first couple of kilobytes of each stream and hangs up straight away. On a provider login it checks two at a time, because logins limit how many streams may be open; on a public list it checks ten. Apps only: a browser cannot read other sites' streams.
- **Profiles and a PIN lock.** Settings > Profiles & PIN. Each profile keeps its own My List, history and resume positions (the first one, Main, keeps everything you already had). A **Kids** profile shows only categories that look made for children, by name. With more than one profile the app asks "Who's watching?" when it starts. Set a four-digit PIN to lock Settings while a Kids profile is in use, to ask for it when leaving a Kids profile, and to lock any profile you choose. Five wrong tries lock the PIN for 30 seconds. It is a family lock for a shared screen, not high security.
- **Live pictures.** Cable Box shows the channel behind its big number, and every Mosaic tile plays its channel (only the tile with the sound is audible; on a phone only the big tile plays). They play only while you can see them, wait a moment after you change channel, and fall back to the old look if anything fails. Settings > Appearance > Live pictures turns them off.
- **Gzipped guides.** `.xml.gz` XMLTV guides are unpacked and read in the background, so large guides load faster and more providers' guides work.
- Free-list and provider fix from 0.3.0b10 is unchanged.

## 0.3.0b10 - 2026-10-08
- Fix: the free public channels (and any other `https://` playlist or provider) failed on phones, tablets, TVs and desktops with "Invalid request method". The connection helper that tries IPv4 first handed Dart a plain socket and never started TLS, so servers received unencrypted data on port 443 and refused it. HTTPS now does its TLS handshake. Plain `http://` addresses and the web build were not affected.
- A test now runs a real local HTTPS server so this cannot come back.

## 0.3.0b9 - 2026-10-08
- A new app icon and logo, with four to choose from: **Crown**, **Bold B**, **Signal** and **Screen**. Settings > Appearance > App icon changes the icon of the installed app whenever you like.
  - Android and Android TV: the launcher icon switches for real (adaptive icons, a one-color layer for Android 13 themed icons, and a matching TV and Fire TV banner for each). Your launcher can take a few seconds to show the change, and a few of them close the app for a moment.
  - macOS: the Dock icon changes, and is set again every time the app starts.
  - iOS, Windows, Linux, the web, tvOS and Roku cannot change their icon while the app runs, so they get the Crown icon in place of the Flutter default. The Roku icon and splash screen are new too.
- The default icon on a fresh install is Crown.
- The drawings and the script that makes every size are in `design/`.

## 0.3.0b8 - 2026-10-08
- Type a channel number. While watching live TV with a channel list, press digits on the remote or keyboard (2, 0, 7) and the player jumps to channel 207 when you pause, or at once on OK. A number with no channel says so.
- Last channel. A Last channel button in the player (and the L key, or the Last key on remotes that have one) goes back to the channel before this one.
- Play the next episode. When an episode ends, "Up next" counts down from 10 and starts the following episode, with Play now and Cancel. Turn it off in Settings > Playback > Play the next episode.
- Picture shape. A new player button cycles Auto, 16:9, 4:3, Fill the screen and Stretch, and remembers the choice (also in Settings > Playback > Picture shape). On Android TV's hardware surface output the device may ignore the shape.
- Account info. For Xtream sources, Settings > Source & library > Account shows the status, the expiry date with the days left (highlighted in the last week) and how many connections are in use.
- Free channels that need a Referer, User-Agent or Origin header (iptv-org lists name them in `#EXTVLCOPT` lines, about 6% of channels) now send them, so they can play.
- A Test connection button on the connect screen checks the address without logging in: DNS, each address, a connection and one request. Handy for telling a network problem from a wrong address.

## 0.3.0b7 - 2026-10-08
- Three more layouts join the twelve in Settings > Appearance > Layout (now fifteen cards): **Orbit**, **Mood** and **Mosaic**.
  - Orbit puts the sections on a big dial: Live, Movies, Series, Guide, My list, Search and Settings. Left and Right (or a swipe, or a tap on a label) spin it, Up and Down pick one of the titles fanned out beside it, and OK opens that title or, with none picked, the section. On a phone the dial rises from the bottom and a slim bar returns to it from inside a section.
  - Mood asks "What are you in the mood for?" and offers six pills: Something live, A movie night (best rated first), A short watch (series), Keep watching, Kids (categories named kids, family, cartoon and the like) and Surprise me. The picked pill shows a shelf. A mood the library cannot fill says so instead of showing a wrong shelf.
  - Mosaic shows four channel tiles at once, with the sound marked on the focused one, a tray to choose which channel fills it, and OK for full screen. The tiles show each channel and what is on, not live video: four streams at once needs more decoders than most TV sticks have. On a phone it is one big tile with a strip of the other three.
- Each has a picker wireframe, phone navigation and tests.

## 0.3.0b6 - 2026-10-06
- Three more layouts join the nine in Settings > Appearance > Layout (now twelve cards): **Glass**, **Bento** and **Library**.
  - Glass puts frosted panels over a soft colored backdrop, with a dock at the bottom for navigation (on a phone the bottom bar floats). Home is a frosted feature panel, a Live now panel, a Continue panel and the usual shelves. On a phone and desktop the panels blur what is behind them; on a TV they use a translucent fill only, because blur is costly on weak sticks.
  - Bento makes Home a board of flat colored tiles: Continue, Live now (with now and next), your library at a glance, My list, a strip of what is on now, and search. Tiles share the screen on a TV and stack on a phone. The navigation is a row of flat blocks.
  - Library is laid out like a media server: a tree of screens with counts on the left, a thin breadcrumb on top, and dense rows (poster, title, kind, rating, progress) on Home. Live, Movies and Series use the category list with a details pane.
- Each layout has a wireframe card in the picker.

## 0.3.0b5 - 2026-10-06
- Three more layouts join the six in Settings > Appearance > Layout (now nine cards): **Daylight**, **Cable Box** and **Index**.
  - Daylight is the first light layout: soft grey ground, white cards and one green accent. It has a feature card, a Live now row of channel cards with progress, and the usual shelves. The focus ring turns black so it still stands out on white. The whole app follows the light palette, including Settings, the connect screen and the guide.
  - Cable Box opens on the last channel you watched with a big channel number and a banner showing what is on now and next. Up and Down (or a swipe on a phone) change channel, Right reaches the categories and the nearby channels, and OK plays full screen. Guide, Channels, Movies, Series, Search and Settings are labeled keys under the banner. This screen shows the banner, not live video; the picture opens in the player.
  - Index is text first: Home is a list of very large words (Live now, Continue, Movies, Series, Guide, Settings) with counts. On a TV the highlighted word shows what is inside it on the right, with one thumbnail. On a phone the word opens in place and a slim bar returns to the list. It loads no poster wall on Home, so it is the lightest layout.
- The phone's More sheet now uses each layout's own names for screens.

## 0.3.0b4 - 2026-10-06
- Free public channels: when several lists are added and none loads, the error now says why (for example "Couldn't look up 'iptv-org.github.io'" or "Playlist returned 403") instead of only "None of the N playlists could be loaded".

## 0.3.0b3 - 2026-10-06
- Free public channels. The connect screen (and Settings > Source > Add free public channels) now opens a browser of the public iptv-org and Free-TV playlist directories. Pick one list, several, or Select all on a tab: Categories, Countries (loaded from iptv-org, with search), Languages, and More (the whole iptv-org index, Free-TV and similar). Your picks are downloaded in parallel, combined, de-duplicated and saved as one source, and a list that fails to load is skipped instead of failing the rest. Very large picks ask first, because they can take a minute on a phone or a TV stick.
- A source can now hold several playlist addresses (one per line); they load as one library. Pasting any M3U link of your own still works as before.
- These are volunteer-maintained public lists of free-to-air channels. StreamBoss does not host, check or vouch for them, and the screen says so. Many streams are region-locked or offline.
- The setup wizard's last step mentions the free channels option.

## 0.3.0b2 - 2026-10-06
- Three more layouts join the three from the first beta, in Settings > Appearance > Layout (now six cards): **Prime Time**, **Coverflow** and **Hub**.
  - Prime Time: the TV guide is Home. The details of the highlighted programme (channel, title, time left) sit above the time grid. Live uses the channel list with a details pane, Movies and Series use poster grids.
  - Coverflow: one big title in the middle with its neighbors fanned out. Left and Right (or a swipe) flip through them and OK plays. It is used for Home, Movies, Series and Live, with category chips on top.
  - Hub: Home is a launcher of big colored tiles (Live TV, Movies, Series, Guide, Favorites, Search, Settings) with Continue watching underneath. Inside a section a bar takes you back to the Hub, and Back always returns to it. A new My list page opens from the Favorites tile.
- First-run setup. On a device with no saved provider the app now opens a short wizard: what the app is, your screen (TV mode, text size, TV zoom), the layout, playback defaults (audio language, subtitles) and then the connect screen. Every choice applies as you make it, it can be skipped at any step, and Settings > About > Run setup again opens it later. People who already have a provider never see it.
- The guide uses the selected layout's colors.

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
