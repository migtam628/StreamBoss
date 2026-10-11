import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/sync/sync_policy.dart';

void main() {
  group('which preferences sync', () {
    test('taste does, and so do the lists of every profile', () {
      for (final k in [
        'language',
        'autoResume',
        'subSize',
        'tmdbKey',
        'userAgent',
        'sources',
        'extraSources',
        'active',
        'profiles',
        'pinHash',
        'pinSalt'
      ]) {
        expect(SyncPolicy.kindOf(k), isNotNull, reason: k);
      }
      expect(SyncPolicy.kindOf('favorites'), SyncKind.set);
      expect(SyncPolicy.kindOf('favorites:p1abc'), SyncKind.set);
      expect(SyncPolicy.kindOf('positions:p1abc'), SyncKind.map);
      expect(SyncPolicy.kindOf('reminders'), SyncKind.byId);
      expect(SyncPolicy.kindOf('profileSettings:p2'), SyncKind.map);
      expect(SyncPolicy.kindOf('language'), SyncKind.scalar);
    });
    test('the device, passwords, recents and caches stay where they are', () {
      for (final k in [
        'tvMode',
        'tvWidth',
        'layout',
        'onboarded',
        'appIcon',
        'decoder',
        'videoOutput',
        'fastStart',
        'bufferSecs',
        'startOnBoot',
        'updating',
        'lastTab',
        'lastLive',
        'lastLiveOpen',
        'uiScale',
        'posterSize',
        'screensaver',
        'osPass',
        'recents',
        'recents:p1',
        'profileCurrent',
        'posterCache',
        'deadStreams',
        'syncBase',
        'syncServer',
        'syncEmail',
        'syncAuto',
        'syncLast',
        'something-unknown',
      ]) {
        expect(SyncPolicy.kindOf(k), isNull, reason: k);
      }
    });
  });

  group('no password leaves the device', () {
    test('a source loses its password and the one in its address', () {
      final x = SyncPolicy.sanitizeSource({
        'name': 'A',
        'type': 'xtream',
        'url': 'http://h:80',
        'user': 'u',
        'pass': 'secret'
      });
      expect(x['pass'], '');
      expect(x['user'], 'u');
      final m = SyncPolicy.sanitizeSource({
        'name': 'B',
        'type': 'm3u',
        'url': 'http://h/get.php?username=u&password=SeCrEt&type=m3u_plus',
        'user': '',
        'pass': '',
      });
      expect(m['url'], 'http://h/get.php?username=u&password=&type=m3u_plus');
      expect(jsonEncode(m).contains('SeCrEt'), isFalse);
      expect(SyncPolicy.stripUrlPassword('http://user:pw@host/list.m3u'),
          'http://user@host/list.m3u');
      expect(SyncPolicy.stripUrlPassword('http://host/list.m3u'),
          'http://host/list.m3u');
      expect(SyncPolicy.stripUrlPassword('http://h/x?PASSWORD=zzz&a=1'),
          'http://h/x?PASSWORD=&a=1');
    });
    test('outgoing cleans the sources list and leaves other preferences alone',
        () {
      final raw = [
        jsonEncode({
          'name': 'B',
          'type': 'm3u',
          'url': 'http://h/get.php?username=u&password=SeCrEt',
          'user': '',
          'pass': ''
        })
      ];
      final out = SyncPolicy.outgoing('sources', raw) as List;
      expect(out.join().contains('SeCrEt'), isFalse);
      expect(SyncPolicy.outgoing('favorites', ['x']), ['x']);
      expect(SyncPolicy.outgoing('language', 'es'), 'es');
    });
    test(
        'a source this device already has keeps its own login when the server\'s copy only lacks the password',
        () {
      final own = jsonEncode({
        'name': 'B',
        'type': 'm3u',
        'url': 'http://h/get.php?username=u&password=SeCrEt',
        'user': '',
        'pass': ''
      });
      final theirs = jsonEncode(
          SyncPolicy.sanitizeSource(jsonDecode(own) as Map<String, dynamic>));
      final kept = SyncPolicy.incoming('sources', [theirs], [own]) as List;
      expect(kept.single, own);
      // A source the server has and this device has not arrives as it is: without a password.
      final fresh = jsonEncode({
        'name': 'N',
        'type': 'xtream',
        'url': 'http://n',
        'user': 'u',
        'pass': ''
      });
      expect(
          (SyncPolicy.incoming('sources', [theirs, fresh], [own]) as List).last,
          fresh);
      // An edit made elsewhere (another address) replaces ours.
      final edited = jsonEncode({
        'name': 'B',
        'type': 'm3u',
        'url': 'http://other/list.m3u',
        'user': '',
        'pass': ''
      });
      expect((SyncPolicy.incoming('sources', [edited], [own]) as List).single,
          edited);
    });
  });

  group('putting a password back', () {
    test('a link that had its password taken out is recognised and filled in',
        () {
      const blank = 'http://h/get.php?username=u&password=&type=m3u_plus';
      expect(SyncPolicy.urlPasswordBlank(blank), isTrue);
      expect(
          SyncPolicy.urlPasswordBlank(
              'http://h/get.php?username=u&password=abc'),
          isFalse);
      expect(SyncPolicy.urlPasswordBlank('http://h/list.m3u'), isFalse);
      expect(SyncPolicy.fillUrlPassword(blank, 'p w&1'),
          'http://h/get.php?username=u&password=p+w%261&type=m3u_plus');
      expect(SyncPolicy.fillUrlPassword('http://user@host/x.m3u', 'pw'),
          'http://user:pw@host/x.m3u');
      expect(SyncPolicy.urlPasswordBlank('http://user@host/x.m3u'), isTrue);
    });
  });
}
