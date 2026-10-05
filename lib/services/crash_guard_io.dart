import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'crash_report.dart';

/// Flight recorder for playback. libmpv and the video output are native code, so a crash there
/// takes the whole app down with no chance to report it from Dart. Instead each playback session
/// writes its steps (and libmpv's warnings and errors, with URLs reduced to their host) to a small
/// file, flushed as it goes, and deletes it on a clean exit. If the file is still there at the next
/// start, the last session did not end cleanly and its content says how far it got.
class CrashGuard {
  static File? _session, _last;
  static CrashReport? _pending;
  static int _bytes = 0;
  static const _cap = 48 * 1024;

  static Future<void> init() async {
    try {
      initIn(await getApplicationSupportDirectory());
    } catch (_) {
      // No storage: the app still works, it just can't keep a playback log.
    }
  }

  /// [init] with an explicit directory (tests).
  static void initIn(Directory dir) {
    _pending = null;
    _bytes = 0;
    try {
      dir.createSync(recursive: true);
      _session = File('${dir.path}/playback.session');
      _last = File('${dir.path}/last_playback.log');
      if (_session!.existsSync()) {
        final text = _session!.readAsStringSync();
        _last!.writeAsStringSync(text);
        _session!.deleteSync();
        if (text.trim().isNotEmpty) _pending = CrashReport(text);
      }
    } catch (_) {
      _session = null;
    }
  }

  /// The report for an unclean last session, once. Null if the last session ended normally.
  static CrashReport? takeReport() {
    final r = _pending;
    _pending = null;
    return r;
  }

  /// The most recent playback session's log (for Settings > About).
  static String lastLog() {
    try {
      final s = _session;
      if (s != null && s.existsSync()) return s.readAsStringSync();
      return _last != null && _last!.existsSync() ? _last!.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  static String _now() => DateTime.now().toIso8601String().substring(11, 23);

  /// [capped] lines (libmpv's chatter) stop once the log is full; steps are few and always kept,
  /// because they are what tells a startup crash from a later one.
  static void _write(String line, {bool truncate = false, bool capped = false}) {
    final f = _session;
    if (f == null) return;
    if (capped && _bytes > _cap) return;
    try {
      final out = '[${_now()}] $line\n';
      f.writeAsStringSync(out, mode: truncate ? FileMode.write : FileMode.append, flush: true);
      _bytes = truncate ? out.length : _bytes + out.length;
    } catch (_) {}
  }

  static void begin(String info) => _write('step begin $info', truncate: true);
  static void mark(String step) => _write('step $step');
  static void log(String line) => _write('log $line', capped: true);

  /// A clean end: keep the log for About, remove the "still running" file.
  static void end() {
    final s = _session;
    if (s == null) return;
    try {
      if (s.existsSync()) {
        _last?.writeAsStringSync(s.readAsStringSync());
        s.deleteSync();
      }
    } catch (_) {}
  }
}
