import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// What the sync server said, in words a person can read.
class SyncException implements Exception {
  final String message;

  /// The server refused the token: the account has to be signed in again.
  final bool signedOut;
  const SyncException(this.message, {this.signedOut = false});
  @override
  String toString() => message;
}

/// One value on the server: its text (null = removed) and the revision it is at.
class RemoteItem {
  final String? value;
  final int rev;
  const RemoteItem(this.value, this.rev);
}

/// The answer to a write built on an old revision.
class Conflict {
  final RemoteItem current;
  const Conflict(this.current);
}

/// Talks to a StreamBoss sync server (see server/). Only the address, the e-mail and the password or token are
/// ever sent with it; nothing about providers.
class SyncApi {
  final Uri base;
  final http.Client _http;
  String? token;
  static const _timeout = Duration(seconds: 25);

  SyncApi(String server, {this.token, http.Client? client})
      : base = Uri.parse(normalizeServer(server)),
        _http = client ?? http.Client();

  /// `sync.example.com` becomes `https://sync.example.com`; a full address is kept (http is for a server on your
  /// own network). Throws [SyncException] for something that cannot be an address.
  static String normalizeServer(String raw) {
    var s = raw.trim();
    if (s.isEmpty) {
      throw const SyncException('Type the address of your sync server.');
    }
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null ||
        u.host.isEmpty ||
        !(u.scheme == 'https' || u.scheme == 'http')) {
      throw const SyncException('That does not look like a server address.');
    }
    return s.replaceFirst(RegExp(r'/+$'), '');
  }

  Uri _u(String path) => Uri.parse('${base.toString()}$path');

  Future<(int, Map<String, dynamic>?)> _call(String method, String path,
      {Object? body, bool auth = true}) async {
    final req = http.Request(method, _u(path))
      ..headers['content-type'] = 'application/json';
    if (auth && token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(
          await _http.send(req).timeout(_timeout));
    } on TimeoutException {
      throw const SyncException('The sync server did not answer.');
    } catch (e) {
      throw SyncException(
          "Could not reach the sync server. Check the address and that you are online. ($e)"
              .replaceAll(RegExp(r'\s+'), ' '));
    }
    Map<String, dynamic>? json;
    if (res.body.isNotEmpty) {
      try {
        final j = jsonDecode(res.body);
        if (j is Map<String, dynamic>) json = j;
      } catch (_) {
        throw const SyncException(
            'That address did not answer like a StreamBoss sync server.');
      }
    }
    return (res.statusCode, json);
  }

  SyncException _error(int status, Map<String, dynamic>? j) => SyncException(
        (j?['error'] as String?) ??
            'The server answered with an error ($status).',
        signedOut: status == 401,
      );

  /// Checks that [base] is a StreamBoss sync server, and says whether it takes new accounts.
  Future<String> health() async {
    final (s, j) = await _call('GET', '/api/health', auth: false);
    if (s != 200 || j?['ok'] != true) {
      throw const SyncException(
          'That address did not answer like a StreamBoss sync server.');
    }
    return (j!['registration'] as String?) ?? 'first';
  }

  /// Signs in (or creates the account) and keeps the token for the calls that follow. Returns the e-mail.
  Future<String> signIn(String email, String password,
      {required bool create, required String device}) async {
    final (s, j) = await _call('POST', create ? '/api/register' : '/api/login',
        body: {'email': email.trim(), 'password': password, 'device': device},
        auth: false);
    if ((s != 200 && s != 201) || j?['token'] is! String) throw _error(s, j);
    token = j!['token'] as String;
    return (j['email'] as String?) ?? email;
  }

  Future<void> signOut() async {
    try {
      await _call('POST', '/api/logout', body: {});
    } catch (_) {}
    token = null;
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    final (s, j) = await _call('POST', '/api/password',
        body: {'old': oldPassword, 'new': newPassword});
    if (s != 204) throw _error(s, j);
  }

  Future<void> deleteAccount(String password) async {
    final (s, j) =
        await _call('DELETE', '/api/account', body: {'password': password});
    if (s != 204) throw _error(s, j);
    token = null;
  }

  /// Everything stored for the account.
  Future<Map<String, RemoteItem>> fetch() async {
    final (s, j) = await _call('GET', '/api/data');
    if (s != 200) throw _error(s, j);
    final items = (j?['items'] as Map?) ?? const {};
    return {
      for (final e in items.entries)
        e.key as String: RemoteItem((e.value as Map)['value'] as String?,
            ((e.value as Map)['rev'] as num).toInt()),
    };
  }

  /// Writes [value] (null removes it) on top of revision [rev]. Returns the new revision, or a [Conflict] holding
  /// what the server has now when another device wrote first.
  Future<Object> put(String key, String? value, int rev) async {
    final (s, j) = await _call('PUT', '/api/data/${Uri.encodeComponent(key)}',
        body: {'value': value, 'base': rev});
    if (s == 200) return (j!['rev'] as num).toInt();
    if (s == 409) {
      return Conflict(RemoteItem(
          j?['value'] as String?, ((j?['rev'] ?? 0) as num).toInt()));
    }
    throw _error(s, j);
  }

  void close() => _http.close();
}
