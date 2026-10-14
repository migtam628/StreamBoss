import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:media_kit/media_kit.dart';
import 'http_client.dart';
import 'net_config.dart';
import '../models/media.dart';

/// Opt-in renewal of MooBee's four-hour signed-HLS VOD URLs.
///
/// No refresh is attempted for live TV, ordinary providers, browser sessions,
/// or URLs other than the original credential-authenticated Xtream VOD entry.
/// Never log an entry URL; it contains the subscriber password.
Duration? signedHlsRefreshInterval(MediaItem item, int? hintSeconds,
    {required bool isWeb}) {
  if (isWeb || hintSeconds == null ||
      hintSeconds < 300 || hintSeconds > 12600 ||
      item.kind == MediaKind.live) {
    return null;
  }
  final url = item.streamUrl;
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !RegExp(r'^/(?:movie|series)/[^/]+/[^/]+/[1-9][0-9]*\.m3u8$')
          .hasMatch(uri.path)) {
    return null;
  }
  // Explicit debug-only opt-in. Production builds always use the server hint.
  // Flutter run example: --dart-define=MOOBEE_TEST_HLS_REFRESH_SECONDS=45
  const testSeconds = int.fromEnvironment(
      'MOOBEE_TEST_HLS_REFRESH_SECONDS', defaultValue: 0);
  if (kDebugMode && testSeconds >= 30 && testSeconds <= 300) {
    return Duration(seconds: testSeconds);
  }
  return Duration(seconds: hintSeconds);
}

/// Tracks a media_kit Player's original HLS lease across the watch page and
/// fullscreen when they share that same player. Never stores the bearer token.
class SignedHlsLeaseClock {
  static final Expando<DateTime> _opened = Expando<DateTime>('hls-opened');
  static final Expando<DateTime> _retryNotBefore =
      Expando<DateTime>('hls-retry-after');

  static void opened(Object player, {DateTime? at}) {
    _opened[player] = at ?? DateTime.now();
    _retryNotBefore[player] = null;
  }

  static void ensure(Object player, {DateTime? at}) {
    if (_opened[player] == null) opened(player, at: at);
  }

  static bool due(Object player, Duration interval, {DateTime? now}) {
    final openedAt = _opened[player];
    if (openedAt == null) return false;
    final current = now ?? DateTime.now();
    final retry = _retryNotBefore[player];
    return !current.isBefore(openedAt.add(interval)) &&
        (retry == null || !current.isBefore(retry));
  }

  static void retryLater(Object player, {DateTime? at}) {
    _retryNotBefore[player] =
        (at ?? DateTime.now()).add(const Duration(minutes: 2));
  }
}

/// Obtain a fresh *authenticated initial playlist* before replacing media_kit's
/// playlist. If the server rejects auth or cannot be reached, leave the
/// currently playing media alone; the caller retries before original expiry.
/// Returns false when the preflight response is not an HLS manifest.
/// Throws only on network/player errors; callers must redact error details.
Future<bool> renewSignedHlsMedia(
    Player player,
    MediaItem item, {
    bool Function()? isCurrent,
  }) async {
  final address = item.streamUrl;
  if (address == null) return false;
  final response = await appHttp
      .get(Uri.parse(address), headers: {...NetConfig.headers, ...?item.headers})
      .timeout(const Duration(seconds: 20));
  if (response.statusCode != 200 ||
      !response.body.startsWith('#EXTM3U')) {
    return false;
  }
  if (isCurrent != null && !isCurrent()) return false;

  final pos = player.state.position;
  final playing = player.state.playing;
  final rate = player.state.rate;
  await player.open(Media(address, start: pos, httpHeaders: item.headers),
      play: playing);
  if (rate != 1.0) {
    await player.setRate(rate);
  }
  return true;
}
