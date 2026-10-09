import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class Programme {
  final String title;
  final DateTime start, end;
  const Programme(this.title, this.start, this.end);

  bool get isNow {
    final n = DateTime.now();
    return !n.isBefore(start) && n.isBefore(end);
  }
}

class XmltvData {
  /// Programmes by lower-cased XMLTV channel id, sorted by start.
  final Map<String, List<Programme>> programmes;

  /// Lower-cased display-name -> lower-cased channel id (fallback matching).
  final Map<String, String> nameToId;
  const XmltvData(this.programmes, this.nameToId);
  static const empty = XmltvData({}, {});
}

/// XMLTV times look like `20240131183000 +0100` (offset optional, seconds optional).
DateTime? parseXmltvTime(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?')
      .firstMatch(s.trim());
  if (m == null) return null;
  var t = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
      int.parse(m[4]!), int.parse(m[5]!), int.tryParse(m[6] ?? '0') ?? 0);
  final off = m[7];
  if (off != null) {
    final sign = off.startsWith('-') ? -1 : 1;
    final mins = int.parse(off.substring(1, 3)) * 60 + int.parse(off.substring(3, 5));
    t = t.subtract(Duration(minutes: sign * mins));
  }
  return t;
}

/// Parses an XMLTV document, keeping only programmes that overlap [from, to]
/// so large guides stay small in memory.
XmltvData parseXmltv(String xml, {required DateTime from, required DateTime to}) {
  final doc = XmlDocument.parse(xml);
  final names = <String, String>{};
  final progs = <String, List<Programme>>{};

  for (final c in doc.findAllElements('channel')) {
    final id = c.getAttribute('id')?.toLowerCase();
    if (id == null) continue;
    for (final n in c.findElements('display-name')) {
      names.putIfAbsent(n.innerText.trim().toLowerCase(), () => id);
    }
  }
  for (final p in doc.findAllElements('programme')) {
    final id = p.getAttribute('channel')?.toLowerCase();
    final start = parseXmltvTime(p.getAttribute('start') ?? '');
    final end = parseXmltvTime(p.getAttribute('stop') ?? '');
    if (id == null || start == null || end == null) continue;
    if (!end.isAfter(from) || !start.isBefore(to)) continue;
    final title = p.getElement('title')?.innerText.trim() ?? '';
    (progs[id] ??= []).add(Programme(title.isEmpty ? 'Untitled' : title, start, end));
  }
  for (final l in progs.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  return XmltvData(progs, names);
}

/// True when [b] starts with the gzip magic number. Guides are often served as `.xml.gz`
/// without a `Content-Encoding` header, so a client never unpacks them by itself.
bool isGzip(List<int> b) => b.length > 2 && b[0] == 0x1f && b[1] == 0x8b;

/// The text of a downloaded guide, unpacked first when it is gzipped.
String decodeXmltvBytes(List<int> b) =>
    utf8.decode(isGzip(b) ? const GZipDecoder().decodeBytes(b) : b, allowMalformed: true);

/// Top-level wrapper so it can run via `compute`: takes the raw download, so unpacking and parsing
/// both happen off the UI thread. Args: bytes, from (ms), to (ms).
XmltvData parseXmltvBytesJob(List<Object> args) => parseXmltv(
      decodeXmltvBytes(args[0] as List<int>),
      from: DateTime.fromMillisecondsSinceEpoch(args[1] as int),
      to: DateTime.fromMillisecondsSinceEpoch(args[2] as int),
    );
