import 'package:flutter/foundation.dart' show kIsWeb;

/// Helpers for the "paste whatever your provider gave you" case.
class ProviderLogin {
  final String server; // http://host[:port]
  final String username;
  final String password;
  const ProviderLogin(this.server, this.username, this.password);
}

/// Providers usually hand out a playlist link like
/// `http://host:port/get.php?username=U&password=P&type=m3u_plus&output=ts`.
/// Pasted into the Xtream form, that should just work: pull out the server and credentials.
/// Returns null when [raw] doesn't carry credentials in its query string.
ProviderLogin? parseProviderLink(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return null;
  final user = u.queryParameters['username'];
  final pass = u.queryParameters['password'];
  if (user == null || user.isEmpty || pass == null || pass.isEmpty) return null;
  return ProviderLogin(
      '${u.scheme}://${u.host}${u.hasPort ? ':${u.port}' : ''}', user, pass);
}

final _secret =
    RegExp(r'(username|password)=[^&\s)\x27"]+', caseSensitive: false);

/// Never show credentials in error text (they would end up in screenshots and logs).
String redactSecrets(String s) =>
    s.replaceAllMapped(_secret, (m) => '${m[1]}=***');

/// Turns low-level exceptions into something a person can act on.
String friendlyError(Object e, {bool web = kIsWeb, bool secure = false}) {
  final raw = e.toString().replaceFirst('Exception: ', '');
  if (web && RegExp(r'Failed to fetch|NetworkError when attempting to fetch|Load failed').hasMatch(raw)) {
    return webBlockedMessage(raw, secure: secure || Uri.base.scheme == 'https');
  }
  final host = RegExp(r"host lookup: '([^']+)'").firstMatch(raw)?[1];
  if (host != null) {
    return "Couldn't look up '$host'. Check the address and your internet connection.";
  }
  // errno 51/50 = network unreachable/down, 65 = no route to host (macOS); 101/113 on Linux/Android.
  if (RegExp(r'errno = (51|50|65|101|113)\b').hasMatch(raw) ||
      raw.contains('Network is unreachable') ||
      raw.contains('No route to host')) {
    final at = RegExp(r'address = ([^,)]+)').firstMatch(raw)?[1];
    return "This device can't reach ${at == null ? 'the server' : "'$at'"}. Check that you are online and that a VPN, "
        "firewall or content filter isn't blocking StreamBoss, then try again.";
  }
  if (raw.contains('Connection refused') ||
      raw.contains('Connection timed out') ||
      raw.contains('TimeoutException')) {
    return "The server didn't answer. Check the address, port and your connection.";
  }
  return redactSecrets(raw);
}

/// A browser refuses some requests the apps make: a plain http address from a page opened over https (mixed content)
/// and any server that does not say websites may read it (CORS). The browser hides which one it was, so this says
/// what is likely and what to do.
String webBlockedMessage(String raw, {required bool secure}) {
  final at = RegExp(r'uri=https?://(\[[^\]]+\]|[^/:\s?)]+)', caseSensitive: false).firstMatch(raw)?[1];
  final where = at == null ? 'that server' : "'$at'";
  final plainHttp = secure && RegExp(r'uri=http://', caseSensitive: false).hasMatch(raw);
  // A server on this very computer is not blocked as plain http (browsers let a secure page reach it): what stops the
  // page is that the server does not say websites may read it.
  if (at != null && _isLoopback(at)) {
    return "The browser blocked $where, a server on this computer. A web page may not read it unless that server allows it "
        '(it has to send an Access-Control-Allow-Origin header, and for a page on the internet, Access-Control-Allow-Private-Network too). '
        'Use the StreamBoss app for your device, or run the web app from this computer, or let that server allow websites.';
  }
  if (plainHttp) {
    return "The browser blocked $where: it is a plain http address and this page is secure (https). "
        'Use an https address if your provider has one, or use the StreamBoss app for your device, which has no such limit.';
  }
  return "The browser could not read $where. Either it is offline, or it does not allow websites to read it "
      '(a browser rule that the StreamBoss apps do not have). Use the StreamBoss app for your device, or ask the provider for an https address that allows it.';
}

bool _isLoopback(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  return h == 'localhost' || h == '::1' || RegExp(r'^127(\.\d{1,3}){3}$').hasMatch(h);
}

/// What the player (libmpv) reported, in words a person can act on. Returns the message and
/// whether the usual advice (switch the decoder) is relevant: it isn't for network problems.
({String message, bool decoderAdvice}) friendlyPlayerError(String raw) {
  final dns = RegExp(r'Failed to resolve hostname ([^\s:]+)|No address associated with hostname|Name or service not known|nodename nor servname')
      .firstMatch(raw);
  if (dns != null) {
    final host = RegExp(r'Failed to resolve hostname ([^\s:]+)').firstMatch(raw)?[1];
    return (
      message: "This network can't look up ${host == null ? 'the video server' : "'$host'"}. "
          'The catalog loaded, but the video itself is served from that other address, and the DNS your connection uses '
          '(mobile carrier, router, Private DNS or an ad-blocking DNS) is not resolving it. Try Wi-Fi instead of mobile data '
          '(or the other way round), turn off any ad-blocking or filtering DNS or VPN, or set Private DNS to dns.google or one.one.one.one.',
      decoderAdvice: false,
    );
  }
  if (RegExp(r'Connection (refused|timed out)|Network is unreachable|No route to host|Failed to open|HTTP error 4\d\d|HTTP error 5\d\d').hasMatch(raw)) {
    return (message: raw, decoderAdvice: false);
  }
  return (message: raw, decoderAdvice: true);
}

/// Reduces every stream or playlist URL in [s] to scheme://host/…, dropping the path, query
/// and any user:password@. Xtream stream URLs carry the login in the path, so logs that may be
/// copied or shared must never contain them.
String redactUrls(String s) => s.replaceAllMapped(
      RegExp(r'\b(https?|rtmps?|rtsp|udp|rtp|mms)://([^/\s"\x27)<>]*)[^\s"\x27)<>]*', caseSensitive: false),
      (m) {
        final host = m[2]!.contains('@') ? m[2]!.substring(m[2]!.lastIndexOf('@') + 1) : m[2]!;
        return '${m[1]}://$host/…';
      },
    );
