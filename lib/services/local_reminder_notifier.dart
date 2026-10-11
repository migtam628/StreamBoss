import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'reminder_notifier.dart';
import 'reminders.dart';

/// Reminders as system notifications on Android, iOS and macOS (the platforms that can schedule one for a
/// later time). Tapping one reports the channel's key through [onOpen].
class LocalReminderNotifier implements ReminderNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final void Function(String channelKey) onOpen;
  bool _ready = false;

  LocalReminderNotifier({required this.onOpen});

  static bool get platformSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS);

  @override
  bool get supported => platformSupported && _ready;

  /// Sets the plugin up. Returns the channel key of a notification that started the app, if one did.
  Future<String?> init() async {
    if (!platformSupported) return null;
    try {
      tzdata.initializeTimeZones();
      const darwin = DarwinInitializationSettings(
          requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) onOpen(p);
        },
      );
      _ready = true;
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final p = launch?.notificationResponse?.payload;
      return (launch?.didNotificationLaunchApp ?? false) && p != null && p.isNotEmpty ? p : null;
    } catch (_) {
      _ready = false;
      return null;
    }
  }

  @override
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          final ok = await a?.areNotificationsEnabled() ?? true;
          if (ok) return true;
          return await a?.requestNotificationsPermission() ?? false;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: false, sound: true) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                  ?.requestPermissions(alert: true, badge: false, sound: true) ??
              false;
        default:
          return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(Reminder r, DateTime at, String body) async {
    if (!_ready) return;
    try {
      var mode = AndroidScheduleMode.inexactAllowWhileIdle;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        // On Android 12 and later exact timing is a permission the person can switch off; without it the
        // reminder still comes, a few minutes late at worst.
        if (await a?.canScheduleExactNotifications() ?? false) mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: body,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, at.millisecondsSinceEpoch),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('reminders', 'Programme reminders',
              channelDescription: 'A heads-up shortly before a programme you asked about starts',
              importance: Importance.high,
              priority: Priority.high),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: mode,
        payload: r.channelKey,
      );
    } catch (_) {
      // A reminder that cannot be scheduled is still shown by the banner while the app is open.
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
