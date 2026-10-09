import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../models/media.dart';
import '../services/mpv_props.dart';
import '../state/settings_state.dart';

/// A small live picture of [channel], for layouts that show channels on the home screen.
///
/// It plays only while it can be seen: not when another tab or a full-screen player covers it, not
/// while the app is in the background. Changing channel waits a moment first, so flicking through
/// channels does not open every stream on the way. If playing fails for any reason the widget just
/// shows [fallback], so a layout never depends on it.
class LivePreview extends StatefulWidget {
  final MediaItem channel;
  final bool sound;
  final Widget fallback;
  final BoxFit fit;
  final Duration delay;

  /// Set once the video library is started (see main). Tests never start it, so no preview plays.
  static bool ready = false;

  const LivePreview({
    super.key,
    required this.channel,
    required this.fallback,
    this.sound = false,
    this.fit = BoxFit.cover,
    this.delay = const Duration(milliseconds: 600),
  });

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> with WidgetsBindingObserver {
  Player? _player;
  VideoController? _controller;
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  bool _live = false, _failed = false;
  bool _visible = true, _enabled = true, _appActive = true;
  String? _openKey;

  bool get _wanted =>
      LivePreview.ready &&
      !_failed &&
      _visible &&
      _enabled &&
      _appActive &&
      widget.channel.streamUrl != null &&
      widget.channel.kind == MediaKind.live;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden by another tab (IndexedStack turns tickers off) or by a screen pushed on top.
    _visible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _enabled = Provider.of<SettingsState?>(context)?.livePreview ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(LivePreview old) {
    super.didUpdateWidget(old);
    if (old.sound != widget.sound) _player?.setVolume(widget.sound ? 100 : 0);
    if (old.channel.key != widget.channel.key) {
      _live = false;
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!_wanted) {
      _stop();
      return;
    }
    if (_openKey == widget.channel.key && _player != null) return;
    _timer?.cancel();
    _timer = Timer(widget.delay, _open);
  }

  Future<void> _open() async {
    if (!mounted || !_wanted) return;
    try {
      final first = _player == null;
      final player = _player ??= Player(
          configuration: const PlayerConfiguration(
              logLevel: MPVLogLevel.error, bufferSize: 4 * 1024 * 1024));
      if (first) {
        _controller = VideoController(player);
        await applyPreview(player);
        _subs.addAll([
          player.stream.playing.listen((v) {
            if (mounted && v != _live) setState(() => _live = v);
          }),
          player.stream.error.listen((_) {
            if (mounted) setState(() => _live = false);
          }),
        ]);
      }
      _openKey = widget.channel.key;
      await player.setVolume(widget.sound ? 100 : 0);
      await player.open(Media(widget.channel.streamUrl!,
          httpHeaders: widget.channel.headers));
      if (mounted) setState(() {});
    } catch (_) {
      _failed = true;
      _stop();
      if (mounted) setState(() {});
    }
  }

  void _stop() {
    _timer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final p = _player;
    _player = null;
    _controller = null;
    _openKey = null;
    _live = false;
    p?.dispose();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Stack(fit: StackFit.expand, children: [
      widget.fallback,
      if (c != null)
        AnimatedOpacity(
          opacity: _live ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          child: Video(
              controller: c,
              fit: widget.fit,
              controls: NoVideoControls,
              fill: Colors.transparent),
        ),
    ]);
  }
}
