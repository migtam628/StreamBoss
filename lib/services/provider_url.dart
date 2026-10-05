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
String friendlyError(Object e) {
  final raw = e.toString().replaceFirst('Exception: ', '');
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
