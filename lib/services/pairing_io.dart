import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../models/media.dart';
import 'provider_url.dart';

/// Lets someone type their provider login on a phone instead of with a TV remote.
///
/// While a session is open the app serves one small web page on the local network. The phone
/// opens it (scan the QR code or type the address), enters the 4-digit PIN shown on the TV plus
/// the login, and the page posts it back to the app. Nothing leaves the local network, the
/// server only runs while the pairing screen is open, and wrong PINs lock it after a few tries.
abstract class PairingSession {
  /// What the phone should open, e.g. http://192.168.1.20:41234
  String get url;
  String get pin;
  Stream<Source> get sources;
  Future<void> close();
}

bool get pairingSupported => true;

/// Starts a session, or returns null when the device has no local network address.
/// [host] overrides the address shown to the phone (tests).
Future<PairingSession?> startPairing({String? host, Duration lifetime = const Duration(minutes: 10)}) async {
  final address = host ?? await _lanAddress();
  if (address == null) return null;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
  final session = _Session(server, address, lifetime);
  session._listen();
  return session;
}

/// The device's private IPv4 address, preferring typical home-network ranges.
Future<String?> _lanAddress() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final all = [for (final i in ifaces) ...i.addresses.map((a) => a.address)];
    bool private(String a) =>
        a.startsWith('192.168.') || a.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
    for (final a in all) {
      if (private(a)) return a;
    }
    return all.isEmpty ? null : all.first;
  } catch (_) {
    return null;
  }
}

class _Session implements PairingSession {
  _Session(this._server, String host, Duration lifetime)
      : url = 'http://$host:${_server.port}',
        pin = (1000 + Random.secure().nextInt(9000)).toString() {
    _expiry = Timer(lifetime, close);
  }

  final HttpServer _server;
  final _out = StreamController<Source>.broadcast();
  late final Timer _expiry;
  int _wrong = 0;
  bool _closed = false;

  @override
  final String url;
  @override
  final String pin;
  @override
  Stream<Source> get sources => _out.stream;

  static const _maxWrongPins = 5;
  static const _maxBody = 16 * 1024;

  void _listen() => _server.listen(_handle, onError: (_) {});

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    await _server.close(force: true);
    await _out.close();
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final res = req.response
        ..headers.set('Cache-Control', 'no-store')
        ..headers.set('X-Content-Type-Options', 'nosniff');
      if (req.method == 'GET' && req.uri.path == '/') {
        await _html(res, 200, _formPage());
      } else if (req.method == 'POST' && req.uri.path == '/add') {
        await _add(req, res);
      } else {
        await _html(res, 404, _page('Not found', '<p>Nothing here.</p>'));
      }
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _add(HttpRequest req, HttpResponse res) async {
    if (_wrong >= _maxWrongPins) {
      return _html(res, 429, _page('Locked', '<p class="bad">Too many wrong PINs. Close the pairing screen on the TV and start again.</p>'));
    }
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) return _html(res, 413, _page('Too large', '<p class="bad">That request is too large.</p>'));
    }
    final f = Uri.splitQueryString(utf8.decode(bytes, allowMalformed: true));
    if ((f['pin'] ?? '').trim() != pin) {
      _wrong++;
      final left = _maxWrongPins - _wrong;
      return _html(res, 403, _formPage(error: left > 0 ? 'Wrong PIN. $left ${left == 1 ? 'try' : 'tries'} left.' : 'Too many wrong PINs.'));
    }

    final isM3u = f['type'] == 'm3u';
    var url = (f['url'] ?? '').trim();
    var user = (f['user'] ?? '').trim();
    var pass = f['pass'] ?? '';
    if (!isM3u) {
      // A pasted get.php?username=..&password=.. link carries the whole login.
      final login = parseProviderLink(url);
      if (login != null) {
        url = login.server;
        if (user.isEmpty) user = login.username;
        if (pass.isEmpty) pass = login.password;
      }
    }
    if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return _html(res, 400, _formPage(error: 'That address does not look right. Start with http:// or https://'));
    }
    if (!isM3u && (user.isEmpty || pass.isEmpty)) {
      return _html(res, 400, _formPage(error: 'Xtream needs a username and password (or paste the full get.php link).'));
    }
    final name = (f['name'] ?? '').trim();
    _out.add(Source(
      name: name.isEmpty ? 'My Provider' : name,
      type: isM3u ? SourceType.m3u : SourceType.xtream,
      url: url,
      username: isM3u ? '' : user,
      password: isM3u ? '' : pass,
    ));
    await _html(res, 200, _page('Sent', '<p class="ok">Sent to your TV. You can close this page.</p>'));
  }

  Future<void> _html(HttpResponse res, int status, String body) async {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write(body);
    await res.close();
  }

  String _formPage({String? error}) => _page('Add your provider', '''
${error == null ? '' : '<p class="bad">${_esc(error)}</p>'}
<form method="post" action="/add" autocomplete="off">
  <label>PIN shown on your TV<input name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="4" required autofocus></label>
  <label>Type
    <select name="type"><option value="xtream">Xtream Codes</option><option value="m3u">M3U playlist link</option></select>
  </label>
  <label>Name<input name="name" value="My Provider"></label>
  <label>Server or playlist address<input name="url" type="text" inputmode="url" autocapitalize="off" placeholder="http://host:port" required></label>
  <label>Username (Xtream)<input name="user" autocapitalize="off"></label>
  <label>Password (Xtream)<input name="pass" type="password" autocapitalize="off"></label>
  <button type="submit">Send to TV</button>
</form>
<p class="note">This page talks only to your TV over your home network. Nothing goes to the internet.</p>''');

  String _page(String title, String body) => '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>StreamBoss: ${_esc(title)}</title>
<style>
:root{color-scheme:dark}
body{margin:0;background:#0b0b12;color:#f2f2f7;font:16px/1.4 system-ui,sans-serif}
main{max-width:460px;margin:0 auto;padding:24px 20px}
h1{color:#ff3d71;letter-spacing:3px;font-size:22px;margin:0 0 4px}
h2{font-size:18px;margin:0 0 18px;font-weight:600}
label{display:block;margin:0 0 14px;color:#8c8ca1;font-size:13px}
input,select{display:block;width:100%;box-sizing:border-box;margin-top:5px;padding:13px;border:0;border-radius:10px;background:#1f1f2e;color:#f2f2f7;font-size:16px}
button{width:100%;padding:14px;border:0;border-radius:24px;background:#ff3d71;color:#0b0b12;font-size:16px;font-weight:700}
.bad{color:#ff3d71}.ok{color:#7be495;font-size:18px}.note{color:#8c8ca1;font-size:12px;margin-top:18px}
</style></head><body><main><h1>STREAMBOSS</h1><h2>${_esc(title)}</h2>$body</main></body></html>''';

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}
