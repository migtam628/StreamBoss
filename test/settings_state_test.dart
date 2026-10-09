import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streamboss/services/net_config.dart';
import 'package:streamboss/services/time_format.dart';
import 'package:streamboss/state/settings_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults, typed set, and numeric coercion', () async {
    final s = SettingsState();
    await s.init();
    expect(s.autoResume, true);
    expect(s.seekSecs, 10);
    expect(s.uiScale, 1.0);
    s.set('uiScale', 1); // int into a double setting
    expect(s.uiScale, 1.0);
    s.set('seekSecs', 30.0); // double into an int setting
    expect(s.seekSecs, 30);
    expect(() => s.set('seekSecs', 'x'), throwsArgumentError);
    expect(() => s.set('nope', 1), throwsArgumentError);
  });

  test('values persist across instances, including legacy keys', () async {
    SharedPreferences.setMockInitialValues(
        {'subBg': false, 'decoder': 'software', 'speed': 1.5});
    final a = SettingsState();
    await a.init();
    expect(a.subBackground, false);
    expect(a.decoder, 'software');
    expect(a.speed, 1.5);
    a.set('hideAdult', true);
    a.set('skipSecs', 120);
    final b = SettingsState();
    await b.init();
    expect(b.hideAdult, true);
    expect(b.skipSecs, 120);
  });

  test('user agent drives NetConfig and is skipped when empty', () async {
    final s = SettingsState();
    await s.init();
    expect(NetConfig.headers, isEmpty);
    s.set('userAgent', NetConfig.presets['VLC']!);
    expect(NetConfig.userAgent, startsWith('VLC/'));
    expect(NetConfig.headers['User-Agent'], startsWith('VLC/'));
    s.set('userAgent', '');
    expect(NetConfig.headers, isEmpty);
  });

  test('backups leave API keys out and restore the rest', () async {
    final a = SettingsState();
    await a.init();
    a.set('tmdbKey', 'secret-key');
    a.set('uiScale', 1.3);
    final map = a.toMap();
    expect(map.containsKey('tmdbKey'), isFalse);
    expect(a.toMap(includeSecrets: true)['tmdbKey'], 'secret-key');

    SharedPreferences.setMockInitialValues({}); // a different device
    final b = SettingsState();
    await b.init();
    b.applyMap({...map, 'tmdbKey': 'injected', 'bogus': 5, 'seekSecs': 'bad'});
    expect(b.uiScale, 1.3);
    expect(b.tmdbKey, '');
    expect(b.seekSecs, 10);
  });

  test('resetAll restores defaults and clears shader toggles', () async {
    final s = SettingsState();
    await s.init();
    s.set('sortAz', true);
    s.set('userAgent', 'X');
    s.setShaders(enabled: {'sharpen'});
    s.resetAll();
    expect(s.sortAz, false);
    expect(NetConfig.userAgent, '');
    expect(s.shaderEnabled, isEmpty);
    expect(s.isDefault('sortAz'), true);
  });

  test('fmtTime formats 24h and 12h clocks', () {
    expect(fmtTime(DateTime(2024, 1, 1, 18, 5), use24h: true), '18:05');
    expect(fmtTime(DateTime(2024, 1, 1, 18, 5), use24h: false), '6:05 PM');
    expect(fmtTime(DateTime(2024, 1, 1, 0, 0), use24h: false), '12:00 AM');
    expect(fmtTime(DateTime(2024, 1, 1, 12, 30), use24h: false), '12:30 PM');
    // Guide times are UTC; they show in the device's own time zone.
    final utc = DateTime.utc(2024, 7, 1, 18, 5);
    expect(fmtTime(utc, use24h: true), fmtTime(utc.toLocal(), use24h: true));
  });

  group('surfaceOutput (Android TV hardware surface)', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      SettingsState.detectedTv = false;
    });

    Future<SettingsState> make() async {
      final s = SettingsState();
      await s.init();
      return s;
    }

    test('automatic: on for an Android TV, off for phones and other platforms',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SettingsState.detectedTv = true;
      expect((await make()).surfaceOutput, true);
      SettingsState.detectedTv = false;
      expect((await make()).surfaceOutput, false);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      SettingsState.detectedTv = true;
      expect((await make()).surfaceOutput, false);
    });

    test('explicit choices win, but software decoding never uses the surface',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SettingsState.detectedTv = true;
      final s = await make();
      s.set('videoOutput', 'compat');
      expect(s.surfaceOutput, false);
      s.set('videoOutput', 'surface');
      expect(s.surfaceOutput, true);
      s.set('decoder', 'software');
      expect(s.surfaceOutput, false);
    });

    test('is a device setting, not part of a backup', () {
      expect(SettingsState.deviceKeys, contains('videoOutput'));
    });
  });
}
