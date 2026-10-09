import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

enum PinResult { ok, wrong, lockedOut }

/// The profiles on this device, which one is in use, and the PIN that guards them. The PIN is a
/// family lock for a shared screen, not security: it is stored salted and hashed on the device.
class ProfilesState extends ChangeNotifier {
  SharedPreferences? _p;

  List<Profile> profiles = [Profile.main];
  String currentId = Profile.main.id;
  String? _pinHash, _pinSalt;

  /// Someone has chosen a profile since the app started.
  bool picked = false;

  DateTime? _settingsOpenUntil;
  int _fails = 0;
  DateTime? _lockedUntil;

  /// How many wrong PINs in a row, and for how long the PIN is refused after that.
  static const maxFails = 5;
  static const lockout = Duration(seconds: 30);

  /// How long Settings stay open after the PIN was entered in a Kids profile.
  static const settingsWindow = Duration(minutes: 5);

  static const _maxProfiles = 8;

  Profile get current => profiles.firstWhere((e) => e.id == currentId,
      orElse: () => profiles.first);
  bool get hasPin => _pinHash != null;
  bool get multiple => profiles.length > 1;
  bool get canAdd => profiles.length < _maxProfiles;

  /// Pick a profile first: there is more than one and none was chosen since the app started.
  bool get needsPick => multiple && !picked;

  /// Settings are shut: a Kids profile with a PIN set, and the PIN was not entered lately.
  bool get settingsLocked =>
      hasPin &&
      current.kids &&
      !(_settingsOpenUntil?.isAfter(DateTime.now()) ?? false);

  /// Seconds left before another PIN may be tried, or 0.
  int get lockedSeconds {
    final u = _lockedUntil;
    if (u == null) return 0;
    final left = u.difference(DateTime.now()).inSeconds + 1;
    return left > 0 ? left : 0;
  }

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    final raw = p.getString('profiles');
    if (raw != null) {
      try {
        final l = [
          for (final j in jsonDecode(raw) as List)
            Profile.fromJson(j as Map<String, dynamic>)
        ];
        if (l.isNotEmpty) profiles = l;
      } catch (_) {}
    }
    final cur = p.getString('profileCurrent');
    if (cur != null && profiles.any((e) => e.id == cur)) currentId = cur;
    _pinHash = p.getString('pinHash');
    _pinSalt = p.getString('pinSalt');
  }

  void _save() {
    final p = _p;
    if (p == null) return;
    p.setString('profiles', jsonEncode([for (final e in profiles) e.toJson()]));
    p.setString('profileCurrent', currentId);
    _pinHash == null ? p.remove('pinHash') : p.setString('pinHash', _pinHash!);
    _pinSalt == null ? p.remove('pinSalt') : p.setString('pinSalt', _pinSalt!);
  }

  // --- Profiles ---------------------------------------------------------------------------

  Profile add(String name, {bool kids = false}) {
    final id = 'p${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final n =
        name.trim().isEmpty ? 'Profile ${profiles.length + 1}' : name.trim();
    final p = Profile(id: id, name: n, kids: kids);
    profiles = [...profiles, p];
    _save();
    notifyListeners();
    return p;
  }

  void update(Profile p) {
    profiles = [for (final e in profiles) e.id == p.id ? p : e];
    _save();
    notifyListeners();
  }

  /// Deletes [id]. The last profile cannot be deleted. Returns false then.
  bool remove(String id) {
    if (profiles.length < 2) return false;
    profiles = profiles.where((e) => e.id != id).toList();
    if (currentId == id) currentId = profiles.first.id;
    _save();
    notifyListeners();
    return true;
  }

  void select(String id) {
    if (!profiles.any((e) => e.id == id)) return;
    currentId = id;
    picked = true;
    _settingsOpenUntil = null;
    _save();
    notifyListeners();
  }

  /// Whether moving to [target] needs the PIN: a locked profile, or leaving a Kids profile.
  bool needsPinToEnter(Profile target) =>
      hasPin &&
      target.id != currentId &&
      (target.locked || (current.kids && !target.kids));

  // --- PIN --------------------------------------------------------------------------------

  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool validPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  void setPin(String pin) {
    assert(validPin(pin));
    final r = Random.secure();
    _pinSalt = base64Url.encode([for (var i = 0; i < 12; i++) r.nextInt(256)]);
    _pinHash = hashPin(pin, _pinSalt!);
    _fails = 0;
    _lockedUntil = null;
    _save();
    notifyListeners();
  }

  /// Removing the PIN also lifts every profile lock, since there is nothing left to enter.
  void clearPin() {
    _pinHash = _pinSalt = null;
    profiles = [
      for (final e in profiles) e.locked ? e.copyWith(locked: false) : e
    ];
    _settingsOpenUntil = null;
    _save();
    notifyListeners();
  }

  PinResult checkPin(String pin) {
    if (!hasPin) return PinResult.ok;
    if (lockedSeconds > 0) return PinResult.lockedOut;
    if (hashPin(pin, _pinSalt!) == _pinHash) {
      _fails = 0;
      _lockedUntil = null;
      return PinResult.ok;
    }
    if (++_fails >= maxFails) {
      _fails = 0;
      _lockedUntil = DateTime.now().add(lockout);
      notifyListeners();
      return PinResult.lockedOut;
    }
    return PinResult.wrong;
  }

  void openSettings() {
    _settingsOpenUntil = DateTime.now().add(settingsWindow);
    notifyListeners();
  }
}
