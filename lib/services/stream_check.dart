import 'dart:async';
import '../models/media.dart';
import 'http_client.dart';
import 'net_config.dart';
import 'url_peek.dart';

typedef Peek = Future<UrlPeek> Function(
    Uri uri, Map<String, String> headers, Duration timeout);

/// Why [item]'s stream looks offline, or null when it answers like a stream.
///
/// Asks for the first 2 KB only and hangs up as soon as something arrives, so checking a live
/// channel never keeps a connection open (a provider counts it against the account's connection
/// limit). Sends the headers the playlist asked for.
Future<String?> streamProblem(MediaItem item,
    {Duration timeout = const Duration(seconds: 8),
    Peek peek = peekUrl}) async {
  final url = item.streamUrl;
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return 'bad address';
  try {
    final r = await peek(
        uri,
        {'Range': 'bytes=0-2047', ...NetConfig.headers, ...?item.headers},
        timeout);
    // Too many requests is the provider limiting connections, not a dead channel.
    if (r.status == 429) return null;
    if (r.status >= 400) return 'HTTP ${r.status}';
    if (r.head.isEmpty) return 'no data';
    final head = String.fromCharCodes(r.head.take(16)).trimLeft().toLowerCase();
    if (r.contentType.contains('text/html') ||
        head.startsWith('<!doctype') ||
        head.startsWith('<html')) {
      return 'not a stream';
    }
    return null;
  } on TimeoutException {
    return 'timed out';
  } on UnsupportedError {
    rethrow;
  } catch (_) {
    return 'unreachable';
  }
}

/// Checks [items] with [parallel] requests at a time and reports each one through [onResult]
/// (problem is null when the stream is fine). Stops early when [cancelled] returns true.
Future<void> checkStreams(
  List<MediaItem> items, {
  required int parallel,
  required void Function(MediaItem item, String? problem, int done) onResult,
  bool Function()? cancelled,
  Duration timeout = const Duration(seconds: 8),
  Peek peek = peekUrl,
}) async {
  var next = 0, done = 0;
  Future<void> worker() async {
    while (cancelled?.call() != true) {
      final i = next++;
      if (i >= items.length) return;
      final problem =
          await streamProblem(items[i], timeout: timeout, peek: peek);
      if (cancelled?.call() == true) return;
      onResult(items[i], problem, ++done);
    }
  }

  await Future.wait([for (var k = 0; k < parallel.clamp(1, 32); k++) worker()]);
}
