import 'package:flutter/widgets.dart';

/// Tells widgets below whether the app is in TV ("10-foot") mode, set from the settings in
/// main.dart. Defaults to false so widgets work unchanged in tests and on other devices.
class TvScope extends InheritedWidget {
  final bool tv;
  const TvScope({super.key, required this.tv, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvScope>()?.tv ?? false;

  @override
  bool updateShouldNotify(TvScope old) => old.tv != tv;
}

/// Keeps content inside the area every TV shows (screens crop up to ~5% at the edges).
class TvSafe extends StatelessWidget {
  final Widget child;
  const TvSafe({super.key, required this.child});

  /// Overscan margin in logical pixels on the TV canvas (about 3.5% of its width and 4% of its height).
  static const insets = EdgeInsets.symmetric(horizontal: 44, vertical: 28);

  @override
  Widget build(BuildContext context) => TvScope.of(context) ? Padding(padding: insets, child: child) : child;
}

/// Draws the app on a fixed-width canvas and scales it to fill the screen. TVs report wildly
/// different logical sizes (a 1080p Fire TV can look like 960 px wide, another like 1920), which made
/// the same layout look zoomed in on one and tiny on another. With this the TV layout always has
/// [width] logical pixels across and the same proportions, whatever the device says.
/// Off (phones, desktop, web) it passes the child through untouched.
class TvCanvas extends StatelessWidget {
  final bool enabled;
  final int width;
  final Widget child;
  const TvCanvas({super.key, required this.enabled, required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return LayoutBuilder(builder: (context, c) {
      if (!c.hasBoundedWidth || !c.hasBoundedHeight || c.maxWidth <= 0 || c.maxHeight <= 0) return child;
      final w = width.toDouble();
      final h = w * c.maxHeight / c.maxWidth;
      final mq = MediaQuery.of(context);
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: w,
          height: h,
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(w, h),
              devicePixelRatio: mq.devicePixelRatio * c.maxWidth / w,
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: child,
          ),
        ),
      );
    });
  }
}
