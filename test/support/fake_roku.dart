import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../tool/roku_installer/roku.dart';

/// A stand-in for a Roku in developer mode: an installer on one port (digest sign-in, user rokudev) and the
/// remote-control port on another.
class FakeRoku {
  late HttpServer installer, ecp;
  late ServerSocket console;
  final _consoleClients = <Socket>[];

  /// What the debug console prints while a file is being installed (a compile error, say).
  String consoleText = '';

  /// A firmware that is particular about the upload: only these button values are accepted (null: any), an empty
  /// `passwd` field is refused or required, or everything is refused with 400.
  Set<String>? acceptSubmits;
  bool rejectPasswdField = false;
  bool requirePasswdField = false;
  bool alwaysBadRequest = false;
  final attempts = <String>[]; // "Replace+passwd", "Install", ... for each upload that arrived
  String? uploadedPasswd;
  final password = 'hunter2';
  final keys = <String>[];
  var launched = false;
  Uint8List? uploadedFile;
  String? uploadedSubmit;
  String result = '<font color="red">Install Success.</font>';
  var developerEnabled = true;
  final nonce = 'abc123nonce';

  Future<void> start() async {
    installer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    installer.listen((req) async {
      final body = BytesBuilder();
      await for (final c in req) {
        body.add(c);
      }
      final auth = req.headers.value('authorization');
      bool ok = false;
      if (auth != null) {
        final c = parseChallenge(auth);
        final ha1 =
            md5.convert(utf8.encode('rokudev:rokudev:$password')).toString();
        final ha2 = md5
            .convert(utf8.encode('${req.method}:${req.uri.path}'))
            .toString();
        final want = md5
            .convert(
                utf8.encode('$ha1:$nonce:${c['nc']}:${c['cnonce']}:auth:$ha2'))
            .toString();
        ok = c['response'] == want &&
            c['username'] == 'rokudev' &&
            c['uri'] == req.uri.path;
      }
      if (!ok) {
        req.response.statusCode = 401;
        req.response.headers.set('www-authenticate',
            'Digest realm="rokudev", nonce="$nonce", qop="auth", algorithm=MD5');
        await req.response.close();
        return;
      }
      if (req.method == 'POST') {
        final text = latin1.decode(body.toBytes());
        final submit =
            RegExp(r'name="mysubmit"\r\n\r\n([^\r]*)').firstMatch(text)?[1];
        final hasPasswd = text.contains('name="passwd"');
        attempts.add('$submit${hasPasswd ? '+passwd' : ''}');
        if (alwaysBadRequest ||
            (acceptSubmits != null && !acceptSubmits!.contains(submit)) ||
            (rejectPasswdField && hasPasswd) ||
            (requirePasswdField && !hasPasswd)) {
          req.response.statusCode = 400;
          req.response.write('<html><body>Bad Request</body></html>');
          await req.response.close();
          return;
        }
        uploadedSubmit = submit;
        uploadedPasswd =
            RegExp(r'name="passwd"\r\n\r\n([^\r]*)').firstMatch(text)?[1];
        for (final c in _consoleClients) {
          c.write(consoleText);
        }
        final start =
            text.indexOf('\r\n\r\n', text.indexOf('name="archive"')) + 4;
        final end = text.lastIndexOf('\r\n--');
        uploadedFile =
            Uint8List.fromList(latin1.encode(text.substring(start, end)));
        // The real Roku answers 400 when the install fails (and says why in the page, which also carries script code).
        if (result.contains('Failure')) req.response.statusCode = 400;
        req.response.write(
            '<html><head><script>document.addEventListener("DOMContentLoaded", function(){ var x = 1; });</script></head>'
            '<body><h1>Roku Development Kit</h1>$result</body></html>');
      } else {
        req.response.write('<html>installer</html>');
      }
      await req.response.close();
    });
    console = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    console.listen(_consoleClients.add);
    ecp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    ecp.listen((req) async {
      await req.drain<void>();
      if (req.uri.path == '/query/device-info') {
        req.response.write(
            '<device-info><user-device-name>Living room</user-device-name><model-name>Roku Ultra</model-name>'
            '<developer-enabled>$developerEnabled</developer-enabled></device-info>');
      } else if (req.uri.path.startsWith('/keypress/')) {
        keys.add(req.uri.pathSegments.last);
      } else if (req.uri.path == '/launch/dev') {
        launched = true;
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  }

  RokuClient client() => RokuClient('127.0.0.1',
      installerPort: installer.port,
      ecpPort: ecp.port,
      consolePort: console.port,
      consoleWait: const Duration(milliseconds: 150));
  Future<void> stop() async {
    for (final c in _consoleClients) {
      c.destroy();
    }
    await console.close();
    await installer.close(force: true);
    await ecp.close(force: true);
  }
}
