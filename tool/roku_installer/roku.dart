// Installing a channel on a Roku in developer mode, without the browser page: find the Roku on the network, send the
// zip to its installer (a web server on port 80 with digest sign-in, user name "rokudev") and start the channel
// through its remote-control port (8060, "ECP").
//
// Only relative imports here: this folder is compiled on its own (dart compile exe roku_installer.dart) and tested from the app's test folder.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

String _md5(String s) => md5.convert(utf8.encode(s)).toString();

// --- Digest sign-in (RFC 2617, MD5, qop=auth) ------------------------------------------------------------------

/// The parts of a `WWW-Authenticate: Digest ...` header.
Map<String, String> parseChallenge(String header) {
  final out = <String, String>{};
  final rest =
      header.replaceFirst(RegExp(r'^\s*Digest\s+', caseSensitive: false), '');
  for (final m in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]*))').allMatches(rest)) {
    out[m[1]!.toLowerCase()] = m[2] ?? m[3] ?? '';
  }
  return out;
}

/// The `Authorization` header value answering [challenge] for [method] [uri].
String digestAuthorization({
  required Map<String, String> challenge,
  required String user,
  required String password,
  required String method,
  required String uri,
  int nonceCount = 1,
  String? cnonce,
}) {
  final realm = challenge['realm'] ?? '';
  final nonce = challenge['nonce'] ?? '';
  final qopOffered =
      (challenge['qop'] ?? '').split(',').map((e) => e.trim()).toList();
  final useQop = qopOffered.contains('auth');
  final nc = nonceCount.toRadixString(16).padLeft(8, '0');
  final cn = cnonce ?? _randomHex(8);
  final ha1 = _md5('$user:$realm:$password');
  final ha2 = _md5('$method:$uri');
  final response =
      useQop ? _md5('$ha1:$nonce:$nc:$cn:auth:$ha2') : _md5('$ha1:$nonce:$ha2');
  // The order curl uses, which is what a Roku's small web server has been tried with.
  final parts = [
    'username="$user"',
    'realm="$realm"',
    'nonce="$nonce"',
    'uri="$uri"',
    if (useQop) ...['cnonce="$cn"', 'nc=$nc', 'qop=auth'],
    'response="$response"',
    if (challenge['opaque'] != null) 'opaque="${challenge['opaque']}"',
    'algorithm=MD5',
  ];
  return 'Digest ${parts.join(', ')}';
}

String _randomHex(int bytes) {
  final r = Random.secure();
  return [
    for (var i = 0; i < bytes; i++)
      r.nextInt(256).toRadixString(16).padLeft(2, '0')
  ].join();
}

// --- The upload ----------------------------------------------------------------------------------------------

/// A multipart/form-data body with text [fields] and one file.
({Uint8List body, String contentType}) buildMultipart({
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  required List<int> file,
  String fileType = 'application/octet-stream',
  String? boundary,
}) {
  final b = boundary ?? '----streamboss${_randomHex(8)}';
  final out = BytesBuilder();
  for (final e in fields.entries) {
    out.add(utf8.encode(
        '--$b\r\nContent-Disposition: form-data; name="${e.key}"\r\n\r\n${e.value}\r\n'));
  }
  out.add(utf8.encode(
      '--$b\r\nContent-Disposition: form-data; name="$fileField"; filename="$fileName"\r\nContent-Type: $fileType\r\n\r\n'));
  out.add(file);
  out.add(utf8.encode('\r\n--$b--\r\n'));
  return (body: out.toBytes(), contentType: 'multipart/form-data; boundary=$b');
}

enum InstallOutcome { installed, identical, failed, unknown }

class InstallResult {
  final InstallOutcome outcome;
  final String message;

  /// What the Roku printed on its debug console while installing (the line of a compile error), if we could read it.
  final String details;
  const InstallResult(this.outcome, this.message, {this.details = ''});
  InstallResult withDetails(String d) => InstallResult(outcome, message, details: d);
  bool get ok =>
      outcome == InstallOutcome.installed ||
      outcome == InstallOutcome.identical;
}

