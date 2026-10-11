import 'reminders.dart';

/// Puts reminders in the system's notification list, so they arrive even when the app is closed.
/// Where that is not possible the app still shows its own banner while it is open (see [AppState]).
abstract class ReminderNotifier {
  /// Whether this platform can show a reminder when the app is not running.
  bool get supported;

  /// Asks the person to allow notifications if the system needs that. True when they are allowed.
  Future<bool> ensurePermission();

  /// Schedules [r] for [at], replacing any earlier schedule of the same reminder.
  Future<void> schedule(Reminder r, DateTime at, String body);

  Future<void> cancel(int id);
  Future<void> cancelAll();
}

/// Does nothing: used on platforms without system notifications, and in tests.
class NoopReminderNotifier implements ReminderNotifier {
  const NoopReminderNotifier();
  @override
  bool get supported => false;
  @override
  Future<bool> ensurePermission() async => false;
  @override
  Future<void> schedule(Reminder r, DateTime at, String body) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}
