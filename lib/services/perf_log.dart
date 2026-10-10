/// Timings of the parts of the app that decide how fast it feels: how long until the first screen,
/// whether the library came from the saved copy or the network, and how long fetching and reading it
/// took. Shown in Settings > About > Copy diagnostics, so slow starts can be tuned from real numbers.
class PerfLog {
  static final Stopwatch _clock = Stopwatch();
  static final Map<String, int> _marks = {};
  static final Map<String, String> _facts = {};

  /// Starts the clock; call first thing in main().
  static void start() {
    _marks.clear();
    _facts.clear();
    _clock
      ..reset()
      ..start();
  }

  /// Notes that [name] happened now (the first time only).
  static void mark(String name) => _marks.putIfAbsent(name, () => _clock.elapsedMilliseconds);

  /// Keeps a measurement or a fact under [name] (the latest wins).
  static void fact(String name, Object value) => _facts[name] = '$value';

  /// Runs [job], notes how long it took under [name] (in milliseconds) and returns its result.
  static Future<T> time<T>(String name, Future<T> Function() job) async {
    final sw = Stopwatch()..start();
    try {
      return await job();
    } finally {
      fact(name, '${sw.elapsedMilliseconds} ms');
    }
  }

  static int? at(String name) => _marks[name];
  static String? factOf(String name) => _facts[name];

  /// One line per measurement, in the order they were taken.
  static List<String> report() => [
        for (final e in (_marks.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))) '${e.key}: ${e.value} ms after start',
        for (final e in _facts.entries) '${e.key}: ${e.value}',
      ];
}
