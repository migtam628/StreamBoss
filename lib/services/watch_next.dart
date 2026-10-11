import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/media.dart';

/// A title you are partway through, for the "Continue watching" row on the Android TV / Google TV home screen.
class ContinueEntry {
  final MediaItem item;
  final int positionMs, durationMs;
  const ContinueEntry(this.item, this.positionMs, this.durationMs);

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  Map<String, Object?> toMap() => {
        'key': item.key,
        'title': item.name,
        'poster': item.poster,
        'position': positionMs,
        'duration': durationMs,
      };
}

/// The most recent films and episodes that have a resume position and are not finished, newest first.
/// [recents] is newest first; live channels and titles with an unknown length are left out.
List<ContinueEntry> continueEntries(List<MediaItem> recents,
    Map<String, int> positions, Map<String, int> durations,
    {Set<String> watched = const {}, int max = 10}) {
  final out = <ContinueEntry>[];
  for (final i in recents) {
    if (i.kind == MediaKind.live ||
        i.streamUrl == null ||
        watched.contains(i.key)) {
      continue;
    }
    final p = positions[i.key], d = durations[i.key];
    if (p == null || d == null || d <= 0 || p <= 0 || p >= d) continue;
    out.add(ContinueEntry(i, p, d));
    if (out.length >= max) break;
  }
  return out;
}

/// Where the row goes. A small interface so the app and tests do not depend on the platform.
abstract class WatchNextSink {
  bool get supported;

  /// Replaces the row with [entries] (an empty list removes it).
  Future<void> publish(List<ContinueEntry> entries);
}

class NoopWatchNext implements WatchNextSink {
  const NoopWatchNext();
  @override
  bool get supported => false;
  @override
  Future<void> publish(List<ContinueEntry> entries) async {}
}

/// Android TV's "Watch Next" row, through the native side added by tool/patch_android.dart. Phones and Fire TV
/// have no such row: the calls do nothing there.
class AndroidWatchNext implements WatchNextSink {
  static const _channel = MethodChannel('com.streamboss/watchnext');

  /// [onLaunch] gets the key of the title whose card was chosen on the home screen.
  AndroidWatchNext({required void Function(String key) onLaunch}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'launch' && call.arguments is String) {
        onLaunch(call.arguments as String);
      }
    });
  }

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get supported => platformSupported;

  /// The title chosen on the home screen that started the app, if any (cleared once read).
  Future<String?> launchKey() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('takeLaunch');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> publish(List<ContinueEntry> entries) async {
    if (!supported) return;
    try {
      await _channel
          .invokeMethod<bool>('publish', [for (final e in entries) e.toMap()]);
    } catch (_) {
      // No Watch Next on this device (a phone, Fire TV): nothing to show.
    }
  }
}
