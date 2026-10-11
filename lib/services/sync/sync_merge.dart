import 'dart:convert';
import 'sync_policy.dart';

/// A synced preference on the wire: its type and value as JSON text, so every platform stores it back the way it
/// was (`{"t":"l","v":["a","b"]}`). Types: s text, i whole number, d number, b yes/no, l list of texts.
String? encodeValue(Object? v) {
  if (v == null) return null;
  final t = v is String
      ? 's'
      : v is bool
          ? 'b'
          : v is int
              ? 'i'
              : v is double
                  ? 'd'
                  : v is List
                      ? 'l'
                      : null;
  if (t == null) throw ArgumentError('Cannot sync a ${v.runtimeType}');
  return jsonEncode({'t': t, 'v': v});
}

Object? decodeValue(String? s) {
  if (s == null) return null;
  final j = jsonDecode(s) as Map<String, dynamic>;
  final v = j['v'];
  switch (j['t']) {
    case 'l':
      return [for (final e in v as List) '$e'];
    case 'd':
      return (v as num).toDouble();
    case 'i':
      return (v as num).toInt();
    default:
      return v;
  }
}

Map<String, dynamic> _asMap(Object? v) {
  if (v is! String || v.isEmpty) return {};
  try {
    final j = jsonDecode(v);
    return j is Map ? Map<String, dynamic>.from(j) : {};
  } catch (_) {
    return {};
  }
}

String _canon(Object? v) => jsonEncode(v);

/// The elements of a list preference as id -> JSON object, in order. [key] says which list it is.
Map<String, Map<String, dynamic>> _byId(String key, Object? v) {
  final out = <String, Map<String, dynamic>>{};
  List<dynamic> list = const [];
  if (v is String && v.isNotEmpty) {
    try {
      final j = jsonDecode(v);
      if (j is List) list = j;
    } catch (_) {}
  } else if (v is List) {
    list = [
      for (final s in v)
        if (s is String)
          () {
            try {
              return jsonDecode(s);
            } catch (_) {
              return null;
            }
          }()
    ];
  }
  for (final e in list) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    final id = SyncPolicy.idOf(key, m);
    if (id != null) out[id] = m;
  }
  return out;
}

/// Puts elements back the way [like] stored them: one JSON text for a string, a list of JSON texts for a list.
Object _fromById(Object? like, Iterable<Map<String, dynamic>> elements) =>
    like is String
        ? jsonEncode(elements.toList())
        : [for (final e in elements) jsonEncode(e)];

/// Whether two values of kind [kind] mean the same, whatever the order of a JSON object's entries.
bool sameValue(SyncKind kind, String key, Object? a, Object? b) {
  if (a == null || b == null) return a == b;
  switch (kind) {
    case SyncKind.map:
      return _canon(_sorted(_asMap(a))) == _canon(_sorted(_asMap(b)));
    case SyncKind.byId:
      return _canon(_byId(key, a)) == _canon(_byId(key, b));
    case SyncKind.set:
      return _canon(a) == _canon(b);
    case SyncKind.scalar:
      return _canon(a) == _canon(b);
  }
}

Object? _sorted(Object? v) {
  if (v is Map) {
    return {for (final k in (v.keys.toList()..sort())) k: _sorted(v[k])};
  }
  if (v is List) return [for (final e in v) _sorted(e)];
  return v;
}

/// Three-way merge of one synced preference.
///
/// [base] is what this device saw at its last sync, [local] what it holds now, [server] what the server holds;
/// null means the key does not exist there. [hadBase] is false for a device that has never synced this key
/// (it is joining): then the server wins where the two disagree, and lists and objects are joined.
/// Otherwise what this device changed since [base] is laid over what the server has now, so two devices that
/// each changed something different both keep their changes.
Object? mergeValue(SyncKind kind, String key,
    {required Object? base,
    required Object? local,
    required Object? server,
    required bool hadBase}) {
  switch (kind) {
    case SyncKind.scalar:
      if (!hadBase) return server ?? local;
      if (sameValue(kind, key, local, base)) return server;
      return local;

    case SyncKind.set:
      final s = [...?(server as List?)?.cast<String>()];
      final l = [...?(local as List?)?.cast<String>()];
      final b = {...?(base as List?)?.cast<String>()};
      if (server == null && local == null) return null;
      if (!hadBase) return [...s, ...l.where((e) => !s.contains(e))];
      final removed = b.where((e) => !l.contains(e)).toSet();
      final out = [
        for (final e in s)
          if (!removed.contains(e)) e
      ];
      for (final e in l) {
        if (!b.contains(e) && !out.contains(e)) out.add(e);
      }
      return out;

    case SyncKind.map:
      if (server == null && local == null) return null;
      final s = _asMap(server), l = _asMap(local), b = _asMap(base);
      Map<String, dynamic> out;
      if (!hadBase) {
        out = {...l, ...s};
      } else {
        out = {...s};
        for (final e in l.entries) {
          if (!b.containsKey(e.key) || _canon(b[e.key]) != _canon(e.value)) {
            out[e.key] = e.value;
          }
        }
        for (final k in b.keys) {
          if (!l.containsKey(k)) out.remove(k);
        }
      }
      return jsonEncode(out);

    case SyncKind.byId:
      if (server == null && local == null) return null;
      final s = _byId(key, server), l = _byId(key, local), b = _byId(key, base);
      Map<String, Map<String, dynamic>> out;
      if (!hadBase) {
        out = {...s};
        for (final e in l.entries) {
          out.putIfAbsent(e.key, () => e.value);
        }
      } else {
        out = {...s};
        for (final e in l.entries) {
          if (!b.containsKey(e.key) || _canon(b[e.key]) != _canon(e.value)) {
            out[e.key] = e.value;
          }
        }
        for (final k in b.keys) {
          if (!l.containsKey(k)) out.remove(k);
        }
      }
      return _fromById(server ?? local, out.values);
  }
}
