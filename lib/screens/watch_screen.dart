import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../layouts/ui_layout.dart';
import '../l10n/l10n.dart';
import '../models/media.dart';
import '../services/crash_guard.dart';
import '../services/details_logic.dart';
import '../services/mini_player.dart';
import '../services/mpv_props.dart';
import '../services/nav_guard.dart';
import '../services/play_choices.dart';
import '../services/provider_url.dart';
import '../services/tmdb.dart';
import '../services/watch_logic.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../widgets/collections_sheet.dart';
import '../widgets/details_kit.dart';
import '../widgets/net_image.dart';
import '../widgets/play_options.dart' show clock;
import '../widgets/screensaver.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'series_screen.dart';

/// The watch page: the video in the page, what it is underneath, and a column of what to watch next beside it
/// (stacked under it on a narrow screen). It plays movies and episodes; the full-screen player stays one tap
/// away and takes over the same running video. TVs, live channels and catch-up keep the full-screen player.
class WatchScreen extends StatefulWidget {
  /// The movie or episode that plays first.
  final MediaItem item;
  final String title;
  final Duration? startAt;
  final PlayChoices? choices;

  /// For an episode: the series it belongs to and all of its episodes, in order.
  final MediaItem? series;
  final List<WatchEpisode>? episodes;

  /// For tests: where the details come from, and a stand-in for the video (no player is started then).
  final Future<TmdbInfo?> Function()? loadInfo;
  final Widget? stage;
  const WatchScreen({
    super.key,
    required this.item,
    required this.title,
    this.startAt,
    this.choices,
    this.series,
    this.episodes,
    this.loadInfo,
    this.stage,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  late final SettingsState _settings = context.read<SettingsState>();
  late final AppState _app = context.read<AppState>();

  Player? _player;
  VideoController? _controller;
  final _subs = <StreamSubscription>[];
  Timer? _hideTimer, _saveTimer, _nextTimer;
  final _focus = FocusNode(debugLabel: 'watch-root');

  late MediaItem _cur = widget.item;
  late Future<TmdbInfo?> _info = _load(widget.series ?? widget.item);
  int?
      _season; // the season the episode list shows; null follows the episode playing

  List<QualityChoice> _quality = const []; // what the stream offers (empty for a plain file)
  VideoTrack? _track; // the picture size the player has selected
  bool _pausedByLeave = false; // paused because the tab or window was hidden
  bool _playing = true,
      _buffering = true,
      _controls = true,
      _full = false,
      _more = false;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  double _volume = 100, _lastVolume = 100;
  double? _drag; // the seek bar while it is being dragged (0 to 1)
  String? _error;
  WatchEpisode? _upNext;
  int _nextIn = 0;

  bool get _hasPlayer => widget.stage == null;
  bool get _isEpisode => widget.series != null && widget.episodes != null;
  WatchEpisode? get _episode {
    for (final e in widget.episodes ?? const <WatchEpisode>[]) {
      if (e.item.key == _cur.key) return e;
    }
    return null;
  }

  Future<TmdbInfo?> _load(MediaItem of) =>
      widget.loadInfo?.call() ?? loadDetails(context, of);

  @override
  void initState() {
    super.initState();
    Screensaver.busy.value++;
    // Only one stream at a time: a mini player running something else stops when a player opens.
    if (_hasPlayer && MiniPlayer.instance.active) {
      scheduleMicrotask(MiniPlayer.instance.close);
    }
    // Into the history once the page is up (it tells the rest of the app, which cannot happen while building).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _app.markWatched(_cur);
    });
    if (!_hasPlayer) return;
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable().catchError((_) {});
    final p = Player(
        configuration: PlayerConfiguration(
            logLevel: MPVLogLevel.warn,
            bufferSize: _settings.isTv ? 16 * 1024 * 1024 : 32 * 1024 * 1024));
    _player = p;
    _controller = VideoController(p,
        configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: _settings.decoder != 'software'));
    _subs.addAll([
      p.stream.playing.listen((v) => _set(() => _playing = v)),
      p.stream.buffering.listen((v) => _set(() => _buffering = v)),
      p.stream.duration.listen((v) => _set(() => _dur = v)),
      p.stream.position.listen((v) {
        if (!mounted || _full) return;
        // The seek bar moves a few times a second; repaint only when the shown second changes.
        if (v.inSeconds != _pos.inSeconds && _drag == null) {
          setState(() => _pos = v);
        }
        if (_error != null && v > Duration.zero) setState(() => _error = null);
      }),
      p.stream.volume.listen((v) => _set(() => _volume = v)),
      p.stream.tracks.listen((t) => _set(() => _quality = qualityChoices(t.video))),
      p.stream.track.listen((t) => _set(() => _track = t.video)),
      p.stream.error.listen((e) {
        CrashGuard.log('error ${redactUrls(e)}');
        _set(() => _error = redactUrls(e));
      }),
      p.stream.completed.listen((done) {
        if (done && !_full && mounted) _offerNext();
      }),
    ]);
    _saveTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    _start();
    _scheduleHide();
  }

  void _set(VoidCallback f) {
    if (mounted && !_full) setState(f);
  }

  Future<void> _start() async {
    final p = _player!;
    try {
      await applyBuffer(p, _settings.bufferSecs);
      await applyPlaybackPrefs(
        p,
        audioLang: widget.choices?.audioLang ?? _settings.audioLang,
        subLang: widget.choices?.subLang ?? _settings.subLang,
        subsOn: widget.choices?.subsOn ?? _settings.subsOn,
        userAgent: _settings.userAgent,
      );
      await p.open(Media(_cur.streamUrl!,
          start: widget.startAt, httpHeaders: _cur.headers));
      final speed = widget.choices?.speed ?? _settings.speed;
      if (speed != 1) await p.setRate(speed);
    } catch (e) {
      CrashGuard.log('exception ${redactUrls('$e')}');
      _set(() => _error = redactUrls('$e'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = _player;
    if (p == null || _full) return; // the full player looks after itself
    switch (leaveAction(state: state, enabled: _settings.pauseOnLeave, playing: p.state.playing, pausedByUs: _pausedByLeave)) {
      case LeaveAction.pause:
        _pausedByLeave = true;
        p.pause();
      case LeaveAction.resume:
        _pausedByLeave = false;
        p.play();
      case LeaveAction.none:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Screensaver.busy.value--;
    _savePosition(notify: true);
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _nextTimer?.cancel();
    _focus.dispose();
    if (_hasPlayer) {
      WakelockPlus.disable().catchError((_) {});
      _player?.dispose();
    }
    super.dispose();
  }

  void _savePosition({bool notify = false}) {
    final p = _player;
    if (p == null) return;
    _app.savePosition(_cur, p.state.position, p.state.duration, notify: notify);
  }

  // --- Playing --------------------------------------------------------------------------------------------

  /// Plays [it] in the page. A movie from "More like this" brings its own details; an episode keeps the series'.
  Future<void> _switchTo(MediaItem it, {Duration? at}) async {
    if (it.streamUrl == null) return;
    _savePosition();
    _nextTimer?.cancel();
    final startAt = at ?? (_settings.autoResume ? _app.resumeFor(it) : null);
    setState(() {
      if (!_isEpisode && it.key != _cur.key) _info = _load(it);
      _cur = it;
      _upNext = null;
      _error = null;
      _quality = const [];
      _pos = startAt ?? Duration.zero;
      _dur = Duration.zero;
      _season = null;
    });
    _app.markWatched(it);
    final p = _player;
    if (p == null) return;
    try {
      await p
          .open(Media(it.streamUrl!, start: startAt, httpHeaders: it.headers));
    } catch (e) {
      CrashGuard.log('exception ${redactUrls('$e')}');
      _set(() => _error = redactUrls('$e'));
    }
  }

  WatchEpisode? _after(MediaItem it) {
    final eps = widget.episodes;
    if (eps == null) return null;
    final at = eps.indexWhere((e) => e.item.key == it.key);
    return at >= 0 && at + 1 < eps.length ? eps[at + 1] : null;
  }

  /// The episode ended: the next one starts after a short countdown the viewer can cancel.
  void _offerNext() {
    _savePosition(notify: true);
    final n = _after(_cur);
    if (n == null || !_settings.autoplayNext) return;
    setState(() {
      _upNext = n;
      _nextIn = 10;
    });
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_nextIn <= 1) {
        t.cancel();
        _playUpNext();
      } else {
        setState(() => _nextIn--);
      }
    });
  }

  void _playUpNext() {
    final n = _upNext;
    _nextTimer?.cancel();
    if (n != null) _switchTo(n.item, at: Duration.zero);
  }

  void _cancelUpNext() {
    _nextTimer?.cancel();
    setState(() => _upNext = null);
  }

  void _togglePlay() => _player?.playOrPause();

  void _seekBy(int secs) {
    final p = _player;
    if (p == null) return;
    var to = p.state.position + Duration(seconds: secs);
    if (to < Duration.zero) to = Duration.zero;
    if (_dur > Duration.zero && to > _dur) to = _dur;
    p.seek(to);
    _showControls();
  }

  void _toggleMute() {
    final p = _player;
    if (p == null) return;
    if (_volume > 0) {
      _lastVolume = _volume;
      p.setVolume(0);
    } else {
      p.setVolume(_lastVolume > 0 ? _lastVolume : 100);
    }
  }

  /// Opens the full-screen player on the video that is already running. The page takes it back when that closes.
  Future<void> _fullScreen() async {
    final p = _player, c = _controller;
    if (p == null || c == null || !NavGuard.allow()) return;
    _savePosition();
    // The page lets go of the picture first: a video can be on one screen at a time, which matters in a browser.
    setState(() => _full = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final eps = widget.episodes;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        title: _cur.name,
        url: _cur.streamUrl!,
        item: _cur,
        episodes: eps == null ? null : [for (final e in eps) e.item],
        adopt:
            MiniSession(player: p, controller: c, item: _cur, title: _cur.name),
        lent: true,
        onItem: (it, _) => _cur = it,
      ),
    ));
    if (!mounted) return;
    final st = p.state;
    setState(() {
      _full = false;
      _playing = st.playing;
      _buffering = st.buffering;
      _dur = st.duration;
      _pos = st.position;
      _season = null;
      _error = null;
    });
    _showControls();
  }

  // --- Controls -------------------------------------------------------------------------------------------

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void _showControls() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final secs = _settings.controlsHideSecs;
    if (secs <= 0) return;
    _hideTimer = Timer(Duration(seconds: secs), () {
      if (mounted && _playing && _drag == null && _controls) {
        setState(() => _controls = false);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent || _player == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-_settings.seekSecs);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(_settings.seekSecs);
    } else if (k == LogicalKeyboardKey.keyF) {
      _fullScreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else {
      return KeyEventResult.ignored;
    }
    _showControls();
    return KeyEventResult.handled;
  }

  // --- Building -------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = isWatchWide(size.width);
    final pinned = !wide &&
        size.height >
            size.width; // a phone held upright keeps the video on top while the page scrolls
    final heading = watchHeading(
        item: _cur, series: widget.series, episode: _episode?.episode);
    final app = context.watch<AppState>();

    final main = _Main(
      heading: heading,
      info: _info,
      item: _cur,
      series: widget.series,
      more: _more,
      onMore: () => setState(() => _more = !_more),
      onOpenDetails: _openDetails,
      onSwitch: _switchTo,
    );
    final side = _Side(
      item: _cur,
      series: widget.series,
      episodes: widget.episodes,
      season: _season ?? seasonOfItem(widget.episodes ?? const [], _cur.key),
      onSeason: (s) => setState(() => _season = s),
      onEpisode: (e) => _switchTo(e.item),
      onMovie: _switchTo,
      app: app,
    );

    final top = _TopBar(
        title: heading.title, onBack: () => Navigator.of(context).maybePop());
    final Widget body;
    if (wide) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 32),
              children: [_stage(p), main]),
        ),
        SizedBox(
            width: size.width >= 1300 ? 440 : 380,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 20, 32),
                children: [side])),
      ]);
    } else if (pinned) {
      body = Column(children: [
        _stage(p),
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [main, const SizedBox(height: 8), side])),
      ]);
    } else {
      body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [_stage(p), main, const SizedBox(height: 8), side]);
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(child: Column(children: [top, Expanded(child: body)])),
      ),
    );
  }

  Widget _stage(LayoutPalette p) {
    final st = _settings;
    Widget video;
    if (widget.stage != null) {
      video = widget.stage!;
    } else if (_full) {
      video = const SizedBox.expand();
    } else {
      video = Video(
        controller: _controller!,
        controls: NoVideoControls,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          style: TextStyle(
            fontSize: (st.subSize * 0.6).clamp(14.0, 40.0),
            fontWeight: st.subBold ? FontWeight.w700 : FontWeight.w400,
            height: 1.4,
            color: Color(st.subColor),
            backgroundColor: st.subBackground ? const Color(0xAA000000) : null,
          ),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 44),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
              MediaQuery.sizeOf(context).width >= watchWideFrom ? 14 : 0),
          child: MouseRegion(
            onHover: (_) => _showControls(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_touch) {
                  _controls
                      ? setState(() => _controls = false)
                      : _showControls();
                } else {
                  _togglePlay();
                  _showControls();
                }
              },
              onDoubleTap: _fullScreen,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(fit: StackFit.expand, children: [
                  video,
                  if (_hasPlayer && _buffering && _error == null && !_full)
                    const Center(child: CircularProgressIndicator()),
                  if (_error != null) _errorBanner(),
                  if (_upNext != null) _upNextCard(p),
                  if (_hasPlayer) _controlBar(p),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() => Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.black87, borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('This did not play.'),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      );

  Widget _upNextCard(LayoutPalette p) {
    final n = _upNext!;
    return Positioned(
      right: 12,
      bottom: 52,
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
            color: Colors.black87, borderRadius: BorderRadius.circular(10)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(trf('Next episode in {n}', {'n': _nextIn}),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 2),
              Text('${episodeTag(n.episode)} · ${n.episode.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton(
                    onPressed: _playUpNext, child: Text(tr('Play now'))),
                const SizedBox(width: 8),
                TextButton(onPressed: _cancelUpNext, child: Text(tr('Cancel'))),
              ]),
            ]),
      ),
    );
  }

  Widget _controlBar(LayoutPalette p) {
    final value = _drag ??
        (_dur.inMilliseconds > 0
            ? (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0);
    final shown = _drag == null
        ? _pos
        : Duration(milliseconds: (_dur.inMilliseconds * _drag!).round());
    final narrow = MediaQuery.sizeOf(context).width < 520;
    Widget icon(IconData i, String tip, VoidCallback f) => IconButton(
          icon: Icon(i, color: Colors.white),
          tooltip: tip,
          onPressed: () {
            f();
            _showControls();
          },
          visualDensity: VisualDensity.compact,
        );
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls || !_playing ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 18, 6, 2),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000)]),
            ),
            child: Row(children: [
              icon(_playing ? Icons.pause : Icons.play_arrow,
                  _playing ? tr('Pause') : tr('Play'), _togglePlay),
              if (!narrow)
                icon(Icons.replay_10, '-${_settings.seekSecs}s',
                    () => _seekBy(-_settings.seekSecs)),
              if (!narrow)
                icon(Icons.forward_10, '+${_settings.seekSecs}s',
                    () => _seekBy(_settings.seekSecs)),
              Text('${clock(shown)} / ${clock(_dur)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()])),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: p.accent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: p.accent,
                  ),
                  child: Slider(
                    value: value,
                    onChanged: _dur > Duration.zero
                        ? (v) => setState(() => _drag = v)
                        : null,
                    onChangeEnd: (v) {
                      _player?.seek(Duration(
                          milliseconds: (_dur.inMilliseconds * v).round()));
                      setState(() {
                        _pos = Duration(
                            milliseconds: (_dur.inMilliseconds * v).round());
                        _drag = null;
                      });
                      _showControls();
                    },
                  ),
                ),
              ),
              if (_quality.isNotEmpty) _qualityMenu(),
              icon(_volume <= 0 ? Icons.volume_off : Icons.volume_up,
                  _volume <= 0 ? tr('Unmute') : tr('Mute'), _toggleMute),
              icon(Icons.fullscreen, tr('Full player'), _fullScreen),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _qualityMenu() => PopupMenuButton<QualityChoice>(
        tooltip: tr('Quality'),
        icon: const Icon(Icons.settings, color: Colors.white),
        iconSize: 22,
        padding: EdgeInsets.zero,
        onOpened: _showControls,
        onSelected: (c) {
          _player?.setVideoTrack(c.track ?? VideoTrack.auto());
          _showControls();
        },
        itemBuilder: (_) => [
          for (final c in _quality)
            CheckedPopupMenuItem(
              value: c,
              checked: qualityIsCurrent(c, _track),
              child: Text(c.track == null ? tr('Auto') : c.label),
            ),
        ],
      );

  void _openDetails() {
    if (!NavGuard.allow()) return;
    _player?.pause();
    final s = widget.series;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            s != null ? SeriesScreen(series: s) : DetailScreen(item: _cur)));
  }
}

