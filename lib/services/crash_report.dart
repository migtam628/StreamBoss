/// A playback session recorded by CrashGuard that never reached a clean end: the app was
/// killed or crashed while it was running. Pure Dart so it can be tested and shown anywhere.
class CrashReport {
  final String text;
  const CrashReport(this.text);

  /// The last recorded step, e.g. `begin`, `props`, `open`, `opened`, `playing`.
  String get lastStep {
    String step = 'unknown';
    for (final line in text.split('\n')) {
      final m = RegExp(r'^\[[^\]]*\] step (\S+)').firstMatch(line);
      if (m != null) step = m[1]!;
    }
    return step;
  }

  /// True when it died before any picture appeared, i.e. while setting up or opening the stream.
  /// Later steps (playing, background, closing) are not startup failures: the system may simply
  /// have ended an app that was sent to the background.
  bool get duringStartup => const {'begin', 'props', 'open', 'opened'}.contains(lastStep);

  /// The most recent [n] lines, for showing on a TV screen.
  String tail([int n = 14]) {
    final lines = text.trimRight().split('\n');
    return lines.skip(lines.length > n ? lines.length - n : 0).join('\n');
  }
}
