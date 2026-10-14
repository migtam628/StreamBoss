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
      item.kind == MediaKind.live) return null;
  final url = item.streamUrl;
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !RegExp(r'^/(?:movie|series)/[^/]+/[^/]+/[1-9][0-9]*\.m3u8$')
          .hasMatch(uri.path)) return null;
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