// --- The pieces of the page -----------------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return SizedBox(
      height: 48,
      child: Row(children: [
        const SizedBox(width: 6),
        IconButton(
            icon: Icon(Icons.arrow_back, color: p.text),
            tooltip: tr('Back'),
            onPressed: onBack),
        Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600))),
        const SizedBox(width: 16),
      ]),
    );
  }
}

/// A small rounded button for the actions under the video.
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool on;
  const _Pill(this.icon, this.label, {this.onTap, this.on = false});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    return Material(
      color: on ? p.accent.withValues(alpha: 0.18) : p.wash(0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: on ? p.accent : p.text),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    color: p.text, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

/// Under the video: the title, the facts, the actions and the information card.
class _Main extends StatelessWidget {
  final ({String title, String? subtitle}) heading;
  final Future<TmdbInfo?> info;
  final MediaItem item;
  final MediaItem? series;
  final bool more;
  final VoidCallback onMore, onOpenDetails;
  final void Function(MediaItem) onSwitch;
  const _Main({
    required this.heading,
    required this.info,
    required this.item,
    required this.series,
    required this.more,
    required this.onMore,
    required this.onOpenDetails,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final s = context.watch<AppState>();
    final subject = series ?? item;
    final versions =
        series == null ? versionsOf(item, s.shown.movies) : const <MediaItem>[];
    final watched = s.isWatched(item);
    final fav = s.isFavorite(subject);

    return FutureBuilder<TmdbInfo?>(
      future: info,
      builder: (context, snap) {
        final t = snap.data;
        final overview = (t?.overview?.isNotEmpty ?? false)
            ? t!.overview!
            : (subject.plot ?? '');
        final rating = t?.rating?.toStringAsFixed(1) ?? subject.rating;
        final facts = [
          if (t?.year != null) t!.year!,
          if (t?.runtimeMin != null && t!.runtimeMin! > 0)
            formatRuntime(t.runtimeMin!),
          if (rating != null && rating != '0' && rating != '0.0') '★ $rating',
          if (t?.certification != null) t!.certification!,
          qualityTagOf(item.name) ?? t?.tech?.resolution,
        ].whereType<String>().toList();
        final long = overview.length > 260;

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(heading.title,
              style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2)),
          if (heading.subtitle != null)
            Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(heading.subtitle!,
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600))),
          if (facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(facts.join('  ·  '),
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Pill(fav ? Icons.favorite : Icons.favorite_border,
                fav ? tr('In My list') : tr('My list'),
                on: fav, onTap: () => s.toggleFavorite(subject)),
            _Pill(watched ? Icons.check_circle : Icons.check_circle_outline,
                watched ? tr('Mark not watched') : tr('Mark watched'),
                on: watched, onTap: () => s.setWatched([item], !watched)),
            _Pill(
                Icons.collections_bookmark_outlined,
                s.collections.values.any((l) => l.contains(subject.key))
                    ? tr('In a collection')
                    : tr('Collection'),
                onTap: () => showCollectionsSheet(context, subject)),
            if (versions.isNotEmpty)
              PopupMenuButton<MediaItem>(
                tooltip: tr('Other copies'),
                onSelected: onSwitch,
                itemBuilder: (_) => [
                  for (final v in versions)
                    PopupMenuItem(
                        value: v,
                        child: Text(qualityTagOf(v.name) ?? v.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                child: IgnorePointer(
                    child: _Pill(Icons.layers_outlined, tr('Other copies'))),
              ),
            if (t?.trailerKey != null)
              _Pill(Icons.ondemand_video, tr('Trailer'),
                  onTap: () => launchUrl(
                      Uri.parse(
                          'https://www.youtube.com/watch?v=${t!.trailerKey}'),
                      mode: LaunchMode.externalApplication)),
            _Pill(Icons.info_outline, tr('Details'), onTap: onOpenDetails),
          ]),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.line)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                overview.isEmpty
                    ? tr('No description from your provider yet.')
                    : overview,
                maxLines: more || !long ? null : 4,
                overflow: more || !long ? null : TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: 14, height: 1.45),
              ),
              if (long)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: onMore,
                      child: Text(more ? tr('Show less') : tr('Show more'))),
                ),
              if (t != null && t.genres.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final g in t.genres)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: p.wash(0.08),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(g,
                          style: TextStyle(color: p.text, fontSize: 12)),
                    ),
                ]),
              ],
              if (t != null && t.directors.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('${tr('Directed by')} ${t.directors.join(', ')}',
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ],
              if (t != null && t.people.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(t.people.take(6).map((x) => x.name).join(', '),
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

/// Beside the video: an episode's season and its episodes, then "More like this".
class _Side extends StatelessWidget {
  final MediaItem item;
  final MediaItem? series;
  final List<WatchEpisode>? episodes;
  final int season;
  final void Function(int) onSeason;
  final void Function(WatchEpisode) onEpisode;
  final void Function(MediaItem) onMovie;
  final AppState app;
  const _Side({
    required this.item,
    required this.series,
    required this.episodes,
    required this.season,
    required this.onSeason,
    required this.onEpisode,
    required this.onMovie,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final eps = episodes;
    final subject = series ?? item;
    final similar = similarTo(
        subject, series == null ? app.shown.movies : app.shown.series,
        limit: 24);
    Widget head(String t, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(children: [
            Expanded(
                child: Text(t,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800))),
            if (trailing != null) trailing,
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (eps != null && eps.isNotEmpty) ...[
        head(tr('Episodes'), trailing: _seasonPicker(context, p, eps)),
        for (final e in inSeason(eps, season))
          _EpisodeTile(e,
              current: e.item.key == item.key,
              app: app,
              onTap: () => onEpisode(e)),
        const SizedBox(height: 12),
      ],
      head(tr('More like this')),
      if (similar.isEmpty)
        Padding(
            padding: const EdgeInsets.all(4),
            child: Text(tr('Nothing else in this category.'),
                style: TextStyle(color: p.muted)))
      else
        for (final m in similar)
          _RelatedTile(
            m,
            app: app,
            onTap: () {
              // A movie plays right here; a series opens its own page.
              if (m.kind == MediaKind.movie) {
                onMovie(m);
              } else if (NavGuard.allow()) {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SeriesScreen(series: m)));
              }
            },
          ),
    ]);
  }

  Widget _seasonPicker(
      BuildContext context, LayoutPalette p, List<WatchEpisode> eps) {
    final all = watchSeasons(eps);
    if (all.length < 2) return const SizedBox.shrink();
    return DropdownButton<int>(
      value: all.contains(season) ? season : all.first,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: p.surfaceHi,
      style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
      items: [
        for (final s in all)
          DropdownMenuItem(value: s, child: Text(trf('Season {n}', {'n': s})))
      ],
      onChanged: (v) {
        if (v != null) onSeason(v);
      },
    );
  }
}

class _RelatedTile extends StatelessWidget {
  final MediaItem item;
  final AppState app;
  final VoidCallback onTap;
  const _RelatedTile(this.item, {required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final progress = app.progressOf(item);
    final rating = item.rating;
    final meta = [
      app.vodCategoryName(item),
      if (rating != null && rating != '0' && rating != '0.0') '★ $rating',
    ].where((x) => x.isNotEmpty).join('  ·  ');
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 68,
              height: 102,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(color: p.surfaceHi),
                if (item.poster != null)
                  NetImage(item.poster!, decodeWidth: 200),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25)),
              if (meta.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12))),
              if (app.isWatched(item))
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle, size: 15, color: p.accent))
              else if (progress != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ProgressStripe(progress)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final WatchEpisode ep;
  final bool current;
  final AppState app;
  final VoidCallback onTap;
  const _EpisodeTile(this.ep,
      {required this.current, required this.app, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final e = ep.episode;
    final progress = app.progressOf(ep.item);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: current ? p.accent.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 112,
                height: 63,
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: p.surfaceHi),
                  if (e.image != null && e.image!.isNotEmpty)
                    NetImage(e.image!, decodeWidth: 300),
                  Center(
                    child: current
                        ? Icon(Icons.play_circle_fill,
                            color: p.accent, size: 28)
                        : e.image == null || e.image!.isEmpty
                            ? Text('${e.number}',
                                style: TextStyle(
                                    color: p.muted,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18))
                            : const SizedBox.shrink(),
                  ),
                  if (progress != null && !app.isWatched(ep.item))
                    Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ProgressStripe(progress)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.number}. ${e.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            height: 1.25)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (e.minutes != null && e.minutes! > 0)
                          '${e.minutes} min',
                        if (e.airDate != null && e.airDate!.isNotEmpty)
                          e.airDate!
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ]),
            ),
            if (app.isWatched(ep.item))
              Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(Icons.check_circle, size: 16, color: p.accent)),
          ]),
        ),
      ),
    );
  }
}
