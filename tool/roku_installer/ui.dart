// The installer's window: a small web page served from this computer only (127.0.0.1) and opened in the browser.
// No toolkit, no extra packages, the same on Windows, macOS and Linux. The page asks this program to look for Rokus,
// check one, open the Developer Settings screen and install; the password is held in memory for the upload only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'roku.dart';
import 'ui_page.dart';

typedef ChannelFile = ({List<int> bytes, String name, String tag});

/// Words for what went wrong, for people (the command line version prints the same sentences).
String describeError(Object e) {
  if (e is RokuException) return e.toString();
  if (e is SocketException) {
    return 'Could not reach the Roku (${e.message}). Check the address and that this computer is on the same network.';
  }
  if (e is TimeoutException) {
    return 'The Roku did not answer in time. Check that it is on and on the same network, then try again.';
  }
  if (e is HttpException) return 'The network stopped: ${e.message}';
  return 'Something went wrong: $e';
}

/// Opens [url] in the person's browser. Quietly does nothing if that is not possible (the address is printed too).
Future<void> openInBrowser(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {}
}

class _Step {
  final String label;
  String state = 'wait'; // wait, run, done, fail
  String? note;
  _Step(this.label);
  Map<String, Object?> toJson() =>
      {'label': label, 'state': state, if (note != null) 'note': note};
}

class InstallerUi {
  /// Rokus on the network (addresses).
  final Future<List<String>> Function() discover;
  final RokuClient Function(String host) clientFor;

  /// The channel to install: a downloader for the newest release, or a file the person named.
  final Future<ChannelFile> Function() channel;
  final bool launchAfter;

  /// The pause between remote-control key presses when opening Developer Settings.
  final Duration keyGap;

  /// With no page open for this long, the program quits (closing the tab closes the installer).
  final Duration idleTimeout;

  InstallerUi({
    this.discover = discoverHosts,
    RokuClient Function(String host)? clientFor,
    Future<ChannelFile> Function()? channel,
    this.launchAfter = true,
    this.keyGap = const Duration(milliseconds: 350),
    this.idleTimeout = const Duration(seconds: 30),
  })  : clientFor = clientFor ?? RokuClient.new,
        channel = channel ?? downloadLatest;

  late final String token = _newToken();
  HttpServer? _server;
  Timer? _watch;
  DateTime? _lastPing;
  final _done = Completer<void>();
  var _stopped = false;

  // The install, as the page shows it.
  List<_Step> _steps = [];
  String _state = 'idle'; // idle, running, done, failed
  String _message = '';
  String _details = ''; // what the Roku printed, when an install failed
  bool _launchFailed = false;

  static String _newToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  int get port => _server!.port;

  /// Completes when the program should end (the page said so, the tab was closed, or [stop] was called).
  Future<void> get done => _done.future;

