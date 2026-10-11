import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamboss/services/sync/sync_merge.dart';
import 'package:streamboss/services/sync/sync_policy.dart';

Object? merge(SyncKind k,
        {Object? base,
        Object? local,
        Object? server,
        bool hadBase = true,
        String key = 'k'}) =>
    mergeValue(k, key,
        base: base, local: local, server: server, hadBase: hadBase);

void main() {
  group('values on the wire', () {
    test('every type survives the trip', () {
      for (final v in <Object>[
        'text',
        3,
        2.5,
        true,
        false,
        <String>['a', 'b'],
        <String>[]
      ]) {
        expect(decodeValue(encodeValue(v)), v, reason: '$v');
      }
      expect(encodeValue(null), isNull);
      expect(decodeValue(null), isNull);
      // A whole number stored as a double stays a double.
      expect(decodeValue(encodeValue(1.0)), isA<double>());
      expect(decodeValue(encodeValue(1)), isA<int>());
    });
  });

  group('one value', () {
    test('joining a server: its value wins, and ours is kept when it has none',
        () {
      expect(
          merge(SyncKind.scalar,
              local: 'mine', server: 'theirs', hadBase: false),
          'theirs');
      expect(
          merge(SyncKind.scalar, local: 'mine', server: null, hadBase: false),
          'mine');
    });
    test('untouched here follows the server, changed here wins', () {
      expect(merge(SyncKind.scalar, base: 'a', local: 'a', server: 'b'), 'b');
      expect(merge(SyncKind.scalar, base: 'a', local: 'c', server: 'b'), 'c');
      expect(merge(SyncKind.scalar, base: 'a', local: 'c', server: 'a'), 'c');
    });
    test('a removal travels both ways', () {
      expect(
          merge(SyncKind.scalar, base: 'a', local: 'a', server: null), isNull);
      expect(
          merge(SyncKind.scalar, base: 'a', local: null, server: 'a'), isNull);
    });
  });

  group('a list of texts (My List)', () {
    List<String> set(
            {List<String>? base,
            List<String>? local,
            List<String>? server,
            bool hadBase = true}) =>
        merge(SyncKind.set,
            base: base,
            local: local,
            server: server,
            hadBase: hadBase) as List<String>;

    test('joining joins', () {
      expect(set(local: ['a', 'b'], server: ['b', 'c'], hadBase: false),
          ['b', 'c', 'a']);
    });
    test('what each device added is kept', () {
      expect(set(base: ['a'], local: ['a', 'x'], server: ['a', 'y']),
          ['a', 'y', 'x']);
    });
    test('what one device removed is removed, and the other\'s addition stays',
        () {
      expect(set(base: ['a', 'b'], local: ['a'], server: ['a', 'b', 'c']),
          ['a', 'c']);
      expect(set(base: ['a', 'b'], local: ['a', 'b', 'n'], server: ['b']),
          ['b', 'n']);
    });
    test('both removing the same thing is fine', () {
      expect(set(base: ['a', 'b'], local: ['a'], server: ['a']), ['a']);
    });
    test('nothing anywhere stays nothing', () {
      expect(
          merge(SyncKind.set, base: null, local: null, server: null), isNull);
    });
  });

  group('an object in a string (resume positions)', () {
    Map<String, dynamic> map(
            {Object? base,
            Object? local,
            Object? server,
            bool hadBase = true}) =>
        jsonDecode(merge(SyncKind.map,
            base: base,
            local: local,
            server: server,
            hadBase: hadBase) as String) as Map<String, dynamic>;
    String j(Map<String, dynamic> m) => jsonEncode(m);

    test('different entries changed on two devices both stay', () {
      final r = map(
          base: j({'a': 1}),
          local: j({'a': 1, 'x': 10}),
          server: j({'a': 1, 'y': 20}));
      expect(r, {'a': 1, 'x': 10, 'y': 20});
    });
    test(
        'the same entry changed on both: this device\'s change, as it syncs last',
        () {
      expect(map(base: j({'a': 1}), local: j({'a': 5}), server: j({'a': 9})),
          {'a': 5});
    });
    test('a removal here removes it there; an entry only the server has stays',
        () {
      expect(
          map(
              base: j({'a': 1, 'b': 2}),
              local: j({'a': 1}),
              server: j({'a': 1, 'b': 2, 'c': 3})),
          {'a': 1, 'c': 3});
    });
    test('joining: the server\'s entries win, ours are added', () {
      expect(
          map(local: j({'a': 1, 'b': 2}), server: j({'a': 9}), hadBase: false),
          {'a': 9, 'b': 2});
    });
    test('the order of entries does not matter to "same"', () {
      expect(
          sameValue(
              SyncKind.map, 'k', j({'a': 1, 'b': 2}), j({'b': 2, 'a': 1})),
          isTrue);
      expect(sameValue(SyncKind.map, 'k', j({'a': 1}), j({'a': 2})), isFalse);
    });
  });

  group('a list of objects with an identity', () {
    String profile(String id, String name) =>
        jsonEncode({'id': id, 'name': name});
    List<Map<String, dynamic>> profiles(Object? v) => [
          for (final e in jsonDecode(v as String) as List)
            e as Map<String, dynamic>
        ];

    test('profiles in a string: added on two devices, both stay', () {
      String list(List<String> ids) =>
          jsonEncode([for (final i in ids) jsonDecode(profile(i, 'N$i'))]);
      final r = merge(SyncKind.byId,
          key: 'profiles',
          base: list(['main']),
          local: list(['main', 'a']),
          server: list(['main', 'b']));
      expect(profiles(r).map((e) => e['id']), ['main', 'b', 'a']);
    });
    test(
        'a profile edited here replaces the server\'s copy; one deleted elsewhere is gone',
        () {
      final base = jsonEncode([
        jsonDecode(profile('main', 'Main')),
        jsonDecode(profile('a', 'Old'))
      ]);
      final local = jsonEncode([
        jsonDecode(profile('main', 'Main')),
        jsonDecode(profile('a', 'New'))
      ]);
      final server = jsonEncode([jsonDecode(profile('main', 'Main'))]);
      expect(
          profiles(merge(SyncKind.byId,
                  key: 'profiles', base: base, local: local, server: server))
              .map((e) => e['name']),
          ['Main', 'New']);
      final r = merge(SyncKind.byId,
          key: 'profiles', base: base, local: base, server: server);
      expect(profiles(r).map((e) => e['id']), ['main']);
    });
    test(
        'sources and reminders are lists of texts holding objects, and stay that way',
        () {
      List<String> src(List<String> names) => [
            for (final n in names)
              jsonEncode({
                'name': n,
                'type': 'xtream',
                'url': 'http://$n',
                'user': 'u',
                'pass': ''
              })
          ];
      final r = merge(SyncKind.byId,
          key: 'sources',
          base: src(['a']),
          local: src(['a', 'b']),
          server: src(['a', 'c'])) as List;
      expect(r.map((e) => jsonDecode(e as String)['name']), ['a', 'c', 'b']);
      String rem(String ch, int at) =>
          jsonEncode({'channelKey': ch, 'startMs': at, 'title': 't'});
      final q = merge(SyncKind.byId,
          key: 'reminders',
          base: <String>[],
          local: [rem('live:1', 5)],
          server: [rem('live:2', 6)]) as List;
      expect(q.length, 2);
    });
  });
}
