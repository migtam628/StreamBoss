import 'crash_report.dart';

/// The browser has no native player to crash; everything is a no-op.
class CrashGuard {
  static Future<void> init() async {}
  static CrashReport? takeReport() => null;
  static String lastLog() => '';
  static void begin(String info) {}
  static void mark(String step) {}
  static void log(String line) {}
  static void end() {}
}
