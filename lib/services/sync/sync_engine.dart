import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'sync_api.dart';
import 'sync_merge.dart';
import 'sync_policy.dart';

/// What a sync did.
class SyncReport {
  /// Preferences changed on this device because another device had changed them.
  final int pulled;

  /// Preferences sent to the server.
  final int pushed;
  const SyncReport(this.pulled, this.pushed);
  bool get changedHere => pulled > 0;
}

/// Brings this device's preferences and the server's into step, key by key (see [SyncPolicy] for which keys, and
/// [mergeValue] for how). What each key looked like at the last sync is kept in the preference `syncBase`, so
/// that what this device changed since can be told from what another device did.
class SyncEngine {
  final SyncApi api;

  /// Called straight after the preferences were changed here, before anything else can write them: the app
  /// reads them again into the settings, profiles and library it is showing.
  final void Function() onLocalChanged;

  static const baseKey = 'syncBase';
  static const _maxRounds = 4;

  SyncEngine(this.api, {required this.onLocalChanged});

  static Map<String, (int, String?)> _loadBase(SharedPreferences p) {
    try {
      final j =
          jsonDecode(p.getString(baseKey) ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in j.entries)
          e.key: (
            ((e.value as Map)['rev'] as num).toInt(),
            (e.value as Map)['value'] as String?
          )
      };
    } catch (_) {
      return {};
    }
  }

  static void _saveBase(
          SharedPreferences p, Map<String, (int, String?)> base) =>
      p.setString(
          baseKey,
          jsonEncode({
            for (final e in base.entries)
              e.key: {'rev': e.value.$1, 'value': e.value.$2}
          }));

  /// Forget what was synced (signing out): the next account starts as a new device would.
  static Future<void> forget() async =>
      (await SharedPreferences.getInstance()).remove(baseKey);

  static void _write(SharedPreferences p, String key, Object? v) {
    switch (v) {
      case null:
        p.remove(key);
      case String s:
        p.setString(key, s);
      case bool b:
        p.setBool(key, b);
      case int i:
        p.setInt(key, i);
      case double d:
        p.setDouble(key, d);
      case List l:
        p.setStringList(key, [for (final e in l) '$e']);
    }
  }

  Future<SyncReport> run() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final remote = await api.fetch();
    final base = _loadBase(p);
    var pulled = 0, pushed = 0;

    // One key: merge, store here what changed, and say whether the server needs the result.
    String? mergeKey(String key) {
      final kind = SyncPolicy.kindOf(key);
      if (kind == null) return null;
      final rawLocal = p.get(key);
      final local = SyncPolicy.outgoing(key, rawLocal);
      final b = base[key];
      final r = remote[key];
      final server = decodeValue(r?.value);
      final merged = mergeValue(kind, key,
          base: decodeValue(b?.$2),
          local: local,
          server: server,
          hadBase: b != null);
      if (!sameValue(kind, key, merged, local)) {
        _write(p, key, SyncPolicy.incoming(key, merged, rawLocal));
        pulled++;
      }
      final need = !sameValue(kind, key, merged, server);
      if (!need) base[key] = (r?.rev ?? 0, encodeValue(merged));
      return need ? encodeValue(merged) ?? '' : null; // '' stands for "remove"
    }

    final keys = {
      for (final k in p.getKeys())
        if (SyncPolicy.kindOf(k) != null) k,
      for (final k in remote.keys)
        if (SyncPolicy.kindOf(k) != null) k,
      ...base.keys.where((k) => SyncPolicy.kindOf(k) != null),
    };

    final send = <String, String?>{};
    for (final k in keys) {
      final out = mergeKey(k);
      if (out != null) send[k] = out.isEmpty ? null : out;
    }
    if (pulled > 0) {
      onLocalChanged(); // before any waiting, so the app cannot write over what was just stored
    }

    for (final k in send.keys.toList()) {
      var value = send[k];
      for (var round = 0; round < _maxRounds; round++) {
        final res = await api.put(k, value, remote[k]?.rev ?? 0);
        if (res is int) {
          base[k] = (res, value);
          pushed++;
          break;
        }
        // Another device wrote in the meantime: merge with what is there now and try again.
        remote[k] = (res as Conflict).current;
        final before = pulled;
        final out = mergeKey(k);
        if (pulled > before) onLocalChanged();
        if (out == null) break;
        value = out.isEmpty ? null : out;
      }
    }
    _saveBase(p, base);
    return SyncReport(pulled, pushed);
  }
}
