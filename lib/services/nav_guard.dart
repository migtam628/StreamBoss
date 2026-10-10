/// Stops a screen from being opened twice by a double tap or a held OK key. Opening the player twice
/// starts two video decoders at once, which a TV stick with little memory cannot always survive.
class NavGuard {
  static DateTime? _last;

  /// How long after one screen opens another may be opened.
  static const gap = Duration(milliseconds: 700);

  /// True when a screen may be opened now, and notes that one is being opened. [now] is for tests.
  static bool allow({DateTime? now}) {
    final t = now ?? DateTime.now();
    final last = _last;
    if (last != null && t.difference(last) < gap && !t.isBefore(last)) return false;
    _last = t;
    return true;
  }

  static void reset() => _last = null;
}

/// Channel zapping that waits for the person to stop pressing: each press moves a pending target and
/// only the final one is tuned. Tuning every channel passed on the way (a held Up key, or a quick run
/// of presses) opens a stream per step, and a decoder that is torn down and started that fast can
/// crash the app.
class Zap {
  int? pending;

  /// Moves the target [delta] channels from where it is now (or from [current] when nothing is
  /// pending), wrapping round [length] channels, and returns it.
  int step(int current, int delta, int length) {
    final base = pending ?? current;
    return pending = (((base + delta) % length) + length) % length;
  }

  /// Sets the target outright (a typed number, a pick from the list).
  int aim(int index) => pending = index;

  /// The target to tune, once; null when nothing is pending.
  int? take() {
    final p = pending;
    pending = null;
    return p;
  }
}
