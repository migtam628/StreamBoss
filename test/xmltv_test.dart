import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/m3u_parser.dart';
import 'package:streamboss/services/xmltv.dart';

void main() {
  test('parses XMLTV times with offsets', () {
    expect(parseXmltvTime('20240131183000 +0100'), DateTime.utc(2024, 1, 31, 17, 30));
    expect(parseXmltvTime('20240131183000 -0500'), DateTime.utc(2024, 1, 31, 23, 30));
    expect(parseXmltvTime('20240131183000'), DateTime.utc(2024, 1, 31, 18, 30));
    expect(parseXmltvTime('garbage'), isNull);
  });

  test('keeps only programmes inside the window, sorted, with name fallback', () {
    const xml = '''<?xml version="1.0"?>
<tv>
  <channel id="News.One"><display-name>News One</display-name></channel>
  <programme start="20240101100000 +0000" stop="20240101110000 +0000" channel="News.One"><title>Late</title></programme>
  <programme start="20240101090000 +0000" stop="20240101100000 +0000" channel="News.One"><title>Early</title></programme>
  <programme start="20240101010000 +0000" stop="20240101020000 +0000" channel="News.One"><title>Too old</title></programme>
</tv>''';
    final d = parseXmltv(xml,
        from: DateTime.utc(2024, 1, 1, 8), to: DateTime.utc(2024, 1, 1, 16));
    expect(d.programmes['news.one']!.map((p) => p.title), ['Early', 'Late']);
    expect(d.nameToId['news one'], 'news.one');
  });

  test('m3u header url-tvg and tvg-id are captured', () {
    final c = parseM3u('#EXTM3U url-tvg="http://x/guide.xml,http://y/other.xml"\n'
        '#EXTINF:-1 tvg-id="a.b" group-title="G",Chan\nhttp://h/1.m3u8\n');
    expect(c.epgUrl, 'http://x/guide.xml');
    expect(c.live.single.epgId, 'a.b');
  });

  group('gzipped guides', () {
    const xml = '<tv><channel id="a"><display-name>A</display-name></channel>'
        '<programme start="20240101100000 +0000" stop="20240101110000 +0000" channel="a"><title>Show \u00e9</title></programme></tv>';
    final args = [DateTime.utc(2024, 1, 1, 8), DateTime.utc(2024, 1, 1, 16)]
        .map((d) => d.millisecondsSinceEpoch)
        .toList();

    test('are unpacked before parsing', () {
      final gz = const GZipEncoder().encodeBytes(utf8.encode(xml));
      expect(isGzip(gz), isTrue);
      final d = parseXmltvBytesJob(<Object>[gz, ...args]);
      expect(d.programmes['a']!.single.title, 'Show \u00e9');
    });

    test('plain XML still parses and is not mistaken for gzip', () {
      final raw = utf8.encode(xml);
      expect(isGzip(raw), isFalse);
      expect(parseXmltvBytesJob(<Object>[raw, ...args]).programmes['a'], hasLength(1));
    });

    test('a short or empty body is not gzip', () {
      expect(isGzip(const []), isFalse);
      expect(isGzip(const [0x1f, 0x8b]), isFalse);
    });
  });
}
