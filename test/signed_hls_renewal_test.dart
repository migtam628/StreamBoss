import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/models/media.dart';
import 'package:streamboss/services/signed_hls_renewal.dart';
import 'package:streamboss/services/xtream_client.dart';

void main() {
  const item = MediaItem(
    id: '101', name: 'Test movie', kind: MediaKind.movie,
    streamUrl: 'http://127.0.0.1:18001/movie/stageviewer/secret/101.m3u8',
  );

  test('only native provider-advertised Xtream VOD receives a refresh schedule', () {
    expect(signedHlsRefreshInterval(item, 10800, isWeb: false),
        const Duration(hours: 3));
    expect(signedHlsRefreshInterval(item, null, isWeb: false), isNull);
    expect(signedHlsRefreshInterval(item, 10800, isWeb: true), isNull);
    expect(signedHlsRefreshInterval(item, 12, isWeb: false), isNull);
    expect(signedHlsRefreshInterval(item, 14400, isWeb: false), isNull);
    const live = MediaItem(
      id: '10', name: 'Live', kind: MediaKind.live,
      streamUrl: 'http://127.0.0.1:18001/live/viewer/pass/10.m3u8',
    );
    expect(signedHlsRefreshInterval(live, 10800, isWeb: false), isNull);
    const other = MediaItem(
      id: '10', name: 'Other', kind: MediaKind.movie,
      streamUrl: 'https://example.invalid/video/10.mp4',
    );
    expect(signedHlsRefreshInterval(other, 10800, isWeb: false), isNull);
  });

  test('account metadata accepts only bounded opt-in renewal hint', () {
    final info = AccountInfo.fromUserInfo({
      'status': 'Active', 'moobee_hls_refresh_after_seconds': 10800,
    });
    expect(info.hlsRefreshAfterSeconds, 10800);
    expect(AccountInfo.fromUserInfo({
      'moobee_hls_refresh_after_seconds': -1,
    }).hlsRefreshAfterSeconds, isNull);
    expect(AccountInfo.fromUserInfo({
      'moobee_hls_refresh_after_seconds': 'garbage',
    }).hlsRefreshAfterSeconds, isNull);
  });

  test('player lease shared across watch and fullscreen, with retry backoff', () {
    final p = Object();
    final started = DateTime.utc(2026, 10, 14);
    SignedHlsLeaseClock.opened(p, at: started);
    const interval = Duration(hours: 3);
    expect(SignedHlsLeaseClock.due(p, interval,
        now: started.add(const Duration(hours: 2))), isFalse);
    expect(SignedHlsLeaseClock.due(p, interval,
        now: started.add(interval)), isTrue);
    SignedHlsLeaseClock.retryLater(p,
        at: started.add(interval));
    expect(SignedHlsLeaseClock.due(p, interval,
        now: started.add(interval).add(const Duration(minutes: 1))), isFalse);
    expect(SignedHlsLeaseClock.due(p, interval,
        now: started.add(interval).add(const Duration(minutes: 2))), isTrue);
    SignedHlsLeaseClock.opened(p, at: started.add(interval));
    expect(SignedHlsLeaseClock.due(p, interval,
        now: started.add(interval).add(const Duration(minutes: 1))), isFalse);
    expect(SignedHlsLeaseClock.due(Object(), interval,
        now: started.add(const Duration(days: 1))), isFalse);
  });
}
