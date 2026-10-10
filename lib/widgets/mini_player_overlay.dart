import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../layouts/common.dart';
import '../layouts/ui_layout.dart';
import '../models/media.dart';
import '../screens/player_screen.dart';
import '../services/mini_player.dart';
import '../state/app_state.dart';
import 'tv.dart';

/// The mini player window, drawn above every screen. Nothing is built while no mini player is active.
class MiniPlayerOverlay extends StatelessWidget {
  const MiniPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: MiniPlayer.instance,
        builder: (context, _) {
          final s = MiniPlayer.instance.session;
          if (s == null) return const SizedBox.shrink();
          return _MiniWindow(key: ValueKey(s.player), session: s);
        },
      );
}

/// Opens the full player on what the mini player is playing, carrying the same player over.
void expandMiniPlayer() {
  final s = MiniPlayer.instance.take();
  final nav = MiniPlayer.navigatorKey.currentState;
  if (s == null || nav == null) return;
  // The channel playing now may not be the one the window started on (it can zap).
  var item = s.item;
  if (s.queue != null) {
    final i = s.player.state.playlist.index;
    if (i >= 0 && i < s.queue!.length) item = s.queue![i];
  }
  s.player.setVolume(100); // the window may have been muted
  nav.push(MaterialPageRoute(
    builder: (_) => PlayerScreen(
      title: item.name == s.item.name ? s.title : item.name,
      url: item.streamUrl ?? '',
      item: item,
      queue: s.queue,
      episodes: s.episodes,
      catchUp: s.catchUp,
      adopt: s,
    ),
  ));
}

class _MiniWindow extends StatefulWidget {
  final MiniSession session;
  const _MiniWindow({super.key, required this.session});

  @override
  State<_MiniWindow> createState() => _MiniWindowState();
}

class _MiniWindowState extends State<_MiniWindow> {
  bool _right = true, _bottom = true;
  Offset? _drag; // top-left while being dragged
  bool _playing = true, _muted = false, _buffering = true;
  int _index = 0;
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _save;
  late final AppState _app = context.read<AppState>();

  MiniSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    final st = s.player.state;
    _playing = st.playing;
    _buffering = st.buffering;
    _index = st.playlist.index;
    _subs.addAll([
      s.player.stream.playing
          .listen((v) => mounted ? setState(() => _playing = v) : null),
      s.player.stream.buffering
          .listen((v) => mounted ? setState(() => _buffering = v) : null),
      s.player.stream.playlist
          .listen((p) => mounted ? setState(() => _index = p.index) : null),
    ]);
    // A movie being watched in the window keeps its resume position.
    _save = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
  }

  void _savePosition() {
    if (s.live || s.catchUp) return;
    _app.savePosition(s.item, s.player.state.position, s.player.state.duration);
  }

  @override
  void dispose() {
    _savePosition();
    _save?.cancel();
    for (final x in _subs) {
      x.cancel();
    }
    super.dispose();
  }

  MediaItem get _now {
    final q = s.queue;
    return q != null && _index >= 0 && _index < q.length ? q[_index] : s.item;
  }

  @override
  Widget build(BuildContext context) {
    final p = LayoutPalette.of(context);
    final tv = TvScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final w = tv ? 360.0 : (size.width * 0.58).clamp(200.0, 300.0);
    final h = w * 9 / 16;
    final m = tv ? 48.0 : 12.0;
    final pad = MediaQuery.paddingOf(context);
    final left =
        _drag?.dx ?? (_right ? size.width - w - m - pad.right : m + pad.left);
    // Above the bottom bar when there is one on a phone.
    final bottomGap = tv ? m : 76.0 + pad.bottom;
    final top =
        _drag?.dy ?? (_bottom ? size.height - h - bottomGap : m + pad.top);
    final item = _now;

    Widget btn(IconData icon, String tip, VoidCallback onTap) => FocusSurface(
          radius: 16,
          semanticLabel: tip,
          onTap: onTap,
          builder: (_, __) => Container(
            width: tv ? 36 : 30,
            height: tv ? 36 : 30,
            decoration: const BoxDecoration(
                color: Color(0x99000000), shape: BoxShape.circle),
            child: Icon(icon, size: tv ? 20 : 17, color: Colors.white),
          ),
        );

    return Stack(children: [
      AnimatedPositioned(
        duration:
            _drag == null ? const Duration(milliseconds: 200) : Duration.zero,
        curve: Curves.easeOut,
        left: left,
        top: top,
        width: w,
        height: h,
        child: GestureDetector(
          onPanUpdate: (d) => setState(() {
            final cur = _drag ?? Offset(left, top);
            _drag = Offset((cur.dx + d.delta.dx).clamp(0.0, size.width - w),
                (cur.dy + d.delta.dy).clamp(0.0, size.height - h));
          }),
          onPanEnd: (_) {
            final c = _drag ?? Offset(left, top);
            final snap = snapCorner(
                (c.dx + w / 2) / size.width, (c.dy + h / 2) / size.height);
            setState(() {
              _right = snap.right;
              _bottom = snap.bottom;
              _drag = null;
            });
          },
          child: Material(
            elevation: 12,
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Stack(fit: StackFit.expand, children: [
              Video(
                  controller: s.controller,
                  controls: NoVideoControls,
                  fill: Colors.black),
              // The whole picture opens the full player.
              Positioned.fill(
                child: FocusSurface(
                  radius: 12,
                  semanticLabel: 'Open ${item.name} full screen',
                  onTap: expandMiniPlayer,
                  onLongPress: MiniPlayer.instance.close,
                  builder: (_, __) => const SizedBox.expand(),
                ),
              ),
              if (_buffering)
                const Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
                    decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xCC000000), Color(0x00000000)])),
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: tv ? 15 : 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.queue != null) ...[
                    btn(Icons.skip_previous, 'Previous channel',
                        s.player.previous),
                    const SizedBox(width: 4),
                    btn(Icons.skip_next, 'Next channel', s.player.next),
                    const SizedBox(width: 4),
                  ],
                  btn(_playing ? Icons.pause : Icons.play_arrow,
                      _playing ? 'Pause' : 'Play', s.player.playOrPause),
                  const SizedBox(width: 4),
                  btn(_muted ? Icons.volume_off : Icons.volume_up,
                      _muted ? 'Unmute' : 'Mute', () {
                    setState(() => _muted = !_muted);
                    s.player.setVolume(_muted ? 0 : 100);
                  }),
                  const SizedBox(width: 4),
                  btn(Icons.open_in_full, 'Full screen', expandMiniPlayer),
                  const SizedBox(width: 4),
                  btn(Icons.close, 'Close mini player',
                      MiniPlayer.instance.close),
                ]),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: p.accent.withValues(alpha: 0.7),
                            width: 1.5)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
