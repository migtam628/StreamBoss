import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sync/sync_api.dart';
import '../services/sync/sync_engine.dart';

/// The account on a StreamBoss sync server and the sync itself: signing in and out, and keeping this device's
/// settings, sources (without passwords), lists and positions in step with the other devices.
class SyncState extends ChangeNotifier {
  SyncState(
      {http.Client? client, FlutterSecureStorage? secure, this.deviceName})
      : _client = client,
        _secure = secure ??
            const FlutterSecureStorage(
                mOptions: MacOsOptions(useDataProtectionKeyChain: false));

  final http.Client? _client;
  final FlutterSecureStorage _secure;
  final String? deviceName;
  SharedPreferences? _p;
  SyncApi? _api;

  String server = '';
  String email = '';
  bool auto = true;
  bool busy = false;
  String? error;
  DateTime? lastSync;

  /// Run by the app to read storage back into what it is showing after a sync changed it.
  void Function() reload = () {};

  Timer? _soon, _every;

  static const _tokenKey = 'sync:token';
  bool get signedIn => _api?.token != null;

  /// How often a running app syncs by itself, and how soon after a change.
  static const interval = Duration(minutes: 10);
  static const afterChange = Duration(seconds: 45);

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    server = p.getString('syncServer') ?? '';
    email = p.getString('syncEmail') ?? '';
    auto = p.getBool('syncAuto') ?? true;
    final ms = p.getInt('syncLast');
    if (ms != null) lastSync = DateTime.fromMillisecondsSinceEpoch(ms);
    String? token;
    try {
      token = await _secure.read(key: _tokenKey);
    } catch (_) {}
    if (server.isNotEmpty && token != null) {
      try {
        _api = SyncApi(server, token: token, client: _client);
      } catch (_) {}
    }
    _arm();
  }

  void _arm() {
    _every?.cancel();
    _every = null;
    if (signedIn && auto) {
      _every = Timer.periodic(interval, (_) => syncNow(quiet: true));
    }
  }

  String get _device {
    final n = deviceName ?? defaultTargetPlatform.name;
    return 'StreamBoss on $n';
  }

  /// Signs in, or creates the account when [create]. Returns null when it worked, else what to tell the person.
  Future<String?> signIn(String serverText, String emailText, String password,
      {required bool create}) async {
    if (busy) return null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final api = SyncApi(serverText, client: _client);
      if (create) {
        final mode = await api.health();
        if (mode == 'closed') {
          throw const SyncException(
              'This server is not accepting new accounts.');
        }
      }
      final who = await api.signIn(emailText, password,
          create: create, device: _device);
      _api = api;
      server = api.base.toString();
      email = who;
      await _p?.setString('syncServer', server);
      await _p?.setString('syncEmail', email);
      try {
        await _secure.write(key: _tokenKey, value: api.token);
      } catch (_) {}
      _arm();
    } on SyncException catch (e) {
      busy = false;
      error = e.message;
      notifyListeners();
      return e.message;
    }
    busy = false;
    notifyListeners();
    await syncNow();
    return error;
  }

  Future<void> signOut() async {
    final api = _api;
    _api = null;
    _every?.cancel();
    _soon?.cancel();
    await api?.signOut();
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    await SyncEngine.forget();
    lastSync = null;
    await _p?.remove('syncLast');
    error = null;
    notifyListeners();
  }

  /// Deletes the account and everything stored for it on the server. This device keeps its own data.
  Future<String?> deleteAccount(String password) async {
    try {
      await _api?.deleteAccount(password);
    } on SyncException catch (e) {
      return e.message;
    }
    await signOut();
    return null;
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      await _api?.changePassword(oldPassword, newPassword);
      return null;
    } on SyncException catch (e) {
      return e.message;
    }
  }

  void setAuto(bool v) {
    auto = v;
    _p?.setBool('syncAuto', v);
    _arm();
    notifyListeners();
  }

  /// A change was made on this device: sync soon, once, rather than after every tap.
  void changed() {
    if (!signedIn || !auto || _soon != null) return;
    _soon = Timer(afterChange, () {
      _soon = null;
      syncNow(quiet: true);
    });
  }

  /// The app was brought back or is being put away: sync now if an automatic sync is on.
  void lifecycle() {
    if (signedIn && auto) syncNow(quiet: true);
  }

  Future<void> syncNow({bool quiet = false}) async {
    final api = _api;
    if (api == null || busy) return;
    busy = true;
    if (!quiet) error = null;
    notifyListeners();
    try {
      await SyncEngine(api, onLocalChanged: reload).run();
      lastSync = DateTime.now();
      await _p?.setInt('syncLast', lastSync!.millisecondsSinceEpoch);
      error = null;
    } on SyncException catch (e) {
      error = e.message;
      if (e.signedOut) {
        // The token no longer works (the password was changed, or the device was removed).
        _api = null;
        _every?.cancel();
        try {
          await _secure.delete(key: _tokenKey);
        } catch (_) {}
      }
    } catch (e) {
      error = 'Sync stopped: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _soon?.cancel();
    _every?.cancel();
    super.dispose();
  }
}
