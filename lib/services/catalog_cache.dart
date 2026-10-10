import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media.dart';
import 'perf_log.dart';

/// A saved copy of what a provider last sent, so the app can show a library the moment it starts and
/// refresh it quietly afterwards. What is saved is the provider's own answer (the Xtream API's JSON, or
/// the playlist), compressed: the same bytes that are parsed when the library comes from the network, so
/// there is one way to read a library and no second format to get wrong. It lives in the app's private
/// folder and holds nothing the source's own saved address does not already hold.
class CatalogCache {
  static Directory? _dir;

  /// For tests: use this folder.
  @visibleForTesting
  static set directory(Directory? d) => _dir = d;

  static bool get supported => !kIsWeb;
  static const _version = 1;

  static Future<Directory?> _folder() async {
    if (!supported) return null;
    try {
      final base = _dir ?? Directory('${(await getApplicationSupportDirectory()).path}/library');
      await base.create(recursive: true);
      return base;
    } catch (_) {
      return null;
    }
  }

  /// A name for [s] that changes when its address or login changes but never contains the password.
  static String keyOf(Source s) =>
      sha1.convert(utf8.encode('${s.type.name}|${s.url}|${s.username}')).toString().substring(0, 20);

  /// Saves [blobs] (the provider's answers, in a fixed order) for [s]. Compression and writing happen
  /// off the UI thread. Never throws: a library that cannot be saved is just not saved.
  static Future<void> save(Source s, String kind, List<Uint8List> blobs) async {
    final dir = await _folder();
    if (dir == null) return;
    try {
      final parts = [for (final b in blobs) TransferableTypedData.fromList([b])];
      await Isolate.run(() => _writeJob(['${dir.path}/${keyOf(s)}.lib', kind, ...parts]));
    } catch (_) {}
  }

  /// The saved answer for [s], or null when there is none (or it cannot be read).
  static Future<({String kind, List<Uint8List> blobs, DateTime savedAt})?> load(Source s) async {
    final dir = await _folder();
    if (dir == null) return null;
    final f = File('${dir.path}/${keyOf(s)}.lib');
    try {
      if (!await f.exists()) return null;
      final stamp = await f.lastModified();
      final r = await Isolate.run(() => _readJob(f.path));
      if (r == null) return null;
      return (kind: r.$1, blobs: [for (final t in r.$2) t.materialize().asUint8List()], savedAt: stamp);
    } catch (_) {
      return null;
    }
  }

  /// Forgets every saved library (Settings > Source & library > Clear saved library).
  static Future<void> clear() async {
    final dir = await _folder();
    if (dir == null) return;
    try {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.lib')) await e.delete();
      }
    } catch (_) {}
  }

  /// How much space the saved libraries take.
  static Future<int> size() async {
    final dir = await _folder();
    if (dir == null) return 0;
    var n = 0;
    try {
      await for (final e in dir.list()) {
        if (e is File && e.path.endsWith('.lib')) n += await e.length();
      }
    } catch (_) {}
    return n;
  }
}

/// Parses in a background isolate when the answer is big enough for that to be worth it (starting an
/// isolate costs a few milliseconds; parsing 100,000 titles on the UI thread costs seconds and freezes
/// every animation and key press meanwhile).
Future<T> parseAway<T>(String name, int bytes, T Function() job) {
  return PerfLog.time(name, () => bytes < 200 * 1024 ? Future.value(job()) : Isolate.run(job));
}

// ---- file format: "SBL1", kind, count, then each blob as (length, bytes), all gzipped ----------------

void _writeJob(List<Object> a) {
  final path = a[0] as String, kind = a[1] as String;
  final blobs = [for (final t in a.skip(2)) (t as TransferableTypedData).materialize().asUint8List()];
  final out = BytesBuilder(copy: false);
  final head = ByteData(8)
    ..setUint32(0, CatalogCache._version)
    ..setUint32(4, blobs.length);
  final k = utf8.encode(kind);
  out
    ..add(head.buffer.asUint8List())
    ..addByte(k.length)
    ..add(k);
  for (final b in blobs) {
    final len = ByteData(4)..setUint32(0, b.length);
    out
      ..add(len.buffer.asUint8List())
      ..add(b);
  }
  final tmp = File('$path.part');
  tmp.writeAsBytesSync(gzip.encode(out.takeBytes()));
  tmp.renameSync(path); // a half written file is never read
}

(String, List<TransferableTypedData>)? _readJob(String path) {
  final raw = gzip.decode(File(path).readAsBytesSync());
  final d = ByteData.sublistView(Uint8List.fromList(raw));
  if (raw.length < 9 || d.getUint32(0) != CatalogCache._version) return null;
  final n = d.getUint32(4);
  var at = 8;
  final kl = raw[at++];
  final kind = utf8.decode(raw.sublist(at, at + kl));
  at += kl;
  final blobs = <TransferableTypedData>[];
  for (var i = 0; i < n; i++) {
    final len = d.getUint32(at);
    at += 4;
    blobs.add(TransferableTypedData.fromList([Uint8List.sublistView(Uint8List.fromList(raw), at, at + len)]));
    at += len;
  }
  return (kind, blobs);
}