/// What the Roku's installer page said after an upload.
InstallResult parseInstallResult(String html) {
  final text = html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final lower = text.toLowerCase();
  if (lower.contains('identical to previous version')) {
    return const InstallResult(
        InstallOutcome.identical, 'The Roku already has exactly this version.');
  }
  if (lower.contains('install success'))
    return const InstallResult(InstallOutcome.installed, 'Installed.');
  final failure =
      RegExp(r'install failure[^.<]*[.:]?[^.]*', caseSensitive: false)
          .firstMatch(text);
  if (failure != null)
    return InstallResult(InstallOutcome.failed, failure[0]!.trim());
  if (lower.contains('compilation failed') || lower.contains('failure')) {
    return const InstallResult(
        InstallOutcome.failed, 'The Roku refused the channel file.');
  }
  return const InstallResult(InstallOutcome.unknown,
      'The Roku answered, but not with a message this installer knows.');
}

/// The lines of a Roku's debug console worth showing after a failed install: errors, compile messages, file names.
String consoleErrors(String log, {int max = 12}) {
  final lines = log
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final hits = <String>[];
  for (final l in lines) {
    if (RegExp(r'error|fail|compil|pkg:/|not found|undefined', caseSensitive: false)
            .hasMatch(l) &&
        !hits.contains(l)) {
      hits.add(l.length > 220 ? '${l.substring(0, 220)}...' : l);
    }
  }
  final shown = hits.isNotEmpty ? hits : lines.reversed.take(8).toList().reversed.toList();
  return shown.length > max ? shown.sublist(shown.length - max).join('\n') : shown.join('\n');
}

// --- Finding Rokus -------------------------------------------------------------------------------------------

/// The address in an SSDP answer's `LOCATION` header (`http://192.168.1.40:8060/`), or null.
String? parseSsdpHost(String datagram) {
  final m = RegExp(r'^location:\s*https?://([^:/\s]+)',
          caseSensitive: false, multiLine: true)
      .firstMatch(datagram);
  return m?[1];
}

class RokuDevice {
  final String host;
  final String name;
  final String model;
  final bool? developerMode;
  const RokuDevice(this.host,
      {this.name = '', this.model = '', this.developerMode});
  String get label => [
        if (name.isNotEmpty) name,
        if (model.isNotEmpty) '($model)',
        host
      ].join(' ');
}

/// Asks the network which Rokus are there (SSDP), for [wait]. Returns their addresses.
Future<List<String>> discoverHosts(
    {Duration wait = const Duration(seconds: 3)}) async {
  final found = <String>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = socket!.receive();
        if (d == null) return;
        final host = parseSsdpHost(utf8.decode(d.data, allowMalformed: true));
        if (host != null) found.add(host);
      }
    });
    final msg = utf8.encode(
        'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nST: roku:ecp\r\nMX: 2\r\n\r\n');
    for (var i = 0; i < 2; i++) {
      socket.send(msg, InternetAddress('239.255.255.250'), 1900);
      await Future<void>.delayed(wait ~/ 2);
    }
  } catch (_) {
    // No network, or one that blocks multicast: the caller asks for the address instead.
  } finally {
    socket?.close();
  }
  return found.toList()..sort();
}

// --- One Roku ------------------------------------------------------------------------------------------------

class RokuClient {
  final String host;
  final int installerPort; // 80 on a real Roku
  final int ecpPort; // 8060 on a real Roku
  final int consolePort; // 8085 on a real Roku: the debug console, where it prints compile errors
  final Duration consoleWait; // how long to listen to it after a failed install
  final Duration timeout;
  final HttpClient _http;

  RokuClient(this.host,
      {this.installerPort = 80,
      this.ecpPort = 8060,
      this.consolePort = 8085,
      this.consoleWait = const Duration(seconds: 2),
      this.timeout = const Duration(seconds: 20)})
      : _http = HttpClient()..connectionTimeout = const Duration(seconds: 6);

  Uri _installer(String path) =>
      Uri(scheme: 'http', host: host, port: installerPort, path: path);
  Uri _ecp(String path) =>
      Uri(scheme: 'http', host: host, port: ecpPort, path: path);

