import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/media.dart';
import '../services/crash_guard.dart';
import '../services/mpv_props.dart';
import '../services/pip.dart';
import '../services/provider_url.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../state/settings_state.dart';
import '../theme.dart';

/// Full-screen player. Remote / keyboard behaviour (mpvNova-style):
///  * controls hidden: OK = pause + show controls, Left/Right = seek 10s (VOD),
///    Up/Down = next/previous channel (live)
///  * controls visible: arrows move focus between buttons, Back hides them.
class PlayerScreen extends StatefulWidget {
  final String title;
  final String url;
  final MediaItem item;

  /// Live channels to zap through with Up/Down (the tapped one is [item]).
  final List<MediaItem>? queue;

  /// Where to start (movies/episodes). Null = from the beginning.
  final Duration? startAt;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    required this.item,
    this.queue,
    this.startAt,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  // Warnings and errors from libmpv go to the playback log (see CrashGuard).
  late final Player _player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
  late final VideoController _controller;
  late final AppState _app = context.read<AppState>();
  late final SettingsState _settings = context.read<SettingsState>();

  final _root = FocusNode(debugLabel: 'player-root');
  final _playBtn = FocusNode(debugLabel: 'player-play');
  final _pos = ValueNotifier(Duration.zero);

  final _subs = <StreamSubscription>[];
  Timer? _hideTimer, _saveTimer, _sleepTimer, _statsTimer;
  DateTime? _sleepAt;

  late int _index;
  bool _controls = true;
  bool _stats = false;
  bool _playing = true;
  bool _buffering = true;
  Duration _dur = Duration.zero;
  double _rate = 1;
  List<EpgEntry> _epg = const [];
  bool _canPip = false;
  String? _error;
  bool _reportedPlaying = false;

  List<MediaItem>? get _queue => widget.queue;
  MediaItem get _cur => _queue != null ? _queue![_index] : widget.item;
  String get _title => _queue != null ? _cur.name : widget.title;
  bool get _live => _cur.kind == MediaKind.live;

