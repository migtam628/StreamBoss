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

  /// Overscan margin in logical pixels (about 2.5% / 5% of a 960x540 layout).
  static const insets = EdgeInsets.symmetric(horizontal: 32, vertical: 24);

  @override
  Widget build(BuildContext context) => TvScope.of(context) ? Padding(padding: insets, child: child) : child;
}