  /// Starts listening; returns the address to open.
  Future<Uri> start({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle, onError: (_) {});
    final every = idleTimeout ~/ 3 < const Duration(seconds: 5)
        ? idleTimeout ~/ 3
        : const Duration(seconds: 5);
    _watch = Timer.periodic(every, (_) {
      final last = _lastPing;
      if (last != null && DateTime.now().difference(last) > idleTimeout) {
        stop();
      }
    });
    return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: _server!.port,
        path: '/',
        queryParameters: {'t': token});
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _watch?.cancel();
    await _server?.close(force: true);
    if (!_done.isCompleted) _done.complete();
  }

  // --- Requests ----------------------------------------------------------------------------------------------

  bool _hostOk(HttpRequest r) {
    final host = r.headers.value(HttpHeaders.hostHeader) ?? '';
    return host == '127.0.0.1:${_server!.port}' ||
        host == 'localhost:${_server!.port}';
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Frame-Options', 'DENY')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');
    try {
      // A page on the internet must not be able to talk to this program: only our own address, and the token.
      if (!_hostOk(req)) return await _send(res, 403, {'error': 'forbidden'});
      final path = req.uri.path;
      if (path == '/') {
        if (req.uri.queryParameters['t'] != token) {
          return await _send(res, 403, {'error': 'forbidden'});
        }
        res.headers
          ..contentType = ContentType.html
          ..set('Content-Security-Policy',
              "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'");
        res.write(installerPage);
        await res.close();
        return;
      }
      if (!path.startsWith('/api/') ||
          req.headers.value('x-token') != token) {
        return await _send(res, 403, {'error': 'forbidden'});
      }
      final body = req.method == 'POST' ? await _readJson(req) : const <String, Object?>{};
      switch (path) {
        case '/api/ping':
          _lastPing = DateTime.now();
          return await _send(res, 200, {'ok': true});
        case '/api/scan':
          return await _send(res, 200, await _scan());
        case '/api/check':
          return await _send(res, 200, await _check(_host(body)));
        case '/api/devsettings':
          return await _send(res, 200, await _devSettings(_host(body)));
        case '/api/install':
          return await _send(res, 200, _startInstall(_host(body), '${body['password'] ?? ''}'));
        case '/api/status':
          return await _send(res, 200, _status());
        case '/api/quit':
          await _send(res, 200, {'ok': true});
          unawaited(stop());
          return;
      }
      return await _send(res, 404, {'error': 'not found'});
    } on FormatException catch (e) {
      return await _send(res, 400, {'error': e.message});
    } catch (e) {
      return await _send(res, 500, {'error': describeError(e)});
    }
  }

  Future<Map<String, Object?>> _readJson(HttpRequest req) async {
    final bytes = <int>[];
    await for (final c in req) {
      bytes.addAll(c);
      if (bytes.length > 65536) throw const FormatException('too large');
    }
    if (bytes.isEmpty) return {};
    final v = jsonDecode(utf8.decode(bytes));
    if (v is! Map) throw const FormatException('expected an object');
    return v.cast<String, Object?>();
  }

  String _host(Map<String, Object?> body) {
    var h = '${body['host'] ?? ''}'.trim();
    h = h.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'[/:].*$'), '');
    if (h.isEmpty || !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-]*$').hasMatch(h)) {
      throw const FormatException('That is not an address. Use something like 192.168.1.40.');
    }
    return h;
  }

  Future<void> _send(HttpResponse res, int status, Object json) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(json));
    await res.close();
  }

  // --- What the page can ask ---------------------------------------------------------------------------------

  Future<Map<String, Object?>> _scan() async {
    final hosts = await discover();
    final out = await Future.wait(hosts.map((h) async {
      final c = clientFor(h);
      try {
        final d = await c.deviceInfo() ?? RokuDevice(h);
        return {'host': h, 'label': d.label};
      } finally {
        c.close();
      }
    }));
    return {'devices': out};
  }

  Future<Map<String, Object?>> _check(String host) async {
    final c = clientFor(host);
    try {
      final r = await Future.wait<Object?>([c.deviceInfo(), c.installerUp()]);
      final d = r[0] as RokuDevice?;
      final up = r[1] as bool;
      return {
        'host': host,
        'label': (d ?? RokuDevice(host)).label,
        'reachable': d != null || up,
        'installerUp': up,
      };
    } finally {
      c.close();
    }
  }

  Future<Map<String, Object?>> _devSettings(String host) async {
    final c = clientFor(host);
    try {
      await c.openDeveloperSettings(gap: keyGap);
      return {'ok': true};
    } catch (_) {
      return {
        'ok': false,
        'error':
            'The Roku did not accept that. Do it with the remote instead (the keys are listed on this page).'
      };
    } finally {
      c.close();
    }
  }

  Map<String, Object?> _startInstall(String host, String password) {
    if (_state == 'running') return {'started': false, 'error': 'Already installing.'};
    if (password.isEmpty) {
      throw const FormatException('Type the password you chose on the TV.');
    }
    _steps = [
      _Step('Download the newest StreamBoss channel'),
      _Step('Send it to the Roku'),
      if (launchAfter) _Step('Start StreamBoss'),
    ];
    _state = 'running';
    _message = '';
    _details = '';
    _launchFailed = false;
    unawaited(_run(host, password));
    return {'started': true};
  }

  Future<void> _run(String host, String password) async {
    final c = clientFor(host);
    var i = 0;
    try {
      _steps[i].state = 'run';
      final file = await channel();
      _steps[i]
        ..state = 'done'
        ..note = '${file.name} (${file.tag})';
      i++;
      _steps[i].state = 'run';
      final result = await c.installWithLog(file.bytes, password);
      if (!result.ok) {
        _steps[i]
          ..state = 'fail'
          ..note = result.message;
        _state = 'failed';
        _message = result.message;
        _details = result.details;
        return;
      }
      _steps[i]
        ..state = 'done'
        ..note = result.message;
      i++;
      if (launchAfter) {
        _steps[i].state = 'run';
        try {
          await c.launchDev();
          _steps[i].state = 'done';
        } catch (_) {
          _launchFailed = true;
          _steps[i]
            ..state = 'fail'
            ..note = 'Open StreamBoss from the end of the Roku\'s home screen.';
        }
      }
      _state = 'done';
      _message = _launchFailed
          ? 'StreamBoss is on the Roku. Open it from the end of the home screen.'
          : 'StreamBoss is on your Roku.';
    } catch (e) {
      final msg = describeError(e);
      if (i < _steps.length) {
        _steps[i]
          ..state = 'fail'
          ..note = msg;
      }
      _state = 'failed';
      _message = msg;
    } finally {
      c.close();
    }
  }

  Map<String, Object?> _status() => {
        'state': _state,
        'message': _message,
        'details': _details,
        'steps': [for (final s in _steps) s.toJson()],
      };
}