  @override
  void initState() {
    super.initState();
    _index = _queue == null ? 0 : _queue!.indexWhere((e) => e.key == widget.item.key).clamp(0, _queue!.length - 1);
    WidgetsBinding.instance.addObserver(this);
    CrashGuard.begin('${_live ? 'live' : 'vod'} host=${Uri.tryParse(widget.url)?.host} decoder=${_settings.decoder}');
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: _settings.decoder != 'software',
      ),
    );
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    // Browsers may deny the wake lock (no user activation / policy); that must not surface as an error.
    WakelockPlus.enable().catchError((_) {});

    _subs.addAll([
      _player.stream.playing.listen((v) => setState(() => _playing = v)),
      _player.stream.log.listen((l) => CrashGuard.log('${l.level} ${l.prefix}: ${redactUrls(l.text)}')),
      _player.stream.error.listen((e) {
        CrashGuard.log('error ${redactUrls(e)}');
        if (mounted) setState(() => _error = redactUrls(e));
      }),
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
      _player.stream.duration.listen((v) => setState(() => _dur = v)),
      _player.stream.rate.listen((v) => setState(() => _rate = v)),
      _player.stream.position.listen((v) {
        _pos.value = v;
        // Time moving means the stream opened and the video path is working; later deaths are not startup failures.
        if (v > Duration.zero && !_reportedPlaying) {
          _reportedPlaying = true;
          CrashGuard.mark('playing');
          if (_error != null) setState(() => _error = null);
        }
      }),
      _player.stream.playlist.listen((p) {
        if (_queue != null && p.index != _index && p.index < _queue!.length) {
          setState(() => _index = p.index);
          _onChannelChanged();
        }
      }),
    ]);
    Pip.available.then((v) {
      if (mounted) setState(() => _canPip = v);
    });
    _subs.add(Pip.changes.listen((inPip) {
      if (inPip) _hideControls();
    }));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    _start();
    _scheduleHide();
  }

  Future<void> _start() async {
    try {
      await applyBuffer(_player, _settings.bufferSecs);
      await applyPlaybackPrefs(
        _player,
        audioLang: _settings.audioLang,
        subLang: _settings.subLang,
        subsOn: _settings.subsOn,
        userAgent: _settings.userAgent,
      );
      await _applyShaders();
      CrashGuard.mark('props');
      CrashGuard.mark('open');
      if (_queue != null) {
        await _player.open(Playlist(
          [for (final q in _queue!) Media(q.streamUrl!)],
          index: _index,
        ));
      } else {
        await _player.open(Media(widget.url, start: widget.startAt));
      }
      CrashGuard.mark('opened');
      if (!_live && _settings.speed != 1) await _player.setRate(_settings.speed);
      _onChannelChanged();
    } catch (e) {
      // Show what went wrong instead of an endless spinner.
      CrashGuard.log('exception ${redactUrls('$e')}');
      if (mounted) setState(() => _error = redactUrls('$e'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An app the system ends while it is in the background is not a playback crash.
    if (state == AppLifecycleState.paused) CrashGuard.mark('background');
  }

  Future<void> _applyShaders() => applyShaders(_player, [
        for (final sh in _settings.activeShaders) MapEntry(sh.id, sh.source),
      ]);

  void _onChannelChanged() {
    _app.markWatched(_cur);
    _epg = const [];
    if (_live) {
      _app.epg(_cur).then((e) {
        if (mounted) setState(() => _epg = e);
      }).catchError((_) {});
    }
  }

  void _savePosition({bool notify = false}) {
    if (!_live) {
      _app.savePosition(widget.item, _player.state.position, _player.state.duration, notify: notify);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CrashGuard.mark('closing');
    _savePosition(notify: true);
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    _statsTimer?.cancel();
    _root.dispose();
    _playBtn.dispose();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _player.dispose();
    CrashGuard.end();
    super.dispose();
  }

  // --- controls visibility ----------------------------------------------

  void _showControls() {
    setState(() => _controls = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controls && !_playBtn.hasFocus) _playBtn.requestFocus();
    });
    _scheduleHide();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (!_controls) return;
    setState(() => _controls = false);
    _root.requestFocus();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    final secs = _settings.controlsHideSecs;
    if (secs <= 0) return; // "never": controls stay until dismissed
    _hideTimer = Timer(Duration(seconds: secs), () {
      // Don't hide behind an open menu.
      if (mounted && _playing && ModalRoute.of(context)?.isCurrent == true) _hideControls();
    });
  }

  // --- actions ----------------------------------------------------------

  void _seekBy(int secs) {
    final target = _player.state.position + Duration(seconds: secs);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;

    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _player.playOrPause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext) {
      _live ? _player.next() : _seekBy(30);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious) {
      _live ? _player.previous() : _seekBy(-30);
      return KeyEventResult.handled;
    }

    if (_controls) {
      _scheduleHide();
      return KeyEventResult.ignored; // normal focus traversal
    }

    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space) {
      _player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft && !_live) {
      _seekBy(-_settings.seekSecs);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight && !_live) {
      _seekBy(_settings.seekSecs);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && _queue != null) {
      _player.next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && _queue != null) {
      _player.previous();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      _showControls(); // arrows that have no direct action just reveal the controls
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _seekIcon(bool forward) => switch (_settings.seekSecs) {
        5 => forward ? Icons.forward_5 : Icons.replay_5,
        30 => forward ? Icons.forward_30 : Icons.replay_30,
        _ => forward ? Icons.forward_10 : Icons.replay_10,
      };

  // --- pickers ----------------------------------------------------------

  Future<void> _sheet(String title, List<Widget> children) {
    _hideTimer?.cancel();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Boss.surface,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          ...children,
        ]),
      ),
    ).whenComplete(_scheduleHide);
  }

  String _trackLabel(dynamic t) {
    if (t.id == 'auto') return 'Auto';
    if (t.id == 'no') return 'Off';
    final parts = <String>[
      if ((t.title as String?)?.isNotEmpty ?? false) t.title as String,
      if ((t.language as String?)?.isNotEmpty ?? false) (t.language as String).toUpperCase(),
    ];
    return parts.isEmpty ? 'Track ${t.id}' : parts.join(' · ');
  }

  void _pickAudio() {
    final tracks = _player.state.tracks.audio;
    final cur = _player.state.track.audio;
    _sheet('Audio', [
      for (final t in tracks)
        ListTile(
          title: Text(_trackLabel(t)),
          trailing: t.id == cur.id ? const Icon(Icons.check, color: Boss.accent) : null,
          onTap: () {
            _player.setAudioTrack(t);
            Navigator.pop(context);
          },
        ),
    ]);
  }

  void _pickSubtitle() {
    final tracks = _player.state.tracks.subtitle;
    final cur = _player.state.track.subtitle;
    _sheet('Subtitles', [
      for (final t in tracks)
        ListTile(
          title: Text(_trackLabel(t)),
          trailing: t.id == cur.id ? const Icon(Icons.check, color: Boss.accent) : null,
          onTap: () {
            _player.setSubtitleTrack(t);
            Navigator.pop(context);
          },
        ),
    ]);
  }

  void _pickSpeed() {
    _sheet('Speed', [
      for (final r in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
        ListTile(
          title: Text('${r}x'),
          trailing: r == _rate ? const Icon(Icons.check, color: Boss.accent) : null,
          onTap: () {
            _player.setRate(r);
            Navigator.pop(context);
          },
        ),
    ]);
  }

  void _pickSleep() {
    _sheet('Sleep timer', [
      ListTile(
        title: const Text('Off'),
        trailing: _sleepAt == null ? const Icon(Icons.check, color: Boss.accent) : null,
        onTap: () {
          _sleepTimer?.cancel();
          setState(() => _sleepAt = null);
          Navigator.pop(context);
        },
      ),
      for (final m in const [15, 30, 45, 60, 90])
        ListTile(
          title: Text('$m minutes'),
          onTap: () {
            _sleepTimer?.cancel();
            _sleepTimer = Timer(Duration(minutes: m), () {
              if (mounted) Navigator.of(context).maybePop();
            });
            setState(() => _sleepAt = DateTime.now().add(Duration(minutes: m)));
            Navigator.pop(context);
          },
        ),
    ]);
  }

  void _pickShaders() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Boss.surface,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      builder: (_) => ListenableBuilder(
        listenable: _settings,
        builder: (ctx, _) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Shaders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (!shadersSupported)
              const ListTile(title: Text('Not available on web')),
            for (final sh in _settings.shaders)
              SwitchListTile(
                title: Text(sh.name),
                subtitle: sh.builtin ? Text(sh.description) : null,
                value: _settings.shaderEnabled.contains(sh.id),
                activeThumbColor: Boss.accent,
                onChanged: shadersSupported
                    ? (v) {
                        _settings.setShaders(
                          enabled: v
                              ? {..._settings.shaderEnabled, sh.id}
                              : ({..._settings.shaderEnabled}..remove(sh.id)),
                        );
                        _applyShaders();
                      }
                    : null,
              ),
          ]),
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  Future<void> _enterPip() async {
    await Pip.enter();
  }

  void _toggleStats() {
    setState(() => _stats = !_stats);
    _statsTimer?.cancel();
    if (_stats) {
      _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    }
  }

  // --- build ------------------------------------------------------------

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    return '${h > 0 ? '$h:' : ''}${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final st = _settings;
    return PopScope(
      canPop: !_controls,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hideControls();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _root,
          autofocus: true,
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _controls ? _hideControls() : _showControls(),
            child: Stack(fit: StackFit.expand, children: [
              Video(
                controller: _controller,
                controls: NoVideoControls,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    fontSize: st.subSize,
                    fontWeight: st.subBold ? FontWeight.w700 : FontWeight.w400,
                    height: 1.4,
                    color: Color(st.subColor),
                    backgroundColor: st.subBackground ? const Color(0xAA000000) : null,
                  ),
                  padding: EdgeInsets.fromLTRB(24, 0, 24, st.subBottom),
                ),
              ),
              if (_buffering && _error == null) const Center(child: CircularProgressIndicator()),
              if (_error != null) _errorBanner(),
              if (_stats) _statsOverlay(),
              if (_controls) _overlay(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() => Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Boss.accent, size: 36),
            const SizedBox(height: 10),
            const Text("This can't be played", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Boss.muted)),
            const SizedBox(height: 8),
            const Text('Press Back to leave. If this keeps happening, try Settings > Playback > Decoder > Software.',
                textAlign: TextAlign.center, style: TextStyle(color: Boss.muted, fontSize: 12)),
          ]),
        ),
      );

  Widget _statsOverlay() {
    final s = _player.state;
    final text = [
      'Video   ${s.width ?? '?'}x${s.height ?? '?'}',
      'Buffer  ${s.buffer.inSeconds}s${kIsWeb ? '' : ' (target ${_settings.bufferSecs}s)'}',
      if (!kIsWeb) 'Decoder ${_settings.decoder}',
      'Speed   ${_rate}x',
      'Pos     ${_fmt(s.position)} / ${_fmt(s.duration)}',
    ].join('\n');
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4)),
      ),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {FocusNode? node, bool on = false}) =>
      IconButton(
        focusNode: node,
        tooltip: tip,
        icon: Icon(icon, color: on ? Boss.accent : Colors.white),
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.focused) ? const BorderSide(color: Boss.accent, width: 2) : null),
        ),
        onPressed: () {
          _scheduleHide();
          onTap();
        },
      );

  Widget _overlay() {
    final now = _epg.where((e) => e.isNow).firstOrNull;
    final next = _epg.where((e) => e.start.isAfter(DateTime.now())).firstOrNull;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent, Colors.transparent, Color(0xCC000000)],
          stops: [0, 0.25, 0.65, 1],
        ),
      ),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              // pop(), not maybePop(): maybePop is intercepted by PopScope to hide the controls first.
              _btn(Icons.arrow_back, 'Back', () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (now != null)
                    Text('Now: ${now.title}'
                        '${next != null ? '   ·   Next: ${next.title}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Boss.muted, fontSize: 13)),
                ]),
              ),
              if (_sleepAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('Sleep ${_fmt(_sleepAt!.difference(DateTime.now()))}',
                      style: const TextStyle(color: Boss.accent2, fontSize: 12)),
                ),
            ]),
          ),
          const Spacer(),
          if (!_live)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ValueListenableBuilder<Duration>(
                valueListenable: _pos,
                builder: (_, p, __) {
                  final max = _dur.inMilliseconds.toDouble();
                  return Row(children: [
                    Text(_fmt(p), style: const TextStyle(fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: p.inMilliseconds.toDouble().clamp(0.0, max <= 0 ? 1.0 : max).toDouble(),
                        max: max <= 0 ? 1 : max,
                        activeColor: Boss.accent,
                        onChanged: (v) {
                          _scheduleHide();
                          _player.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                    ),
                    Text(_fmt(_dur), style: const TextStyle(fontSize: 12)),
                  ]);
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                if (_queue != null) _btn(Icons.skip_previous, 'Previous channel', _player.previous),
                if (!_live)
                  _btn(_seekIcon(false), 'Back ${_settings.seekSecs}s', () => _seekBy(-_settings.seekSecs)),
                _btn(_playing ? Icons.pause : Icons.play_arrow, 'Play / pause', _player.playOrPause,
                    node: _playBtn),
                if (!_live)
                  _btn(_seekIcon(true), 'Forward ${_settings.seekSecs}s', () => _seekBy(_settings.seekSecs)),
                if (_queue != null) _btn(Icons.skip_next, 'Next channel', _player.next),
                if (!_live)
                  _btn(Icons.fast_forward, 'Skip ahead (+${_settings.skipSecs}s)', () => _seekBy(_settings.skipSecs)),
                _btn(Icons.audiotrack, 'Audio', _pickAudio),
                _btn(Icons.subtitles, 'Subtitles', _pickSubtitle),
                if (!_live) _btn(Icons.speed, 'Speed', _pickSpeed, on: _rate != 1),
                if (shadersSupported)
                  _btn(Icons.auto_fix_high, 'Shaders', _pickShaders, on: _settings.shaderEnabled.isNotEmpty),
                _btn(Icons.bedtime, 'Sleep timer', _pickSleep, on: _sleepAt != null),
                if (_canPip) _btn(Icons.picture_in_picture_alt, 'Picture-in-picture', _enterPip),
                _btn(Icons.analytics_outlined, 'Stats', _toggleStats, on: _stats),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
