import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/update_check.dart';

/// Guards the "bump the version with every feature" rule: pubspec.yaml and the top CHANGELOG.md
/// entry must agree, and the changelog must list versions newest first.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final headings = [
    for (final l in File('CHANGELOG.md').readAsLinesSync())
      if (l.startsWith('## ')) l,
  ];
  String versionOf(String h) => RegExp(r'^## (\S+)').firstMatch(h)![1]!;

  test('pubspec has a version like 0.2.3+1', () {
    expect(RegExp(r'^version: \d+\.\d+\.\d+\+\d+$', multiLine: true).hasMatch(pubspec), isTrue);
  });

  test('every changelog heading is "## <version> - <date>"', () {
    expect(headings, isNotEmpty);
    for (final h in headings) {
      expect(RegExp(r'^## \d+\.\d+\.\d+(b\d+|-[0-9A-Za-z.]+)? - \d{4}-\d{2}-\d{2}$').hasMatch(h), isTrue, reason: h);
    }
  });

  test('the newest changelog entry matches the x.y.z in pubspec.yaml', () {
    final pub = RegExp(r'^version: (\d+\.\d+\.\d+)\+', multiLine: true).firstMatch(pubspec)![1]!;
    final top = AppVersion.parse(versionOf(headings.first));
    expect(top.core.join('.'), pub, reason: 'bumped one but not the other? update pubspec.yaml and CHANGELOG.md together');
  });

  test('changelog versions are strictly newest first', () {
    final v = [for (final h in headings) versionOf(h)];
    for (var i = 1; i < v.length; i++) {
      expect(compareVersions(v[i - 1], v[i]) > 0, isTrue, reason: '${v[i - 1]} should be newer than ${v[i]}');
    }
  });
}
