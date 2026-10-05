import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'provider_url.dart';

/// Dart races IPv4 and IPv6 and, when everything fails, reports the *first* error, which is
/// usually the instant "Network is unreachable" from a missing IPv6 route and hides what
/// actually went wrong over IPv4. This tries IPv4 addresses first and reports their error.
Future<ConnectionTask<Socket>> ipv4FirstConnect(
    Uri url, String? proxyHost, int? proxyPort) async {
  final host = proxyHost ?? url.host;
  final port = proxyPort ?? url.port;
  List<InternetAddress> v4;
  try {
    v4 = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
  } on SocketException {
    v4 = const [];
  }
  if (v4.isEmpty) return Socket.startConnect(host, port);

  var cancelled = false;
  final socket = () async {
    Object? firstError;
    StackTrace? firstStack;
    for (final a in v4) {
      if (cancelled) break;
      try {
        return await Socket.connect(a, port,
            timeout: const Duration(seconds: 12));
      } catch (e, s) {
        firstError ??= e;
        firstStack ??= s;
      }
    }
    Error.throwWithStackTrace(
        firstError ?? const SocketException('Connection cancelled'),
        firstStack ?? StackTrace.current);
  }();
  return ConnectionTask.fromSocket(socket, () => cancelled = true);
}

http.Client makeHttpClient() =>
    IOClient(HttpClient()..connectionFactory = ipv4FirstConnect);

String _err(Object e) => redactSecrets(e is SocketException
    ? '${e.message}${e.osError == null ? '' : ' (${e.osError})'}'
    : '$e');

/// A step-by-step reachability report for [url]'s host. Contains no credentials.
Future<String> diagnoseConnection(Uri url, http.Client client) async {
  final out = StringBuffer();
  final host = url.host;
  final port = url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80);
  out.writeln('Host: $host:$port');
  final addrs = <InternetAddress>[];
  for (final t in [InternetAddressType.IPv4, InternetAddressType.IPv6]) {
    final label = t == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6';
    try {
      final r = await InternetAddress.lookup(host, type: t);
      out.writeln('DNS $label: ${r.map((a) => a.address).join(', ')}');
      addrs.addAll(r.take(2));
    } catch (e) {
      out.writeln('DNS $label: ${_err(e)}');
    }
  }
  for (final a in addrs) {
    final sw = Stopwatch()..start();
    try {
      final s =
          await Socket.connect(a, port, timeout: const Duration(seconds: 6));
      s.destroy();
      out.writeln('Connect ${a.address}: ok in ${sw.elapsedMilliseconds} ms');
    } catch (e) {
      out.writeln(
          'Connect ${a.address}: failed after ${sw.elapsedMilliseconds} ms, ${_err(e)}');
    }
  }
  try {
    final res = await client
        .get(url.replace(path: '/', query: ''))
        .timeout(const Duration(seconds: 15));
    out.writeln('HTTP GET /: ${res.statusCode}');
  } catch (e) {
    out.writeln('HTTP GET /: failed, ${_err(e)}');
  }
  return out.toString().trimRight();
}
