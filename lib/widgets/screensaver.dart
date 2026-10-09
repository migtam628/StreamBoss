import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'net_image.dart';

/// Coordinates the screensaver with the rest of the app.
class Screensaver {
  /// Greater than zero while something is on screen that should not be interrupted (the player).
  static final ValueNotifier<int> busy = ValueNotifier(0);

  /// Bump this to show the screensaver right now (the preview button in Settings).
  static final ValueNotifier<int> preview = ValueNotifier(0);
}

/// Shows [view] over [child] when nothing has been pressed or touched for [after] and nothing is
/// playing. The first key press or touch wakes it, and is not passed on to the app underneath.
class IdleScreensaver extends StatefulWidget {
  final Widget child;

  /// How long without input; zero turns the screensaver off.
  final Duration after;

  /// How often to look at the clock (a few seconds is plenty).
  final Duration check;
  final Widget Function(BuildContext context) view;
  const IdleScreensaver({
    super.key,
    required this.child,
    required this.after,
    required this.view,
    this.check = const Duration(seconds: 10),
  });

  @override
  State<IdleScreensaver> createState() => _IdleScreensaverState();
}

class _IdleScreensaverState extends State<IdleScreensaver>
    with WidgetsBindingObserver {
  Duration _idle = Duration.zero;
  Timer? _timer;
  bool _active = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    Screensaver.preview.addListener(_onPreview);
    Screensaver.busy.addListener(_onBusy);
    _restart();
  }

  @override
  void didUpdateWidget(IdleScreensaver old) {
    super.didUpdateWidget(old);
    if (old.after != widget.after || old.check != widget.check) _restart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    Screensaver.preview.removeListener(_onPreview);
    Screensaver.busy.removeListener(_onBusy);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _idle = Duration.zero;
  }

  void _restart() {
    _timer?.cancel();
    _idle = Duration.zero;
    if (widget.after > Duration.zero) {
      _timer = Timer.periodic(widget.check, (_) => _tick());
    }
    if (_active && widget.after == Duration.zero) {
      setState(() => _active = false);
    }
  }

  void _tick() {
    if (_active) return;
    if (!_foreground || Screensaver.busy.value > 0) {
      _idle = Duration.zero;
      return;
    }
    // Counting ticks rather than comparing clocks, so a clock change cannot start it early.
    _idle += widget.check;
    if (_idle >= widget.after) setState(() => _active = true);
  }

  void _onBusy() {
    // Starting a video ends the screensaver, and what is on screen next counts as fresh activity.
    _idle = Duration.zero;
    if (_active && Screensaver.busy.value > 0) setState(() => _active = false);
  }

  void _onPreview() {
    if (mounted) setState(() => _active = true);
  }

  void _poke() => _idle = Duration.zero;

  void _wake() {
    _poke();
    if (_active) setState(() => _active = false);
  }

  bool _onKey(KeyEvent e) {
    if (_active) {
      if (e is KeyDownEvent) _wake();
      return true; // the key that woke it does nothing else
    }
    _poke();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _poke(),
      onPointerMove: (_) => _poke(),
      onPointerSignal: (_) => _poke(),
      child: Stack(fit: StackFit.passthrough, children: [
        widget.child,
        if (_active)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _wake(),
              onPanStart: (_) => _wake(),
              child: widget.view(context),
            ),
          ),
      ]),
    );
  }
}

/// Columns of posters drifting up and down at different speeds, with the time in a corner.
/// Everything moves slowly and the clock wanders, so nothing burns into the screen.
class ScreensaverView extends StatefulWidget {
  /// Poster or logo addresses to show.
  final List<String> images;
  final String Function() clock;
  const ScreensaverView({super.key, required this.images, required this.clock});

  @override
  State<ScreensaverView> createState() => _ScreensaverViewState();
}

class _ScreensaverViewState extends State<ScreensaverView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 240))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF05050A),
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 6 : 3;
        final w = box.maxWidth / cols;
        final tileW = w * 0.84, tileH = tileW * 1.5;
        final imgs = widget.images;
        return Stack(fit: StackFit.expand, children: [
          if (imgs.isNotEmpty)
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Stack(children: [
                for (var i = 0; i < cols; i++)
                  _column(i, cols, w, tileW, tileH, box.maxHeight, imgs),
              ]),
            ),
          // Darkens the artwork so the clock reads from across the room.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.1,
                colors: [Color(0x66000000), Color(0xCC000000)],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              // The clock walks slowly around the screen.
              final t = _c.value * 2 * math.pi * 6;
              return Align(
                alignment:
                    Alignment(0.55 * math.sin(t), 0.45 * math.cos(t * 0.7)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.clock(),
                      style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                          letterSpacing: 2)),
                  const Text('StreamBoss',
                      style: TextStyle(
                          fontSize: 14,
                          letterSpacing: 6,
                          color: Colors.white54)),
                ]),
              );
            },
          ),
        ]);
      }),
    );
  }

  Widget _column(int i, int cols, double w, double tileW, double tileH,
      double h, List<String> imgs) {
    const gap = 14.0;
    final step = tileH + gap;
    // Enough tiles to cover the screen twice, so the loop has no visible seam.
    final count = (h / step).ceil() + 2;
    final loop = count * step;
    final speed =
        1.0 + (i % 3) * 0.6; // loops per animation cycle, a slow drift
    final dir = i.isEven ? -1.0 : 1.0;
    final off = (_c.value * speed * 3) % 1.0 * loop * dir;
    return Positioned(
      left: i * w + (w - tileW) / 2,
      top: 0,
      width: tileW,
      height: h,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: loop * 2,
          child: Transform.translate(
            offset: Offset(0, off - (dir > 0 ? loop : 0)),
            child: RepaintBoundary(
              child: Column(children: [
                for (var k = 0; k < count * 2; k++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: SizedBox(
                      width: tileW,
                      height: tileH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: NetImage(imgs[(i * 7 + k % count) % imgs.length],
                            fallback: () =>
                                const ColoredBox(color: Color(0xFF15151F))),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
