import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/media.dart';
import '../services/channel_number.dart';
import '../services/chapters.dart';
import '../services/crash_guard.dart';
import '../services/mpv_props.dart';
import '../services/next_episode.dart';
import '../services/mini_player.dart';
import '../services/pip.dart';
import '../services/provider_url.dart';
import '../services/xtream_client.dart';
import '../state/app_state.dart';
import '../services/time_format.dart';
import 'open_item.dart';
import '../state/settings_state.dart';
import '../services/subtitle_search.dart';
import '../theme.dart';
import '../widgets/screensaver.dart';

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

  /// The episodes of the series this one belongs to, in order, so the next one can start by itself.
  final List<MediaItem>? episodes;

  /// Playing a past programme from the provider's archive: nothing is added to history or resume positions.
  final bool catchUp;

  /// A player the in-app mini window was already running; it carries on here without restarting.
  final MiniSession? adopt;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    required this.item,
    this.queue,
    this.startAt,
    this.episodes,
    this.catchUp = false,
    this.adopt,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  // Warnings and errors from libmpv go to the playback log (see CrashGuard).
  late final SettingsState _settings = context.read<SettingsState>();
  // TV boxes have little memory: a smaller demuxer buffer (libmpv default here is 32 MB forward + 32 MB back).
  late final Player _player = widget.adopt?.player ??
      Player(
          configuration: PlayerConfiguration(
              logLevel: MPVLogLevel.warn, bufferSize: _settings.isTv ? 16 * 1024 * 1024 : 32 * 1024 * 1024));
  late final VideoController _controller;
  late final AppState _app = context.read<AppState>();

  final _root = FocusNode(debugLabel: 'player-root');
  final _playBtn = FocusNode(debugLabel: 'player-play');
  final _pos = ValueNotifier(Duration.zero);

  final _subs = <StreamSubscription>[];
  Timer? _hideTimer, _saveTimer, _sleepTimer, _statsTimer, _typeTimer, _toastTimer, _nextTimer, _stallTimer;
  DateTime? _sleepAt;

  late int _index;
  int? _lastIndex; // the channel before this one, for the Last channel key
  String _typed = ''; // digits typed on the remote for a channel number
  String? _toast;
  late MediaItem _vod = widget.item; // the movie or episode playing (changes when the next episode starts)
  late String _vodTitle = widget.title;
  MediaItem? _upNext;
  int _nextIn = 0;
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
  bool _handedOff = false; // the player now belongs to the mini window, so it must not be disposed here

  // How far behind the live picture this is. The live edge is where the first picture was, moving on
  // with the clock, so a pause, a stall or a rewind all show up as time behind.
  Duration? _anchorPos;
  DateTime? _anchorAt;
  Timer? _lagTimer;

  // Chapters (movies and episodes): a Skip intro or Skip credits button when the one playing is named so.
  List<Chapter> _chapters = const [];
  SkipHint? _skip;
  int _chapterGen = 0;

  Duration get _behind {
    final a = _anchorPos, at = _anchorAt;
    if (!_live || a == null || at == null) return Duration.zero;
    final b = a + DateTime.now().difference(at) - _pos.value;
    return b.isNegative ? Duration.zero : b;
  }

  // A merged channel has other copies. When the one playing fails, the next one is tried.
  final _override = <int, MediaItem>{}; // queue position -> the copy playing instead
  final _altTried = <String, int>{}; // channel key -> copies tried so far

  MediaItem _source(int i) => _override[i] ?? (_queue != null ? _queue![i] : widget.item);

  List<MediaItem>? get _queue => widget.queue;
  MediaItem get _cur => _queue != null ? _queue![_index] : _vod;
  String get _title => _queue != null ? _cur.name : _vodTitle;
  bool get _live => _cur.kind == MediaKind.live;

  @override
  void initState() {
    super.initState();
    Screensaver.busy.value++;
    // Only one stream at a time: a mini player running something else stops when a full player opens.
    if (widget.adopt == null && MiniPlayer.instance.active) scheduleMicrotask(MiniPlayer.instance.close);
    _index = _queue == null ? 0 : _queue!.indexWhere((e) => e.key == widget.item.key).clamp(0, _queue!.length - 1);
    WidgetsBinding.instance.addObserver(this);
    final surface = _settings.surfaceOutput;
    CrashGuard.begin('${_live ? 'live' : 'vod'} host=${Uri.tryParse(widget.url)?.host} '
        'decoder=${_settings.decoder} output=${surface ? 'surface' : 'gpu'}');
    _controller = widget.adopt?.controller ??
        VideoController(
          _player,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: _settings.decoder != 'software',
            vo: surface ? 'mediacodec_embed' : null,
            hwdec: surface ? 'mediacodec' : null,
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
        if (_failover()) return;
        if (mounted) setState(() => _error = redactUrls(e));
      }),
      _player.stream.buffering.listen((v) => setState(() => _buffering = v)),
      _player.stream.duration.listen((v) => setState(() => _dur = v)),
      _player.stream.rate.listen((v) => setState(() => _rate = v)),
      _player.stream.position.listen((v) {
        _pos.value = v;
        if (_anchorPos == null && v > Duration.zero) {
          _anchorPos = v;
          _anchorAt = DateTime.now();
        }
        if (_chapters.isNotEmpty) {
          final h = skipHintAt(_chapters, v, _dur);
          if (h?.kind != _skip?.kind || h?.to != _skip?.to) setState(() => _skip = h);
        }
        // Time moving means the stream opened and the video path is working; later deaths are not startup failures.
        if (v > Duration.zero && !_reportedPlaying) {
          _reportedPlaying = true;
          CrashGuard.mark('playing');
          if (_error != null) setState(() => _error = null);
        }
      }),
      _player.stream.playlist.listen((p) {
        if (_queue != null && p.index != _index && p.index < _queue!.length) {
          setState(() {
            _lastIndex = _index;
            _index = p.index;
          });
          _onChannelChanged();
        }
      }),
      _player.stream.completed.listen((done) {
        if (done && !_live && mounted) _offerNextEpisode();
      }),
    ]);
    Pip.available.then((v) {
      if (mounted) setState(() => _canPip = v);
    });
    _subs.add(Pip.changes.listen((inPip) {
      if (inPip) _hideControls();
    }));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    // The "behind live" figure moves with the clock, so redraw it while the controls are showing.
    _lagTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _live && _controls) setState(() {});
    });
    _start();
    _scheduleHide();
  }

  Future<void> _start() async {
    if (widget.adopt != null) {
      // The stream is already open and playing: take over its state instead of opening it again.
      final st = _player.state;
      _playing = st.playing;
      _buffering = st.buffering;
      _dur = st.duration;
      _pos.value = st.position;
      _reportedPlaying = true;
      CrashGuard.mark('playing');
      _loadChapters();
      _onChannelChanged();
      return;
    }
    try {
      await applyBuffer(_player, _settings.bufferSecs);
      if (_live) await allowRewind(_player, _settings.isTv ? 24 : 48);
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
        await _openQueue();
      } else {
        await _player.open(Media(widget.url, start: widget.startAt, httpHeaders: _vod.headers));
      }
      CrashGuard.mark('opened');
      _armStall();
      _loadChapters();
      if (!_live && _settings.speed != 1) await _player.setRate(_settings.speed);
      _onChannelChanged();
    } catch (e) {
      // Show what went wrong instead of an endless spinner.
      CrashGuard.log('exception ${redactUrls('$e')}');
      if (mounted) setState(() => _error = redactUrls('$e'));
    }
  }

  Future<void> _openQueue() => _player.open(Playlist(
        [for (var i = 0; i < _queue!.length; i++) Media(_source(i).streamUrl!, httpHeaders: _source(i).headers)],
        index: _index,
      ));

  /// A live channel that has not started after a while counts as failed, like one that errors.
  void _armStall() {
    _stallTimer?.cancel();
    if (!_live) return;
    _stallTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_reportedPlaying) _failover();
    });
  }

  /// Moves to the next copy of the channel that is playing. False when there is none left (or
  /// this is not a live channel), so the caller shows the error instead.
  bool _failover() {
    if (!_live || !mounted) return false;
    final shown = _cur;
    final alts = _app.alternatesFor(shown);
    var n = _altTried[shown.key] ?? 0;
    while (n < alts.length && alts[n].streamUrl == null) {
      n++;
    }
    if (n >= alts.length) return false;
    _altTried[shown.key] = n + 1;
    _override[_index] = alts[n];
    _reportedPlaying = false;
    _flash('Trying another copy of ${shown.name}');
    final alt = alts[n];
    (_queue != null ? _openQueue() : _player.open(Media(alt.streamUrl!, httpHeaders: alt.headers))).then((_) => _armStall()).catchError((_) {});
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // An app the system ends while it is in the background is not a playback crash.
    if (state == AppLifecycleState.paused) CrashGuard.mark('background');
  }

  // Shaders run in libmpv's GPU renderer, which the surface output bypasses.
  Future<void> _applyShaders() => _settings.surfaceOutput ? Future.value() : applyShaders(_player, [
        for (final sh in _settings.activeShaders) MapEntry(sh.id, sh.source),
      ]);

  void _onChannelChanged() {
    _anchorPos = null; // a new channel starts a new "live edge"
    if (!widget.catchUp) _app.markWatched(_cur);
    _epg = const [];
    if (_live) {
      _app.epg(_cur).then((e) {
        if (mounted) setState(() => _epg = e);
      }).catchError((_) {});
    }
  }

  void _savePosition({bool notify = false}) {
    if (!_live && !widget.catchUp) {
      _app.savePosition(_vod, _player.state.position, _player.state.duration, notify: notify);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Screensaver.busy.value--;
    CrashGuard.mark('closing');
    _savePosition(notify: true);
    for (final s in _subs) {
      s.cancel();
    }
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _sleepTimer?.cancel();
    _statsTimer?.cancel();
    _typeTimer?.cancel();
    _toastTimer?.cancel();
    _nextTimer?.cancel();
    _stallTimer?.cancel();
    _lagTimer?.cancel();
    _root.dispose();
    _playBtn.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (!_handedOff) {
      WakelockPlus.disable().catchError((_) {});
      _player.dispose();
    }
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

  /// Live rewind: goes back [secs] in what the player has kept. A stream that keeps nothing cannot.
  Future<void> _rewindLive(int secs) async {
    final before = _player.state.position;
    await _player.seek(before - Duration(seconds: secs));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (_player.state.position >= before - const Duration(seconds: 1)) {
      _flash('Nothing earlier is saved for this channel');
    } else {
      _flash('${_fmt(_behind)} behind live');
    }
  }

  void _forwardLive(int secs) {
    if (_behind < const Duration(seconds: 2)) {
      _flash('Already live');
      return;
    }
    _seekBy(secs);
  }

  /// Back to the live picture: the channel is opened again, which starts at the live edge.
  Future<void> _goLive() async {
    if (_behind < const Duration(seconds: 2)) return;
    _anchorPos = null;
    _reportedPlaying = true;
    if (_queue != null) {
      await _player.jump(_index);
    } else {
      await _player.open(Media(_source(0).streamUrl!, httpHeaders: _source(0).headers));
    }
    if (!_player.state.playing) await _player.play();
    _flash('Back to live');
  }

  /// Reads the chapters once the file has told libmpv about them (that takes a moment).
  Future<void> _loadChapters() async {
    if (_live) return;
    final mine = ++_chapterGen;
    for (final secs in const [2, 5, 12]) {
      await Future<void>.delayed(Duration(seconds: secs));
      if (!mounted || mine != _chapterGen) return;
      final c = await readChapters(_player);
      if (c.isNotEmpty) {
        if (mounted) setState(() => _chapters = c);
        return;
      }
    }
  }

  void _doSkip() {
    final h = _skip;
    if (h == null) return;
    _player.seek(h.to >= _dur - const Duration(seconds: 2) ? _dur : h.to);
    setState(() => _skip = null);
  }

  void _pickChapter() {
    final pos = _pos.value;
    var now = 0;
    for (var i = 0; i < _chapters.length; i++) {
      if (_chapters[i].start <= pos) now = i;
    }
    _sheet('Chapters', [
      for (var i = 0; i < _chapters.length; i++)
        ListTile(
          selected: i == now,
          leading: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
          title: Text(_chapters[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_fmt(_chapters[i].start), style: const TextStyle(color: Boss.muted)),
          onTap: () {
            Navigator.pop(context);
            _player.seek(_chapters[i].start);
          },
        ),
    ]);
  }

  /// A list of every channel in the zapping queue to jump to; typing filters it by name or number.
  Future<void> _pickChannel() {
    final q = _queue;
    if (q == null) return Future.value();
    _hideTimer?.cancel();
    final ctl = TextEditingController();
    final scroll = ScrollController(initialScrollOffset: (_index * 56.0 - 120).clamp(0, double.infinity));
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Boss.surface,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 560),
      builder: (sheet) => StatefulBuilder(builder: (_, setS) {
        final f = ctl.text.trim().toLowerCase();
        final rows = [
          for (var i = 0; i < q.length; i++)
            if (f.isEmpty || q[i].name.toLowerCase().contains(f) || '${i + 1}' == f) i,
        ];
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: ctl,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Channel name or number'),
                onChanged: (_) => setS(() {}),
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: scroll,
                itemExtent: 56,
                itemCount: rows.length,
                itemBuilder: (_, k) {
                  final i = rows[k];
                  final c = q[i];
                  return ListTile(
                    selected: i == _index,
                    autofocus: i == _index && f.isEmpty,
                    leading: SizedBox(
                        width: 40,
                        child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: _app.isDead(c) ? const Text('Offline at the last check') : null,
                    onTap: () {
                      Navigator.pop(sheet);
                      if (i != _index) _player.jump(i);
                    },
                  );
                },
              ),
            ),
          ]),
        );
      }),
    ).whenComplete(() {
      ctl.dispose();
      scroll.dispose();
      _scheduleHide();
    });
  }

  /// Past programmes of this channel that the provider still has.
  Future<void> _pickCatchUp() async {
    _hideTimer?.cancel();
    await _app.loadGuide();
    if (!mounted) return;
    final now = DateTime.now();
    final past = [
      for (final p in _app.programmesFor(_cur))
        if (_app.catchUpFor(_cur, p, now: now)) p,
    ].reversed.take(40).toList();
    _sheet('Catch-up: ${_cur.name}', [
      if (past.isEmpty)
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('No past programmes in the guide yet'),
          subtitle: Text('The TV guide has to be loaded, and the provider has to keep an archive for this channel.'),
        ),
      for (final p in past)
        ListTile(
          leading: Icon(p.end.isAfter(now) ? Icons.replay : Icons.history),
          title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${fmtTime(p.start, use24h: _settings.use24h)} to ${fmtTime(p.end, use24h: _settings.use24h)}'
              '${p.end.isAfter(now) ? '  ·  on now, from the start' : ''}'),
          onTap: () {
            Navigator.pop(context);
            openCatchUp(context, _cur, p, replace: true);
          },
        ),
    ]);
  }

  void _flash(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  static String? _digit(LogicalKeyboardKey k) {
    final label = k.keyLabel;
    if (label.length == 1 && '0123456789'.contains(label)) return label;
    return null;
  }

  /// A digit on the remote or keyboard: collect "2", "0", "7" and jump to channel 207 once typing pauses.
  void _typeDigit(String d) {
    if (_queue == null) return;
    if (_controls) _hideControls();
    _typeTimer?.cancel();
    setState(() => _typed = (_typed + d).length > 4 ? d : _typed + d);
    _typeTimer = Timer(const Duration(milliseconds: 1800), _commitTyped);
  }

  void _commitTyped() {
    _typeTimer?.cancel();
    final typed = _typed;
    if (typed.isEmpty) return;
    final at = channelIndexForDigits(typed, _queue?.length ?? 0);
    setState(() => _typed = '');
    if (at == null) {
      _flash('No channel $typed');
    } else if (at != _index) {
      _player.jump(at);
    }
  }

  void _goLast() {
    final at = _lastIndex;
    if (_queue == null || at == null || at >= _queue!.length) {
      _flash('No previous channel yet');
      return;
    }
    _player.jump(at);
  }

  // Up next: when an episode ends, count down and start the following one.
  void _offerNextEpisode() {
    if (!_settings.autoplayNext || _upNext != null) return;
    final n = nextEpisodeAfter(widget.episodes, _vod);
    if (n == null || n.streamUrl == null) return;
    _nextTimer?.cancel();
    setState(() {
      _upNext = n;
      _nextIn = 10;
    });
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_nextIn <= 1) {
        _playNext();
      } else {
        setState(() => _nextIn--);
      }
    });
  }

  void _cancelNext() {
    _nextTimer?.cancel();
    if (_upNext != null) setState(() => _upNext = null);
  }

  Future<void> _playNext() async {
    _nextTimer?.cancel();
    final n = _upNext;
    if (n == null) return;
    _savePosition();
    setState(() {
      _upNext = null;
      _vod = n;
      _vodTitle = n.name;
      _error = null;
      _chapters = const [];
      _skip = null;
    });
    try {
      await _player.open(Media(n.streamUrl!, httpHeaders: n.headers));
      _onChannelChanged();
      _loadChapters();
    } catch (e) {
      if (mounted) setState(() => _error = redactUrls('$e'));
    }
  }

  // Picture shape: the player button cycles through these and remembers the last one.
  static const _shapes = <(String, String, BoxFit, double?)>[
    ('auto', 'Auto', BoxFit.contain, null),
    ('16:9', '16:9', BoxFit.fill, 16 / 9),
    ('4:3', '4:3', BoxFit.fill, 4 / 3),
    ('fill', 'Fill the screen', BoxFit.cover, null),
    ('stretch', 'Stretch', BoxFit.fill, null),
  ];

  (String, String, BoxFit, double?) get _shape =>
      _shapes.firstWhere((s) => s.$1 == _settings.aspect, orElse: () => _shapes.first);

  void _cycleShape() {
    final at = _shapes.indexWhere((s) => s.$1 == _shape.$1);
    final next = _shapes[(at + 1) % _shapes.length];
    _settings.set('aspect', next.$1);
    _flash('Picture: ${next.$2}');
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

    final d = _digit(k);
    if (d != null && _queue != null) {
      _typeDigit(d);
      return KeyEventResult.handled;
    }
    if (_typed.isNotEmpty && (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      _commitTyped();
      return KeyEventResult.handled;
    }
    if ((k == LogicalKeyboardKey.mediaLast || k == LogicalKeyboardKey.keyL) && _queue != null) {
      _goLast();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.keyM) {
      _minimize();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyC && _queue != null && _queue!.length > 1) {
      _pickChannel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyS && _skip != null) {
      _doSkip();
      return KeyEventResult.handled;
    }

    if (_controls) {
      _scheduleHide();
      return KeyEventResult.ignored; // normal focus traversal
    }

    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space) {
      // While Skip intro / Skip credits is on screen, OK takes it.
      if (_skip != null) {
        _doSkip();
        return KeyEventResult.handled;
      }
      _player.playOrPause();
      _showControls();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _live ? _rewindLive(_settings.seekSecs) : _seekBy(-_settings.seekSecs);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _live ? _forwardLive(_settings.seekSecs) : _seekBy(_settings.seekSecs);
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

  /// Looks the title up on OpenSubtitles and offers the best matches; the chosen one is loaded as a track.
  Future<void> _findSubtitles() async {
    final st = context.read<SettingsState>();
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    if (st.osKey.isEmpty) {
      say('Add your OpenSubtitles API key under Settings > Playback first.');
      return;
    }
    final item = _cur;
    final se = parseSeasonEpisode(item.name);
    final svc = SubtitleSearch(st.osKey, username: st.osUser, password: st.osPass);
    final lang = st.subLang.length == 2 || st.subLang.length == 3 ? st.subLang : '';
    List<SubtitleHit> hits;
    try {
      hits = await svc.search(SubtitleSearch.queryFor(item, season: se?.$1, episode: se?.$2, language: lang));
    } catch (e) {
      say('$e');
      return;
    }
    if (!mounted) return;
    if (hits.isEmpty) {
      say('No subtitles found for ${item.name}.');
      return;
    }
    await _sheet('Subtitles for ${item.name}', [
      for (final h in hits.take(25))
        ListTile(
          title: Text(h.name.isEmpty ? 'Subtitle ${h.fileId}' : h.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            h.language.toUpperCase(),
            if (h.hearingImpaired) 'for the deaf and hard of hearing',
            if (h.downloads > 0) '${h.downloads} downloads',
          ].where((e) => e.isNotEmpty).join('  ·  ')),
          onTap: () async {
            Navigator.pop(context);
            try {
              final text = await svc.download(h);
              if (!mounted) return;
              await _player.setSubtitleTrack(SubtitleTrack.data(text, title: h.name, language: h.language));
              say('Subtitles loaded.');
            } catch (e) {
              say('$e');
            }
          },
        ),
    ]);
  }

  void _pickSubtitle() {
    final tracks = _player.state.tracks.subtitle;
    final cur = _player.state.track.subtitle;
    _sheet('Subtitles', [
      if (_cur.kind != MediaKind.live)
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('Search online'),
          subtitle: const Text('OpenSubtitles'),
          onTap: () {
            Navigator.pop(context);
            _findSubtitles();
          },
        ),
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

  /// Picture-in-picture inside the app: close this screen and keep the stream going in a small window
  /// above everything, which opens this screen again when tapped.
  void _minimize() {
    if (_error != null) return;
    _handedOff = true;
    _savePosition(notify: true);
    MiniPlayer.instance.start(MiniSession(
      player: _player,
      controller: _controller,
      item: _cur,
      title: _title,
      queue: _queue,
      episodes: widget.episodes,
      catchUp: widget.catchUp,
    ));
    Navigator.of(context).pop();
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
                fit: _shape.$3,
                aspectRatio: _shape.$4,
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
              if (_typed.isNotEmpty) _typedOverlay(),
              if (_toast != null) _toastBar(),
              if (_upNext != null) _upNextCard(),
              if (_skip != null && !_controls && _upNext == null) _skipChip(),
              if (_controls) _overlay(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() {
    final f = friendlyPlayerError(_error!);
    return Center(
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
            Text(f.message, textAlign: TextAlign.center, style: const TextStyle(color: Boss.muted)),
            const SizedBox(height: 8),
            Text(
                f.decoderAdvice
                    ? 'Press Back to leave. If this keeps happening, try Settings > Playback > Decoder > Software.'
                    : 'Press Back to leave.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Boss.muted, fontSize: 12)),
          ]),
        ),
      );
  }

  /// The number being typed, with the channel it would open.
  Widget _typedOverlay() {
    final at = channelIndexForDigits(_typed, _queue?.length ?? 0);
    return Positioned(
      top: 24,
      right: 28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(_typed, style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, height: 1, color: Boss.accent2)),
          Text(at == null ? 'No such channel' : _queue![at].name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, color: Colors.white70)),
          const Text('OK to go now', style: TextStyle(fontSize: 12, color: Colors.white54)),
        ]),
      ),
    );
  }

  Widget _skipChip() => Positioned(
        right: 24,
        bottom: 56,
        child: Material(
          color: Colors.black.withValues(alpha: 0.8),
          shape: const StadiumBorder(side: BorderSide(color: Colors.white54)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _doSkip,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.skip_next, size: 20),
                const SizedBox(width: 8),
                Text(_skip!.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(width: 10),
                const Text('OK', style: TextStyle(color: Boss.muted, fontSize: 12)),
              ]),
            ),
          ),
        ),
      );

  Widget _toastBar() => Positioned(
        bottom: 96,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(24)),
            child: Text(_toast!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  Widget _upNextCard() {
    final n = _upNext!;
    return Positioned(
      right: 24,
      bottom: 24,
      child: Container(
        width: 340,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('UP NEXT  ·  $_nextIn', style: const TextStyle(color: Boss.accent2, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontSize: 13)),
          const SizedBox(height: 6),
          Text(n.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(autofocus: true, onPressed: _playNext, child: const Text('Play now')),
            const SizedBox(width: 10),
            TextButton(onPressed: _cancelNext, child: const Text('Cancel')),
          ]),
        ]),
      ),
    );
  }

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
              if (_live && _behind >= const Duration(seconds: 2))
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('-${_fmt(_behind)} behind live',
                      style: const TextStyle(color: Boss.accent2, fontSize: 12, fontWeight: FontWeight.w700)),
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
                _btn(_seekIcon(false), 'Back ${_settings.seekSecs}s',
                    () => _live ? _rewindLive(_settings.seekSecs) : _seekBy(-_settings.seekSecs)),
                _btn(_playing ? Icons.pause : Icons.play_arrow, 'Play / pause', _player.playOrPause,
                    node: _playBtn),
                _btn(_seekIcon(true), 'Forward ${_settings.seekSecs}s',
                    () => _live ? _forwardLive(_settings.seekSecs) : _seekBy(_settings.seekSecs)),
                if (_live && _behind >= const Duration(seconds: 2))
                  _btn(Icons.sensors, 'Back to live (${_fmt(_behind)} behind)', _goLive, on: true),
                if (_live && _app.canCatchUp(_cur)) _btn(Icons.history, 'Catch-up', _pickCatchUp),
                if (_queue != null) _btn(Icons.skip_next, 'Next channel', _player.next),
                if (_queue != null) _btn(Icons.swap_horiz, 'Last channel', _goLast),
                if (_queue != null && _queue!.length > 1) _btn(Icons.format_list_numbered, 'Channels', _pickChannel),
                if (_skip != null) _btn(Icons.skip_next, _skip!.label, _doSkip, on: true),
                if (_chapters.length > 1) _btn(Icons.bookmarks_outlined, 'Chapters', _pickChapter),
                if (!_live)
                  _btn(Icons.fast_forward, 'Skip ahead (+${_settings.skipSecs}s)', () => _seekBy(_settings.skipSecs)),
                _btn(Icons.aspect_ratio, 'Picture shape (${_shape.$2})', _cycleShape, on: _shape.$1 != 'auto'),
                _btn(Icons.audiotrack, 'Audio', _pickAudio),
                _btn(Icons.subtitles, 'Subtitles', _pickSubtitle),
                if (!_live) _btn(Icons.speed, 'Speed', _pickSpeed, on: _rate != 1),
                if (shadersSupported)
                  _btn(Icons.auto_fix_high, 'Shaders', _pickShaders, on: _settings.shaderEnabled.isNotEmpty),
                _btn(Icons.bedtime, 'Sleep timer', _pickSleep, on: _sleepAt != null),
                _btn(Icons.picture_in_picture, 'Mini player (P)', _minimize),
                if (_canPip) _btn(Icons.picture_in_picture_alt, 'Picture-in-picture (system)', _enterPip),
                _btn(Icons.analytics_outlined, 'Stats', _toggleStats, on: _stats),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