  void close() => _http.close(force: true);

  /// Name, model and whether developer mode is on, from the remote-control port. Null if it does not answer.
  Future<RokuDevice?> deviceInfo() async {
    try {
      final req =
          await _http.getUrl(_ecp('/query/device-info')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      String? tag(String t) =>
          RegExp('<$t>([^<]*)</$t>').firstMatch(body)?[1]?.trim();
      final dev = tag('developer-enabled');
      return RokuDevice(host,
          name: tag('user-device-name') ?? tag('friendly-device-name') ?? '',
          model: tag('model-name') ?? '',
          developerMode: dev == null ? null : dev == 'true');
    } catch (_) {
      return null;
    }
  }

  /// Whether the installer page answers (developer mode is on and the web server is up).
  Future<bool> installerUp() async {
    try {
      final req = await _http
          .getUrl(_installer('/'))
          .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
      return res.statusCode == 200 || res.statusCode == 401;
    } catch (_) {
      return false;
    }
  }

  Future<void> keypress(String key) async {
    final req = await _http.postUrl(_ecp('/keypress/$key')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>();
  }

  /// Presses the remote's secret sequence for the Developer Settings screen (Home x3, Up x2, Right, Left, Right,
  /// Left, Right). A Roku set to refuse network control ignores it.
  Future<void> openDeveloperSettings(
      {Duration gap = const Duration(milliseconds: 350)}) async {
    for (final k in const [
      'Home',
      'Home',
      'Home',
      'Up',
      'Up',
      'Right',
      'Left',
      'Right',
      'Left',
      'Right'
    ]) {
      await keypress(k);
      await Future<void>.delayed(gap);
    }
  }

  /// Sends [zip] to the Roku's installer. [user] is `rokudev`; [password] is the one chosen on the TV.
  ///
  /// Roku firmware differs in what its upload form wants (the button is "Install" or "Replace", and some versions
  /// want an empty `passwd` field), so a 400 ("bad request") is answered by trying the next way of sending it.
  Future<InstallResult> install(List<int> zip, String password,
      {String user = 'rokudev', String fileName = 'streamboss.zip'}) async {
    const ways = [
      _UploadWay('Replace', true, 'application/octet-stream'),
      _UploadWay('Install', true, 'application/octet-stream'),
      _UploadWay('Install', false, 'application/octet-stream'),
      _UploadWay('Replace', false, 'application/zip'),
    ];
    var lastBody = '';
    for (final way in ways) {
      final r = await _upload(zip, password, user, fileName, way);
      if (r.status == 401) {
        throw const RokuException(
            'The Roku refused the password. It is the one you chose on the TV when you turned developer mode on (the user name is rokudev).');
      }
      if (r.status == 400) {
        lastBody = r.body;
        continue;
      }
      if (r.status != 200) {
        throw RokuException(
            'The Roku answered ${r.status}${_snippet(r.body)}.');
      }
      return parseInstallResult(r.body);
    }
    throw RokuException(
        'The Roku answered 400 (bad request) to every way this installer sends the file${_snippet(lastBody)}. '
        'Try the Roku\'s own upload page instead (docs/ROKU.md, "Install by hand").');
  }

  static String _snippet(String body) {
    final text = body
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return '';
    return ' ("${text.length > 160 ? '${text.substring(0, 160)}...' : text}")';
  }

  Future<({int status, String body})> _upload(List<int> zip, String password,
      String user, String fileName, _UploadWay way) async {
    const path = '/plugin_install';
    // 1. An unsigned request, to get the challenge.
    final probe = await (await _http.getUrl(_installer(path)).timeout(timeout))
        .close()
        .timeout(timeout);
    await probe.drain<void>();
    final header = probe.headers.value(HttpHeaders.wwwAuthenticateHeader);
    if (probe.statusCode != 401 ||
        header == null ||
        !header.toLowerCase().startsWith('digest')) {
      throw const RokuException(
          'The Roku did not ask for a password. Is developer mode on, and is this the Roku\'s address?');
    }
    final challenge = parseChallenge(header);
    // 2. The upload, signed.
    final mp = buildMultipart(
        fields: {'mysubmit': way.submit, if (way.passwdField) 'passwd': ''},
        fileField: 'archive',
        fileName: fileName,
        fileType: way.fileType,
        file: zip);
    final req = await _http.postUrl(_installer(path)).timeout(timeout);
    req.headers
      ..set(
          HttpHeaders.authorizationHeader,
          digestAuthorization(
              challenge: challenge,
              user: user,
              password: password,
              method: 'POST',
              uri: path))
      ..set(HttpHeaders.contentTypeHeader, mp.contentType)
      ..contentLength = mp.body.length;
    req.add(mp.body);
    final res = await req.close().timeout(const Duration(minutes: 2));
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }

  /// [install], and when it does not work, the Roku's own words: its debug console is read while the file goes
  /// in, and the error lines (a compile error names the file and line) are put in [InstallResult.details].
  Future<InstallResult> installWithLog(List<int> zip, String password,
      {String user = 'rokudev',
      String fileName = 'streamboss.zip'}) async {
    final log = StringBuffer();
    Socket? console;
    try {
      console = await Socket.connect(host, consolePort,
          timeout: const Duration(seconds: 3));
      console.listen((d) => log.write(utf8.decode(d, allowMalformed: true)),
          onError: (_) {}, cancelOnError: true);
    } catch (_) {
      console = null; // no console to read: the install still goes ahead
    }
    try {
      final r = await install(zip, password, user: user, fileName: fileName);
      if (r.ok || console == null) return r;
      await Future<void>.delayed(consoleWait);
      final details = consoleErrors(log.toString());
      return details.isEmpty ? r : r.withDetails(details);
    } finally {
      console?.destroy();
    }
  }

  /// Starts the sideloaded channel.
  Future<void> launchDev() async {
    final req = await _http.postUrl(_ecp('/launch/dev')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>();
  }
}

class _UploadWay {
  final String submit; // the value of the form's button: Install or Replace
  final bool passwdField; // an empty `passwd` field, as the Roku's own page sends
  final String fileType;
  const _UploadWay(this.submit, this.passwdField, this.fileType);
}

class RokuException implements Exception {
  final String message;
  const RokuException(this.message);
  @override
  String toString() => message;
}

// --- The channel file ----------------------------------------------------------------------------------------

/// Whether [bytes] start like a zip file.
bool looksLikeZip(List<int> bytes) =>
    bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;

/// The address and name of the newest `*-roku.zip` among the releases in [releasesJson] (GitHub's list, newest first).
({String url, String name, String tag})? pickRokuAsset(String releasesJson) {
  final list = jsonDecode(releasesJson);
  if (list is! List) return null;
  for (final r in list) {
    if (r is! Map || r['draft'] == true) continue;
    for (final a in (r['assets'] as List? ?? const [])) {
      final name = '${a['name']}';
      if (name.endsWith('-roku.zip'))
        return (
          url: '${a['browser_download_url']}',
          name: name,
          tag: '${r['tag_name']}'
        );
    }
  }
  return null;
}

/// Downloads the newest channel file from the project's releases.
Future<({List<int> bytes, String name, String tag})> downloadLatest(
    {String repo = 'migtam628/StreamBoss', HttpClient? client}) async {
  final http = client ?? HttpClient();
  try {
    Future<List<int>> get(String url) async {
      final req = await http.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'StreamBoss-Roku-Installer');
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200)
        throw RokuException('Could not download $url (${res.statusCode}).');
      return await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    }

    final pick = pickRokuAsset(utf8.decode(
        await get('https://api.github.com/repos/$repo/releases?per_page=15')));
    if (pick == null)
      throw const RokuException('No release has a Roku channel file yet.');
    final bytes = await get(pick.url);
    if (!looksLikeZip(bytes))
      throw const RokuException('The download is not a zip file.');
    return (bytes: bytes, name: pick.name, tag: pick.tag);
  } finally {
    if (client == null) http.close();
  }
}
