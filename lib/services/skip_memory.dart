import 'chapters.dart';

/// Where the viewer skipped the opening of a series, so the next episodes can offer the same skip even
/// when the files have no chapters.
class IntroWindow {
  final Duration from, to;
  const IntroWindow(this.from, this.to);

  Map<String, dynamic> toJson() => {'f': from.inMilliseconds, 't': to.inMilliseconds};

  factory IntroWindow.fromJson(Map<String, dynamic> j) =>
      IntroWindow(Duration(milliseconds: (j['f'] as num).toInt()), Duration(milliseconds: (j['t'] as num).toInt()));

  @override
  bool operator ==(Object other) => other is IntroWindow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The window a skip makes, or null when it does not look like skipping an opening: it has to start in the
/// first eight minutes, jump between 45 seconds and four minutes, and be in something long enough to
/// be an episode.
IntroWindow? learnIntro(Duration before, Duration after, Duration total) {
  final jump = after - before;
  if (before > const Duration(minutes: 8)) return null;
  if (jump < const Duration(seconds: 45) || jump > const Duration(minutes: 4)) return null;
  if (total < const Duration(minutes: 15)) return null;
  return IntroWindow(before, after);
}

/// The skip button a learned [window] gives at [position]: from ten seconds before where the viewer
/// skipped last time, until three seconds before it ends. Starts at zero if the earlier skip began
/// within the first twenty seconds, so the button is there from the first frame.
SkipHint? introHintFromMemory(IntroWindow window, Duration position, Duration total) {
  final start = window.from <= const Duration(seconds: 20) ? Duration.zero : window.from - const Duration(seconds: 10);
  if (position < start || position >= window.to - const Duration(seconds: 3)) return null;
  if (total > Duration.zero && window.to >= total) return null;
  return SkipHint(SkipKind.intro, window.to);
}
